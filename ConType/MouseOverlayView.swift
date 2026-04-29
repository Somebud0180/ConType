//
//  MouseOverlayView.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/29/26.
//

import SwiftUI

struct MouseOverlayView: View {
    @ObservedObject var settings: AppSettings
    @State var isPressed = false
    
    var body: some View {
        ZStack {
            Button(action: {
                withAnimation {
                    settings.inMouseMode = false
                }
            }) {
                Image(systemName: "pointer.arrow.rays")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .clear
                .interactive(),
                in: Circle()
            )
        }
        .frame(width: 64, height: 64)
    }
}

#Preview {
    MouseOverlayView(settings: AppSettings())
        .frame(width: 128, height: 128)
}
