import ActivityKit

struct LocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var coordinate: String
        var city: String
        var country: String
    }

    var title: String
}
