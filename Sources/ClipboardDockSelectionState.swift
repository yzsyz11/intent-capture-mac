import Foundation

struct ClipboardDockSelectionState {
    private(set) var isActive = false
    private(set) var selectedIDs: Set<String> = []

    mutating func enter() {
        isActive = true
        selectedIDs.removeAll()
    }

    mutating func cancel() {
        isActive = false
        selectedIDs.removeAll()
    }

    mutating func toggle(id: String) {
        guard isActive else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    mutating func selectAll(ids: [String]) {
        guard isActive else { return }
        selectedIDs = Set(ids)
    }
}
