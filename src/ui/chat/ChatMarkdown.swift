import Cocoa

extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("chatCodeBlock")
}

/// renders the markdown that actually turns up in answers: fenced code, headers, lists, quotes, and inline styling.
/// block structure is parsed here; the inside of a line is parsed by Foundation, so escapes and nested spans stay
/// correct without hand-written scanning
class ChatMarkdown {
    static let bodyFont = NSFont.systemFont(ofSize: bodyFontSize)
    private static let bodyFontSize = CGFloat(14)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: bodyFontSize - 1, weight: .regular)
    private static let listIndent = CGFloat(16)
    private static let codeIndent = CGFloat(8)
    private static let fence = "```"
    private static let markupCharacters = CharacterSet(charactersIn: "*_`[~\\")

    private static let bodyStyle = makeStyle { $0.paragraphSpacing = 8 }
    private static let listStyle = makeStyle {
        $0.paragraphSpacing = 3
        $0.headIndent = listIndent
    }
    private static let quoteStyle = makeStyle {
        $0.paragraphSpacing = 8
        $0.headIndent = listIndent
        $0.firstLineHeadIndent = listIndent
    }
    private static let codeStyle = makeStyle {
        $0.paragraphSpacing = 0
        $0.headIndent = codeIndent
        $0.firstLineHeadIndent = codeIndent
        $0.tailIndent = -codeIndent
        $0.lineHeightMultiple = 1.1
    }

    static let codeBackgroundColor = NSColor(name: "chatCodeBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06)
    }

    /// unstyled text in the body font; what the answer is drawn with while it streams in
    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyStyle,
        ])
    }

    static func render(_ markdown: String) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        var codeBlock: [String]?
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                if let lines = codeBlock {
                    rendered.append(codeParagraph(lines))
                    codeBlock = nil
                } else {
                    codeBlock = []
                }
                continue
            }
            if codeBlock != nil {
                codeBlock!.append(line)
            } else {
                rendered.append(paragraph(line))
            }
        }
        // an unterminated fence is normal for an answer that was stopped mid-code-block
        if let lines = codeBlock {
            rendered.append(codeParagraph(lines))
        }
        trimTrailingNewline(rendered)
        return rendered
    }

    private static func paragraph(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let level = headerLevel(trimmed) {
            let size = bodyFontSize + CGFloat(max(0, 4 - level))
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            return block(String(trimmed.dropFirst(level + 1)), font, bodyStyle)
        }
        if let bullet = bulletContent(trimmed) {
            return block("•  " + bullet, bodyFont, listStyle)
        }
        if isNumberedItem(trimmed) {
            return block(trimmed, bodyFont, listStyle)
        }
        if trimmed.hasPrefix("> ") {
            return block(String(trimmed.dropFirst(2)), bodyFont, quoteStyle, .secondaryLabelColor)
        }
        return block(line, bodyFont, bodyStyle)
    }

    private static func codeParagraph(_ lines: [String]) -> NSAttributedString {
        let code = NSMutableAttributedString(string: lines.joined(separator: "\n") + "\n", attributes: [
            .font: codeFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: codeStyle,
            .codeBlock: true,
        ])
        code.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)]))
        return code
    }

    private static func block(_ text: String, _ font: NSFont, _ style: NSParagraphStyle,
                              _ color: NSColor = .labelColor) -> NSAttributedString {
        let paragraph = NSMutableAttributedString(attributedString: inline(text, font, color))
        paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
        paragraph.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
        return paragraph
    }

    /// bold, italic, inline code, strikethrough, and links, parsed by Foundation and mapped onto fonts here.
    /// most lines of an answer carry no markup at all, and the parser costs more than the test that skips it
    private static func inline(_ text: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        let plainAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        guard text.rangeOfCharacter(from: markupCharacters) != nil else {
            return NSAttributedString(string: text, attributes: plainAttributes)
        }
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false,
                                                              interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: plainAttributes)
        }
        let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        let all = NSRange(location: 0, length: result.length)
        result.addAttributes(plainAttributes, range: all)
        result.enumerateAttribute(.inlinePresentationIntent, in: all) { value, range, _ in
            guard let raw = value as? UInt else { return }
            applyInlineIntent(InlinePresentationIntent(rawValue: raw), result, range, font)
        }
        result.enumerateAttribute(.link, in: all) { value, range, _ in
            guard value != nil else { return }
            result.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        }
        return result
    }

    private static func applyInlineIntent(_ intent: InlinePresentationIntent, _ text: NSMutableAttributedString,
                                          _ range: NSRange, _ font: NSFont) {
        if intent.contains(.code) {
            text.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                .backgroundColor: codeBackgroundColor,
            ], range: range)
            return
        }
        var traits = NSFontTraitMask()
        if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
        if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            text.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
        }
        if intent.contains(.strikethrough) {
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    private static func headerLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    private static func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    /// the marker is kept rather than replaced, so the model's own numbering is what the reader sees
    private static func isNumberedItem(_ line: String) -> Bool {
        let digits = line.prefix { $0.isNumber }
        return !digits.isEmpty && line.dropFirst(digits.count).hasPrefix(". ")
    }

    private static func trimTrailingNewline(_ text: NSMutableAttributedString) {
        while text.string.hasSuffix("\n") {
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
    }

    private static func makeStyle(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        configure(style)
        return style
    }
}

class ChatLayoutManager: NSLayoutManager {
    private static let cornerRadius = CGFloat(6)
    private static let verticalPadding = CGFloat(4)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        fillCodeBlocks(origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func fillCodeBlocks(_ origin: NSPoint) {
        guard let textStorage, let container = textContainers.first else { return }
        ChatMarkdown.codeBackgroundColor.setFill()
        textStorage.enumerateAttribute(.codeBlock, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            let rect = blockRect(range, container, origin)
            NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        }
    }

    private func blockRect(_ range: NSRange, _ container: NSTextContainer, _ origin: NSPoint) -> NSRect {
        let glyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x = 0
        rect.size.width = container.size.width
        return rect.insetBy(dx: 0, dy: -Self.verticalPadding).offsetBy(dx: origin.x, dy: origin.y)
    }
}
