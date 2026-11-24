import SwiftUI
import SwiftData

@main
struct OutfitAppApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: ClothingItem.self,
                Outfit.self,
                WearLog.self,
                Inspiration.self,
                StyleRule.self
            )
        } catch {
            fatalError("本地数据库初始化失败：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
