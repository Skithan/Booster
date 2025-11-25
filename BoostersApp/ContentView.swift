//
//  ContentView.swift
//  BoostersApp
//
//  Created by Ethan Alward on 2025-11-24.
//

import SwiftUI
import CoreBluetooth
import Combine
import AVKit

// MARK: - Data Models

/// Represents a single booster wheel on the golf cart
struct BoosterWheel: Identifiable {
    let id = UUID()
    let position: WheelPosition
    var isConnected: Bool = false
    var batteryLevel: Int? = nil
    var speed: Double = 0.0 // -1.0 to 1.0 (negative = reverse)
    var peripheral: CBPeripheral?
    
    init(position: WheelPosition) {
        self.position = position
    }
}

/// Position of the wheel on the golf cart
enum WheelPosition: String, CaseIterable {
    case left = "Left"
    case right = "Right"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Connection status of the booster system
enum ConnectionStatus: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected, .error:
            return .red
        case .scanning, .connecting:
            return .orange
        case .connected:
            return .green
        }
    }
}

/// Joystick input data
struct JoystickInput: Equatable {
    let x: Double // -1.0 to 1.0 (left to right)
    let y: Double // -1.0 to 1.0 (backward to forward)
    let magnitude: Double // 0.0 to 1.0
    
    init(x: Double, y: Double) {
        self.x = max(-1.0, min(1.0, x))
        self.y = max(-1.0, min(1.0, y))
        self.magnitude = min(1.0, sqrt(x * x + y * y))
    }
    
    static let zero = JoystickInput(x: 0, y: 0)
}

/// Motor control command for a wheel
struct MotorCommand {
    let wheelPosition: WheelPosition
    let speed: Double // -1.0 to 1.0
    let timestamp: Date
    
    init(wheelPosition: WheelPosition, speed: Double) {
        self.wheelPosition = wheelPosition
        self.speed = max(-1.0, min(1.0, speed))
        self.timestamp = Date()
    }
}

// MARK: - Motor Controller

class MotorController: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var leftWheelCommand: MotorCommand = MotorCommand(wheelPosition: .left, speed: 0)
    @Published private(set) var rightWheelCommand: MotorCommand = MotorCommand(wheelPosition: .right, speed: 0)
    
    @Published var maxSpeedMultiplier: Double = 0.8
    @Published var steeringSensitivity: Double = 1.0
    @Published var deadZone: Double = 0.05
    
    // MARK: - Public Methods
    
    func processJoystickInput(_ input: JoystickInput) {
        let adjustedInput = applyDeadZone(input)
        let (leftSpeed, rightSpeed) = calculateDifferentialSteering(
            forward: adjustedInput.y,
            turn: adjustedInput.x
        )
        
        let finalLeftSpeed = leftSpeed * maxSpeedMultiplier
        let finalRightSpeed = rightSpeed * maxSpeedMultiplier
        
        leftWheelCommand = MotorCommand(wheelPosition: .left, speed: finalLeftSpeed)
        rightWheelCommand = MotorCommand(wheelPosition: .right, speed: finalRightSpeed)
    }
    
    func emergencyStop() {
        leftWheelCommand = MotorCommand(wheelPosition: .left, speed: 0)
        rightWheelCommand = MotorCommand(wheelPosition: .right, speed: 0)
    }
    
    // MARK: - Private Methods
    
    private func applyDeadZone(_ input: JoystickInput) -> JoystickInput {
        if input.magnitude < deadZone {
            return JoystickInput.zero
        }
        
        let scaledMagnitude = (input.magnitude - deadZone) / (1.0 - deadZone)
        let scale = scaledMagnitude / input.magnitude
        
        return JoystickInput(x: input.x * scale, y: input.y * scale)
    }
    
    private func calculateDifferentialSteering(forward: Double, turn: Double) -> (Double, Double) {
        let adjustedTurn = turn * steeringSensitivity
        
        var leftSpeed = forward + adjustedTurn
        var rightSpeed = forward - adjustedTurn
        
        let maxSpeed = max(abs(leftSpeed), abs(rightSpeed))
        if maxSpeed > 1.0 {
            leftSpeed /= maxSpeed
            rightSpeed /= maxSpeed
        }
        
        return (leftSpeed, rightSpeed)
    }
    
    var speedDescription: String {
        return String(format: "L: %.2f, R: %.2f", leftWheelCommand.speed, rightWheelCommand.speed)
    }
    
    var isMoving: Bool {
        return abs(leftWheelCommand.speed) > 0.01 || abs(rightWheelCommand.speed) > 0.01
    }
    
    var movementDirection: String {
        let avgSpeed = (leftWheelCommand.speed + rightWheelCommand.speed) / 2.0
        let turnRate = leftWheelCommand.speed - rightWheelCommand.speed
        
        if abs(avgSpeed) < 0.1 && abs(turnRate) < 0.1 {
            return "Stopped"
        } else if abs(turnRate) > abs(avgSpeed) {
            return turnRate > 0 ? "Turning Right" : "Turning Left"
        } else {
            return avgSpeed > 0 ? "Forward" : "Backward"
        }
    }
}

