import Foundation

/// Extracts image destinations without resolving paths or loading media.
public enum MarkdownImageReferences {
    public static func firstImages(in markdown: String, limit: Int = 4) -> [String] {
        let maximum = min(4, max(0, limit))
        guard maximum > 0 else { return [] }
        var source = Array(markdown.utf8)
        maskCodeAndComments(in: &source)
        let definitions = referenceDefinitions(in: &source)
        var images: [String] = []
        var index = 0
        while index < source.count, images.count < maximum {
            if source[index] == 92 {
                index += 2
                continue
            }
            if source[index] == 60, let end = htmlTagEnd(in: source, from: index) {
                let tag = String(decoding: source[index..<end], as: UTF8.self)
                if let destination = htmlImageSource(tag), !destination.isEmpty {
                    images.append(destination)
                }
                index = end
                continue
            }
            guard source[index] == 33, index + 1 < source.count, source[index + 1] == 91,
                  let close = closingBracket(in: source, from: index + 1) else {
                index += 1
                continue
            }
            let label = String(decoding: source[(index + 2)..<close], as: UTF8.self)
            var next = close + 1
            var destination: String?
            if next < source.count, source[next] == 40,
               let inline = inlineDestination(in: source, from: next + 1) {
                destination = inline.value
                next = inline.end
            } else if next < source.count, source[next] == 91,
                      let referenceEnd = closingBracket(in: source, from: next) {
                let explicit = String(decoding: source[(next + 1)..<referenceEnd], as: UTF8.self)
                destination = definitions[normalizedLabel(explicit.isEmpty ? label : explicit)]
                next = referenceEnd + 1
            } else {
                destination = definitions[normalizedLabel(label)]
            }
            if let destination, !destination.isEmpty { images.append(destination) }
            index = next
        }
        return images
    }

    private static func maskCodeAndComments(in source: inout [UInt8]) {
        var fence: (marker: UInt8, count: Int)?
        var previousLineBlank = true
        var inIndentedCode = false
        var listIndent: Int?
        var index = 0
        while index < source.count {
            if index == 0 || source[index - 1] == 10 {
                let lineEnd = source[index...].firstIndex(of: 10) ?? source.count
                var start = index
                while start < lineEnd, source[start] == 32, start - index < 3 { start += 1 }
                // Blockquotes may contain fenced code with their own indentation.
                while start < lineEnd, source[start] == 62 {
                    start += 1
                    var spaces = 0
                    while start < lineEnd, source[start] == 32, spaces < 3 { start += 1; spaces += 1 }
                }
                var marker: (value: UInt8, count: Int, end: Int)?
                if start < lineEnd, source[start] == 96 || source[start] == 126 {
                    var end = start
                    while end < lineEnd, source[end] == source[start] { end += 1 }
                    marker = (source[start], end - start, end)
                }
                if let active = fence {
                    if let marker, marker.value == active.marker, marker.count >= active.count,
                       source[marker.end..<lineEnd].allSatisfy({ isWhitespace($0) }) {
                        fence = nil
                    }
                    mask(index..<lineEnd, in: &source)
                    previousLineBlank = true
                    index = lineEnd + 1
                    continue
                } else if let marker, marker.count >= 3,
                          marker.value != 96 || !source[marker.end..<lineEnd].contains(96) {
                    fence = (marker.value, marker.count)
                    mask(index..<lineEnd, in: &source)
                    previousLineBlank = true
                    index = lineEnd + 1
                    continue
                }
                var contentStart = index
                var indentation = 0
                while contentStart < lineEnd, source[contentStart] == 32 || source[contentStart] == 9 {
                    indentation += source[contentStart] == 9 ? 4 - indentation % 4 : 1
                    contentStart += 1
                }
                if contentStart == lineEnd || source[contentStart] == 13 {
                    previousLineBlank = true
                } else {
                    if indentation <= 3, let markerWidth = listMarkerWidth(in: source, from: contentStart, until: lineEnd) {
                        listIndent = indentation + markerWidth
                    } else if indentation < (listIndent ?? 1) {
                        listIndent = nil
                    }
                    if indentation - (listIndent ?? 0) >= 4, previousLineBlank || inIndentedCode {
                        mask(index..<lineEnd, in: &source)
                        inIndentedCode = true
                        previousLineBlank = false
                        index = lineEnd + 1
                        continue
                    }
                    inIndentedCode = false
                    previousLineBlank = false
                }
            }
            if source[index] == 92 { index += 2; continue }
            if matches([60, 33, 45, 45], in: source, at: index) {
                var end = index + 4
                while end < source.count, !matches([45, 45, 62], in: source, at: end) { end += 1 }
                end = min(source.count, end + 3)
                mask(index..<end, in: &source)
                index = end
            } else if source[index] == 96 {
                var start = index
                while start < source.count, source[start] == 96 { start += 1 }
                let count = start - index
                var end = start
                var closing: Int?
                while end < source.count {
                    if source[end] != 96 { end += 1; continue }
                    let runStart = end
                    while end < source.count, source[end] == 96 { end += 1 }
                    if end - runStart == count { closing = end; break }
                }
                if let closing {
                    mask(index..<closing, in: &source)
                    index = closing
                } else {
                    index = start
                }
            } else {
                index += 1
            }
        }
    }

