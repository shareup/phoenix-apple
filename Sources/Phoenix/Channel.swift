import Combine
import Foundation
import SimplePublisher
import Synchronized

public final class Channel: Synchronized {
    typealias JoinPayloadBlock = () -> Payload
    
    private var subject = SimpleSubject<Output, Failure>()
    private var refGenerator = Ref.Generator.global
    private var pending: [Push] = []
    private var inFlight: [Ref: PushedMessage] = [:]
    
    private var shouldRejoin = true
    private var state: State = .closed
    
    private weak var socket: Socket?
    
    // TODO: just know it's going to be a certain type that is Cancellable so we can cancel it
    private var socketSubscriber: AnySubscriber<SubscriberInput, SubscriberFailure>?
    
    private var customTimeout: TimeInterval? = nil
    
    public var timeout: TimeInterval {
        if let customTimeout = customTimeout {
            return customTimeout
        } else if let socket = socket {
            return socket.timeout
        } else {
            return Socket.defaultTimeout
        }
    }
    
    private var pushedMessagesTimer: Timer?
    
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
        
        self.socketSubscriber = internallySubscribe(
            socket.compactMap { message in
                switch message {
                case .closing, .connecting, .unreadableMessage, .websocketError:
                    return nil // not interesting
                case .close:
                    return .socketClose
                case .open:
                    return .socketOpen
                case .incomingMessage(let message):
                    guard message.topic == topic else {
                        return nil
                    }
                    
                    return .channelMessage(message)
                }
            }
        )
    }
    
    enum InterestingMessage {
        case socketClose
        case socketOpen
        case channelMessage(IncomingMessage)
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

// MARK: Writing

extension Channel {
    public func join(timeout customTimeout: TimeInterval) {
        self.customTimeout = customTimeout
        join()
    }
    
    public func join() {
        rejoin()
    }
    
    
    private func rejoin() {
        sync {
            guard shouldRejoin else { return }
            
            switch state {
            case .joining, .joined:
                return
            case .closed, .errored, .leaving:
                let ref = refGenerator.advance()
                self.state = .joining(ref)
                
                DispatchQueue.global().async {
                    self.writeJoinPush()
                }
            }
        }
    }
    
    private func send(_ message: OutgoingMessage) {
        send(message) { _ in }
    }
    
    private func send(_ message: OutgoingMessage, completionHandler: @escaping Socket.Callback) {
        guard let socket = socket else {
            self.errored(Channel.Error.lostSocket)
            completionHandler(Channel.Error.lostSocket)
            return
        }
        
        socket.send(message) { error in
            if let error = error {
                Swift.print("There was an error writing to the socket: \(error)")
//                self.errored(error)
            }
            
            completionHandler(error)
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
                    }
                }
            default:
                self.errored(Channel.Error.noLongerJoining)
            }
        }
    }
    
    private func writeJoinPushAsync() {
        DispatchQueue.global().async {
            self.writeJoinPush()
        }
    }
    
    public func leave(timeout: TimeInterval) {
        self.customTimeout = timeout
        leave()
    }
    
    public func leave() {
        sync {
            self.shouldRejoin = false
            
            switch state {
            case .joining(let joinRef), .joined(let joinRef):
                let ref = refGenerator.advance()
                let message = OutgoingMessage(leavePush, ref: ref, joinRef: joinRef)
                self.state = .leaving(joinRef: joinRef, leavingRef: ref)
                
                DispatchQueue.global().async {
                    self.send(message)
                }
            case .leaving, .errored, .closed:
                Swift.print("Can only leave if we are joining or joined, currently \(state)")
                return
            }
        }
    }
    
    func remoteClosed(_ error: Swift.Error) {
        sync {
            if isClosed && !shouldRejoin { return }
            errored(error)
        }
    }
    
    func errored(_ error: Swift.Error) {
        sync {
            self.state = .errored(error)
            subject.send(.error(error))
        }
    }
    
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
    
    private func flush() {
        sync {
            guard case .joined(let joinRef) = state else { return }
            
            guard let push = pending.first else { return }
            self.pending = Array(self.pending.dropFirst())
            
            let ref = refGenerator.advance()
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
        DispatchQueue.global().async { self.flush() }
    }
    
    private func timeoutPushedMessages() {
        sync {
            if let pushedMessagesTimer = pushedMessagesTimer {
                self.pushedMessagesTimer = nil
                pushedMessagesTimer.invalidate()
            }
            
            guard !inFlight.isEmpty else { return }
            
            let now = Date()
        
            let messages = inFlight.values.sorted().filter {
                $0.timeoutDate < now
            }
            
            for message in messages {
                inFlight[message.ref] = nil
                message.callback(error: Error.timeout)
            }
            
            createPushedMessagesTimer()
        }
    }
    
    private func createPushedMessagesTimer() {
        sync {
            guard !inFlight.isEmpty,
                pushedMessagesTimer == nil else {
                    return
            }
            
            let possibleNext = inFlight.values.sorted().first
            
            guard let next = possibleNext else { return }
            
            self.pushedMessagesTimer = Timer(fire: next.timeoutDate, interval: 0, repeats: false) { _ in
                self.timeoutPushedMessagesAsync()
            }
        }
    }
    
    private func timeoutPushedMessagesAsync() {
        DispatchQueue.global().async { self.timeoutPushedMessages() }
    }
}

// MARK: :Publisher

extension Channel: Publisher {
    public typealias Output = Channel.Event
    public typealias Failure = Never
    
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input {
        subject.receive(subscriber: subscriber)
    }
    
    func publish(_ output: Output) {
        subject.send(output)
    }
}

// MARK: :Subscriber

extension Channel: DelegatingSubscriberDelegate {
    typealias SubscriberInput = InterestingMessage
    typealias SubscriberFailure = Never
    
    func receive(_ input: SubscriberInput) {
        Swift.print("channel input", input)
        
        switch input {
        case .channelMessage(let message):
            handle(message)
        case .socketOpen:
            handleSocketOpen()
        case .socketClose:
            handleSocketClose()
        }
    }
    
    func receive(completion: Subscribers.Completion<SubscriberFailure>) {
        assertionFailure("Socket Failure = Never, should never complete")
    }
}

// MARK: input handlers

extension Channel {
    private func handleSocketOpen() {
        sync {
            switch state {
            case .joining:
                writeJoinPushAsync()
            case .errored:
                let ref = refGenerator.advance()
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
                    self.errored(Channel.Error.invalidJoinReply(reply))
                    break
                }
                
                self.state = .joined(joinRef)
                subject.send(.join)
                flushAsync()
                
            case .joined(let joinRef):
                guard let pushed = inFlight[reply.ref],
                      reply.joinRef == joinRef else {
                    return
                }
                
                pushed.callback(reply: reply)
                
            case .leaving(let joinRef, let leavingRef):
                guard reply.ref == leavingRef,
                      reply.joinRef == joinRef else {
                    break
                }
                
                self.state = .closed
                subject.send(.leave)
                // TODO: send completion instead if we leave
//                subject.send(completion: Never)
                
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
