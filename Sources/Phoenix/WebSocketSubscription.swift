import Foundation
import Combine

class WebSocketSubscription: Subscription {
    let subscriber: AnySubscriber<Result<WebSocket.Message, Error>, Error>
    var demand: Subscribers.Demand? = nil
    
    private let _queue = DispatchQueue(label: "Phoenix.WebSocketSubscription._queue")
    
    init(subscriber: AnySubscriber<Result<WebSocket.Message, Error>, Error>) {
        self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
        _queue.sync {
            self.demand = demand
        }
    }
    
    func cancel() {
        _queue.sync {
            self.demand = nil
        }
    }
}
