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
                        Label("Welcome to ConType!", systemImage: "flag.pattern.checkered")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .shadow(radius: 10)
                            .transition(.symbolEffect)
                        
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
                        Label("Before we begin the tutorial, would you like to look over the settings?", systemImage: "gear")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .transition(.symbolEffect)
                        
                        Button("Open Settings") {
                            viewModel.openSettings?()
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
                        Label("About your controller.", systemImage: "gamecontroller.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .transition(.symbolEffect)
                        if viewModel.displayedGuideButtons().count < 1 {
                            Text("Oops, please connect your controller to proceed.")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                        } else {
                            Group {
                                if viewModel.displayedGuideButtons().count == 1 {
                                    Text("Below is what we call your controller's guide Button. This powers the shortcuts of the app.")
                                } else if viewModel.displayedGuideButtons().count > 1 {
                                    Text("Below are what we call the controller's guide Buttons. These power the shortcuts of the app.")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 500)
                            
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
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 500)
                            
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
                    .animation(.easeInOut(duration: 0.3), value: settings.detectedController)
                    
                case 3:
                    VStack {
                        Label("Let's try opening the keyboard.", systemImage: "keyboard.badge.eye.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .transition(.symbolEffect)
                        
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
                        
                        if !viewModel.keyboardMoved {
                            Group {
                                Label("Great! Welcome to the keyboard overlay.", systemImage: "keyboard.fill")
                                    .font(.title2)
                                    .transition(.symbolEffect)
                                
                                Text("This is where ConType comes into action. Try moving around the keyboard with")
                                    .font(.headline)
                                    .padding(.horizontal, 8)
                                
                                viewModel.axisBindings(for: .overlayMovement)
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
                        } else {
                            Group {
                                if !viewModel.completedTyping {
                                    Label("Good job! Now let's try typing. Type the following words to continue.", systemImage: "checkmark.circle.fill")
                                        .font(.title2)
                                        .padding(.horizontal, 8)
                                        .transition(.symbolEffect)
                                    
                                    Text("Hello ConType!")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .padding(8)
                                        .padding(.horizontal, 12)
                                        .glassEffect(
                                            .clear,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                } else if viewModel.keyboardMoved && viewModel.completedTyping {
                                    Label("Time to close the overlay.", systemImage: "x.circle.fill")
                                        .font(.title2)
                                    
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
                                            .animation(.spring(.bouncy, blendDuration: 0.3), value: settings.detectedController)
                                    } else {
                                        Text("To proceeed, dismiss the keyboard by pressing the following shortcut buttons again.")
                                            .font(.headline)
                                            .padding(.horizontal, 8)
                                        
                                        viewModel.axisBindings(for: .overlayMovement)
                                            .padding(4)
                                            .padding(.horizontal, 8)
                                            .glassEffect(
                                                .clear,
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                    }
                                }
                                
                                viewModel.pseudoTextFieldView()
                                    .padding(.horizontal, 12)
                                
                                if !viewModel.completedTyping {
                                    Text("Notice the controller button in some keys like shift? Try pressing those buttons on your controller and see what happens!")
                                        .foregroundStyle(.white)
                                        .transition(.opacity)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 500)
                                }
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
                        Label("Now let's try opening the mouse overlay.", systemImage: "pointer.arrow.square.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .transition(.symbolEffect)
                        
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
                    
                case 6:
                    ZStack(alignment: .bottomLeading) {
                        VStack {
                            Group {
                                if !viewModel.mouseMoved {
                                    Label("Welcome to the mouse overlay.", systemImage: "pointer.arrow.rays")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .transition(.symbolEffect)
                                    
                                    Text("When the bubble is on-screen, it means ConType is in mouse mode. In this mode, ConType only simulates mouse inputs. Try moving the mouse around with.")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 500)
                                    
                                    viewModel.axisBindings(for: .mouseMovement)
                                        .padding(4)
                                        .padding(.horizontal, 8)
                                        .glassEffect(
                                            .clear,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                } else if !viewModel.completedMousing {
                                    Label("Great job!", systemImage: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .transition(.symbolEffect)
                                    
                                    Text("Now try clicking the container below. Use the button indicated inside the container to click.")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 500)
                                    
                                    viewModel.mouseClickButtons()
                                        .padding(4)
                                        .padding(.horizontal, 8)
                                        .glassEffect(
                                            .clear
                                            .tint(
                                                viewModel.mouseButtonFrameDown
                                                ? .gray
                                                : nil
                                            ),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .background(
                                            GeometryReader { targetProxy in
                                                Color.clear
                                                    .onAppear {
                                                        viewModel.mouseButtonFrame = targetProxy.frame(in: .named("TutorialLocalSpace"))
                                                    }
                                                    .onChange(of: targetProxy.frame(in: .named("TutorialLocalSpace"))) { oldFrame, newFrame in
                                                        viewModel.mouseButtonFrame = newFrame
                                                    }
                                            }
                                        )
                                } else {
                                    Label("Time to close the overlay.", systemImage: "x.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .transition(.symbolEffect)
                                    
                                    if settings.dismissWithGuideButton {
                                        Group {
                                            if viewModel.displayedGuideButtons().count == 1 {
                                                Text("To proceeed, dismiss the mouse overlay by pressing the button below")
                                            } else {
                                                Text("To proceeed, dismiss the mouse overlay by pressing one of the buttons below")
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
                                            .animation(.spring(.bouncy, blendDuration: 0.3), value: settings.detectedController)
                                    } else {
                                        Text("To proceeed, dismiss the mouse overlay by pressing the following shortcut buttons again.")
                                            .font(.headline)
                                            .padding(.horizontal, 8)
                                        
                                        viewModel.axisBindings(for: .mouseMovement)
                                            .padding(4)
                                            .padding(.horizontal, 8)
                                            .glassEffect(
                                                .clear,
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        MouseOverlayView(onPress: viewModel.onMouseOverlayPressed)
                            .padding(16)
                        
                        viewModel.mouseCursorLayer(proxy, mousePos: viewModel.mousePosition)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear {
                                viewModel.mousePosition = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            }
                    }
                    .padding(.top)
                    .transition(.opacity)
                    .coordinateSpace(name: "TutorialLocalSpace")
                    
                default:
                    VStack {
                        Label("This is the end of the tutorial. Enjoy using ConType!", systemImage: "flag.pattern.checkered")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .transition(.symbolEffect)
                        
                        Button("Close") {
                            viewModel.onComplete?()
                        }
                        .roundGlassProminent()
                    }
                    .padding(.top)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                viewModel.viewProxy = proxy
            }
            .onChange(of: proxy.size) {
                viewModel.viewProxy = proxy
                viewModel.reclampMouse()
            }
        }
    }
}

#Preview {
    TutorialView(viewModel: TutorialViewModel(settings: AppSettings()), settings: AppSettings())
        .frame(width: 960, height: 540)
}