    private static func listMarkerWidth(in source: [UInt8], from start: Int, until end: Int) -> Int? {
        var cursor = start
        if [42, 43, 45].contains(source[cursor]) {
            cursor += 1
        } else {
            while cursor < end, (48...57).contains(source[cursor]), cursor - start < 9 { cursor += 1 }
            guard cursor > start, cursor < end, source[cursor] == 46 || source[cursor] == 41 else { return nil }
            cursor += 1
        }
        guard cursor < end, source[cursor] == 32 || source[cursor] == 9 else { return nil }
        return cursor - start + (source[cursor] == 9 ? 4 : 1)
    }

    private static func referenceDefinitions(in source: inout [UInt8]) -> [String: String] {
        var definitions: [String: String] = [:]
        var lineStart = 0
        while lineStart < source.count {
            let lineEnd = source[lineStart...].firstIndex(of: 10) ?? source.count
            var start = lineStart
            while start < lineEnd, source[start] == 32, start - lineStart < 3 { start += 1 }
            if start < lineEnd, source[start] == 91,
               let close = closingBracket(in: source, from: start), close + 1 < lineEnd,
               source[close + 1] == 58 {
                let label = normalizedLabel(String(decoding: source[(start + 1)..<close], as: UTF8.self))
                var cursor = close + 2
                while cursor < lineEnd, isWhitespace(source[cursor]) { cursor += 1 }
                if !label.isEmpty, let parsed = destination(in: source, from: cursor, until: lineEnd) {
                    if definitions[label] == nil { definitions[label] = parsed.value }
                    mask(lineStart..<lineEnd, in: &source)
                }
            }
            lineStart = lineEnd + 1
        }
        return definitions
    }

