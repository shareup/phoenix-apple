import Foundation
import WebSocketProtocol

public typealias OutgoingMessageEncoder = (OutgoingMessage) throws -> RawOutgoingMessage
public typealias IncomingMessageDecoder = (RawIncomingMessage) throws -> IncomingMessage
