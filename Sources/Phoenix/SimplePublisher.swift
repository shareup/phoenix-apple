import Foundation
import Combine
import Synchronized

protocol SimplePublisher: Publisher, Synchronized {
    var subscriptions: [SimpleSubscription<Output, Failure>] { get set }
}

extension SimplePublisher {
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = SimpleSubscription(subscriber: AnySubscriber(subscriber))
        subscriber.receive(subscription: subscription)
        
        sync {
            subscriptions.append(subscription)
        }
    }
    
    func publish(_ output: Output) {
        var subscriptions = [SimpleSubscription<Output, Failure>]()
        
        sync {
            subscriptions = self.subscriptions
        }
        
        for subscription in subscriptions {
            guard let demand = subscription.demand else { continue }
            guard demand > 0 else { continue }
            
            let newDemand = subscription.subscriber.receive(output)
            subscription.request(newDemand)
        }
    }
    
    func complete() {
        complete(.finished)
    }
    
    func complete(_ failure: Failure) {
        complete(.failure(failure))
    }
    
    func complete(_ failure: Subscribers.Completion<Failure>) {
        var subscriptions = [SimpleSubscription<Output, Failure>]()
        
        sync {
            subscriptions = self.subscriptions
            self.subscriptions.removeAll()
        }
        
        for subscription in subscriptions {
            subscription.subscriber.receive(completion: failure)
        }
    }
}
