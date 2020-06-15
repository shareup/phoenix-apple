import Combine
import Foundation
import Forever
import Synchronized

private let backgroundQueue = DispatchQueue(label: "Channel.backgroundQueue")

public final class Channel: Publisher, Synchronized {
    public typealias Output = Channel.Event
    public typealias Failure = Never

    typealias SocketOutput = ChannelSpecificSocketMessage
    typealias SocketFailure = Never

    typealias JoinPayloadBlock = () -> Payload
    typealias RejoinTimeout = (Int) -> DispatchTimeInterval
    
    private var subject = PassthroughSubject<Output, Failure>()
    private var pending: [Push] = []
    private var inFlight: [Ref: PushedMessage] = [:]
    
    private var shouldRejoin = true
    private var state: State = .closed
    
    private weak var socket: Socket?

    private var socketSubscriber: AnySubscriber<SocketOutput, SocketFailure>?
    
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
    
    private var pushedMessagesTimer: Timer?
    
    private var joinTimer: JoinTimer = .off

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
    
    public let topic: String
    
    let joinPayloadBlock: JoinPayloadBlock
    var joinPayload: Payload { joinPayloadBlock() }
    
    // NOTE: init shouldn't be public because we want Socket to always have a record of the channels that have been created in it's dictionary
    convenience init(topic: String, socket: Socket) {
        self.init(topic: topic, joinPayloadBlock: { [:] }, socket: socket)
    }
    
    convenience init(topic: String, joinPayload: Payload, socket: Socket) {
        self.init(topic: topic, joinPayloadBlock: { joinPayload }, socket: socket)
    }
    
    init(topic: String, joinPayloadBlock: @escaping JoinPayloadBlock, socket: Socket) {
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
    
    var joinedOnce = false
    
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
            subject.send(.error(error))
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
}

// MARK: join

extension Channel {
    public func join(timeout customTimeout: DispatchTimeInterval) {
        self.customTimeout = customTimeout
        join()
    }
    
    public func join() {
        rejoin()
    }
    
    private func rejoin() {
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            guard shouldRejoin else { return }
            
            Swift.print("$$ rejoin!")
            
            switch state {
            case .joining, .joined:
                return
            case .closed, .errored, .leaving:
                let ref = socket.advanceRef()
                self.state = .joining(ref)
                
                backgroundQueue.async {
                    self.writeJoinPush()
                }
            }
        }
    }
    
