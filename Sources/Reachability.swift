import Combine
import Foundation
import Network

final class Reachability: ObservableObject {
    static let shared = Reachability()

    @Published private(set) var isOnline = true
    @Published private(set) var isUnmetered = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let unmetered = !path.isExpensive && !path.isConstrained
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
                if self.isUnmetered != unmetered { self.isUnmetered = unmetered }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.lunara.reachability"))
    }
}
