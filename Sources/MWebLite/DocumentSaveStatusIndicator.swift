import MWebCore
import SwiftUI

enum DocumentSaveStatus: Equatable {
    case unavailable, unsaved, saving, saved, failed

    var symbol: String {
        switch self {
        case .unavailable: return "minus.circle.fill"
        case .unsaved: return "clock.fill"
        case .saving: return "arrow.triangle.2.circlepath.circle.fill"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .unavailable: return L10n.string("No Article Selected")
        case .unsaved: return L10n.string("Unsaved")
        case .saving: return L10n.string("Saving")
        case .saved: return L10n.string("Saved Locally")
        case .failed: return L10n.string("Save Failed")
        }
    }

    var help: String {
        switch self {
        case .unavailable: return L10n.string("Select an article to see its local save status")
        case .unsaved: return L10n.string("Unsaved changes will save automatically when you stop typing · ⌘S to save now")
        case .saving: return L10n.string("Saving changes to the local library")
        case .saved: return L10n.string("The current content is saved to the local library")
        case .failed: return L10n.string("Changes are not saved. Resolve the error, then press ⌘S to retry.")
        }
    }
}

/// Show save feedback only while changes still need to reach the local library.
struct DocumentSaveStatusIndicator: View {
    let status: DocumentSaveStatus

    var body: some View {
        switch status {
        case .unsaved, .saving, .failed:
            Image(systemName: status.symbol)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .help(status.help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("Local save status"))
                .accessibilityValue(status.title)
                .accessibilityIdentifier("document-save-status")
        case .saved, .unavailable:
            EmptyView()
        }
    }
}
