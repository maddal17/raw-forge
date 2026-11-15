import AppKit
import Foundation

/// Installs local keyboard shortcuts (`1`-`9`, `0`, `\`, arrow navigation, mode switches) while preserving text fields.
@MainActor
final class KeyEventMonitor {
    private var monitor: Any?

    func install(for viewModel: AppViewModel) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            guard let viewModel else { return event }

            // Never steal keystrokes while user is typing in any text field or search box
            if event.window?.firstResponder is NSText || event.window?.firstResponder is NSTextView {
                return event
            }
            if viewModel.activeModal != nil {
                return event
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control])
            if flags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "1":
                    viewModel.workspaceMode = .list
                    return nil
                case "2":
                    viewModel.workspaceMode = .loupe
                    return nil
                case "e":
                    viewModel.openExportSheet()
                    return nil
                case "a":
                    viewModel.selectAllVisible()
                    return nil
                default:
                    return event
                }
            }

            guard flags.isEmpty else { return event }

            switch event.keyCode {
            case 123: // Left arrow
                viewModel.stepActivePhoto(delta: -1)
                return nil
            case 124: // Right arrow
                viewModel.stepActivePhoto(delta: 1)
                return nil
            case 125: // Down arrow
                viewModel.stepActivePhoto(delta: 1)
                return nil
            case 126: // Up arrow
                viewModel.stepActivePhoto(delta: -1)
                return nil
            default:
                break
            }

            guard let chars = event.charactersIgnoringModifiers?.lowercased(), let ch = chars.first else {
                return event
            }

            if ch >= "1" && ch <= "9", let num = Int(String(ch)) {
                viewModel.assignByShortcutNumber(num)
                return nil
            }
            switch ch {
            case "0":
                viewModel.assignByShortcutNumber(0)
                return nil
            case "\\":
                viewModel.showBeforeOriginal.toggle()
                viewModel.scheduleLoupeRender(draft: false)
                return nil
            case "g":
                viewModel.workspaceMode = .list
                return nil
            case "d":
                viewModel.workspaceMode = .loupe
                return nil
            default:
                return event
            }
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
