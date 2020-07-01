import Combine
import Foundation
import Synchronized

private let backgroundQueue = DispatchQueue(label: "Channel.backgroundQueue")

public final class Channel: Publisher {
    public typealias Output = Channel.Event
    public typealias Failure = Never

    typealias SocketOutput = ChannelSpecificSocketMessage
    typealias SocketFailure = Never

    typealias JoinPayloadBlock = () -> Payload
    typealias RejoinTimeout = (Int) -> DispatchTimeInterval

    private let lock: RecursiveLock = RecursiveLock()
    private func sync<T>(_ block: () throws -> T) rethrows -> T { return try lock.locked(block) }
    
    private var subject = PassthroughSubject<Output, Failure>()
    
    var pending: [Push] { sync { return _pending } }
    private var _pending: [Push] = []
    
    var inFlight: [Ref: PushedMessage] { sync { return _inFlight }}
    private var _inFlight: [Ref: PushedMessage] = [:]
    
    private var shouldRejoin = true
    private var state: State = .closed
    
    private weak var socket: Socket?

    private var socketSubscriber: AnyCancellable?
    
    private var customTimeout: DispatchTimeInterval? = nil
    
    public var timeout: DispatchTimeInterval {
        if let customTimeout = customTimeout {
            return customTimeout
        } else if let socket = socket {
            return socket.timeout
        } else {
            return Socket.defaultTimeout
        }
    }
    
    var canPush: Bool { return self.isJoined }
    
    private let notifySubjectQueue = DispatchQueue(label: "Channel.notifySubjectQueue")
    
    private var inFlightMessagesTimer: Timer?
    
    private(set) var joinTimer: JoinTimer = .off
    private var leaveTimer: Timer? = nil

    var rejoinTimeout: RejoinTimeout = { attempt in
        // https://github.com/phoenixframework/phoenix/blob/7bb70decc747e6b4286f17abfea9d3f00f11a77e/assets/js/phoenix.js#L777
        switch attempt {
        case 0: assertionFailure("Rejoins are 1-indexed"); return .seconds(1)
        case 1: return .seconds(1)
        case 2: return .seconds(2)
        case 3: return .seconds(5)
        default: return .seconds(10)
        }
    }
    
    public let topic: Topic
    
    let joinPayloadBlock: JoinPayloadBlock
    var joinPayload: Payload { joinPayloadBlock() }
    
    // NOTE: init shouldn't be public because we want Socket to always have a record of the channels that have been created in it's dictionary
    convenience init(topic: Topic, socket: Socket) {
        self.init(topic: topic, joinPayloadBlock: { [:] }, socket: socket)
    }
    
    convenience init(topic: Topic, joinPayload: Payload, socket: Socket) {
        self.init(topic: topic, joinPayloadBlock: { joinPayload }, socket: socket)
    }
    
    init(topic: Topic, joinPayloadBlock: @escaping JoinPayloadBlock, socket: Socket) {
        self.topic = topic
        self.socket = socket
        self.joinPayloadBlock = joinPayloadBlock
        self.socketSubscriber = makeSocketSubscriber(with: socket, topic: topic)
    }

    var joinRef: Ref? { sync {
        switch state {
        case .joining(let ref):
            return ref
        case .joined(let ref):
            return ref
        case .leaving(let joinRef, _):
            return joinRef
        default:
            return nil
        }
    } }
    
    var joinPush: Push {
        Push(channel: self, event: .join, payload: joinPayload, timeout: timeout)
    }
    
    var leavePush: Push {
        Push(channel: self, event: .leave, timeout: timeout)
    }
    
    public var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    public var isJoining: Bool { sync {
        guard case .joining = state else { return false }
        return true
    } }
    
    public var isJoined: Bool { sync {
        guard case .joined = state else { return false }
        return true
    } }
    
    public var isLeaving: Bool { sync {
        guard case .leaving = state else { return false }
        return true
    } }
    
