import AppKit
import SwiftUI
import Testing
@testable import ClashGlassCore

@Suite(.serialized)
@MainActor
struct MenuBarSearchEditingTests {
    @Test func nativeEditingKeepsContinuousTextAndDeleteCommandsWorking() throws {
        let fixture = try SearchEditingFixture()
        defer { fixture.close() }
        let editor = try #require(fixture.editor)
        editor.insertText("香港HK", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.refresh()
        #expect(fixture.text == "香港HK")
        #expect(editor.string == "香港HK")
        #expect(editor.selectedRange() == NSRange(location: 4, length: 0))

        editor.deleteBackward(nil)
        fixture.refresh()
        #expect(fixture.text == "香港H")
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0))

        editor.setSelectedRange(NSRange(location: 0, length: 3))
        editor.deleteBackward(nil)
        fixture.refresh()
        #expect(fixture.text.isEmpty)
        #expect(editor.string.isEmpty)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(fixture.window.firstResponder === editor)
    }

    @Test func clearFromSwiftUIDoesNotLeaveAnOldEditorValueOrSelection() throws {
        let fixture = try SearchEditingFixture()
        defer { fixture.close() }
        fixture.editor.insertText("日本JP01", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.refresh()
        fixture.text = ""
        fixture.refresh()
        #expect(fixture.editor.string.isEmpty)
        #expect(fixture.field.stringValue.isEmpty)
        #expect(fixture.editor.selectedRange() == NSRange(location: 0, length: 0))
        fixture.editor.insertText("HK", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.refresh()
        #expect(fixture.text == "HK")
    }
}

@MainActor
private final class SearchEditingFixture {
    var text = ""
    let window: NSWindow
    let field: ClickToEditSearchField
    private(set) var editor: NSTextView!
    private var coordinator: MenuBarSearchField.Coordinator!

    init() throws {
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        field = ClickToEditSearchField(frame: NSRect(x: 10, y: 15, width: 300, height: 28))
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.setSearchPlaceholder("Search")
        coordinator = MenuBarSearchField.Coordinator(text: Binding(
            get: { [unowned self] in self.text }, set: { [unowned self] in self.text = $0 }
        ), onEditingChanged: { _ in })
        field.delegate = coordinator
        window.contentView?.addSubview(field)
        field.selectText(nil)
        editor = try #require(field.currentEditor() as? NSTextView)
    }

    func refresh() { coordinator.update(field: field, value: text) }
    func close() { window.makeFirstResponder(nil); window.close() }
}
