//
//  MouseOverlayView.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/29/26.
//

import SwiftUI

struct MouseOverlayView: View {
    var onPress: () -> Void
    
    var body: some View {
        ZStack {
            Button(action: {
                onPress()
            }) {
                Image(systemName: "pointer.arrow.rays")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular
                .interactive(),
                in: Circle()
            )
        }
        .frame(width: 64, height: 64)
    }
}

#Preview {
    MouseOverlayView() {
        debugPrint("Mouse overlay pressed")
    }
        .frame(width: 128, height: 128)
}
