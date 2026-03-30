import AppKit
import Carbon.HIToolbox
import Foundation

final class PasteEmitter {
    private let keyEmitter = KeyEmitter()

    func pasteText(_ text: String, addReturn: Bool) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        let paste = keyEmitter.send(KeyStroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand]))
        if addReturn {
            _ = keyEmitter.send(TerminalControl.enter.keyStroke)
        }
        return paste
    }
}
