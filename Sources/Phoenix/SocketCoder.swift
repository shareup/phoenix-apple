import Foundation
import WebSocketProtocol

public typealias OutgoingMessageEncoder = (OutgoingMessage) throws -> WebSocketMessage
public typealias IncomingMessageDecoder = (Data) throws -> IncomingMessage