    private static func closingBracket(in source: [UInt8], from start: Int) -> Int? {
        var depth = 1
        var index = start + 1
        while index < source.count {
            if source[index] == 92 { index += 2; continue }
            if source[index] == 91 { depth += 1 }
            if source[index] == 93 {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func inlineDestination(in source: [UInt8], from start: Int) -> (value: String, end: Int)? {
        var cursor = start
        while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
        guard let parsed = destination(in: source, from: cursor, until: source.count) else { return nil }
        cursor = parsed.end
        let hasSeparator = cursor < source.count && isWhitespace(source[cursor])
        while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
        if hasSeparator, cursor < source.count, [34, 39, 40].contains(source[cursor]) {
            let closing: UInt8 = source[cursor] == 40 ? 41 : source[cursor]
            cursor += 1
            while cursor < source.count, source[cursor] != closing {
                cursor += source[cursor] == 92 ? 2 : 1
            }
            guard cursor < source.count else { return nil }
            cursor += 1
            while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
        }
        guard cursor < source.count, source[cursor] == 41 else { return nil }
        return (parsed.value, cursor + 1)
    }

    private static func destination(in source: [UInt8], from start: Int, until end: Int) -> (value: String, end: Int)? {
        guard start < end else { return nil }
        var cursor = start
        if source[cursor] == 60 {
            cursor += 1
            let valueStart = cursor
            while cursor < end, source[cursor] != 62 {
                if source[cursor] == 10 || source[cursor] == 13 || source[cursor] == 60 { return nil }
                cursor += source[cursor] == 92 ? 2 : 1
            }
            guard cursor < end else { return nil }
            return (decoded(String(decoding: source[valueStart..<cursor], as: UTF8.self)), cursor + 1)
        }
        var depth = 0
        while cursor < end, !isWhitespace(source[cursor]) {
            if source[cursor] == 92 { cursor += min(2, end - cursor); continue }
            if source[cursor] == 40 {
                depth += 1
                if depth > 32 { return nil }
            } else if source[cursor] == 41 {
                if depth == 0 { break }
                depth -= 1
            }
            cursor += 1
        }
        guard depth == 0 else { return nil }
        return (decoded(String(decoding: source[start..<cursor], as: UTF8.self)), cursor)
    }

    private static func htmlTagEnd(in source: [UInt8], from start: Int) -> Int? {
        guard start + 1 < source.count,
              (65...90).contains(source[start + 1]) || (97...122).contains(source[start + 1])
                || source[start + 1] == 47 else { return nil }
        var quote: UInt8?
        var cursor = start + 1
        while cursor < source.count {
            if let active = quote {
                if source[cursor] == active { quote = nil }
            } else if source[cursor] == 34 || source[cursor] == 39 {
                quote = source[cursor]
            } else if source[cursor] == 62 {
                return cursor + 1
            }
            cursor += 1
        }
        return nil
    }

    private static func htmlImageSource(_ tag: String) -> String? {
        guard tag.range(of: #"(?i)^<img(?:\s|/?>)"#, options: .regularExpression) != nil else { return nil }
        let source = Array(tag.utf8)
        var cursor = 4
        while cursor < source.count {
            while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
            guard cursor < source.count, source[cursor] != 62, source[cursor] != 47 else { break }
            let nameStart = cursor
            while cursor < source.count, !isWhitespace(source[cursor]), ![61, 62, 47].contains(source[cursor]) {
                cursor += 1
            }
            let name = String(decoding: source[nameStart..<cursor], as: UTF8.self).lowercased()
            while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
            guard cursor < source.count, source[cursor] == 61 else { continue }
            cursor += 1
            while cursor < source.count, isWhitespace(source[cursor]) { cursor += 1 }
            guard cursor < source.count else { break }
            let quote: UInt8? = source[cursor] == 34 || source[cursor] == 39 ? source[cursor] : nil
            if quote != nil { cursor += 1 }
            let valueStart = cursor
            while cursor < source.count {
                if let quote {
                    if source[cursor] == quote { break }
                } else if isWhitespace(source[cursor]) || source[cursor] == 62 {
                    break
                }
                cursor += 1
            }
            let value = String(decoding: source[valueStart..<cursor], as: UTF8.self)
            if quote != nil, cursor < source.count { cursor += 1 }
            if name == "src" { return decoded(value) }
        }
        return nil
    }

    private static func normalizedLabel(_ value: String) -> String {
        decoded(value).split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func decoded(_ value: String) -> String {
        let unescaped = value.replacingOccurrences(of: #"\\([!-/:-@\[-`{-~])"#, with: "$1", options: .regularExpression)
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        guard let expression = try? NSRegularExpression(pattern: #"&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|amp|lt|gt|quot|apos);"#) else { return unescaped }
        let text = unescaped as NSString
        var result = unescaped
        for match in expression.matches(in: unescaped, range: NSRange(location: 0, length: text.length)).reversed() {
            let entity = text.substring(with: match.range(at: 1))
            let replacement: String?
            if entity.hasPrefix("#") {
                let hex = entity.dropFirst().hasPrefix("x") || entity.dropFirst().hasPrefix("X")
                replacement = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10)
                    .flatMap { UnicodeScalar($0) }.map { String($0) }
            } else {
                replacement = named[entity]
            }
            if let replacement, let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func isWhitespace(_ value: UInt8) -> Bool {
        value == 32 || value == 9 || value == 10 || value == 13
    }

    private static func matches(_ token: [UInt8], in source: [UInt8], at index: Int) -> Bool {
        index + token.count <= source.count && source[index..<(index + token.count)].elementsEqual(token)
    }

    private static func mask(_ range: Range<Int>, in source: inout [UInt8]) {
        for index in range where source[index] != 10 && source[index] != 13 { source[index] = 32 }
    }
}