// MARK: - Joystick View

struct JoystickView: View {
    
    @Binding var joystickInput: JoystickInput
    @State private var knobPosition: CGPoint = .zero
    @State private var isDragging: Bool = false
    
    // Adaptive sizing based on available space
    private var knobSize: CGFloat { 
        let calculatedSize = baseSize * 0.4
        return min(80, max(20, calculatedSize))
    }
    private var baseSize: CGFloat { 
        // Responsive base size - adapts to screen size
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let minDimension = min(screenWidth, screenHeight)
        
        // For very small windows (minimized), use much smaller sizes
        if minDimension < 300 {
            return min(120, max(60, minDimension * 0.6))
        }
        
        return min(200, max(140, screenWidth * 0.5))
    }
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ZStack {
            // Base circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.6)
                        ]),
                        center: .center,
                        startRadius: baseSize * 0.2,
                        endRadius: baseSize * 0.5
                    )
                )
                .frame(width: baseSize, height: baseSize)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.8), lineWidth: 3)
                )
            
            // Center indicator
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
            
            // Direction indicators
            VStack {
                Text("Forward")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("Reverse")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(height: baseSize - 40)
            
            HStack {
                Text("L")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("R")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: baseSize - 40)
            
            // Knob
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            isDragging ? Color.blue : Color.white,
                            isDragging ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3)
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: knobSize * 0.5
                    )
                )
                .frame(width: knobSize, height: knobSize)
                .overlay(
                    Circle()
                        .stroke(
                            isDragging ? Color.blue.opacity(0.8) : Color.gray.opacity(0.8),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: isDragging ? 8 : 4, x: 2, y: 2)
                .position(
                    x: baseSize / 2 + knobPosition.x,
                    y: baseSize / 2 + knobPosition.y
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            handleDrag(value)
                        }
                        .onEnded { _ in
                            handleDragEnd()
                        }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: knobPosition)
                .animation(.easeInOut(duration: 0.2), value: isDragging)
        }
        .frame(width: baseSize, height: baseSize)
    }
    
    private func handleDrag(_ drag: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            hapticFeedback.impactOccurred()
        }
        
        let maxRadius = (baseSize - knobSize) / 2
        let center = CGPoint(x: baseSize / 2, y: baseSize / 2)
        let knobCenter = CGPoint(
            x: center.x + drag.translation.width,
            y: center.y + drag.translation.height
        )
        
        let distance = sqrt(
            pow(knobCenter.x - center.x, 2) + pow(knobCenter.y - center.y, 2)
        )
        
        if distance <= maxRadius {
            knobPosition = CGPoint(x: drag.translation.width, y: drag.translation.height)
        } else {
            let angle = atan2(knobCenter.y - center.y, knobCenter.x - center.x)
            knobPosition = CGPoint(
                x: cos(angle) * maxRadius,
                y: sin(angle) * maxRadius
            )
        }
        
        updateJoystickInput()
    }
    
    private func handleDragEnd() {
        isDragging = false
        knobPosition = .zero
        joystickInput = JoystickInput.zero
        hapticFeedback.impactOccurred()
    }
    
    private func updateJoystickInput() {
        let maxRadius = (baseSize - knobSize) / 2
        let normalizedX = knobPosition.x / maxRadius
        let normalizedY = -knobPosition.y / maxRadius // Invert Y for intuitive control
        
        joystickInput = JoystickInput(x: normalizedX, y: normalizedY)
    }
}

