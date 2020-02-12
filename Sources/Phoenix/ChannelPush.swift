import Foundation

extension Channel {
    public typealias Callback = (Result<Channel.Reply, Swift.Error>) -> ()

    struct Push {    
        let channel: Channel
        let event: PhxEvent
        let payload: Payload
        let timeout: TimeInterval
        let callback: Callback?
        
        init(channel: Channel, event: PhxEvent, timeout: Double? = nil, callback: Callback? = nil) {
            self.init(channel: channel, event: event, payload: [String: String](), timeout: timeout, callback: callback)
        }
        
        init(channel: Channel, event: PhxEvent, payload: Payload, timeout: Double? = nil, callback: Callback? = nil) {
            self.channel = channel
            self.event = event
            self.payload = payload
            self.timeout = timeout ?? channel.timeout
            self.callback = callback
        }

        func asyncCallback(result: Result<Channel.Reply, Swift.Error>) {
            if let cb = callback {
                DispatchQueue.global().async { cb(result) }
            }
        }
    }
}
