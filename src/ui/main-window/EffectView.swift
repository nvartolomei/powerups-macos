@available(macOS 26.0, *)
class LiquidGlassEffectView: NSGlassEffectView, EffectView {
    convenience init(_: Int?) {
        self.init()
        style = .regular
        updateAppearance()
        wantsLayer = true
        // without this, there are weird shadows around the corners
        layer!.masksToBounds = true
    }

    func updateAppearance() {
        cornerRadius = Appearance.windowCornerRadius
    }

    /// hosting content in the glass' contentView (instead of as sibling subviews) lets AppKit keep it
    /// legible as the glass tints itself light or dark to match whatever is behind the panel
    func setContent(_ view: NSView) {
        contentView = view
    }
}

protocol EffectView: NSView {
    func updateAppearance()
    func setContent(_ view: NSView)
}

func makeAppropriateEffectView() -> EffectView {
    LiquidGlassEffectView(nil)
}
