import AppKit

final class DefaultBrowserRadioGroupView: NSStackView {
    override func keyDown(with event: NSEvent) {
        let step: Int
        switch event.keyCode {
        case 123, 126: step = -1
        case 124, 125: step = 1
        default:
            super.keyDown(with: event)
            return
        }
        let buttons = arrangedSubviews.compactMap { $0 as? NSButton }
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let focused = window?.firstResponder as? NSButton,
              let index = buttons.firstIndex(of: focused)
        else {
            super.keyDown(with: event)
            return
        }
        let next = buttons[(index + step + buttons.count) % buttons.count]
        window?.makeFirstResponder(next)
        next.performClick(nil)
    }
}
