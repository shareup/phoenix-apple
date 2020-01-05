import Foundation
import Synchronized

class Pusher: Synchronized {
    enum Error: Swift.Error {
        case cancelled
        case exceededRetryCount
    }
    
    enum Push {
        case channel(Channel.Push)
        case socket(Socket.Push)
        
        var shouldTrackInFlight: Bool {
            switch self {
            case .socket(_):
                return false
            case .channel(let push):
                return push.callback != nil
            }
        }
        
        func outgoingMessage(ref: Ref) throws -> OutgoingMessage {
            switch self {
            case .channel(let push):
                let joinRef = push.channel.joinRef!
                // TODO: nope
                return OutgoingMessage(push, ref: ref, joinRef: joinRef)
            case .socket(let push):
                return OutgoingMessage(push, ref: ref)
            }
        }
        
        func errorCallback(_ error: Swift.Error) {
            switch self {
            case .channel(let push):
                push.asyncCallback(result: .failure(error))
            case .socket(let push):
                push.asyncCallback(error)
            }
        }
        
        func successCallback(_ reply: Channel.Reply) {
            switch self {
            case .channel(let push):
                push.asyncCallback(result: .success(reply))
            case .socket(_):
                Swift.print("Received a reply to a channel-less push, which should be impossible: \(reply)")
                break
            }
        }
    }
    
    struct PushedMessage {
        let push: Push
        let message: OutgoingMessage
        
        var joinRef: Ref? { message.joinRef }
        
        func successCallback(_ reply: Channel.Reply) {
            push.successCallback(reply)
        }
    }
    
    var socket: Socket?
    
    private var pending: [Push] = []
    // TODO: sweep the inFlight dictionary periodically
    private var inFlight: [Ref: PushedMessage] = [:]
    
    private var willFlushAfterDelay = false
    
    func push(_ channelPush: Channel.Push) {
        sync {
            pending.append(.channel(channelPush))
        }
        
        flushASAP()
    }
    
    func push(_ socketPush: Socket.Push) {
        sync {
            pending.append(.socket(socketPush))
        }
        
        flushASAP()
    }
    
    func handleReply(_ reply: Channel.Reply) {
        guard let pushed = inFlight[reply.ref],
              reply.joinRef == pushed.joinRef else {
            return
        }
        
        pushed.successCallback(reply)
    }
    
    func cancel() {
        sync {
            for push in pending {
                push.errorCallback(Error.cancelled)
            }
            pending.removeAll()
        }
    }
    
    private func flushASAP() {
        sync {
            guard !willFlushAfterDelay else { return }
            DispatchQueue.global().async { self.flush() }
        }
    }

    private func flushAfterDelay() {
        sync {
            guard !willFlushAfterDelay else { return }
            self.willFlushAfterDelay = true
        }
        
        let deadline = DispatchTime.now().advanced(by: .milliseconds(100))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.flush()
        }
    }
    
    private func flush() {
        sync {
            guard pending.count > 0 else { return }
            guard let socket = socket else { return }
            
            let remaining = pending.drop { push in
                do {
                    let ref = Ref.Generator.global.advance()
                    let message = try push.outgoingMessage(ref: ref)
                    socket.send(message) { error in
                        if let error = error {
                            push.errorCallback(error)
                        }
                    }
                    
                    if push.shouldTrackInFlight {
                        inFlight[ref] = PushedMessage(push: push, message: message)
                    }
                    
                    return true
                } catch {
                    Swift.print("Error writing to Socket \(error)")
                    return false
                }
            }
            
            self.pending = Array(remaining)
            
            if pending.count > 0 {
                flushAfterDelay()
            }
        }
    }
}
