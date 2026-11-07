import CoreGraphics

public enum DisplayInfo {
    /// Refresh rate of the main display in Hz (120 on ProMotion MacBook Pros), or 60 when the display reports none,
    /// as some external displays do.
    public static func refreshRate() -> Int {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()), mode.refreshRate > 0 else { return 60 }
        return Int(mode.refreshRate.rounded())
    }

    /// Size of the main display in points (the size Wine reports to games) and its pixels per point (2 on Retina).
    public static func pointSizeAndScale() -> (width: Int, height: Int, scale: Int)? {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()), mode.width > 0 else { return nil }
        return (mode.width, mode.height, max(1, Int((Double(mode.pixelWidth) / Double(mode.width)).rounded())))
    }
}
