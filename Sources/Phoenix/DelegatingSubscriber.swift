import Foundation
import Combine
import Synchronized

protocol DelegatingSubscriberDelegate: class {
    associatedtype SubscriberInput
    associatedtype SubscriberFailure: Error
    
    func receive(_ input: SubscriberInput)
    func receive(completion: Subscribers.Completion<SubscriberFailure>)
}

class DelegatingSubscriber<D: DelegatingSubscriberDelegate>: Subscriber, Synchronized {
    weak var delegate: D?
    private var subscription: Subscription?
    
    typealias Input = D.SubscriberInput
    typealias Failure = D.SubscriberFailure
    
    init(delegate: D) {
        self.delegate = delegate
    }

    func receive(subscription: Subscription) {
        subscription.request(.unlimited)

        sync {
            self.subscription = subscription
        }
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        delegate?.receive(input)
        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        delegate?.receive(completion: completion)
    }
    
    func cancel() {
        sync {
            self.subscription?.cancel()
            self.subscription = nil
        }
    }
}
