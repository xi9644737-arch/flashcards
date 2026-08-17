import SwiftUI

@main
struct FlashCardsApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            DeckListView()
                .environmentObject(store)
        }
    }
}
