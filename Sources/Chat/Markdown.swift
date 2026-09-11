import UIKit

/// A small, allocation-light Markdown renderer.
///
/// A full CommonMark parser is overkill here and third-party ones drop iOS 14
/// support quickly, so this handles the subset the assistant actually emits:
/// headings, bold, italic, inline code, fenced code, lists, quotes and links.
enum Markdown {
    static func render(_ source: String, font: ChatFontChoice) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = source.components(separatedBy: "\n")

        var insideFence = false
        var fenceBuffer: [String] = []

        func flushFence() {
            guard !fenceBuffer.isEmpty else { return }
            output.append(codeBlock(fenceBuffer.joined(separator: "\n")))
            fenceBuffer.removeAll()
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if insideFence {
                    flushFence()
                    insideFence = false
                } else {
                    insideFence = true
                }
                continue
            }

            if insideFence {
                fenceBuffer.append(line)
                continue
            }

            output.append(block(line, font: font))
            output.append(NSAttributedString(string: "\n"))
        }

        if insideFence { flushFence() }

        // Trim the trailing newline so bubbles do not gain phantom padding.
        if output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        return output
    }

    private static func block(_ line: String, font: ChatFontChoice) -> NSAttributedString {
        var text = line
        var attributes = font.attributes()
        let paragraph = font.paragraphStyle()

        if text.hasPrefix("### ") {
            text.removeFirst(4)
            attributes[.font] = font.font(size: font.bodyFont().pointSize + 1, weight: .semibold)
        } else if text.hasPrefix("## ") {
            text.removeFirst(3)
            attributes[.font] = font.font(size: font.bodyFont().pointSize + 3, weight: .semibold)
        } else if text.hasPrefix("# ") {
            text.removeFirst(2)
            attributes[.font] = font.font(size: font.bodyFont().pointSize + 6, weight: .bold)
        } else if text.hasPrefix("> ") {
            text.removeFirst(2)
            attributes[.foregroundColor] = Theme.textSecondary
            paragraph.firstLineHeadIndent = 14
            paragraph.headIndent = 14
            attributes[.paragraphStyle] = paragraph
        } else if let bullet = bulletPrefix(text) {
            text = "\u{2022}  " + String(text.dropFirst(bullet))
            paragraph.firstLineHeadIndent = 4
            paragraph.headIndent = 22
            attributes[.paragraphStyle] = paragraph
        } else if let ordered = orderedPrefix(text) {
            text = String(text.dropFirst(ordered.length)).trimmingCharacters(in: .whitespaces)
            text = ordered.label + "  " + text
            paragraph.firstLineHeadIndent = 4
            paragraph.headIndent = 24
            attributes[.paragraphStyle] = paragraph
        } else if text.trimmingCharacters(in: .whitespaces) == "---" {
            return NSAttributedString(
                string: String(repeating: "\u{2500}", count: 24),
                attributes: [.font: font.font(size: 12), .foregroundColor: Theme.border]
            )
        }

        return inline(text, baseAttributes: attributes, font: font)
    }

    private static func bulletPrefix(_ text: String) -> Int? {
        for marker in ["- ", "* ", "+ "] where text.hasPrefix(marker) {
            return marker.count
        }
        return nil
    }

    private static func orderedPrefix(_ text: String) -> (label: String, length: Int)? {
        let scanner = Scanner(string: text)
        var value: Int = 0
        guard scanner.scanInt(&value) else { return nil }
        let index = scanner.scanLocation
        guard index < text.count else { return nil }
        let remainder = text.dropFirst(index)
        guard remainder.hasPrefix(". ") || remainder.hasPrefix(") ") else { return nil }
        return ("\(value).", index + 2)
    }

    /// Handles `**bold**`, `*italic*`, `` `code` `` and `[title](url)`.
    private static func inline(
        _ text: String,
        baseAttributes: [NSAttributedString.Key: Any],
        font: ChatFontChoice
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let baseFont = (baseAttributes[.font] as? UIFont) ?? font.bodyFont()

        applyPairs(in: result, marker: "**") { range in
            result.addAttribute(
                .font,
                value: bold(baseFont),
                range: range
            )
        }

        applyPairs(in: result, marker: "`") { range in
            result.addAttributes(
                [
                    .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                    .foregroundColor: Theme.accent,
                    .backgroundColor: Theme.codeBackground
                ],
                range: range
            )
        }

        applyPairs(in: result, marker: "*") { range in
            result.addAttribute(.font, value: italic(baseFont), range: range)
        }

        applyLinks(in: result)
        return result
    }

    private static func applyPairs(
        in string: NSMutableAttributedString,
        marker: String,
        style: (NSRange) -> Void
    ) {
        while true {
            let plain = string.string as NSString
            let openRange = plain.range(of: marker)
            guard openRange.location != NSNotFound else { return }

            let searchStart = openRange.location + openRange.length
            guard searchStart < plain.length else {
                string.replaceCharacters(in: openRange, with: "")
                return
            }

            let closeRange = plain.range(
                of: marker,
                options: [],
                range: NSRange(location: searchStart, length: plain.length - searchStart)
            )
            guard closeRange.location != NSNotFound else {
                string.replaceCharacters(in: openRange, with: "")
                return
            }

            string.replaceCharacters(in: closeRange, with: "")
            string.replaceCharacters(in: openRange, with: "")

            let styled = NSRange(
                location: openRange.location,
                length: closeRange.location - openRange.location - marker.count
            )
            if styled.length > 0, styled.location + styled.length <= string.length {
                style(styled)
            }
        }
    }

    private static func applyLinks(in string: NSMutableAttributedString) {
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        while true {
            let plain = string.string
            let full = NSRange(location: 0, length: (plain as NSString).length)
            guard let match = regex.firstMatch(in: plain, options: [], range: full) else { return }

            let nsPlain = plain as NSString
            let title = nsPlain.substring(with: match.range(at: 1))
            let link = nsPlain.substring(with: match.range(at: 2))

            let attributes = string.attributes(at: match.range.location, effectiveRange: nil)
            let replacement = NSMutableAttributedString(string: title, attributes: attributes)
            if let url = URL(string: link) {
                replacement.addAttributes(
                    [.link: url, .foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue],
                    range: NSRange(location: 0, length: replacement.length)
                )
            }
            string.replaceCharacters(in: match.range, with: replacement)
        }
    }

    private static func codeBlock(_ code: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        paragraph.paragraphSpacing = 12
        paragraph.paragraphSpacingBefore = 6
        paragraph.lineHeightMultiple = 1.15

        return NSAttributedString(
            string: code + "\n",
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: Theme.textPrimary,
                .backgroundColor: Theme.codeBackground,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func italic(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// Plain-text extraction for copy actions.
    static func plainText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