    public var isErrored: Bool { sync {
        guard case .errored = state else { return false }
        return true
    } }
    
    func errored(_ error: Swift.Error) {
        sync {
            self.state = .errored(error)
            let subject = self.subject
            notifySubjectQueue.async { subject.send(.error(error)) }
        }
    }
    
    public var connectionState: String {
        switch state {
        case .closed:
            return "closed"
        case .errored:
            return "errored"
        case .joined:
            return "joined"
        case .joining:
            return "joining"
        case .leaving:
            return "leaving"
        }
    }

    deinit {
        inFlightMessagesTimer = nil
        joinTimer = .off
        leaveTimer = nil
        socketSubscriber?.cancel()
    }
}

// MARK: join

extension Channel {
    public func join(timeout customTimeout: DispatchTimeInterval? = nil) {
        sync { self.customTimeout = customTimeout }
        rejoin()
    }
    
    private func rejoin() {
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            guard shouldRejoin else { return }
            
            switch state {
            case .joining, .joined:
                return
            case .closed, .errored, .leaving:
                let ref = socket.advanceRef()
                self.state = .joining(ref)
                self.writeJoinPushAsync()
            }
        }
    }
    
    private func writeJoinPush() {
        sync {
            switch self.state {
            case .joining(let joinRef):
                let message = OutgoingMessage(joinPush, ref: joinRef, joinRef: joinRef)

                createJoinTimer()

                send(message) { error in
                    if let error = error {
                        Swift.print("There was a problem writing to the socket: \(error)")
                        self.createRejoinTimer()
                    }
                }
            default:
                self.errored(Channel.Error.noLongerJoining)
            }
        }
    }
    
    private func writeJoinPushAsync() {
        backgroundQueue.async {
            self.writeJoinPush()
        }
    }
}

// MARK: leave

extension Channel {
    func leave(timeout customTimeout: DispatchTimeInterval? = nil) {
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            self.shouldRejoin = false

            switch state {
            case .joining(let joinRef), .joined(let joinRef):
                let ref = socket.advanceRef()
                let message = OutgoingMessage(leavePush, ref: ref, joinRef: joinRef)
                self.state = .leaving(joinRef: joinRef, leavingRef: ref)

                let timeout = DispatchTime.now().advanced(by: customTimeout ?? self.timeout)
                
                backgroundQueue.async {
                    self.send(message)
                    self.sync {
                        self.leaveTimer = Timer(fireAt: timeout) { [weak self] in self?.timeoutLeavePush() }
                    }
                }
            case .leaving, .errored, .closed:
                return
            }
        }
    }

    private func sendLeaveAndCompletionToSubjectAsync() {
        let subject = self.subject
        notifySubjectQueue.async {
            subject.send(.leave)
            subject.send(completion: .finished)
        }
    }
}

// MARK: Push

extension Channel {
    public func push(_ eventString: String) {
        push(eventString, payload: [String: Any](), callback: nil)
    }
    
    public func push(_ eventString: String, callback: Channel.Callback?) {
        push(eventString, payload: [String: Any](), callback: callback)
    }

    public func push(_ eventString: String, payload: Payload) {
        push(eventString, payload: payload, callback: nil)
    }

    public func push(
        _ eventString: String,
        payload: Payload,
        timeout: DispatchTimeInterval? = nil,
        callback: Channel.Callback?)
    {
        sync {
            let push = Channel.Push(
                channel: self,
                event: PhxEvent(eventString),
                payload: payload,
                timeout: timeout ?? self.timeout,
                callback: callback
            )
            
            _pending.append(push)
        }
        
        self.flushAsync()
    }
}

// MARK: Push

extension Channel {
    private func send(_ message: OutgoingMessage) {
        send(message) { _ in }
    }
    
