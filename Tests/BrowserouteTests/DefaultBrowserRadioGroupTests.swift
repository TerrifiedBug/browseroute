@testable import Browseroute
import AppKit
import Testing

@Suite(.serialized)
@MainActor
struct DefaultBrowserRadioGroupTests {
    @Test(arguments: [UInt16(123), 124, 125, 126])
    func `arrows move selection and focus together`(_ keyCode: UInt16) throws {
        let fixture = Fixture(count: 3, selected: 1)
        defer { fixture.window.close() }
        try fixture.press(keyCode)
        let expected = keyCode == 123 || keyCode == 126 ? 0 : 2
        #expect(fixture.selection.index == expected)
        #expect(fixture.window.firstResponder === fixture.buttons[expected])
        #expect(fixture.buttons.filter { $0.state == .on }.count == 1)
    }

    @Test(arguments: [UInt16(123), 124, 125, 126])
    func `arrows wrap at group boundaries`(_ keyCode: UInt16) throws {
        let backwards = keyCode == 123 || keyCode == 126
        let fixture = Fixture(count: 3, selected: backwards ? 0 : 2)
        defer { fixture.window.close() }
        try fixture.press(keyCode)
        let expected = backwards ? 2 : 0
        #expect(fixture.selection.index == expected)
        #expect(fixture.window.firstResponder === fixture.buttons[expected])
    }

    @Test func `single browser stays selected`() throws {
        let fixture = Fixture(count: 1, selected: 0)
        defer { fixture.window.close() }
        for code: UInt16 in [123, 124, 125, 126] {
            try fixture.press(code)
            #expect(fixture.selection.index == 0)
            #expect(fixture.buttons[0].state == .on)
            #expect(fixture.window.firstResponder === fixture.buttons[0])
        }
    }

    @Test func `modified arrows do not change default`() throws {
        let fixture = Fixture(count: 3, selected: 1)
        defer { fixture.window.close() }
        for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
            try fixture.press(125, flags: flags)
            #expect(fixture.selection.index == 1)
            #expect(fixture.selection.activations == 0)
        }
    }

    @MainActor
    private final class Selection: NSObject {
        var index: Int
        var activations = 0

        init(index: Int) {
            self.index = index
        }

        @objc func select(_ sender: NSButton) {
            index = sender.tag
            activations += 1
        }
    }

    @MainActor
    private struct Fixture {
        let window: NSWindow
        let group: DefaultBrowserRadioGroupView
        let buttons: [NSButton]
        let selection: Selection

        init(count: Int, selected: Int) {
            _ = NSApplication.shared
            let selection = Selection(index: selected)
            self.selection = selection
            group = DefaultBrowserRadioGroupView()
            group.orientation = .vertical
            buttons = (0 ..< count).map { index in
                let button = NSButton(
                    radioButtonWithTitle: "Browser \(index)",
                    target: selection,
                    action: #selector(Selection.select(_:)),
                )
                button.tag = index
                button.state = index == selected ? .on : .off
                return button
            }
            for button in buttons {
                group.addArrangedSubview(button)
            }
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            window.contentView = group
            window.makeFirstResponder(buttons[selected])
        }

        func press(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode,
            ))
            group.keyDown(with: event)
        }
    }
}
