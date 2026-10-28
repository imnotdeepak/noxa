import Foundation

enum InstagramSiteMode: String, CaseIterable, Identifiable {
    case off
    case distractionFree

    var id: Self { self }
}
