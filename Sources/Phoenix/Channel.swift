import Foundation
import Combine
import Synchronized
import SimplePublisher
import Atomic



public final class Channel: Synchronized {
    public enum Error: Swift.Error {
        case invalidJoinReply(Channel.Reply)
        case isClosed
        case lostSocket
        case noLongerJoining
    }
    
    enum State {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(joinRef: Ref, leavingRef: Ref)
        case errored(Swift.Error)
    }
    
    struct PushedMessage {
        let push: Push
        let message: OutgoingMessage
        
        var joinRef: Ref? { message.joinRef }
        
        func callback(reply: Channel.Reply) {
            push.asyncCallback(result: .success(reply))
        }
        
        func callback(error: Swift.Error) {
            push.asyncCallback(result: .failure(error))
        }
    }
    
    public typealias Output = Result<Channel.Event, Swift.Error>
    public typealias Failure = Swift.Error

    private lazy var internalSubscriber: DelegatingSubscriber<Channel> = {
        DelegatingSubscriber(delegate: self)
    }()
    
    private var subject = SimpleSubject<Output, Failure>()
    private var refGenerator = Ref.Generator.global
    private var pending: [Push] = []
    private var inFlight: [Ref: PushedMessage] = [:]
    
    private var waitToFlush: Int = 0
    
    private var shouldRejoin = true
    private var state: State = .closed
    
    weak var socket: Socket?
    
    public let topic: String
    public let joinPayload: Payload
    
    // NOTE: init shouldn't be public because we want Socket to always have a record of the channels that have been created in it's dictionary
    init(topic: String, socket: Socket, joinPayload: Payload = [:]) {
        self.topic = topic
        self.socket = socket
        self.joinPayload = joinPayload
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
        case .leaving(let joinRef, _):
            return joinRef
        default:
            return nil
        }
    } }
    
    var joinPush: Socket.Push {
        Socket.Push(topic: topic, event: .join, payload: joinPayload) { _ in }
    }
    
    var leavePush: Socket.Push {
        Socket.Push(topic: topic, event: .leave, payload: [:]) { _ in }
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
    // TODO: make join public
    func join() {
        sync {
            guard isClosed || isErrored || isLeaving else {
                assertionFailure("Can't join unless we are closed, errored, or leaving")
                return
            }
            
            let ref = refGenerator.advance()
            self.state = .joining(ref)
        }
        
        DispatchQueue.global().async {
            self.writeJoinPush()
        }
    }
    
    private func send(_ message: OutgoingMessage) {
        send(message) { _ in }
    }
    
    private func send(_ message: OutgoingMessage, completionHandler: @escaping Socket.Callback) {
        guard let socket = socket else {
            self.state = .errored(Channel.Error.lostSocket)
            publish(.failure(Channel.Error.lostSocket))
            completionHandler(Channel.Error.lostSocket)
            return
        }
        
        socket.send(message, completionHandler: completionHandler)
    }
    
    private func writeJoinPush() {
        sync {
            switch self.state {
            case .joining(let joinRef):
                let message = OutgoingMessage(joinPush, ref: joinRef, joinRef: joinRef)
                
                send(message) { error in
                    if let error = error {
                        Swift.print("There was a problem writing to the socket, so going to try to join again after a delay: \(error)")
                        self.writeJoinPushAfterDelay()
                    }
                }
            default:
                self.state = .errored(Channel.Error.noLongerJoining)
            }
        }
    }
    
    private func writeJoinPushAfterDelay() {
        writeJoinPushAfterDelay(milliseconds: 200)
    }
    
    private func writeJoinPushAfterDelay(milliseconds: Int) {
        let deadline = DispatchTime.now().advanced(by: .milliseconds(milliseconds))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.writeJoinPush()
        }
    }
    
    func rejoin() {
        sync {
            if !shouldRejoin || isJoining || isJoined { return }

            let ref = refGenerator.advance()
            self.state = .joining(ref)
            
            DispatchQueue.global().async {
                self.writeJoinPush()
            }
        }
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
            default:
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
            subject.send(.failure(error))
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
            let push = Channel.Push(
                channel: self,
                event: PhxEvent(eventString),
                payload: payload,
                callback: callback
            )
            
            pending.append(push)
        }
        
        DispatchQueue.global().async {
            self.flushNow()
        }
    }
    
    private func flush() {
        assert(waitToFlush == 0)
        
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
                        // no longer in flight
                        self.inFlight[ref] = nil
                        // put it back to retry later
                        self.pending.append(push)
                        // flush again in a bit
                        self.flushAfterDelay()
                    }
                } else {
                    self.flushNow()
                }
            }
        }
    }
    
    private func flushNow() {
        sync {
            guard waitToFlush == 0 else { return }
        }
        DispatchQueue.global().async { self.flush() }
    }
    
    private func flushAfterDelay() {
        flushAfterDelay(milliseconds: 200)
    }
    
    private func flushAfterDelay(milliseconds: Int) {
        sync {
            guard waitToFlush == 0 else { return }
            self.waitToFlush = milliseconds
        }
        
        let deadline = DispatchTime.now().advanced(by: .milliseconds(waitToFlush))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.sync {
                self.waitToFlush = 0
                self.flushNow()
            }
        }
    }
}

// MARK: :Publisher

extension Channel: Publisher {
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input {
        subject.receive(subscriber: subscriber)
    }
    
    func publish(_ output: Output) {
        subject.send(output)
    }
    
    func complete() {
        complete(.finished)
    }
    
    func complete(_ failure: Failure) {
        complete(.failure(failure))
    }
    
    func complete(_ completion: Subscribers.Completion<Failure>) {
        subject.send(completion: completion)
    }
}

// MARK: :Subscriber

extension Channel: DelegatingSubscriberDelegate {
    typealias Input = IncomingMessage
    
    func internallySubscribe<P>(_ publisher: P)
        where P: Publisher, Input == P.Output, Failure == P.Failure {
        publisher.subscribe(internalSubscriber)
    }
    
    func receive(_ input: Input) {
        Swift.print("channel input", input)
        
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
    
    func receive(completion: Subscribers.Completion<Swift.Error>) {
        internalSubscriber.cancel()
    }
}

// MARK: input handlers

extension Channel {
    private func handle(_ reply: Channel.Reply) {
        sync {
            switch state {
            case .joining(let joinRef):
                guard reply.ref == joinRef && reply.joinRef == joinRef else {
                    self.state = .errored(Channel.Error.invalidJoinReply(reply))
                    break
                }
                
                self.state = .joined(joinRef)
                subject.send(.success(.join))
                flushNow()
                
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
                subject.send(.success(.leave))
                
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

            subject.send(.success(.message(message)))
        }
    }
}
