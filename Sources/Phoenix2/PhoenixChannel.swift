import Foundation
import os.log

actor PhoenixChannel {
    nonisolated let topic: Topic
    nonisolated let joinPayload: Payload

    private weak var socket: PhoenixSocket?

    init(
        topic: Topic,
        joinPayload: Payload = [:],
        socket: PhoenixSocket
    ) {
        self.topic = topic
        self.joinPayload = joinPayload
        self.socket = socket
    }
}
