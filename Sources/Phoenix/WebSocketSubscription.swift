import Foundation
import Combine
import Synchronized

class WebSocketSubscription: Subscription, Synchronized {
    let subscriber: AnySubscriber<Result<WebSocket.Message, Error>, Error>
    var demand: Subscribers.Demand? = nil
    
    init(subscriber: AnySubscriber<Result<WebSocket.Message, Error>, Error>) {
        self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
        sync { self.demand = demand }
    }
    
    func cancel() {
        sync { self.demand = nil }
    }
}
