import SwiftUI

/// 四个页面：今日 / 衣橱 / 搭配 / 日历与我的（阶段3 · 3.1）
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
                HistoryView()
            }
            .tabItem { Label("日历与我的", systemImage: "calendar") }
        }
        .tint(Color.accentColor)
    }
}
