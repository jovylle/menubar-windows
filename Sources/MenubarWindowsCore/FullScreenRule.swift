// FullScreenRule.swift
// Which screen a full-screen window takes over. A full-screen window hides the menu bar on its own
// display only, so the strip steps aside on that display and nowhere else. Pure, so the rule is unit tested.
//
// Gotchas:
// - A window belongs to the screen that holds its CENTER. This is the same rule that assigns tabs to
//   screens (WindowProvider.windows(on:)). Both frames must be in Cocoa coordinates (bottom-left origin).
// - A full-screen window whose frame cannot be read hides the strip on every screen. That is the old
//   behavior, kept for the case where Accessibility gives no position or size.

import CoreGraphics

public enum FullScreenRule {
    /// True when the strip on the screen with `screenFrame` should step aside for a full-screen window.
    /// - Parameter fullScreenFrames: one entry per full-screen window of the frontmost app. `nil` is a
    ///   full-screen window whose frame is unknown, which counts for every screen.
    public static func hidesStrip(screenFrame: CGRect, fullScreenFrames: [CGRect?]) -> Bool {
        fullScreenFrames.contains { frame in
            guard let frame else { return true }
            return screenFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
