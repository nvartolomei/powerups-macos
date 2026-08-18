import Cocoa

class AITab {
    static func initTab() -> NSView {
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Endpoint", comment: ""),
                                        rightViews: LabelAndControl.makeTextArea(26, 1, LLMClient.defaultEndpoint, "llmEndpoint")))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Model", comment: ""),
                                        rightViews: LabelAndControl.makeTextArea(26, 1, LLMClient.defaultModel, "llmModel")))
        addFormatRows(table)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("API key", comment: ""),
                                        subTitle: NSLocalizedString("Kept in the keychain, so exported settings never carry it", comment: ""),
                                        rightViews: [ApiKeyField(frame: .zero)]))
        return TableGroupSetView(originalViews: [table], bottomPadding: 0)
    }

    /// only two of the three formats can look things up, so the switch follows the dropdown rather than being
    /// quietly ignored when it can't apply
    private static func addFormatRows(_ table: TableGroupView) {
        let webSearch = LabelAndControl.makeSwitch("llmWebSearch")
        webSearch.isEnabled = Preferences.llmFormat.supportsWebSearch
        let format = LabelAndControl.makeDropdown("llmFormat", LLMFormatPreference.allCases, extraAction: { _ in
            webSearch.isEnabled = Preferences.llmFormat.supportsWebSearch
        })
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("API format", comment: ""), rightViews: [format]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Web search", comment: ""),
                                        subTitle: NSLocalizedString("Lets the model look things up", comment: ""),
                                        rightViews: [webSearch]))
    }
}

/// saves while the key is typed or pasted. a text field only sends its action on return, and a key is normally
/// pasted and then the window is closed, which would drop it with no way to tell that it happened
private class ApiKeyField: NSSecureTextField, NSTextFieldDelegate {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
        // the stored key is never read back into the field: decrypting it is what makes the keychain ask for
        // authorization, and opening the settings is not a moment where that question makes any sense
        placeholderString = Self.placeholder()
        translatesAutoresizingMaskIntoConstraints = false
        fit(220, 22)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func controlTextDidChange(_ notification: Notification) {
        // the field is the only feedback the keychain write has; red means it didn't take
        textColor = LLMKeychain.setApiKey(stringValue) ? .labelColor : .systemRed
        // emptying the field removes the key, and the placeholder that becomes visible says so
        placeholderString = Self.placeholder()
    }

    private static func placeholder() -> String {
        LLMKeychain.hasApiKey()
            ? NSLocalizedString("Stored — type to replace", comment: "")
            : NSLocalizedString("Not set", comment: "")
    }
}
