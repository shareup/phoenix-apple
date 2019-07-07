import Foundation

final class PushTracker {
    private let _queue = DispatchQueue(label: "Phoenix.PushTracker._queue")
    private var _pendingPushes: [Push] = []
    private var _inProgressMessages: [Ref: OutgoingMessage] = [:]
    
    func push(_ push: Push) {
        _queue.sync { _pendingPushes.append(push) }
    }
    
    func process(cb: (Push) -> OutgoingMessage?) {
        _queue.sync {
            let workingArray = _pendingPushes
            _pendingPushes.removeAll()
            
            workingArray.forEach { push in
                if let message = cb(push) {
                    _inProgressMessages[message.ref] = message
                } else {
                    // put it back in the pending array if we cannot currently convert to an outgoing message
                    _pendingPushes.append(push)
                }
            }
        }
    }
    
    func find(related: IncomingMessage) -> OutgoingMessage? {
        guard let id = related.ref else { return nil }
        
        return _queue.sync {
            return _inProgressMessages[id]
        }
    }
    
    func cleanup(related: IncomingMessage) {
        guard let id = related.ref else { return }
        
        _queue.sync {
            _inProgressMessages[id] = nil
        }
    }
}

