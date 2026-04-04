//
//  ABXY_TypeApp.swift
//  ABXY Type
//
//  Created by Ethan John Lagera on 4/5/26.
//

import SwiftUI

@main
struct ABXY_TypeApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("ABXY Type", systemImage: "gamecontroller") {
            Button(coordinator.isOverlayVisible ? "Hide Keyboard Overlay" : "Show Keyboard Overlay") {
                coordinator.toggleOverlay()
            }

            Button("Settings") {
                coordinator.openSettings()
            }

            Divider()

            Button("Quit") {
                coordinator.quit()
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