    private func send(_ message: OutgoingMessage, completionHandler: @escaping Socket.Callback) {
        guard let socket = socket else {
            // TODO: maybe we should just hard ref the socket?
            self.errored(Channel.Error.lostSocket)
            completionHandler(Channel.Error.lostSocket)
            return
        }
        
        socket.send(message) { error in
            if let error = error {
                Swift.print("There was an error writing to the socket: \(error)")
                // NOTE: we don't change state to error here, instead we let the socket close do that for us
            }
            
            completionHandler(error)
        }
    }
}

// MARK: Flush messages

extension Channel {
    private func flush() {
        sync {
            guard case .joined(let joinRef) = state else { return }
            guard let socket = self.socket else { return assertionFailure("No socket") }
            
            guard let push = _pending.first else { return }
            self._pending = Array(self._pending.dropFirst())
            
            let ref = socket.advanceRef()
            let message = OutgoingMessage(push, ref: ref, joinRef: joinRef)
            
            let pushed = PushedMessage(push: push, message: message)
            _inFlight[ref] = pushed
            
            createInFlightMessagesTimer()
            
            send(message) { error in
                if let error = error {
                    Swift.print("Couldn't write to socket from Channel \(self) – \(error) - \(message)")
                    self.sync {
                        // put it back to try again later
                        self._inFlight[ref] = nil
                        self._pending.append(push)
                    }
                } else {
                    self.flushAsync()
                }
            }
        }
    }
    
    private func flushAsync() {
        backgroundQueue.async { self.flush() }
    }
}

// MARK: Timeouts

extension Channel {
    func timeoutJoinPush() {
        errored(Error.joinTimeout)
        createRejoinTimer()
    }

    func timeoutLeavePush() {
        sync {
            leaveTimer = nil
            state = .closed
            sendLeaveAndCompletionToSubjectAsync()
        }
    }
    
    private func createJoinTimer() {
        sync {
            let attempt = (joinTimer.attempt ?? 0) + 1
            self.joinTimer = .off

            let timer = Timer(timeout) { [weak self] in self?.timeoutJoinPush() }

            self.joinTimer = .join(timer: timer, attempt: attempt)
        }
    }
    
    private func createRejoinTimer() {
        sync {
            guard joinTimer.isNotRejoinTimer else { return }
            
            let attempt = joinTimer.attempt ?? 0
            assert(attempt > 0, "we should always join before rejoining")
            self.joinTimer = .off

            let interval = rejoinTimeout(attempt)
            
            let timer = Timer(interval) { [weak self] in self?.rejoin() }
            
            self.joinTimer = .rejoin(timer: timer, attempt: attempt)
        }
    }
    
    private func timeoutInFlightMessages() {
        sync {
            // invalidate a previous timer if it's there
            self.inFlightMessagesTimer = nil
            
            guard !_inFlight.isEmpty else { return }
            
            let now = DispatchTime.now()
        
            let messages = _inFlight.values.sortedByTimeoutDate().filter {
                $0.timeoutDate < now
            }
            
            for message in messages {
                _inFlight[message.ref] = nil
                message.callback(error: Error.pushTimeout)
            }
            
            createInFlightMessagesTimer()
        }
    }
    
    private func timeoutInFlightMessagesAsync() {
        backgroundQueue.async { self.timeoutInFlightMessages() }
    }
    
    private func createInFlightMessagesTimer() {
        sync {
            guard _inFlight.isNotEmpty else { return }

            let possibleNext = _inFlight.values.sortedByTimeoutDate().first
            
            guard let next = possibleNext else { return }
            guard next.timeoutDate < inFlightMessagesTimer?.nextDeadline else { return }
            
            self.inFlightMessagesTimer =  Timer(fireAt: next.timeoutDate) { [weak self] in
                self?.timeoutInFlightMessagesAsync()
            }
        }
    }
}

// MARK: Publisher

extension Channel {
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input {
        subject.receive(subscriber: subscriber)
    }
}

// MARK: Socket Subscriber

extension Channel {
    enum ChannelSpecificSocketMessage {
        case socketOpen
        case socketClose
        case channelMessage(IncomingMessage)
    }

