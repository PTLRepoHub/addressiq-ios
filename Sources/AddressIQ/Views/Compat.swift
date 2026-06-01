import SwiftUI

@available(iOS 15.0, *)
extension View {
    /// `scrollContentBackground(.hidden)` is iOS 16+. On iOS 15 this is a
    /// no-op — the TextEditor keeps its default background. Lets the verify
    /// UI compile and run on the iOS 15 floor while honoring the hidden
    /// background on iOS 16+.
    @ViewBuilder
    func hiddenScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
