import Foundation

extension Phoenix {
    struct OutgoingMessage {
        let joinRef: Ref
        let ref: Ref
        let push: Push
        let sentAt: Date = Date()
        
        var topic: String { push.topic }
        var event: Event { push.event }
        var payload: Payload { push.payload }
        
        func encoded() throws -> Data {
            return try JSONSerialization.data(withJSONObject: asArray(), options: [])
        }
        
        private func asArray() -> Array<Any?> {
            return [
                joinRef,
                ref,
                topic,
                event.stringValue,
                payload
            ]
        }
    }
}
