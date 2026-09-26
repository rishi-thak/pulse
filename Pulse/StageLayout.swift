import CoreGraphics

/// Shared geometry for the pads and the visualizer.
///
/// When the device isn't folded, the pads float over the visualizer, so both
/// views agree on which part of the screen stays clear for the waveform.
struct StageLayout {
    var size: CGSize
    /// Whether the arrangement has split the pads and visualizer into separate regions.
    var isSplit: Bool

    static let panelHeight: CGFloat = 200
    static let margin: CGFloat = 16

    var isWide: Bool {
        size.width > size.height * 1.15
    }

    /// The size the pads and fold panel occupy.
    var controlsSize: CGSize {
        if isSplit { return size }
        if isWide {
            return CGSize(width: min(size.width * 0.6, max(340, size.height - Self.panelHeight)), height: size.height)
        }
        return CGSize(width: size.width, height: min(size.height * 0.7, size.width + Self.panelHeight))
    }

    /// The area where the waveform draws, clear of any overlapping controls.
    var waveformRect: CGRect {
        var area = CGRect(origin: .zero, size: size)
        if !isSplit {
            if isWide {
                area.size.width -= controlsSize.width
            } else {
                area.size.height -= controlsSize.height
            }
        }
        return area.insetBy(dx: 28, dy: max(28, area.height * 0.14))
    }
}
