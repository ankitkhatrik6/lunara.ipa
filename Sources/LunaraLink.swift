import Foundation

enum LunaraLink {
    static let scheme = "lunara"

    static var resume: URL { URL(string: "\(scheme)://resume")! }
    static var favourites: URL { URL(string: "\(scheme)://favourites")! }
    static var downloads: URL { URL(string: "\(scheme)://downloads")! }
    static var search: URL { URL(string: "\(scheme)://search")! }
}
