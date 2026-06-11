import Cocoa

class PopupButtonLikeSystemSettings: NSPopUpButton {
    private var cachedIntrinsicContentSize: NSSize?
    private var cachedIntrinsicContentSizeKey: String?

    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    /// sized to fit the selected item, like in System Settings
    /// measuring through a fake button is expensive, and Auto Layout queries this a lot; we re-measure only when the selected item or cell style changes
    override var intrinsicContentSize: NSSize {
        guard let selectedItem else { return super.intrinsicContentSize }
        let key = intrinsicContentSizeKey(selectedItem)
        if key != cachedIntrinsicContentSizeKey {
            cachedIntrinsicContentSizeKey = key
            cachedIntrinsicContentSize = measureSelectedItemSize(selectedItem)
        }
        return cachedIntrinsicContentSize!
    }

    private func intrinsicContentSizeKey(_ selectedItem: NSMenuItem) -> String {
        let currentCell = cell! as! NSPopUpButtonCell
        let imageKey = selectedItem.image.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue)) } ?? ""
        return "\(title)|\(imageKey)|\(currentCell.bezelStyle.rawValue)|\(currentCell.arrowPosition.rawValue)|\(currentCell.imagePosition.rawValue)|\(showsBorderOnlyWhileMouseInside)"
    }

    private func measureSelectedItemSize(_ selectedItem: NSMenuItem) -> NSSize {
        let fakePopUpButton = NSPopUpButton()
        fakePopUpButton.addItem(withTitle: title)
        fakePopUpButton.item(at: 0)!.image = selectedItem.image
        let fakeCell = fakePopUpButton.cell! as! NSPopUpButtonCell
        let currentCell = cell! as! NSPopUpButtonCell
        fakeCell.bezelStyle = currentCell.bezelStyle
        fakeCell.arrowPosition = currentCell.arrowPosition
        fakeCell.imagePosition = currentCell.imagePosition
        fakePopUpButton.showsBorderOnlyWhileMouseInside = showsBorderOnlyWhileMouseInside
        fakePopUpButton.sizeToFit()
        return fakePopUpButton.intrinsicContentSize
    }
}
