import Foundation
import Combine

//class Heartbeater: Subscriber {
//    typealias Input = IncomingMessage
//    typealias Failure = Error
//
//    let push = Push(topic: "phoenix", event: .heartbeat)
//
//    private var _subscription: Subscription? = nil
//
//    var lastSentAt: Date = Date()
//    var lastReceivedAt: Date = Date()
//    var count: UInt64 = 0
//    var lastRef: UInt64? = nil
//
//    var isSubscribed: Bool {
//        get { _subscription != nil }
//    }
//
//    func pushData(ref: UInt64) -> Data {
//        lastRef = ref
//
//        let arr: [Any?] = [
//            nil,
//            ref,
//            push.topic,
//            push.event.stringValue,
//            [:]
//        ]
//
//        let data = try! JSONSerialization.data(withJSONObject: arr, options: [])
//
//        print("Data on the wire: \(String(describing: String(data: data, encoding: .utf8)))")
//
//        return data
//    }
//
//    func receive(subscription: Subscription) {
//        subscription.request(.unlimited)
//        _subscription = subscription
//    }
//
//    func receive(_ input: Input) -> Subscribers.Demand {
//        guard case .reply = input.event, input.topic == "phoenix" else { fatalError() }
//
//        if let ref = input.ref, ref.rawValue == lastRef {
//            lastReceivedAt = Date()
//            count += 1
//        } else {
//            fatalError()
//        }
//
//        return .unlimited
//    }
//
//    func receive(completion: Subscribers.Completion<Error>) {
//        lastReceivedAt = Date()
//    }
//}
