//
//  SeekerApp.swift
//  Seeker
//
//  Created by Tucker Reeve Blackwell on 9/4/25.
//

import SwiftUI
import AppKit

@main
struct SeekerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We manage our own AppKit window; keep SwiftUI window hidden
        WindowGroup { EmptyView() }
            .windowStyle(.hiddenTitleBar)
        Settings {
            Text("Seeker Preferences")
                .padding()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wc: LinearWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua) // optional default dark
        let root = SeekerRootViewController()
        wc = LinearWindowController(content: root)
        wc.showWindow(self)
    }
}
