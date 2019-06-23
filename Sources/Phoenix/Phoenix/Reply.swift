import Foundation

extension Phoenix {
    public struct Reply {
        internal let joinRef: Ref
        internal let ref: Ref
        
        let message: Message
        
        let status: String
        let response: Dictionary<String, Any>
        
        public var isOk: Bool { return status == "ok" }
        public var isNotOk: Bool { return isOk == false }
    }
}
