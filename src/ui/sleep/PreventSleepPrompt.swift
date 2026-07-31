import Cocoa

/// The "Custom…" prompt: how long to stay awake, and how low the battery may get before the session ends.
/// The cutoff starts from the Settings default and applies to this one session only, so a long unattended job
/// can be loosened without moving the standing policy.
class PreventSleepPrompt: NSPanel, NSTextFieldDelegate {
    static var shared: PreventSleepPrompt?
    override var canBecomeKey: Bool { true }
    private static let width = CGFloat(380)
    private static let padding = CGFloat(20)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    /// weekday and day of the month, ordered the way the locale writes them; the year can't be ambiguous
    /// within the 30 day ceiling
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private var durationField: NSTextField!
    private var durationEcho: NSTextField!
    private var cutoffCheckbox: NSButton!
    private var cutoffSlider: NSSlider!
    private var startButton: NSButton!

    @objc static func show() {
        let panel = shared ?? PreventSleepPrompt()
        panel.loadPreferences()
        App.showSecondaryWindow(panel)
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = NSLocalizedString("Stay awake", comment: "Sleep prevention prompt")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        setupView()
        setFrameAutosaveName("PreventSleepPrompt")
        Self.shared = self
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }

    private func setupView() {
        let stack = NSStackView(views: [makeDurationRow(), makeCutoffCheckbox(), makeCutoffRow(), makeButtonRow()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(4, after: stack.arrangedSubviews[1])
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.padding),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.padding),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.padding),
            stack.arrangedSubviews.last!.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        contentView = content
        setContentSize(NSSize(width: Self.width, height: stack.fittingSize.height + Self.padding * 2))
    }

    private func makeDurationRow() -> NSView {
        durationField = NSTextField(string: "")
        durationField.translatesAutoresizingMaskIntoConstraints = false
        durationField.placeholderString = "1h 30m"
        durationField.delegate = self
        durationField.addOrUpdateConstraint(durationField.widthAnchor, 100)
        durationEcho = TextField("")
        durationEcho.textColor = .secondaryLabelColor
        return Self.makeRow([TextField(NSLocalizedString("For", comment: "Sleep prevention prompt")),
                             durationField, durationEcho])
    }

    /// the checkbox carries the whole sentence, so the percentage never has to be read as a bare number
    private func makeCutoffCheckbox() -> NSView {
        cutoffCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        cutoffCheckbox.translatesAutoresizingMaskIntoConstraints = false
        cutoffCheckbox.onAction = { [weak self] _ in self?.cutoffChanged() }
        return Self.makeRow([cutoffCheckbox])
    }

    private func makeCutoffRow() -> NSView {
        cutoffSlider = NSSlider()
        cutoffSlider.translatesAutoresizingMaskIntoConstraints = false
        cutoffSlider.minValue = Double(SleepPreventionTestable.minCutoff)
        cutoffSlider.maxValue = Double(SleepPreventionTestable.maxCutoff)
        cutoffSlider.isContinuous = true
        cutoffSlider.numberOfTickMarks = SleepPreventionTestable.cutoffTicks
        cutoffSlider.allowsTickMarkValuesOnly = true
        cutoffSlider.tickMarkPosition = .below
        cutoffSlider.addOrUpdateConstraint(cutoffSlider.widthAnchor, 220)
        cutoffSlider.onAction = { [weak self] _ in self?.cutoffChanged() }
        return Self.makeRow([cutoffSlider], left: 20)
    }

    /// the row is stretched to the full width (see setupView), so the buttons ride its trailing gravity area
    private func makeButtonRow() -> NSView {
        let cancel = NSButton(title: NSLocalizedString("Cancel", comment: "Sleep prevention prompt"), target: nil, action: nil)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.keyEquivalent = "\u{1b}"
        cancel.onAction = { [weak self] _ in self?.close() }
        startButton = NSButton(title: NSLocalizedString("Prevent sleep", comment: "Sleep prevention prompt"), target: nil, action: nil)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.keyEquivalent = "\r"
        startButton.bezelColor = .controlAccentColor
        startButton.onAction = { [weak self] _ in self?.startSession() }
        let row = Self.makeRow([])
        row.addView(cancel, in: .trailing)
        row.addView(startButton, in: .trailing)
        return row
    }

    /// the cutoff starts from the Settings default; changing it here only affects the session about to start
    private func loadPreferences() {
        durationField.stringValue = SleepPreventionTestable.formatDuration(SleepPreventionTestable.clampMinutes(Preferences.preventSleepMinutes))
        cutoffCheckbox.state = Preferences.preventSleepBatteryCutoffEnabled ? .on : .off
        cutoffSlider.integerValue = SleepPreventionTestable.clampCutoff(Preferences.preventSleepBatteryCutoff)
        durationChanged()
        cutoffChanged()
        makeFirstResponder(durationField)
    }

    /// only the duration is remembered, as the field it lands back in is right here
    private func startSession() {
        // the default button beats the field editor to the Return key; commit what was typed before reading it
        makeFirstResponder(nil)
        guard let minutes = SleepPreventionTestable.parseDuration(durationField.stringValue) else { return }
        let cutoff = currentCutoff()
        Preferences.set("preventSleepMinutes", String(minutes))
        close()
        PreventSleepCommands.start(minutes, cutoff)
    }

    func controlTextDidChange(_ notification: Notification) {
        durationChanged()
    }

    /// echoes the clock time the session ends, which is what the duration is really being typed to reach.
    /// unreadable text isn't scolded, it just shows the shapes that work and holds the button back.
    private func durationChanged() {
        guard let minutes = SleepPreventionTestable.parseDuration(durationField.stringValue) else {
            durationEcho.stringValue = NSLocalizedString("45m · 2h · 1h30", comment: "Sleep prevention prompt. Examples of durations")
            durationEcho.textColor = .tertiaryLabelColor
            startButton.isEnabled = false
            return
        }
        durationEcho.stringValue = Self.wakeUntil(minutes)
        durationEcho.textColor = .secondaryLabelColor
        startButton.isEnabled = true
    }

    private func cutoffChanged() {
        let cutoff = currentCutoff()
        cutoffSlider.isEnabled = cutoff != SleepPreventionTestable.cutoffOff
        cutoffCheckbox.title = String(format: NSLocalizedString("Let the Mac sleep below %d%% battery", comment: "Sleep prevention prompt"),
                                      cutoffSlider.integerValue)
    }

    private func currentCutoff() -> Int {
        cutoffCheckbox.state == .on ? cutoffSlider.integerValue : SleepPreventionTestable.cutoffOff
    }

    private static func wakeUntil(_ minutes: Int) -> String {
        let end = Date(timeIntervalSinceNow: Double(minutes) * 60)
        let time = timeFormatter.string(from: end)
        switch SleepPreventionTestable.daysAhead(end, Date()) {
        case 0:
            return String(format: NSLocalizedString("until %@", comment: "Sleep prevention prompt. %@ is a time of day"), time)
        case 1:
            return String(format: NSLocalizedString("until %@ tomorrow", comment: "Sleep prevention prompt. %@ is a time of day"), time)
        default:
            return String(format: NSLocalizedString("until %@ on %@", comment: "Sleep prevention prompt. %@s are a time of day and a date"),
                          time, dayFormatter.string(from: end))
        }
    }

    /// centred rather than StackView's baseline default, as these rows pair labels with sliders and checkboxes
    private static func makeRow(_ views: [NSView], left: CGFloat = 0) -> NSStackView {
        let row = StackView(views, .horizontal, false, left: left)
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}
