import Foundation

internal final class Channel {
    private let _queue = DispatchQueue(label: "Phoenix.Channel._queue")
    
    enum State {
        case new
        case closed
        case joining
        case joined(Ref)
        case leaving
        case errored(Error)
    }
    
    let topic: String
    private var _state: State = .new
    
    init(topic: String) {
        self.topic = topic
    }
    
    init(topic: String, state: State) {
        self.topic = topic
        self._state = state
    }
    
    var joinRef: Ref? { _queue.sync {
        guard case let .joined(ref) = _state else { return nil }
        return ref
    } }
    
    var isClosed: Bool { _queue.sync {
        guard case .closed = _state else { return false }
        return true
    } }
    
    var isJoining: Bool { _queue.sync {
        guard case .joining = _state else { return false }
        return true
    } }
    
    var isJoined: Bool { _queue.sync {
        guard case .joined = _state else { return false }
        return true
    } }
    
    var isLeaving: Bool { _queue.sync {
        guard case .leaving = _state else { return false }
        return true
    } }
    
    var isErrored: Bool { _queue.sync {
        guard case .errored = _state else { return false }
        return true
    } }
    
    internal func change(to state: State) { _queue.sync {
        self._state = state
    } }
    
    func makeJoinPush() -> Push {
        return Push(topic: topic, event: .join)
    }
    
    func makeLeavePush() -> Push {
        return Push(topic: topic, event: .leave)
    }
}
