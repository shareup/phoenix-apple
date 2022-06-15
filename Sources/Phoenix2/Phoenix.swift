import Foundation
import WebSocket

public typealias PushEncoder = (Push) throws -> WebSocketMessage
public typealias MessageDecoder = (WebSocketMessage) throws -> Message
