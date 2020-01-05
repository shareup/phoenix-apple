import Foundation

extension Channel {
    public typealias Callback = (Result<Channel.Reply, Swift.Error>) -> ()

    struct Push {    
        let channel: Channel
        let event: PhxEvent
        let payload: Payload
        let timeout: Double = 5.0 // in seconds
        let callback: Callback?
        
        init(channel: Channel, event: PhxEvent, callback: Callback? = nil) {
            self.init(channel: channel, event: event, payload: [String: String](), callback: callback)
        }
        
        init(channel: Channel, event: PhxEvent, payload: Payload, callback: Callback? = nil) {
            self.channel = channel
            self.event = event
            self.payload = payload
            self.callback = callback
        }

        func asyncCallback(result: Result<Channel.Reply, Swift.Error>) {
            if let cb = callback {
                DispatchQueue.global().async { cb(result) }
            }
        }
    }
}
