import Foundation

private enum SelectionTestFailure: Error {
    case assertion(String)
}

@main
struct ClipboardDockSelectionTests {
    static func main() throws {
        try inactiveStateIgnoresSelectionChanges()
        try selectionStateTracksExplicitChoices()
        try batchDeleteRemovesOnlyRequestedItems()
        print("clipboard dock selection tests passed.")
    }

    private static func inactiveStateIgnoresSelectionChanges() throws {
        var state = ClipboardDockSelectionState()
        state.toggle(id: "must-not-select")
        state.selectAll(ids: ["first", "second"])
        try expect(state.selectedIDs.isEmpty, "未进入删除模式时不能选中任何卡片")
    }

    private static func selectionStateTracksExplicitChoices() throws {
        var state = ClipboardDockSelectionState()
        state.enter()
        state.toggle(id: "first")
        state.toggle(id: "second")

        try expect(state.isActive, "进入删除模式后状态必须为 active")
        try expect(state.selectedIDs == Set(["first", "second"]), "卡片点击必须切换对应 ID 的选中状态")

        state.toggle(id: "first")
        try expect(state.selectedIDs == Set(["second"]), "再次点击已选卡片必须取消选中")

        state.cancel()
        try expect(!state.isActive && state.selectedIDs.isEmpty, "取消删除必须退出模式并清空选择")

        state.enter()
        state.selectAll(ids: ["first", "second", "third"])
        try expect(state.selectedIDs == Set(["first", "second", "third"]), "全选必须包含传入的全部 ID")
    }

    private static func batchDeleteRemovesOnlyRequestedItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntentCaptureSelectionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let records = [makeItem(id: "keep"), makeItem(id: "delete-a"), makeItem(id: "delete-b")]
        let data = try JSONEncoder().encode(records)
        try data.write(to: root.appendingPathComponent("index.json"), options: .atomic)

        let store = ClipboardHistoryStore(rootDirectory: root)
        var changeCount = 0
        store.onChange = { _ in changeCount += 1 }
        store.delete(ids: Set(["delete-a", "delete-b"]))

        try expect(store.items.map(\.id) == ["keep"], "批量删除只能移除显式选中的记录")
        try expect(changeCount == 1, "一次批量删除只能触发一次界面刷新")

        let savedData = try Data(contentsOf: root.appendingPathComponent("index.json"))
        let saved = try JSONDecoder().decode([ClipboardHistoryItem].self, from: savedData)
        try expect(saved.map(\.id) == ["keep"], "批量删除结果必须一次性持久化")
    }

    private static func makeItem(id: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 0),
            preview: id,
            detail: "文字",
            fingerprint: "text:\(id)",
            imageFilename: nil,
            imageWidth: nil,
            imageHeight: nil
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelectionTestFailure.assertion(message) }
    }
}
