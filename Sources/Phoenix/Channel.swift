import Foundation
import Combine
import Synchronized
import SimplePublisher

public final class Channel: SimplePublisher, Synchronized {
    enum State {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(Ref)
        case errored(Error)
    }
    
    struct PushedMessage {
        let push: Push
        let message: OutgoingMessage
        
        var joinRef: Ref? { message.joinRef }
        
        func successCallback(_ reply: Channel.Reply) {
            push.asyncCallback(result: .success(reply))
        }
    }
    
    private var subscription: Subscription? = nil

    public typealias Output = Result<Channel.Event, Error>
    public typealias Failure = Error

    public var subject = SimpleSubject<Output, Failure>()
    
    let topic: String
    
    var refGenerator: Ref.Generator = Ref.Generator.global
    
    private var state: State
    weak var socket: Socket?
    
    private var pending: [Push] = []
    private var inFlight: [Ref: PushedMessage] = [:]
    
    init(topic: String, socket: Socket) {
        self.topic = topic
        self.state = .closed
        self.socket = socket
    }
    
    convenience init(topic: String, socket: Socket, refGenerator: Ref.Generator) {
        self.init(topic: topic, socket: socket)
        self.refGenerator = refGenerator
    }
    
    var joinRef: Ref? { sync {
        switch state {
        case .joining(let ref):
            return ref
        case .joined(let ref):
            return ref
        case .leaving(let ref):
            return ref
        default:
            return nil
        }
    } }
    
    var joinPush: Socket.Push {
        Socket.Push(topic: topic, event: .join, payload: [:]) { error in
            if let error = error {
                self.state = .errored(error)
            }
        }
    }
    
    var leavePush: Socket.Push {
        Socket.Push(topic: topic, event: .leave, payload: [:]) { error in
            if let error = error {
                self.state = .errored(error)
            }
        }
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
}

// MARK: Writing



extension Channel {
    func join() {
        sync {
            guard isClosed || isErrored else {
                assertionFailure("Can't join unless we are closed or errored")
                return
            }
            
            let ref = refGenerator.advance()
            self.state = .joined(ref)
            
            self.writeJoinPush(ref)
        }
    }
    
    private func send(_ message: OutgoingMessage) {
        send(message) { _ in }
    }
    
    private func send(_ message: OutgoingMessage, completionHandler: @escaping SocketSendCallback) {
        guard let socket = socket else {
            assertionFailure("Can't write if we don't have a socket")
            self.state = .errored(ChannelError.lostSocket)
            return
        }
        
        socket.send(message, completionHandler: completionHandler)
    }
    
    private func writeJoinPush(_ joinRef: Ref) {
        sync {
            let message = OutgoingMessage(joinPush, ref: joinRef)
            
            send(message) { error in
                if let error = error {
                    Swift.print("There was a problem writing to the socket, so going to try to join again after a delay: \(error)")
                    self.writeJoinPushAfterDelay()
                }
            }
        }
    }
    
    private func writeJoinPushAfterDelay() {
        let deadline = DispatchTime.now().advanced(by: .milliseconds(200))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.sync {
                switch self.state {
                case .joining(let joinRef):
                    self.writeJoinPush(joinRef)
                default:
                    self.state = .errored(ChannelError.noLongerJoining)
                }
            }
        }
    }
    
    func rejoin() {
        sync {
            if isJoining || isJoined { return }

            let ref = refGenerator.advance()
            self.state = .joining(ref)
        }
    }
    
    public func leave() {
        sync {
            guard isJoining || isJoined else {
                assertionFailure("Can only leave if we are joining or joined")
                return
            }
            
            let ref = refGenerator.advance()
            let message = OutgoingMessage(leavePush, ref: ref)
            send(message)
            self.state = .leaving(ref)
        }
    }
    
    func left() {
        sync {
            if isClosed || isErrored { return }
        
            self.state = .closed
            subject.send(.success(.leave))
        }
    }

    public func push(_ eventString: String) {
        push(eventString, payload: [String: Any]())
    }

    public func push(_ eventString: String, payload: Payload) {
        push(eventString, payload: payload, callback: nil)
    }

    public func push(_ eventString: String, payload: Payload, callback: Channel.Callback?) {
        sync {
            guard let joinRef = joinRef else {
                assertionFailure("Cannot write if we are not joined")
                return
            }
            
            let push = Channel.Push(channel: self, event: PhxEvent(eventString), payload: payload, callback: callback)
            let ref = refGenerator.advance()
            let message = OutgoingMessage(push, ref: ref, joinRef: joinRef)
            send(message) // TODO: we need to store the callback for the later reply
        }
    }
}

// MARK: :Subscriber

extension Channel: Subscriber {
    public typealias Input = IncomingMessage
    
    public func receive(subscription: Subscription) {
        subscription.request(.unlimited)
        
        sync {
            self.subscription = subscription
        }
    }
    
    public func receive(_ input: IncomingMessage) -> Subscribers.Demand {
        switch input.event {
        case .custom:
            let message = Channel.Message(incomingMessage: input)
            handle(message)
            break
        case .reply:
            if let reply = Channel.Reply(incomingMessage: input) {
                handle(reply)
            } else {
                assertionFailure("Got an unreadable reply")
            }
            break
        default:
            Swift.print("Need to handle \(input.event) types of events soon")
            Swift.print("> \(input)")
            break
        }
        
        return .unlimited
    }
    
    public func receive(completion: Subscribers.Completion<Error>) {
        sync {
            self.subscription = nil
        }
    }
}

// MARK: input handlers

extension Channel {
    private func handle(_ reply: Channel.Reply) {
        sync {
            switch state {
            case .joining(let joinRef):
                guard reply.ref == joinRef && reply.joinRef == joinRef else {
                    self.state = .errored(ChannelError.invalidJoinReply(reply))
                    break
                }
                
                self.state = .joined(joinRef)
                subject.send(.success(.join))
                
            case .joined(let joinRef):
                guard let pushed = inFlight[reply.ref],
                      reply.joinRef == joinRef else {
                    return
                }
                
                pushed.successCallback(reply)
                
            case .leaving(let ref):
                // TODO: do we need to also check the joinRef to make sure we don't get a left reply from a previous leave?
                guard reply.ref == ref else {
                    break
                }
                
                self.state = .closed
                subject.send(.success(.leave))
                
            default:
                // sorry, not processing replies in other states
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

            subject.send(.success(.message(message)))
        }
    }
}
