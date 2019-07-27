import Foundation

extension Socket {
    final class WeakChannel {
        weak var channel: Channel?

        init(_ channel: Channel) {
            self.channel = channel
        }
    }
}
