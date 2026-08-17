import SwiftUI

@main
struct FlashCardsApp: App {
    @StateObject private var store = Store()
    @StateObject private var ai = AIStore()

    var body: some Scene {
        WindowGroup {
            DeckListView()
                .environmentObject(store)
                .environmentObject(ai)
        }
    }
}
