import Foundation

extension Channel {
    struct Push {
        typealias Callback = (Channel.Reply) -> ()
        
        let channel: Channel
        let event: Event
        let payload: Payload
        let timeout: Double = 5.0 // in seconds
        let callback: Callback?
        
        init(channel: Channel, event: Event, callback: Callback? = nil) {
            self.init(channel: channel, event: event, payload: [String: String](), callback: callback)
        }
        
        init(channel: Channel, event: Event, payload: Payload, callback: Callback? = nil) {
            self.channel = channel
            self.event = event
            self.payload = payload
            self.callback = callback
        }
    }
}
