import Foundation
import Combine

public final class Channel {
    private var _subscription: Subscription? = nil
    
    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix.WebSocket._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)
    
    enum State {
        case closed
        case joining
        case joined(Ref)
        case leaving
        case errored(Error)
    }
    
    let topic: String
    private var _state: State
    
    convenience init(topic: String) {
        self.init(topic: topic, state: .closed)
    }
    
    init(topic: String, state: State) {
        self.topic = topic
        self._state = state
    }
    
    var joinRef: Ref? { sync {
        guard case let .joined(ref) = _state else { return nil }
        return ref
    } }
    
    public var isClosed: Bool { sync {
        guard case .closed = _state else { return false }
        return true
    } }
    
    public var isJoining: Bool { sync {
        guard case .joining = _state else { return false }
        return true
    } }
    
    public var isJoined: Bool { sync {
        guard case .joined = _state else { return false }
        return true
    } }
    
    public var isLeaving: Bool { sync {
        guard case .leaving = _state else { return false }
        return true
    } }
    
    public var isErrored: Bool { sync {
        guard case .errored = _state else { return false }
        return true
    } }
    
    func change(to state: State) { sync {
        self._state = state
    } }
    
    func makeJoinPush() -> Push {
        return Push(topic: topic, event: .join)
    }
    
    func makeLeavePush() -> Push {
        return Push(topic: topic, event: .leave)
    }
}

extension Channel {
    public func push(_ eventString: String, payload: Payload, completionHandler: @escaping Push.Callback) {
        // let event = Event.custom(eventString)
        
    }
}

extension Channel: Subscriber {
    public typealias Input = IncomingMessage
    public typealias Failure = Error
    
    public func receive(subscription: Subscription) {
        subscription.request(.unlimited)
        _subscription = subscription
    }
    
    public func receive(_ input: IncomingMessage) -> Subscribers.Demand {
        // TODO: where to send this?
        print("input: \(String(describing: input))")
        
//        switch input.event {
//            
//        }
        
        return .unlimited
    }
    
    public func receive(completion: Subscribers.Completion<Error>) {
        _subscription = nil
    }
}

extension Channel {
    private func sync<T>(_ block: () throws -> T) rethrows -> T {
        if isSynced {
            return try block()
        } else {
            return try _synchronizationQueue.sync(execute: block)
        }
    }
    
    private func sync(_ block: () throws -> Void) rethrows {
        if isSynced {
            try block()
        } else {
            try _synchronizationQueue.sync(execute: block)
        }
    }
    
    private var isSynced: Bool {
        return DispatchQueue.getSpecific(key: _queueKey) == _queueContext
    }
    
    private func async(_ block: @escaping () -> Void) {
        _synchronizationQueue.async(execute: block)
    }
}
