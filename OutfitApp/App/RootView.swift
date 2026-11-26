import SwiftUI

/// 四个页面：今日 / 衣橱 / 搭配 / 我的
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("今日", systemImage: "sun.max") }

            NavigationStack {
                WardrobeView()
            }
            .tabItem { Label("衣橱", systemImage: "tshirt") }

            NavigationStack {
                OutfitTabView()
            }
            .tabItem { Label("搭配", systemImage: "square.grid.2x2") }

            NavigationStack {
                MyView()
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(Color.accentColor)
    }
}
