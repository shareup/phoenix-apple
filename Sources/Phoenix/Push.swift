import Foundation

public struct Push {
    public typealias Callback = (Reply) -> ()

    public let topic: String
    public let event: Event
    public let payload: Payload
    public let timeout: Double = 5.0 // in seconds
    public let callback: Callback?
    
    init(topic: String, event: Event, callback: Callback? = nil) {
        self.init(topic: topic, event: event, payload: [:], callback: callback)
    }
    
    init(topic: String, event: Event, payload: Payload, callback: Callback? = nil) {
        self.topic = topic
        self.event = event
        self.payload = payload
        self.callback = callback
    }
}

