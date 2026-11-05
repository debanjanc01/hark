import AppKit
import HarkCore

/// The list of developer terms Hark fixes, where the person can see and change all of it.
@MainActor
enum DeveloperWordsEditor {
    /// Returns whether the list changed.
    static func run(settings: Settings) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Developer Words"
        alert.informativeText = """
            Hark fixes these terms when what it heard sounds close and the words around it fit. \
            Each line is the term, then how it can sound.

            Hark keeps getting one wrong? Add what it writes after the colon, like “kubectl: cube cattle”. \
            That's then always replaced.
            """
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restore Defaults")

        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 260)
        scroll.borderType = .bezelBorder
        let text = scroll.documentView as! NSTextView
        text.string = settings.developerWordsList
        text.font = .preferredFont(forTextStyle: .body)
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.textContainerInset = NSSize(width: 4, height: 6)
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = text

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            settings.developerWordsList = text.string
        case .alertThirdButtonReturn:
            settings.developerWordsList = DeveloperWords.defaults.list
        default:
            return false
        }
        return true
    }
}
