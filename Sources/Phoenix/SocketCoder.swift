import Foundation

public typealias OutgoingMessageEncoder = (OutgoingMessage) throws -> Data
public typealias IncomingMessageDecoder = (Data) throws -> IncomingMessage
