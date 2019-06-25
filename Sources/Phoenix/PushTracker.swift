import Foundation

// TODO: Maybe add a timestamp to sent pushes so that we don't retry the same one
// multiple times in quick succession.
internal final class PushTracker {
    private struct MessageID: Hashable {
        let joinRef: Ref
        let ref: Ref
        let topic: String
        let eventName: String
        
        init(joinRef: Ref, ref: Ref, topic: String, eventName: String) {
            self.joinRef = joinRef
            self.ref = ref
            self.topic = topic
            self.eventName = eventName
        }
        
        init(from message: OutgoingMessage) {
            self.init(
                joinRef: message.joinRef,
                ref: message.ref,
                topic: message.topic,
                eventName: message.event.stringValue
            )
        }
        
        init?(from message: IncomingMessage) {
            guard let joinRef = message.joinRef else { return nil }
            guard let ref = message.ref else { return nil }
            
            self.init(
                joinRef: joinRef,
                ref: ref,
                topic: message.topic,
                eventName: message.event.stringValue
            )
        }
    }
    
    private let _queue = DispatchQueue(label: "Phoenix.PushTracker._queue")
    private var _pendingPushes = Array<Push>()
    private var _inProgressMessages = Dictionary<MessageID, OutgoingMessage>()
    
    func push(_ push: Push) {
        _queue.sync { _pendingPushes.append(push) }
    }
    
    func process(cb: (Push) -> OutgoingMessage?) {
        _queue.sync {
            let workingArray = _pendingPushes
            _pendingPushes.removeAll()
            
            workingArray.forEach { push in
                if let message = cb(push) {
                    let id = MessageID(from: message)
                    _inProgressMessages[id] = message
                } else {
                    // put it back in the pending array if we cannot currently convert to an outgoing message
                    _pendingPushes.append(push)
                }
            }
        }
    }
    
    func find(related: IncomingMessage) -> OutgoingMessage? {
        guard let id = MessageID(from: related) else { return nil }
        
        return _queue.sync {
            return _inProgressMessages[id]
        }
    }
    
    func cleanup(related: IncomingMessage) {
        guard let id = MessageID(from: related) else { return }
        
        _queue.sync {
            _inProgressMessages[id] = nil
        }
    }
}

