import Foundation

enum InstagramSiteMode: String, CaseIterable, Identifiable {
    case off
    case distractionFree
    case fullBlock

    var id: Self { self }
}
