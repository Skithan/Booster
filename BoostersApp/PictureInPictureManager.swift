//
//  PictureInPictureManager.swift
//  BoostersApp
//
//  Created by Ethan Alward on 2025-11-24.
//

import SwiftUI
import AVKit
import UIKit

class PictureInPictureManager: NSObject, ObservableObject {
    
    @Published var isPiPSupported = false
    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var dummyPlayer: AVPlayer?
    
    override init() {
        super.init()
        setupPictureInPicture()
    }
    
    private func setupPictureInPicture() {
        // Check if PiP is supported on this device
        isPiPSupported = AVPictureInPictureController.isPictureInPictureSupported()
        
        guard isPiPSupported else {
            print("Picture in Picture is not supported on this device")
            return
        }
        
        // Create a dummy video player (required for PiP)
        // We'll use a transparent/minimal video to enable PiP controls
        createDummyPlayer()
        setupPiPController()
    }
    
    private func createDummyPlayer() {
        // Create a minimal, transparent video for PiP functionality
        // This is a workaround since PiP requires a video player
        guard let path = Bundle.main.path(forResource: "transparent", ofType: "mp4") else {
            // If no video file exists, create a basic AVPlayer
            dummyPlayer = AVPlayer()
            return
        }
        
        let url = URL(fileURLWithPath: path)
        dummyPlayer = AVPlayer(url: url)
        
        // Set up the player layer
        playerLayer = AVPlayerLayer(player: dummyPlayer)
        playerLayer?.videoGravity = .resizeAspect
        playerLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: 1) // Minimal size
        playerLayer?.opacity = 0.01 // Nearly transparent
    }
    
    private func setupPiPController() {
        guard let playerLayer = playerLayer else { return }
        
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        
        // Check if PiP can be started
        updatePiPPossible()
    }
    
    private func updatePiPPossible() {
        isPiPPossible = pipController?.isPictureInPicturePossible ?? false
    }
    
    func startPictureInPicture() {
        guard let pipController = pipController,
              pipController.isPictureInPicturePossible else {
            print("Picture in Picture is not possible right now")
            return
        }
        
        // Start the dummy player if needed
        dummyPlayer?.play()
        
        pipController.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
    
    func addPlayerLayerToView(_ view: UIView) {
        guard let playerLayer = playerLayer else { return }
        view.layer.addSublayer(playerLayer)
        updatePiPPossible()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureManager: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
        }
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("Picture in Picture started")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("Failed to start Picture in Picture: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("Picture in Picture stopped")
        dummyPlayer?.pause()
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // This is called when user taps the PiP window to restore the full app
        completionHandler(true)
    }
}
