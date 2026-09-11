import AppKit
import SwiftUI
import Darwin

// Diagnostic runner: synthetic text only, private storage, no clipboard monitor.
// The visible test window does not request Accessibility or synthesize input.
@main struct MemoryProfile {
    @MainActor static func footprint(_ label: String, model: HistoryModel? = nil) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { fatalError("task_info failed") }
        print("\(label): footprint=\(Double(info.phys_footprint)/1048576) MiB rows=\(model?.entries.count ?? 0) cache=\(model?.previewCache.byteUsage ?? 0)")
        fflush(stdout)
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stash-memory-\(UUID())")
        let suite = "stash-memory-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName:suite) }
        let store = try ClipboardStore(root:root, defaults:defaults)
        for i in 0..<500 { _ = store.saveText("Sample \(i): " + String(repeating:"Bounded clipboard preview. ",count:15),sourceApp:"Fixture") }
        let model = HistoryModel(store:store,defaults:defaults)
        footprint("before UI",model:model)
        let window = NSPanel(contentRect:NSRect(x:0,y:0,width:740,height:540),styleMask:[.titled],backing:.buffered,defer:false)
        window.title = "Stash memory benchmark — sample data"
        window.isReleasedWhenClosed = false
        for cycle in 1...3 {
            model.isPresented = true
            model.reload()
            window.contentView = NSHostingView(rootView:HistoryView(model:model))
            window.orderFront(nil)
            try await Task.sleep(for:.seconds(1))
            footprint("cycle \(cycle) open",model:model)
            for _ in 0..<2 {
                for _ in 0..<50 {
                    model.moveSelection(by:10)
                    try await Task.sleep(for:.milliseconds(25))
                }
                for _ in 0..<50 {
                    model.moveSelection(by:-10)
                    try await Task.sleep(for:.milliseconds(25))
                }
            }
            footprint("cycle \(cycle) scrolled",model:model)
            model.dismiss(); window.orderOut(nil); window.contentView = nil
            try await Task.sleep(for:.seconds(2))
            footprint("cycle \(cycle) closed",model:model)
        }
        window.close()
    }
}
