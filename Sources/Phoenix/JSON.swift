import Foundation

public enum JSON {
    public static func isEqual(_ one: [String: Any], _ two: [String: Any]) -> Bool {
        guard one.keys.sorted() == two.keys.sorted() else { return false }
        for key in one.keys.sorted() {
            guard isEqual(one[key]!, two[key]!) else { return false }
        }
        return true
    }

    public static func isEqual(_ one: [Any], _ two: [Any]) -> Bool {
        guard one.count == two.count else { return false }
        for i in 0 ..< one.count {
            guard isEqual(one[i], two[i]) else { return false }
        }
        return true
    }

    private static func isEqual(_ one: Any, _ two: Any) -> Bool {
        switch (one, two) {
        case (is Bool, is Bool):
            return (one as! Bool) == (two as! Bool)

        case (is Int, is Int):
            return (one as! Int) == (two as! Int)

        case (is Double, is Double):
            return (one as! Double) == (two as! Double)

        case (is String, is String):
            return (one as! String) == (two as! String)

        case (is Data, is Data):
            return (one as! Data) == (two as! Data)

        case (is [String: Any], is [String: Any]):
            return isEqual(one as! [String: Any], two as! [String: Any])

        case (is [Any], is [Any]):
            return isEqual(one as! [Any], two as! [Any])

        default:
            return false
        }
    }
}