// MARK: - Main Content View

struct ContentView: View {
    
    @StateObject private var motorController = MotorController()
    @StateObject private var pipManager = PictureInPictureManager()
    @StateObject private var realBluetoothManager = RealBluetoothManager()
    @State private var joystickInput = JoystickInput.zero
    @State private var showSettings = false
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var leftWheel = BoosterWheel(position: .left)
    @State private var rightWheel = BoosterWheel(position: .right)
    @State private var isMinimized = false
    @State private var useRealBluetooth = false // Toggle between simulation and real hardware
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black,
                            Color.gray.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    // Invisible PiP player view (required for Picture-in-Picture)
                    PiPPlayerView(pipManager: pipManager)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                    
                    // Check if we should show minimized version or PiP mode
                    let windowIsMinimized = isWindowMinimized(geometry: geometry)
                    
                    if pipManager.isPiPActive {
                        // Picture-in-Picture is active - show minimal interface
                        pipModeLayout(in: geometry)
                    } else if connectionStatus == .connected && windowIsMinimized {
                        // Ultra-compact minimized layout when connected and window is small
                        minimizedLayout(in: geometry)
                    } else if geometry.size.width > geometry.size.height {
                        // Landscape/wide layout
                        landscapeLayout(in: geometry)
                    } else {
                        // Portrait/compact layout
                        portraitLayout(in: geometry)
                    }
                }
                .navigationBarHidden(true)
                .onChange(of: joystickInput) { _, newInput in
                    motorController.processJoystickInput(newInput)
                    updateMotorCommands() // Send to real hardware if connected
                }
                .onChange(of: geometry.size) { _, newSize in
                    // Update minimized state when window size changes
                    let wasMinimized = isMinimized
                    let nowMinimized = isWindowMinimized(geometry: geometry)
                    
                    if wasMinimized != nowMinimized && connectionStatus == .connected {
                        // Haptic feedback when entering/exiting minimized mode
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isMinimized = nowMinimized
                    }
                }
                .sheet(isPresented: $showSettings) {
                    settingsView
                }
            }
            .navigationViewStyle(StackNavigationViewStyle()) // Ensures single view in compact mode
            .onAppear {
                setupAudioSession()
            }
        }
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    private func isWindowMinimized(geometry: GeometryProxy) -> Bool {
        // Consider window minimized if:
        // 1. Very small area (less than 120,000 square points - typical for PiP)
        // 2. Very narrow width (less than 300 points)
        // 3. Very short height (less than 400 points)
        let area = geometry.size.width * geometry.size.height
        return area < 120000 || geometry.size.width < 300 || geometry.size.height < 400
    }
    
    // MARK: - Layout Variants
    
    @ViewBuilder
    private func portraitLayout(in geometry: GeometryProxy) -> some View {
        let isCompact = geometry.size.height < 600 || geometry.size.width < 400
        
        VStack(spacing: isCompact ? 8 : 20) {
            // Compact header
            compactHeaderView
            
            if !isCompact {
                // Wheel status cards (only show in larger views)
                wheelStatusView
            }
            
            Spacer(minLength: 0)
            
            // Joystick control - smaller in compact mode
            compactJoystickControlView(isCompact: isCompact)
            
            Spacer(minLength: 0)
            
            // Control buttons - compact version
            compactControlButtonsView
            
            if isCompact {
                // Show minimal status in compact mode
                compactStatusView
            }
        }
        .padding(isCompact ? 8 : 16)
    }
    
    @ViewBuilder
    private func landscapeLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 16) {
            // Left side - Controls and status
            VStack(spacing: 12) {
                compactHeaderView
                wheelStatusView
                Spacer()
                compactControlButtonsView
            }
            .frame(maxWidth: geometry.size.width * 0.4)
            
            Spacer()
            
            // Right side - Joystick
            VStack {
                Text("Joystick Control")
                    .font(.headline)
                    .foregroundColor(.white)
                
                JoystickView(joystickInput: $joystickInput)
                    .scaleEffect(0.8) // Slightly smaller in landscape
                
                compactJoystickInfo
            }
            .frame(maxWidth: geometry.size.width * 0.5)
        }
        .padding(16)
    }
    
    // MARK: - Minimized Layout
    
    @ViewBuilder
    private func minimizedLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 4) {
            // Ultra-minimal header
            HStack {
                Circle()
                    .fill(connectionStatus.color)
                    .frame(width: 6, height: 6)
                
                Text("Boosters")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Emergency stop only
                Button(action: {
                    motorController.emergencyStop()
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            Spacer(minLength: 0)
            
            // Compact joystick - takes most of the space
            JoystickView(joystickInput: $joystickInput)
                .scaleEffect(min(0.5, max(0.3, (min(geometry.size.width, geometry.size.height) - 60) / 200)))
                .frame(maxWidth: geometry.size.width - 16, maxHeight: geometry.size.height - 60)
            
            Spacer(minLength: 0)
            
            // Minimal status bar
            HStack(spacing: 8) {
                // Left wheel indicator
                VStack(spacing: 1) {
                    Text("L")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(Int(motorController.leftWheelCommand.speed * 100))%")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white)
                    Circle()
                        .fill(leftWheel.isConnected ? Color.green : Color.red)
                        .frame(width: 4, height: 4)
                }
                
                Spacer()
                
                // Power indicator
                Text("\(Int(joystickInput.magnitude * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.yellow)
                
                Spacer()
                
                // Right wheel indicator  
                VStack(spacing: 1) {
                    Text("R")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(Int(motorController.rightWheelCommand.speed * 100))%")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white)
                    Circle()
                        .fill(rightWheel.isConnected ? Color.green : Color.red)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
    
    // MARK: - Picture-in-Picture Layout
    
    @ViewBuilder
    private func pipModeLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 2) {
            // PiP header - ultra minimal
            HStack {
                Circle()
                    .fill(connectionStatus.color)
                    .frame(width: 4, height: 4)
                
                Text("Boosters")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Exit PiP button
                Button(action: {
                    pipManager.stopPictureInPicture()
                }) {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 6))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            Spacer(minLength: 0)
            
            // Micro joystick for PiP mode
            JoystickView(joystickInput: $joystickInput)
                .scaleEffect(0.25) // Very small for PiP
                .frame(maxWidth: 50, maxHeight: 50)
            
            Spacer(minLength: 0)
            
            // Micro status
            HStack(spacing: 4) {
                Text("L\(Int(motorController.leftWheelCommand.speed * 100))")
                    .font(.system(size: 4, weight: .semibold))
                    .foregroundColor(.white)
                
                Circle()
                    .fill(.yellow)
                    .frame(width: 2, height: 2)
                
                Text("R\(Int(motorController.rightWheelCommand.speed * 100))")
                    .font(.system(size: 4, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Golf Cart Boosters")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            
            HStack {
                Circle()
                    .fill(connectionStatus.color)
                    .frame(width: 12, height: 12)
                
                Text(connectionStatus.displayText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if motorController.isMoving {
                    Text(motorController.movementDirection)
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Compact Views
    
    private var compactHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Booster Control")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 8, height: 8)
                    
                    Text(connectionStatus.displayText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    if motorController.isMoving {
                        Text("• \(motorController.movementDirection)")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
    }
    
    private func compactJoystickControlView(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 16) {
            if !isCompact {
                Text("Joystick Control")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            JoystickView(joystickInput: $joystickInput)
                .scaleEffect(isCompact ? 0.7 : 1.0)
            
            if !isCompact {
                compactJoystickInfo
            }
        }
    }
    
    private var compactJoystickInfo: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("X: \(String(format: "%.2f", joystickInput.x))")
                Text("Y: \(String(format: "%.2f", joystickInput.y))")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("Power: \(String(format: "%.0f%%", joystickInput.magnitude * 100))")
                Text(motorController.speedDescription)
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var compactControlButtonsView: some View {
        HStack(spacing: 8) {
            // Emergency Stop
            Button(action: {
                motorController.emergencyStop()
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                    Text("STOP")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(width: 50, height: 45)
                .background(Color.red)
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Picture-in-Picture Button (only when connected and supported)
            if connectionStatus == .connected && pipManager.isPiPSupported {
                Button(action: {
                    if pipManager.isPiPActive {
                        pipManager.stopPictureInPicture()
                    } else {
                        pipManager.startPictureInPicture()
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.title3)
                        Text(pipManager.isPiPActive ? "Exit PiP" : "PiP")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 50, height: 45)
                    .background(pipManager.isPiPActive ? Color.purple : Color.indigo)
                    .cornerRadius(8)
                }
            }
            
            Spacer()
            
            // Bluetooth Mode Toggle
            Toggle("Real BT", isOn: $useRealBluetooth)
                .font(.caption2)
                .foregroundColor(.white)
                .frame(width: 55)
            
            // Connect/Disconnect 
            Button(action: {
                if useRealBluetooth {
                    handleRealBluetoothConnection()
                } else {
                    // Simulated connection
                    connectionStatus = connectionStatus == .connected ? .disconnected : .connected
                    leftWheel.isConnected = connectionStatus == .connected
                    rightWheel.isConnected = connectionStatus == .connected
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: getCurrentConnectionIcon())
                        .font(.title3)
                    Text(getCurrentConnectionText())
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .frame(width: 55, height: 45)
                .background(getCurrentConnectionColor())
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Battery Check (Simulated)
            Button(action: {
                // Simulate battery check
                leftWheel.batteryLevel = Int.random(in: 20...100)
                rightWheel.batteryLevel = Int.random(in: 20...100)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.title3)
                    Text("Battery")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .frame(width: 50, height: 45)
                .background(Color.green)
                .cornerRadius(8)
            }
        }
    }
    
    private var compactStatusView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("L: \(String(format: "%.0f%%", motorController.leftWheelCommand.speed * 100))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                Circle()
                    .fill(leftWheel.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
            }
            
            Spacer()
            
            Text("Power: \(String(format: "%.0f%%", joystickInput.magnitude * 100))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("R: \(String(format: "%.0f%%", motorController.rightWheelCommand.speed * 100))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                Circle()
                    .fill(rightWheel.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Wheel Status View
    
    private var wheelStatusView: some View {
        HStack(spacing: 16) {
            wheelCard(for: leftWheel, motorCommand: motorController.leftWheelCommand)
            wheelCard(for: rightWheel, motorCommand: motorController.rightWheelCommand)
        }
    }
    
    private func wheelCard(for wheel: BoosterWheel, motorCommand: MotorCommand) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(wheel.position.displayName) Wheel")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Circle()
                    .fill(wheel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.1f%%", motorCommand.speed * 100))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                if let batteryLevel = wheel.batteryLevel {
                    HStack {
                        Text("Battery:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(batteryLevel)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(batteryColor(for: batteryLevel))
                    }
                }
            }
            
            // Speed indicator bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(speedColor(for: motorCommand.speed))
                        .frame(
                            width: geometry.size.width * CGFloat(abs(motorCommand.speed)),
                            height: 6
                        )
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Joystick Control View
    
    private var joystickControlView: some View {
        VStack(spacing: 16) {
            Text("Joystick Control")
                .font(.headline)
                .foregroundColor(.white)
            
            JoystickView(joystickInput: $joystickInput)
            
            // Joystick info
            HStack {
                VStack(alignment: .leading) {
                    Text("X: \(String(format: "%.2f", joystickInput.x))")
                    Text("Y: \(String(format: "%.2f", joystickInput.y))")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Power: \(String(format: "%.0f%%", joystickInput.magnitude * 100))")
                    Text(motorController.speedDescription)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Control Buttons View
    
    private var controlButtonsView: some View {
        HStack(spacing: 20) {
            // Emergency Stop
            Button(action: {
                motorController.emergencyStop()
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
            }) {
                VStack {
                    Image(systemName: "hand.raised.fill")
                        .font(.title)
                    Text("STOP")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 60)
                .background(Color.red)
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Connect/Disconnect 
            Button(action: {
                if useRealBluetooth {
                    handleRealBluetoothConnection()
                } else {
                    // Simulated connection
                    connectionStatus = connectionStatus == .connected ? .disconnected : .connected
                    leftWheel.isConnected = connectionStatus == .connected
                    rightWheel.isConnected = connectionStatus == .connected
                }
            }) {
                VStack {
                    Image(systemName: connectionStatus == .connected ? "wifi.slash" : "wifi")
                        .font(.title2)
                    Text(connectionStatus == .connected ? "Disconnect" : "Connect")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 60)
                .background(connectionStatus == .connected ? Color.orange : Color.blue)
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Battery Check (Simulated)
            Button(action: {
                // Simulate battery check
                leftWheel.batteryLevel = Int.random(in: 20...100)
                rightWheel.batteryLevel = Int.random(in: 20...100)
            }) {
                VStack {
                    Image(systemName: "battery.100")
                        .font(.title2)
                    Text("Battery")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 60)
                .background(Color.green)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Settings View
    
    private var settingsView: some View {
        NavigationView {
            Form {
                Section("Motor Control") {
                    HStack {
                        Text("Max Speed")
                        Spacer()
                        Text("\(Int(motorController.maxSpeedMultiplier * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $motorController.maxSpeedMultiplier, in: 0.1...1.0, step: 0.1)
                    
                    HStack {
                        Text("Steering Sensitivity")
                        Spacer()
                        Text(String(format: "%.1f", motorController.steeringSensitivity))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $motorController.steeringSensitivity, in: 0.1...2.0, step: 0.1)
                    
                    HStack {
                        Text("Dead Zone")
                        Spacer()
                        Text(String(format: "%.2f", motorController.deadZone))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $motorController.deadZone, in: 0.0...0.2, step: 0.01)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func speedColor(for speed: Double) -> Color {
        if speed > 0 {
            return .green
        } else if speed < 0 {
            return .orange
        } else {
            return .gray
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        if level > 50 {
            return .green
        } else if level > 20 {
            return .yellow
        } else {
            return .red
        }
    }
    
    // MARK: - Bluetooth Helper Methods
    
    private func handleRealBluetoothConnection() {
        if realBluetoothManager.connectionStatus == .connected {
            realBluetoothManager.disconnectAll()
        } else {
            realBluetoothManager.startScanning()
        }
    }
    
    private func getCurrentConnectionIcon() -> String {
        if useRealBluetooth {
            switch realBluetoothManager.connectionStatus {
            case .disconnected:
                return "bluetooth"
            case .scanning:
                return "bluetooth"
            case .connecting:
                return "bluetooth"
            case .connected:
                return "bluetooth.slash"
            case .error:
                return "bluetooth.slash"
            }
        } else {
            return connectionStatus == .connected ? "wifi.slash" : "wifi"
        }
    }
    
    private func getCurrentConnectionText() -> String {
        if useRealBluetooth {
            switch realBluetoothManager.connectionStatus {
            case .disconnected:
                return "Scan"
            case .scanning:
                return "Scanning..."
            case .connecting:
                return "Connecting..."
            case .connected:
                return "Disconnect"
            case .error:
                return "Retry"
            }
        } else {
            return connectionStatus == .connected ? "Disconnect" : "Connect"
        }
    }
    
    private func getCurrentConnectionColor() -> Color {
        if useRealBluetooth {
            switch realBluetoothManager.connectionStatus {
            case .disconnected:
                return .blue
            case .scanning:
                return .yellow
            case .connecting:
                return .orange
            case .connected:
                return .green
            case .error:
                return .red
            }
        } else {
            return connectionStatus == .connected ? .orange : .blue
        }
    }
    
    // Send motor commands to real hardware when connected
    private func updateMotorCommands() {
        if useRealBluetooth && realBluetoothManager.connectionStatus == .connected {
            realBluetoothManager.sendMotorCommand(motorController.leftWheelCommand)
            realBluetoothManager.sendMotorCommand(motorController.rightWheelCommand)
        }
    }
}

#Preview {
    ContentView()
}
