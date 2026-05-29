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
    let settings: AppSettings
    
    var body: some View {
        GeometryReader { proxy in
            let maxKeyboardWidth = min(proxy.size.width * 0.9, 1440)
            let maxKeyboardHeight = min(proxy.size.height * 0.6, 540)
            
            ZStack {
                Image("Wallpaper")
                    .resizable()
                    .antialiased(true)
                    .interpolation(.high)
                    .scaledToFill()
                    .ignoresSafeArea()
                
                switch viewModel.currentPage {
                case 0:
                    VStack {
                        Text("Welcome to ConType!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .shadow(radius: 10)
                        
                        Button("Continue") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.nextPage()
                            }
                        }
                        .roundGlassProminent()
                    }
                    .padding(.top)
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
                                viewModel.nextPage()
                            }
                        }
                        .roundGlassProminent()
                    }
                    .padding(.top)
                    .transition(.opacity)
                    
                case 2:
                    VStack {
                        Text("About your controller.")
                            .font(.title2)
                            .foregroundStyle(.white)
                        if viewModel.displayedGuideButtons().count < 1 {
                            Text("Oops, please connect your controller to proceed.")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                        }  else {
                            Group {
                                if viewModel.displayedGuideButtons().count == 1 {
                                    Text("Below is what we call your controller's guide Button. This powers the shortcuts of the app.")
                                } else if viewModel.displayedGuideButtons().count > 1 {
                                    Text("Below are what we call the controller's guide Buttons. These power the shortcuts of the app.")
                                }
                            }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                            
                            viewModel.guideButtons()
                                .padding(4)
                                .padding(.horizontal, 8)
                                .glassEffect(
                                    .clear,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            
                            Divider()
                                .frame(maxWidth: 512)
                            
                            Group {
                                if viewModel.displayedGuideButtons().count == 1 {
                                    Text("When you see the following glyph, it represents your controller's guide button. To use it, just press the corresponding button above.")
                                } else if viewModel.displayedGuideButtons().count > 1 {
                                    Text("When you see the following glyph, it represents your controller's guide buttons. To use it, just press the corresponding buttons above.")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: 512)
                            
                            viewModel.genericGuideGlyph(size: 32)
                                .padding(4)
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 44)
                                .glassEffect(
                                    .clear,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            
                            Button("Continue") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        viewModel.nextPage()
                                    }
                                }
                                .roundGlassProminent()
                        }
                    }
                    .padding(.top)
                    .transition(.opacity)
                    
                case 3:
                    VStack {
                        Text("Let's try opening the keyboard.")
                            .font(.title2)
                            .foregroundStyle(.white)
                        
                        Text("Pick up your controller and press the following buttons.")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                        
                        viewModel.controllerShortcut(for: .keyboardToggle)
                            .padding(4)
                            .glassEffect(
                                .clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        
                        Text("You can change this in the settings")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                    .padding(.top)
                    .transition(.opacity)
                    
                case 4:
                    VStack {
                        
                        Spacer()
                        
                        if !viewModel.firstMoveDetected {
                            Group {
                                Text("Great! Welcome to the keyboard overlay.")
                                    .font(.title2)
                                
                                Text("This is where ConType comes into action. Try moving around the keyboard with")
                                    .font(.headline)
                                    .padding(.horizontal, 8)
                                
                                viewModel.keyboardAxisBindings()
                                    .padding(4)
                                    .padding(.horizontal, 8)
                                    .glassEffect(
                                        .clear,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                            }
                            .transition(.opacity.combined(with: .slide))
                            .foregroundStyle(.white)
                            
                            Spacer()
                        } else if viewModel.firstMoveDetected {
                            Group {
                                if !viewModel.completedTyping {
                                    Text("Good job! Now let's try typing. Type the following words to continue.")
                                        .font(.title2)
                                        .padding(.horizontal, 8)
                                    
                                    Text("Hello ConType!")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .padding(8)
                                        .padding(.horizontal, 12)
                                        .glassEffect(
                                            .clear,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                } else if viewModel.firstMoveDetected && viewModel.completedTyping {
                                    Text("Well done!")
                                        .font(.title2)
                                        .padding(.horizontal, 8)
                                    
                                    if settings.dismissWithGuideButton {
                                        Group {
                                            if viewModel.displayedGuideButtons().count == 1 {
                                                Text("To proceeed, dismiss the keyboard by pressing the button below")
                                            } else {
                                                Text("To proceeed, dismiss the keyboard by pressing one of the buttons below")
                                            }
                                        }
                                        .font(.headline)
                                        .padding(.horizontal, 8)
                                        
                                        viewModel.guideButtons()
                                            .padding(4)
                                            .padding(.horizontal, 8)
                                            .glassEffect(
                                                .clear,
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                    } else {
                                        Text("To proceeed, dismiss the keyboard by pressing the following shortcut buttons again.")
                                            .font(.headline)
                                            .padding(.horizontal, 8)
                                        
                                        viewModel.keyboardAxisBindings()
                                            .padding(4)
                                            .padding(.horizontal, 8)
                                            .glassEffect(
                                                .clear,
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                    }
                                }
                                
                                viewModel.pseudoTextFieldView()
                                
                                Text("Notice the controller button in some keys like shift? Try pressing those buttons on your controller and see what happens!")
                                    .foregroundStyle(.white)
                                    .transition(.opacity)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                            .transition(.opacity.combined(with: .slide))
                            .foregroundStyle(.white)
                        }
                        
                        KeyboardOverlayView(
                            viewModel: viewModel.keyboardViewModel,
                            onKeyPressed: { key, flags in
                                viewModel.onKeyPressed(key, flags)
                            }
                        )
                        .frame(maxWidth: maxKeyboardWidth, maxHeight: maxKeyboardHeight)
                        .aspectRatio(8/3, contentMode: .fit)
                        
                        Spacer()
                    }
                    .padding(.top)
                    .transition(.opacity)
                    .onChange(of: viewModel.pseudoTextField) {
                        if viewModel.pseudoTextField == "Hello ConType!" {
                            viewModel.completedTyping = true
                        }
                    }
                    
                case 5:
                    VStack {
                        Text("Now let's try opening the mouse overlay.")
                            .font(.title2)
                            .foregroundStyle(.white)
                        
                        Text("Press the following buttons.")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                        
                        viewModel.controllerShortcut(for: .mouseToggle)
                            .padding(4)
                            .glassEffect(
                                .clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        
                        Text("You can change this in the settings")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                    .padding(.top)
                    .transition(.opacity)
                    
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
                    .padding(.top)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

#Preview {
    TutorialView(viewModel: TutorialViewModel(settings: AppSettings()), settings: AppSettings())
}
