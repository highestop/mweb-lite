import MWebCore
import Foundation

struct MarkdownEdit {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

/// Text-only transformations keep Markdown editing independent of the text view.
enum MarkdownEditing {
    static func wrap(_ text: String, selection: NSRange, before: String, after: String) -> MarkdownEdit {
        let source = text as NSString
        let selected = source.substring(with: selection)
        let prefixLength = (before as NSString).length
        let suffixLength = (after as NSString).length
        let isEmphasis = before == after && (before == "*" || before == "_")
        let selectedHasEmphasis = !isEmphasis || (
            selected.prefix(while: { String($0) == before }).count % 2 == 1 &&
            selected.reversed().prefix(while: { String($0) == after }).count % 2 == 1
        )
        if selection.length >= prefixLength + suffixLength,
           selected.hasPrefix(before), selected.hasSuffix(after), selectedHasEmphasis {
            let inner = (selected as NSString).substring(with: NSRange(location: prefixLength, length: selection.length - prefixLength - suffixLength))
            return MarkdownEdit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        if selection.location >= prefixLength,
           NSMaxRange(selection) + suffixLength <= source.length,
           source.substring(with: NSRange(location: selection.location - prefixLength, length: prefixLength)) == before,
           source.substring(with: NSRange(location: NSMaxRange(selection), length: suffixLength)) == after,
           !isEmphasis || (
               source.substring(to: selection.location).reversed().prefix(while: { String($0) == before }).count % 2 == 1 &&
               source.substring(from: NSMaxRange(selection)).prefix(while: { String($0) == after }).count % 2 == 1
           ) {
            return MarkdownEdit(range: NSRange(location: selection.location - prefixLength, length: selection.length + prefixLength + suffixLength), replacement: selected,
                                selection: NSRange(location: selection.location - prefixLength, length: selection.length))
        }
        return MarkdownEdit(range: selection, replacement: before + selected + after,
                            selection: NSRange(location: selection.location + prefixLength, length: selection.length))
    }

    static func link(_ text: String, selection: NSRange) -> MarkdownEdit {
        let selected = (text as NSString).substring(with: selection)
        let title = selected.isEmpty ? L10n.string("Link text") : selected
        let replacement = "[\(title)](https://)"
        return MarkdownEdit(range: selection, replacement: replacement,
                            selection: NSRange(location: selection.location + (title as NSString).length + 3, length: 8))
    }

    static func indent(_ text: String, selection: NSRange, outdent: Bool) -> MarkdownEdit {
        let source = text as NSString
        let lineRange = selectedLineRange(source, selection: selection)
        let original = source.substring(with: lineRange)
        var offset = lineRange.location
        var adjustments: [(location: Int, removed: Int, added: Int)] = []
        let replacement = original.components(separatedBy: "\n").enumerated().map { index, line -> String in
            defer { offset += (line as NSString).length + 1 }
            if line.isEmpty && index > 0 && offset == NSMaxRange(lineRange) { return line }
            if outdent {
                let count = line.hasPrefix("\t") ? 1 : min(4, line.prefix(while: { $0 == " " }).count)
                adjustments.append((offset, count, 0))
                return String(line.dropFirst(count))
            }
            adjustments.append((offset, 0, 4))
            return "    " + line
        }.joined(separator: "\n")
        func adjusted(_ position: Int) -> Int {
            var result = position
            for change in adjustments where change.location <= position {
                result += change.added - min(change.removed, max(0, position - change.location))
            }
            return result
        }
        let start = adjusted(selection.location)
        let end = adjusted(NSMaxRange(selection))
        return MarkdownEdit(range: lineRange, replacement: replacement, selection: NSRange(location: start, length: max(0, end - start)))
    }

    static func prefixLines(_ text: String, selection: NSRange, prefix: String) -> MarkdownEdit {
        let source = text as NSString
        let range = selectedLineRange(source, selection: selection)
        let lines = source.substring(with: range).components(separatedBy: "\n")
        let active = lines.enumerated().filter { !($0.element.isEmpty && $0.offset == lines.count - 1 && lines.count > 1) }
        let remove = active.allSatisfy { $0.element.hasPrefix(prefix) }
        let replacement = lines.enumerated().map { index, line in
            if line.isEmpty && index == lines.count - 1 && lines.count > 1 { return line }
            return remove ? String(line.dropFirst(prefix.count)) : prefix + line
        }.joined(separator: "\n")
        let delta = (replacement as NSString).length - range.length
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(range.location, selection.location + delta), length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: (replacement as NSString).length)
        }
        return MarkdownEdit(range: range, replacement: replacement, selection: newSelection)
    }

