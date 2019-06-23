import Foundation

extension Phoenix {
    internal final class Channel {
        enum State {
            case disconnected
            case joining
            case joined(Ref)
        }
        
        let topic: String
        var state: State = .disconnected
        
        init(topic: String) {
            self.topic = topic
        }
        
        init(topic: String, state: State) {
            self.topic = topic
            self.state = state
        }
        
        var joinRef: Ref? {
            guard case .joined(let ref) = state else { return nil }
            return ref
        }
        
        var isJoined: Bool {
            if case .joined = state {
                return true
            } else {
                return false
            }
        }
        
        func change(to state: State) {
            self.state = state
        }
        
        func makeJoinPush() -> Push {
            return Push(topic: topic, event: .join)
        }
        
        func makeLeavePush() -> Push {
            return Push(topic: topic, event: .leave)
        }
    }
}
