import Foundation
import WebSocket

public typealias PushEncoder = @Sendable (Push) throws -> WebSocketMessage
public typealias MessageDecoder = @Sendable (WebSocketMessage) throws -> Message

public typealias Topic = String
