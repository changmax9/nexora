import AppKit
import SwiftUI

/// A native field owns the field editor, including clicks from another app.
struct MenuBarSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onEditingChanged: onEditingChanged) }

    func makeNSView(context: Context) -> NSTextField {
        let field = ClickToEditSearchField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEditingChanged = onEditingChanged
        (field as? ClickToEditSearchField)?.setSearchPlaceholder(placeholder)
        context.coordinator.update(field: field, value: text)
        (field as? ClickToEditSearchField)?.updateFieldEditorAppearance()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onEditingChanged: (Bool) -> Void
        private var lastPublishedText: String
        init(text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) {
            self.text = text
            self.onEditingChanged = onEditingChanged
            lastPublishedText = text.wrappedValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { onEditingChanged(true) }
        func controlTextDidEndEditing(_ notification: Notification) { onEditingChanged(false) }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let editor = field.currentEditor() as? NSTextView
            guard editor?.hasMarkedText() != true else { return }
            let value = editor?.string ?? field.stringValue
            lastPublishedText = value
            if text.wrappedValue != value { text.wrappedValue = value }
        }

        func update(field: NSTextField, value: String) {
            if let editor = field.currentEditor() as? NSTextView {
                // SwiftUI may refresh before AppKit publishes the next edit.
                // Never put the old model value back into an active editor.
                guard value != lastPublishedText, !editor.hasMarkedText() else { return }
                lastPublishedText = value
                if editor.string != value {
                    let location = min(editor.selectedRange().location, value.utf16.count)
                    editor.string = value
                    editor.setSelectedRange(NSRange(location: location, length: 0))
                    editor.didChangeText()
                }
            } else {
                lastPublishedText = value
                if field.stringValue != value { field.stringValue = value }
            }
        }
    }
}

final class ClickToEditSearchField: NSTextField {
    private var searchPlaceholder: String?
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { updateFieldEditorAppearance() }
        return accepted
    }

    override func textDidBeginEditing(_ notification: Notification) {
        placeholderString = nil
        super.textDidBeginEditing(notification)
        updateFieldEditorAppearance()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        placeholderString = searchPlaceholder
    }

    func setSearchPlaceholder(_ value: String) {
        searchPlaceholder = value
        placeholderString = currentEditor() == nil ? value : nil
    }

    func updateFieldEditorAppearance() {
        // The field editor is a separate NSTextView. Its default fill/focus
        // chrome must not replace the SwiftUI glass while this field is edited.
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.focusRingType = .none
        editor.insertionPointColor = .labelColor
    }
}

struct NativeSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
