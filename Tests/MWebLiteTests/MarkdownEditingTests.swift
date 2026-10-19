import Foundation
import XCTest
@testable import MWebLite

final class MarkdownEditingTests: XCTestCase {
    func testListContinuationAndEmptyItemExit() throws {
        try assertNewline("- 中文", becomes: "- 中文\n- ")
        try assertNewline("  9. 中文", becomes: "  9. 中文\n  10. ")
        try assertNewline("- [x] 完成", becomes: "- [x] 完成\n- [ ] ")
        try assertNewline("- [ ] ", becomes: "")
        try assertNewline("    - ", becomes: "    ")
        try assertNewline("> 引用", becomes: "> 引用\n> ")
        try assertNewline("> ", becomes: "")
    }

    func testFencedCodeDoesNotContinueMarkdownLists() throws {
        try assertNewline("```swift\n- 中文", becomes: "```swift\n- 中文\n")
        try assertNewline("```\n    code", becomes: "```\n    code\n    ")
        try assertNewline("~~~~\n```\n- code", becomes: "~~~~\n```\n- code\n")
        try assertNewline("````\n```\n- code", becomes: "````\n```\n- code\n")
        try assertNewline("```\ncode\n```\n- done", becomes: "```\ncode\n```\n- done\n- ")
    }

    func testFormattingPreservesUTF16Selections() {
        let text = "中文 😀"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let wrapped = MarkdownEditing.wrap(text, selection: selection, before: "**", after: "**")
        XCTAssertEqual(apply(text, wrapped), "**中文 😀**")
        XCTAssertEqual(wrapped.selection, NSRange(location: 2, length: 5))
        let unwrapped = MarkdownEditing.wrap("**中文 😀**", selection: wrapped.selection, before: "**", after: "**")
        XCTAssertEqual(apply("**中文 😀**", unwrapped), text)
        XCTAssertEqual(unwrapped.selection, selection)
    }

    func testItalicCanBeAppliedInsideBoldAndToggledOff() {
        let bold = "**中文 😀**"
        let italic = MarkdownEditing.wrap(bold, selection: NSRange(location: 2, length: 5), before: "*", after: "*")
        XCTAssertEqual(apply(bold, italic), "***中文 😀***")
        let toggled = MarkdownEditing.wrap(apply(bold, italic), selection: italic.selection, before: "*", after: "*")
        XCTAssertEqual(apply(apply(bold, italic), toggled), bold)
        let fullSelection = MarkdownEditing.wrap(bold, selection: NSRange(location: 0, length: (bold as NSString).length), before: "*", after: "*")
        XCTAssertEqual(apply(bold, fullSelection), "***中文 😀***")
    }

    func testIndentExcludesNextLineAtSelectionBoundary() {
        let source = "first\nsecond\nthird"
        let selection = NSRange(location: 0, length: 13)
        let indented = MarkdownEditing.indent(source, selection: selection, outdent: false)
        XCTAssertEqual(apply(source, indented), "    first\n    second\nthird")
        let outdented = MarkdownEditing.indent(apply(source, indented), selection: indented.selection, outdent: true)
        XCTAssertEqual(apply(apply(source, indented), outdented), source)
        XCTAssertEqual(outdented.selection, selection)
    }

    func testOutdentClampsCursorInsideRemovedIndentation() {
        let edit = MarkdownEditing.indent("  中文", selection: NSRange(location: 1, length: 0), outdent: true)
        XCTAssertEqual(edit.selection, NSRange(location: 0, length: 0))
        XCTAssertEqual(apply("  中文", edit), "中文")
    }

    func testLinkSelectsDestinationForImmediateReplacement() {
        let edit = MarkdownEditing.link("测试", selection: NSRange(location: 0, length: 2))
        XCTAssertEqual(apply("测试", edit), "[测试](https://)")
        XCTAssertEqual((edit.replacement as NSString).substring(with: edit.selection), "https://")
    }

    func testLinePrefixCanBeToggledWithoutIncludingNextLine() {
        let source = "中文\nemoji 😀\nother"
        let selection = NSRange(location: 0, length: 12)
        let quote = MarkdownEditing.prefixLines(source, selection: selection, prefix: "> ")
        XCTAssertEqual(apply(source, quote), "> 中文\n> emoji 😀\nother")
        let unquote = MarkdownEditing.prefixLines(apply(source, quote), selection: quote.selection, prefix: "> ")
        XCTAssertEqual(apply(apply(source, quote), unquote), source)
    }

    private func assertNewline(_ source: String, becomes expected: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let range = NSRange(location: (source as NSString).length, length: 0)
        let edit = try XCTUnwrap(MarkdownEditing.newline(source, selection: range), file: file, line: line)
        XCTAssertEqual(apply(source, edit), expected, file: file, line: line)
        XCTAssertLessThanOrEqual(NSMaxRange(edit.selection), (expected as NSString).length, file: file, line: line)
    }

    private func apply(_ source: String, _ edit: MarkdownEdit) -> String {
        (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
}
