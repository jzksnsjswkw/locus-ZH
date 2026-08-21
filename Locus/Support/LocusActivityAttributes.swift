import ActivityKit

@available(iOS 16.1, *)
struct LocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var coordinate: String
        var distance: String
        var elapsed: String
        var city: String
        var country: String
    }

    var title: String
}
