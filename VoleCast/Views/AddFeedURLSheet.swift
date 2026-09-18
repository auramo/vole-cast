import SwiftUI

/// Subscribing to a feed URL directly — the path that always works, whatever a
/// directory does or doesn't know about.
struct AddFeedURLSheet: View {
    let onContinue: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var url: URL? { FeedURL.normalize(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed.xml", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)
                    if let pasted = pasteboardURL, pasted != url {
                        Button("Paste \(pasted.host() ?? pasted.absoluteString)", systemImage: "doc.on.clipboard") {
                            text = pasted.absoluteString
                        }
                    }
                } footer: {
                    Text("Paste the RSS feed address of a podcast. Look for an RSS or feed link on the show's website.")
                }
            }
            .navigationTitle("Add by RSS URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        guard let url else { return }
                        dismiss()
                        onContinue(url)
                    }
                    .disabled(url == nil)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var pasteboardURL: URL? {
        guard UIPasteboard.general.hasStrings, let string = UIPasteboard.general.string else {
            return nil
        }
        return FeedURL.normalize(string)
    }
}

#Preview {
    AddFeedURLSheet { _ in }
}
