import Foundation
import Synchronized

func oneTenthOfOneThousand(of amount: Int) -> Int {
    return Int((Double(amount * 1000) * 0.1).rounded())
}

class Timer {
    private let source: DispatchSourceTimer
    private let block: () -> ()
    private let lock = RecursiveLock()
    
    let isRepeating: Bool

    var nextDeadline: DispatchTime { lock.locked { return _nextDeadline } }
    private var _nextDeadline: DispatchTime
    
    init(_ interval: DispatchTimeInterval, repeat shouldRepeat: Bool = false, block: @escaping () -> ()) {
        self.source = DispatchSource.makeTimerSource()
        self.block = block
        self.isRepeating = shouldRepeat
        
        let deadline = DispatchTime.now().advanced(by: interval)
        _nextDeadline = deadline
        let repeating: DispatchTimeInterval = shouldRepeat ? interval : .never
        source.schedule(deadline: deadline, repeating: repeating, leeway: Self.defaultTolerance(interval))
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.fire()
            
            guard shouldRepeat else { return }
            self.lock.locked { self._nextDeadline = DispatchTime.now().advanced(by: interval) }
        }
        source.activate()
    }
    
    init(fireAt deadline: DispatchTime, block: @escaping () -> ()) {
        self.source = DispatchSource.makeTimerSource()
        self.block = block
        self.isRepeating = false
        _nextDeadline = deadline
        
        let interval = DispatchTime.now().distance(to: deadline)
        
        source.schedule(deadline: deadline, repeating: .never, leeway: Self.defaultTolerance(interval))
        
        source.setEventHandler { [weak self] in self?.fire() }
        source.activate()
    }
    
    private static func defaultTolerance(_ interval: DispatchTimeInterval) -> DispatchTimeInterval {
        switch interval {
        case .seconds(let amount):
            guard amount > 0 else { return .never }
            return .milliseconds(oneTenthOfOneThousand(of: amount))
        case .milliseconds(let amount):
            guard amount > 0 else { return .never }
            return .microseconds(oneTenthOfOneThousand(of: amount))
        case .microseconds(let amount):
            guard amount > 0 else { return .never }
            return .nanoseconds(oneTenthOfOneThousand(of: amount))
        case .nanoseconds, .never:
            return .never
        @unknown default:
            return .never
        }
    }
    
    private func fire() {
        block()
        if !isRepeating { source.cancel() }
    }
    
    deinit {
        source.cancel()
    }
}

extension DispatchTime {
    static func < (lhs: DispatchTime, rhs: Optional<DispatchTime>) -> Bool {
        guard let rhs = rhs else { return true }
        return lhs < rhs
    }
}
