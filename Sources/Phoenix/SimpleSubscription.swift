import Foundation
import Combine
import Synchronized

class SimpleSubscription<Input, Failure: Error>: Subscription, Synchronized {
    let subscriber: AnySubscriber<Input, Failure>
    var demand: Subscribers.Demand? = nil
    
    init(subscriber: AnySubscriber<Input, Failure>) {
        self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
        sync { self.demand = demand }
    }
    
    func cancel() {
        sync { self.demand = nil }
    }
}
