import Foundation

func oneTenthOfOneThousand(of amount: Int) -> Int {
    return Int((Double(amount * 1000) * 0.1).rounded())
}

class Timer {
    private let source: DispatchSourceTimer
    private let block: () -> ()
    
    public let isRepeating: Bool
    
    init(_ interval: DispatchTimeInterval, repeat shouldRepeat: Bool = false, block: @escaping () -> ()) {
        self.source = DispatchSource.makeTimerSource()
        self.block = block
        self.isRepeating = shouldRepeat
        
        let deadline = DispatchTime.now().advanced(by: interval)
        let repeating: DispatchTimeInterval = shouldRepeat ? interval : .never
        source.schedule(deadline: deadline, repeating: repeating, leeway: Self.defaultTolerance(interval))
        
        source.setEventHandler { [weak self] in self?.fire() }
        source.activate()
    }
    
    init(fireAt deadline: DispatchTime, block: @escaping () -> ()) {
        self.source = DispatchSource.makeTimerSource()
        self.block = block
        self.isRepeating = false
        
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
