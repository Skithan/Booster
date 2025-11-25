//
//  PiPPlayerView.swift
//  BoostersApp
//
//  Created by Ethan Alward on 2025-11-24.
//

import SwiftUI
import UIKit

struct PiPPlayerView: UIViewRepresentable {
    let pipManager: PictureInPictureManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // Add the player layer to enable PiP
        pipManager.addPlayerLayerToView(view)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Updates handled by PiP manager
    }
}
