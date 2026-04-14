//
//  ConTypeApp.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/5/26.
//

import SwiftUI

@main
struct ConTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("ConType", image: "extrasicon") {
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
