import SwiftUI

enum DocumentSaveStatus: Equatable {
    case unavailable, unsaved, saving, saved, failed

    var symbol: String {
        switch self {
        case .unavailable: return "minus.circle"
        case .unsaved: return "clock"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    var title: String {
        switch self {
        case .unavailable: return "未选择文章"
        case .unsaved: return "尚未保存"
        case .saving: return "正在保存"
        case .saved: return "已保存到本地"
        case .failed: return "保存失败"
        }
    }

    var help: String {
        switch self {
        case .unavailable: return "选择文章后显示本地保存状态"
        case .unsaved: return "修改尚未保存，停止输入后会自动保存 · ⌘S 立即保存"
        case .saving: return "正在将修改保存到本地文库"
        case .saved: return "当前内容已保存到本地文库"
        case .failed: return "修改尚未保存，请处理错误提示后按 ⌘S 重试"
        }
    }
}

/// Keep one fixed-width indicator mounted in both editor and preview modes.
struct DocumentSaveStatusIndicator: View {
    let status: DocumentSaveStatus

    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: 14, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .help(status.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本地保存状态")
            .accessibilityValue(status.title)
            .accessibilityIdentifier("document-save-status")
    }
}