    func makeSocketSubscriber(
        with socket: Socket,
        topic: Topic
    ) -> AnyCancellable
    {
        let channelSpecificMessage = { (message: Socket.Message) -> SocketOutput? in
            switch message {
            case .closing, .connecting, .unreadableMessage, .websocketError:
                return nil // not interesting
            case .close:
                return .socketClose
            case .open:
                return .socketOpen
            case .incomingMessage(let message):
                guard message.topic == topic else { return nil }
                return .channelMessage(message)
            }
        }

        let completion: (Subscribers.Completion<SocketFailure>) -> Void = { _ in fatalError("`Never` means never") }
        let receiveValue = { [weak self] (input: SocketOutput) -> Void in
            switch input {
            case .channelMessage(let message):
                self?.handle(message)
            case .socketOpen:
                self?.handleSocketOpen()
            case .socketClose:
                self?.handleSocketClose()
            }
        }

        return socket
            .compactMap(channelSpecificMessage)
            .sink(receiveCompletion: completion, receiveValue: receiveValue)
    }
}

// MARK: Input handlers

extension Channel {
    private func handleSocketOpen() {
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            switch state {
            case .joining:
                writeJoinPushAsync()
            case .errored where shouldRejoin:
                let ref = socket.advanceRef()
                self.state = .joining(ref)
                writeJoinPushAsync()
            case .errored:
                break
            case .closed:
                break // NOOP
            case .joined, .leaving:
                preconditionFailure("Really shouldn't get an open if we are \(state) and didn't get a close")
            }
        }
    }
    
    private func handleSocketClose() {
        sync {
            switch state {
            case .joined, .joining, .leaving:
                errored(Error.socketIsClosed)
            case .errored(let error):
                if let error = error as? Channel.Error,
                    case .socketIsClosed = error {
                    // No need to error again if this is the reason we are already errored – although this shouldn't happen
                    return
                }
                errored(Error.socketIsClosed)
            case .closed:
                break // NOOP
            }
        }
    }
    
    private func handle(_ input: IncomingMessage) {
        guard isClosed == false else { return }

        switch input.event {
        case .custom:
            let message = Channel.Message(incomingMessage: input)
            handle(message)
            
        case .reply:
            if let reply = Channel.Reply(incomingMessage: input) {
                handle(reply)
            } else {
                assertionFailure("Got an unreadable reply")
            }
            
        case .close:
            sync {
                self.shouldRejoin = false
                state = .closed
                self.sendLeaveAndCompletionToSubjectAsync()
            }

        default:
            break
        }
    }

    private func handle(_ reply: Channel.Reply) {
        sync {
            switch state {
            case .joining(let joinRef):
                guard reply.ref == joinRef,
                    reply.joinRef == joinRef,
                    reply.isOk else {
                        self.errored(Channel.Error.invalidJoinReply(reply))
                        self.createRejoinTimer()
                    break
                }
                
                self.state = .joined(joinRef)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.join) }

                self.joinTimer = .off
                
                flushAsync()
                
            case .joined(let joinRef):
                guard let pushed = _inFlight.removeValue(forKey: reply.ref),
                      reply.joinRef == joinRef else {
                    return
                }
                
                let subject = self.subject
                notifySubjectQueue.async { subject.send(.message(reply.message)) }
                backgroundQueue.async { pushed.callback(reply: reply) }
                
            case .leaving(let joinRef, let leavingRef):
                guard reply.ref == leavingRef, reply.joinRef == joinRef else { break }

                self.state = .closed
                self.sendLeaveAndCompletionToSubjectAsync()

            case .closed:
                break

            default:
                break
            }
        }
    }
    
    private func handle(_ message: Channel.Message) {
        sync {
            guard case .joined = state else {
                assertionFailure("Shouldn't be getting messages when not joined: \(message)")
                return
            }

            let subject = self.subject
            notifySubjectQueue.async { subject.send(.message(message)) }
        }
    }
}
