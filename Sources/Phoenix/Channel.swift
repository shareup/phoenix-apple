import Foundation
import Combine
import Synchronized

public final class Channel: Publisher, Synchronized {
    enum State {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(Ref)
        case errored(Error)
    }
    
    private var subscription: Subscription? = nil
    // TODO: sweep this dictionary periodically
    private var tracked: [Ref: Channel.Push] = [:]

    public typealias Output = Result<Channel.Event, Error>
    public typealias Failure = Error

    var subject = PassthroughSubject<Output, Failure>()

    public func receive<S>(subscriber: S)
        where S : Subscriber, Failure == S.Failure, Output == S.Input {
            subject.receive(subscriber: subscriber)
    }
    
    let topic: String
    
    private var state: State
    private let pusher: Pusher
    
    init(topic: String, pusher: Pusher) {
        self.topic = topic
        self.state = .closed
        self.pusher = pusher
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
                self.change(to: .errored(error))
            }
        }
    }
    
    var leavePush: Socket.Push {
        Socket.Push(topic: topic, event: .leave, payload: [:]) { error in
            if let error = error {
                self.change(to: .errored(error))
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
    
    func change(to state: State) { sync {
        self.state = state
    } }
}

// MARK: Writing

extension Channel {
    public func join() {
        sync {
            guard isClosed || isErrored else {
                assertionFailure("Can't join unless we are closed or errored")
                return
            }
            
            let ref = pusher.send(joinPush)
            change(to: .joining(ref))
        }
    }
    
    public func leave() {
        sync {
            guard isJoining || isJoined else {
                assertionFailure("Can only leave if we are joining or joined")
                return
            }
            
            let ref = pusher.send(leavePush)
            change(to: .leaving(ref))
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
            let push = Channel.Push(channel: self, event: PhxEvent(eventString), payload: payload, callback: callback)

            // NOTE: the new contract is that when one "sends to the pusher"
            //       one gets back the ref so one can track replies later
            //       and one can assume the push is sent very soon
            let ref = pusher.send(push)
            self.tracked[ref] = push
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
        // TODO: where to send this?
        Swift.print("input: \(String(describing: input))")
        
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
                    change(to: .errored(ChannelError.invalidJoinReply(reply)))
                    break
                }
                
                change(to: .joined(joinRef))
                subject.send(.success(.join))
                
            case .joined(let joinRef):
                guard let push = tracked[reply.ref],
                    reply.joinRef == joinRef else {
                    break
                }

                push.asyncCallback(result: .success(reply))
                tracked[reply.ref] = nil
                
            case .leaving(let ref):
                guard reply.ref == ref else {
                    break
                }
                
                change(to: .closed)
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
