//
//  TutorialView.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/27/26.
//

import AppKit
import SwiftUI

struct TutorialView: View {
    @ObservedObject var viewModel: TutorialViewModel
    private var settings: AppSettings { viewModel.settings }
    
    @State var currentPage: Int = 3
    
    var body: some View {
        ZStack {
            Image("Wallpaper")
                .resizable()
                .antialiased(true)
                .interpolation(.high)
                .scaledToFill()
            
            Group {
                switch currentPage {
                case 0:
                    VStack {
                        Text("Welcome to ConType!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .shadow(radius: 10)
                        
                        Button("Continue") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                        .roundGlassProminent()
                    }
                    .transition(.opacity)
                    
                    
                case 1:
                    VStack {
                        Text("Before we begin the tutorial, would you like to look over the settings?")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                        
                        Button("Open Settings") {
                            // Open Settings
                        }
                        .roundGlassProminent()
                        
                        Button("Continue") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                        .roundGlassProminent()
                    }
                    .transition(.opacity)
                    
                case 2:
                    VStack {
                        Text("Let's try opening the keyboard.")
                            .font(.title2)
                            .foregroundStyle(.white)
                        
                        Text("Pick up your controller and press the following buttons.")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                        
                        viewModel.keyboardShortcut()
                            .padding(4)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        
                        Text("You can change this in the settings")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    
                case 3:
                    VStack {
                        Text("Great! Welcome to the keyboard overlay.")
                            .font(.title2)
                            .foregroundStyle(.white)
                        
                        Text("This is where ConType comes into action. Try moving around the keyboard with")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                        
                        viewModel.keyboardAxisBindings()
                            .padding(4)
                            .padding(.horizontal, 8)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .transition(.opacity)
                    
                    // Move in the Keyboard
                    
                    // Try typing "Hello World!" (Show shift shortcut)
                    
                    // Open the mouse (Listen for mouse shortcut)
                    
                    // Move the mouse
                    
                default:
                    // Press (Guide Button) or (Shortcut) to end tutorial
                    
                    VStack {
                        Text("This is the end of the tutorial. Enjoy using ConType!")
                            .font(.title2)
                            .foregroundStyle(.white)
                        
                        Button("Close") {
                            // Close window
                        }
                        .roundGlassProminent()
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

#Preview {
    let vm = TutorialViewModel(
        settings: AppSettings()
    )
    
    TutorialView(viewModel: vm)
}