    private func writeJoinPush() {
        // TODO: set a timer for timeout for the join push
        sync {
            switch self.state {
            case .joining(let joinRef):
                let message = OutgoingMessage(joinPush, ref: joinRef, joinRef: joinRef)
                
                send(message) { error in
                    if let error = error {
                        Swift.print("There was a problem writing to the socket: \(error)")
                        // TODO: create the rejoin timer now?
                    } else {
                        self.createJoinTimer()
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
    public func leave(timeout: DispatchTimeInterval) {
        self.customTimeout = timeout
        leave()
    }
    
    public func leave() {
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            self.shouldRejoin = false
            
            switch state {
            case .joining(let joinRef), .joined(let joinRef):
                let ref = socket.advanceRef()
                let message = OutgoingMessage(leavePush, ref: ref, joinRef: joinRef)
                self.state = .leaving(joinRef: joinRef, leavingRef: ref)
                
                backgroundQueue.async {
                    self.send(message)
                }
            case .leaving, .errored, .closed:
                Swift.print("Can only leave if we are joining or joined, currently \(state)")
                return
            }
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

    public func push(_ eventString: String, payload: Payload, callback: Channel.Callback?) {
        sync {
            let push = Channel.Push(
                channel: self,
                event: PhxEvent(eventString),
                payload: payload,
                callback: callback
            )
            
            pending.append(push)
        }
        
        self.timeoutPushedMessagesAsync()
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
        guard let socket = self.socket else { return assertionFailure("No socket") }

        sync {
            guard case .joined(let joinRef) = state else { return }
            
            guard let push = pending.first else { return }
            self.pending = Array(self.pending.dropFirst())
            
            let ref = socket.advanceRef()
            let message = OutgoingMessage(push, ref: ref, joinRef: joinRef)
            
            let pushed = PushedMessage(push: push, message: message)
            inFlight[ref] = pushed
            
            send(message) { error in
                if let error = error {
                    Swift.print("Couldn't write to socket from Channel \(self) – \(error) - \(message)")
                    self.sync {
                        // put it back to try again later
                        self.inFlight[ref] = nil
                        self.pending.append(push)
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
    
    private func createJoinTimer() {
        sync {
            let attempt: Int
            
            if case .rejoin(_, let newAttempt) = joinTimer {
                attempt = newAttempt
            } else {
                attempt = 1
            }
            
            self.joinTimer = .off
            
            let timer = Timer(timeout) { [weak self] in
                self?.timeoutJoinPush()
            }
            
            Swift.print("$$ creating join timer", timeout, attempt)
            
            self.joinTimer = .joining(timer: timer, attempt: attempt)
        }
    }
    
    private func createRejoinTimer() {
        sync {
            guard case .joining(_, let attempt) = joinTimer else {
                // NOTE: does this make sense?
                createJoinTimer()
                return
            }
            
            self.joinTimer = .off
            
            let interval = rejoinTimeout(attempt)
            
            let timer = Timer(interval) { [weak self] in
                self?.rejoin()
            }
            
            Swift.print("$$ creating rejoin timer", interval, attempt)
            
            self.joinTimer = .rejoin(timer: timer, attempt: attempt + 1)
        }
    }
    
    private func timeoutPushedMessages() {
        sync {
            // invalidate a previous timer if it's there
            self.pushedMessagesTimer = nil
            
            guard !inFlight.isEmpty else { return }
            
            let now = DispatchTime.now()
        
            let messages = inFlight.values.sortedByTimeoutDate().filter {
                $0.timeoutDate < now
            }
            
            for message in messages {
                inFlight[message.ref] = nil
                message.callback(error: Error.pushTimeout)
            }
            
            createPushedMessagesTimer()
        }
    }
    
    private func timeoutPushedMessagesAsync() {
        backgroundQueue.async { self.timeoutPushedMessages() }
    }
    
    private func createPushedMessagesTimer() {
        sync {
            guard !inFlight.isEmpty,
                pushedMessagesTimer == nil else {
                    return
            }

            let possibleNext = inFlight.values.sortedByTimeoutDate().first
            
            guard let next = possibleNext else { return }
            
            self.pushedMessagesTimer =  Timer(fireAt: next.timeoutDate) { [weak self] in
                self?.timeoutPushedMessagesAsync()
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

    func makeSocketSubscriber(with socket: Socket, topic: String) -> AnySubscriber<SocketOutput, SocketFailure> {
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
            Swift.print("channel input", input)

            switch input {
            case .channelMessage(let message):
                self?.handle(message)
            case .socketOpen:
                self?.handleSocketOpen()
            case .socketClose:
                self?.handleSocketClose()
            }
        }

        let socketSubscriber = socket
            .compactMap(channelSpecificMessage)
            .forever(receiveCompletion: completion, receiveValue: receiveValue)
        return AnySubscriber(socketSubscriber)
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
            case .errored:
                let ref = socket.advanceRef()
                self.state = .joining(ref)
                writeJoinPushAsync()
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
            //            sync {
            //                if isLeaving {
            //                    left()
            //                    subject.send(.success(.leave))
            //                }
            //            }
            // TODO: What should we do when we get a close?
            Swift.print("Not sure what to do with a close event yet")
            
        default:
            Swift.print("Need to handle \(input.event) types of events soon")
            Swift.print("> \(input)")
        }
    }
    
    private func handle(_ reply: Channel.Reply) {
        sync {
            switch state {
            case .joining(let joinRef):
                guard reply.ref == joinRef,
                    reply.joinRef == joinRef,
                    reply.isOk else {
//                    self.errored(Channel.Error.invalidJoinReply(reply))
                    break
                }
                
                self.state = .joined(joinRef)
                subject.send(.join)
                self.joinTimer = .off
                flushAsync()
                
            case .joined(let joinRef):
                guard let pushed = inFlight[reply.ref],
                      reply.joinRef == joinRef else {
                    return
                }
                
                createPushedMessagesTimer()
                
                backgroundQueue.async {
                    pushed.callback(reply: reply)
                }
                
            case .leaving(let joinRef, let leavingRef):
                guard reply.ref == leavingRef,
                      reply.joinRef == joinRef else {
                    break
                }
                
                self.state = .closed
                subject.send(.leave)
                // TODO: send completion instead if we leave
                // subject.send(completion: Never)
                
            default:
                // sorry, not processing replies in other states
                Swift.print("Received reply that we are not expecting in this state (\(state)): \(reply)")
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

            subject.send(.message(message))
        }
    }
}
