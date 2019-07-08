import Foundation
import Combine
import Synchronized

public final class Channel: Synchronized {
    enum State {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(Ref)
        case errored(Error)
    }
    
    enum Errors: Error {
        case invalidJoinReply(Channel.Reply)
    }
    
    private var subscription: Subscription? = nil
    private var pendingPushes: [Channel.Push] = []
    private var trackedPushes: [Ref: (OutgoingMessage, Channel.Push)] = [:]
    private var willFlushLater: Bool = false
    
    var subscriptions = [SimpleSubscription<Output, Failure>]()
    
    let topic: String
    
    private var state: State
    private let socket: Socket
    
    init(topic: String, socket: Socket) {
        self.topic = topic
        self.state = .closed
        self.socket = socket
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
    
    var joinPush: Channel.Push {
        Channel.Push(channel: self, event: .join)
    }
    
    var leavePush: Channel.Push {
        Channel.Push(channel: self, event: .leave)
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
    public func push(_ eventString: String, payload: Payload, callback: @escaping (Channel.Reply) -> Void) {
        let event = PhxEvent.custom(eventString)
        let push = Channel.Push(channel: self, event: event, payload: payload, callback: callback)
        
        sync {
            pendingPushes.append(push)
        }

        DispatchQueue.global().async { self.flush() }
    }
    
    public func join() {
        sync {
            guard isClosed || isErrored else {
                assertionFailure("Can't join unless we are closed or errored")
                return
            }
            
            guard socket.isOpen else {
                assertionFailure("Socket isn't open, cannot attempt to join")
                return
            }
        }
        
        let ref = socket.generator.advance()
        
        change(to: .joining(ref))
        
        let message = OutgoingMessage(joinPush, ref: ref)
        
        socket.send(message) { error in
            if let error = error {
                self.change(to: .errored(error))
            }
        }
    }
    
    public func leave() {
        sync {
            guard isJoining || isJoined else {
                assertionFailure("Can only leave if we are joining or joined")
                return
            }
        }
        
        let ref = socket.generator.advance()
        
        change(to: .leaving(ref))
        
        let message = OutgoingMessage(leavePush, ref: ref)
        
        socket.send(message) { error in
            if let error = error {
                self.change(to: .errored(error))
            }
        }
    }
    
    private func flushLater() {
        sync {
            guard !willFlushLater else { return }
            willFlushLater = true
        }
        
        // TODO: make deadline smart
        let deadline = DispatchTime.now().advanced(by: .seconds(2))
        
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.flush()
        }
    }
    
    private func flush() {
        sync {
            guard isJoined else {
                flushLater()
                return
            }
        }
        
        var pending: [Channel.Push] = []
        
        sync {
            pending = pendingPushes
            pendingPushes.removeAll()
        }
        
        for push in pending { flushOne(push) }
        
        sync {
            if pendingPushes.count > 1 {
                flushLater()
            }
        }
    }
    
    private func flushOne(_ push: Channel.Push) {
        sync {
            guard isJoined else {
                pendingPushes.append(push) // re-insert
                return
            }
        }
        
        let ref = socket.generator.advance()
        let message = OutgoingMessage(push, ref: ref)
        
        socket.send(message) { error in
            if let error = error {
                self.change(to: .errored(error))
            }
        }
    }
}

// MARK: :Subscriber

extension Channel: Subscriber {
    public typealias Input = IncomingMessage
    public typealias Failure = Error
    
    public func receive(subscription: Subscription) {
        subscription.request(.unlimited)
        
        sync {
            self.subscription = subscription
        }
    }
    
    public func receive(_ input: IncomingMessage) -> Subscribers.Demand {
        // TODO: where to send this?
        Swift.print("input: \(String(describing: input))")
        
        if let reply = Channel.Reply(incomingMessage: input) {
            handle(reply)
        } else {
            let message = Channel.Message(incomingMessage: input)
            handle(message)
        }
        
        return .unlimited
    }
    
    public func receive(completion: Subscribers.Completion<Error>) {
        sync {
            self.subscription = nil
        }
    }
}

// MARK: :Publisher

extension Channel: SimplePublisher {
    public typealias Output = Result<Channel.Event, Error>
}

// MARK: input handlers

extension Channel {
    private func handle(_ reply: Channel.Reply) {
        sync {
            switch state {
            case .joining(let joinRef):
                guard reply.ref == joinRef && reply.joinRef == joinRef else {
                    change(to: .errored(Errors.invalidJoinReply(reply)))
                    break
                }
                
                change(to: .joined(joinRef))
                publish(.success(.join))
                
            case .joined(let joinRef):
                guard let (_, push) = trackedPushes[reply.ref],
                    reply.joinRef == joinRef else {
                    break
                }
                
                DispatchQueue.global().async {
                    push.callback?(reply)
                }
                
                trackedPushes[reply.ref] = nil
                
            case .leaving(let ref):
                guard reply.ref == ref else {
                    break
                }
                
                change(to: .closed)
                publish(.success(.leave))
                
            default:
                // sorry, not processing replies in other states
                break
            }
        }
    }
    
    private func handle(_ message: Channel.Message) {
        Swift.print("Would have published out \(message)")
    }
}
