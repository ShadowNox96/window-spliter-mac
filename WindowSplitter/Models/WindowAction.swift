import AppKit

enum WindowAction: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case centerThird
    case rightThird
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case fullscreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf:           return "Left half"
        case .rightHalf:          return "Right half"
        case .topHalf:            return "Top half"
        case .bottomHalf:         return "Bottom half"
        case .leftThird:          return "Left third"
        case .centerThird:        return "Center third"
        case .rightThird:         return "Right third"
        case .topLeftQuarter:     return "Top-left quarter"
        case .topRightQuarter:    return "Top-right quarter"
        case .bottomLeftQuarter:  return "Bottom-left quarter"
        case .bottomRightQuarter: return "Bottom-right quarter"
        case .fullscreen:         return "Fullscreen"
        }
    }

    // Virtual key codes (Carbon / CGKeyCode)
    var defaultKeyCode: Int {
        switch self {
        case .leftHalf:           return 0   // A
        case .rightHalf:          return 2   // D
        case .topHalf:            return 13  // W
        case .bottomHalf:         return 1   // S
        case .leftThird:          return 18  // 1
        case .centerThird:        return 19  // 2
        case .rightThird:         return 20  // 3
        case .topLeftQuarter:     return 32  // U
        case .topRightQuarter:    return 34  // I
        case .bottomLeftQuarter:  return 38  // J
        case .bottomRightQuarter: return 40  // K
        case .fullscreen:         return 36  // Return
        }
    }

    var defaultModifiers: Int {
        Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    }

    /// Computes the target frame within `screenFrame` (AppKit coordinates).
    func frame(in screenFrame: CGRect) -> CGRect {
        let w = screenFrame.width
        let h = screenFrame.height
        let x = screenFrame.minX
        let y = screenFrame.minY
        switch self {
        case .leftHalf:           return CGRect(x: x,           y: y,           width: w / 2,   height: h)
        case .rightHalf:          return CGRect(x: x + w / 2,   y: y,           width: w / 2,   height: h)
        case .topHalf:            return CGRect(x: x,           y: y + h / 2,   width: w,       height: h / 2)
        case .bottomHalf:         return CGRect(x: x,           y: y,           width: w,       height: h / 2)
        case .leftThird:          return CGRect(x: x,           y: y,           width: w / 3,   height: h)
        case .centerThird:        return CGRect(x: x + w / 3,   y: y,           width: w / 3,   height: h)
        case .rightThird:         return CGRect(x: x + 2 * w / 3, y: y,         width: w / 3,   height: h)
        case .topLeftQuarter:     return CGRect(x: x,           y: y + h / 2,   width: w / 2,   height: h / 2)
        case .topRightQuarter:    return CGRect(x: x + w / 2,   y: y + h / 2,   width: w / 2,   height: h / 2)
        case .bottomLeftQuarter:  return CGRect(x: x,           y: y,           width: w / 2,   height: h / 2)
        case .bottomRightQuarter: return CGRect(x: x + w / 2,   y: y,           width: w / 2,   height: h / 2)
        case .fullscreen:         return CGRect(x: x,           y: y,           width: w,       height: h)
        }
    }
}
