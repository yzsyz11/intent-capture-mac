import Foundation

enum CaptureAction: String, CaseIterable, Codable {
    case screenshotCopy
    case screenshotSave
    case screenshotSaveAndCopy
    case ocrCopy
    case pickColor

    var title: String {
        switch self {
        case .screenshotCopy: return "截图复制"
        case .screenshotSave: return "截图保存"
        case .screenshotSaveAndCopy: return "保存并复制"
        case .ocrCopy: return "OCR 复制"
        case .pickColor: return "取色复制"
        }
    }

    var detail: String {
        switch self {
        case .screenshotCopy: return "框选区域，复制图片"
        case .screenshotSave: return "框选区域，保存 PNG"
        case .screenshotSaveAndCopy: return "保存文件，同时复制图片"
        case .ocrCopy: return "框选文字，复制识别结果"
        case .pickColor: return "点击像素，复制色号"
        }
    }
}
