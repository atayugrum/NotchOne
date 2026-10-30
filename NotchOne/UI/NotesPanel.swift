import SwiftUI

/// Notes tab: one quick scratchpad that saves as you type.
struct NotesPanel: View {
    @Bindable var notes: NotesStore
    let model: NotchViewModel
    @FocusState private var focused: Bool
    @State private var copied = false
    /// Clear needs a second press, so a note isn't lost to one click.
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(Typo.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(Space.s)
                if notes.text.isEmpty {
                    Text("Jot something down. It stays on this Mac and is saved as you type.")
                        .font(Typo.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Space.s + 5)
                        .padding(.vertical, Space.s)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard()

            HStack(spacing: Space.s) {
                Text("\(notes.text.count) characters")
                    .font(Typo.micro)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                PillButton(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", isEnabled: !notes.isEmpty) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes.text, forType: .string)
                    withAnimation(Motion.quick) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(Motion.quick) { copied = false }
                    }
                }
                PillButton(title: confirmingClear ? "Clear?" : "Clear", symbol: "trash", tint: confirmingClear ? .red : .white, isEnabled: !notes.isEmpty) {
                    if confirmingClear {
                        notes.clear()
                        confirmingClear = false
                        focused = true
                    } else {
                        withAnimation(Motion.quick) { confirmingClear = true }
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation(Motion.quick) { confirmingClear = false }
                        }
                    }
                }
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { focused = true }
        .onDisappear { notes.saveNow() }
    }
}
