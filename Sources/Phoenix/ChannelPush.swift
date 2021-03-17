import Foundation

extension Channel {
    public typealias Callback = (Result<Channel.Reply, Swift.Error>) -> ()

    struct Push {    
        let channel: Channel
        let event: PhxEvent
        let payload: Payload
        let timeout: DispatchTimeInterval
        let callback: Callback?
        
        init(channel: Channel, event: PhxEvent, timeout: DispatchTimeInterval, callback: Callback? = nil) {
            self.init(channel: channel, event: event, payload: [String: String](), timeout: timeout, callback: callback)
        }
        
        init(channel: Channel, event: PhxEvent, payload: Payload, timeout: DispatchTimeInterval, callback: Callback? = nil) {
            self.channel = channel
            self.event = event
            self.payload = payload
            self.timeout = timeout
            self.callback = callback
        }

        func asyncCallback(result: Result<Channel.Reply, Swift.Error>) {
            if let cb = callback {
                DispatchQueue.backgroundQueue.async { cb(result) }
            }
        }
    }
}
