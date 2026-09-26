import SwiftUI

/// A snapshot of the device hinge, reduced to what the sampler needs.
struct HingeReading: Equatable {
    enum Status {
        case closed
        case partiallyOpen
        case fullyOpen
    }

    var status: Status
    var angle: Angle

    @available(iOS 27.1, *)
    init?(_ hinge: DeviceHinge?) {
        guard let hinge else { return nil }
        switch hinge.status {
        case .closed: status = .closed
        case .fullyOpen: status = .fullyOpen
        default: status = .partiallyOpen
        }
        angle = hinge.angle
    }
}