    static func newline(_ text: String, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let line = source.lineRange(for: selection)
        let before = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let after = source.substring(with: NSRange(location: selection.location, length: NSMaxRange(line) - selection.location)).trimmingCharacters(in: .newlines)
        let indentation = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
        if isInFence(text, at: selection.location) {
            let value = "\n" + indentation
            return MarkdownEdit(range: selection, replacement: value, selection: NSRange(location: selection.location + (value as NSString).length, length: 0))
        }
        let pattern = #"^([ \t]*)([-+*]|[0-9]+[.)])([ \t]+)(\[[ xX]\][ \t]+)?(.*)$"#
        if let match = firstMatch(pattern, in: before) {
            let part = before as NSString
            let indent = part.substring(with: match.range(at: 1))
            let marker = part.substring(with: match.range(at: 2))
            let content = part.substring(with: match.range(at: 5))
            if content.trimmingCharacters(in: .whitespaces).isEmpty && after.trimmingCharacters(in: .whitespaces).isEmpty {
                return MarkdownEdit(range: NSRange(location: line.location, length: selection.location - line.location), replacement: indent,
                                    selection: NSRange(location: line.location + (indent as NSString).length, length: 0))
            }
            let nextMarker: String
            if let number = Int(marker.dropLast()), number < Int.max {
                nextMarker = String(number + 1) + String(marker.suffix(1))
            } else {
                nextMarker = marker
            }
            let task = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
            let value = "\n" + indent + nextMarker + " " + task
            return MarkdownEdit(range: selection, replacement: value, selection: NSRange(location: selection.location + (value as NSString).length, length: 0))
        }
        if let match = firstMatch(#"^([ \t]*(?:>[ \t]*)+)(.*)$"#, in: before) {
            let part = before as NSString
            let prefix = part.substring(with: match.range(at: 1))
            let content = part.substring(with: match.range(at: 2))
            if content.trimmingCharacters(in: .whitespaces).isEmpty && after.trimmingCharacters(in: .whitespaces).isEmpty {
                return MarkdownEdit(range: NSRange(location: line.location, length: selection.location - line.location), replacement: "",
                                    selection: NSRange(location: line.location, length: 0))
            }
            let value = "\n" + prefix
            return MarkdownEdit(range: selection, replacement: value, selection: NSRange(location: selection.location + (value as NSString).length, length: 0))
        }
        guard !indentation.isEmpty else { return nil }
        let value = "\n" + indentation
        return MarkdownEdit(range: selection, replacement: value, selection: NSRange(location: selection.location + (value as NSString).length, length: 0))
    }

    static func isInFence(_ text: String, at location: Int) -> Bool {
        let prefix = (text as NSString).substring(to: location)
        var fence: (character: Character, count: Int)?
        for line in prefix.components(separatedBy: .newlines) {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            guard leadingSpaces <= 3 else { continue }
            let content = line.dropFirst(leadingSpaces)
            guard let first = content.first, first == "`" || first == "~" else { continue }
            let length = content.prefix(while: { $0 == first }).count
            guard length >= 3 else { continue }
            if let open = fence {
                if first == open.character && length >= open.count && content.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
            } else if first != "`" || !content.dropFirst(length).contains("`") {
                fence = (first, length)
            }
        }
        return fence != nil
    }

    private static func selectedLineRange(_ source: NSString, selection: NSRange) -> NSRange {
        // An end point at the next line's start does not select that next line.
        let effective = selection.length > 0 ? NSRange(location: selection.location, length: selection.length - 1) : selection
        return source.lineRange(for: effective)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
