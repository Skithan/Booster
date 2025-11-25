# Golf Cart Booster Control System

A comprehensive iOS framework for controlling motorized wheels ("boosters") on a golf push cart using a virtual joystick interface and Bluetooth connectivity.

## Features

- **Virtual Joystick Control**: Intuitive touch-based joystick for directional control
- **Differential Steering**: Automatically converts joystick input to individual wheel speeds
- **Bluetooth Connectivity**: Connects to up to two booster wheel motors via Bluetooth Low Energy
- **Real-time Monitoring**: Display connection status, battery levels, and motor speeds
- **Safety Features**: Emergency stop functionality and connection management
- **Customizable Settings**: Adjustable speed limits, steering sensitivity, and dead zones

## Architecture

### Core Components

1. **BoosterWheel**: Model representing an individual motorized wheel
2. **MotorController**: Handles joystick input processing and differential steering calculations
3. **BluetoothManager**: Manages Bluetooth connections and communication with the hardware
4. **JoystickView**: SwiftUI virtual joystick control
5. **BoosterControlView**: Main user interface bringing all components together

### Data Flow

```
Joystick Input → Motor Controller → Bluetooth Manager → Hardware
     ↑                                      ↓
User Touch                           Status Updates
```

## Hardware Requirements

Your booster wheel hardware should support:

- Bluetooth Low Energy (BLE) connectivity
- Standard BLE services for motor control
- Battery level reporting (optional)
- Speed control via signed 16-bit integers

### Bluetooth Protocol

The framework expects the following BLE characteristics:

- **Service UUID**: `12345678-1234-1234-1234-123456789ABC` (customize for your hardware)
- **Motor Speed Characteristic**: `12345678-1234-1234-1234-123456789ABD`
- **Battery Level Characteristic**: `2A19` (standard Battery Service)

#### Motor Command Format

Speed commands are sent as 2-byte signed integers:
- Range: -1000 to +1000 (representing -100% to +100% speed)
- Byte order: Little-endian
- Negative values = reverse, positive values = forward

## Usage

### Basic Implementation

```swift
import SwiftUI
import boosters

@main
struct MyGolfCartApp: App {
    var body: some Scene {
        WindowGroup {
            BoosterControlView()
        }
    }
}
```

### Custom Integration

```swift
import boosters

class MyGolfCartController: ObservableObject {
    private let bluetoothManager = BluetoothManager()
    private let motorController = MotorController()
    
    func setupBoosterControl() {
        // Configure motor settings
        motorController.maxSpeedMultiplier = 0.75  // 75% max speed
        motorController.steeringSensitivity = 1.2   // Increased turning
        motorController.deadZone = 0.08            // Larger dead zone
        
        // Start scanning for devices
        bluetoothManager.startScanning()
    }
    
    func processCustomInput(forward: Double, turn: Double) {
        let input = JoystickInput(x: turn, y: forward)
        motorController.processJoystickInput(input)
    }
}
```

## Configuration

### Motor Control Settings

- **Max Speed Multiplier** (0.1 - 1.0): Global speed limit
- **Steering Sensitivity** (0.1 - 2.0): How aggressively the cart turns
- **Dead Zone** (0.0 - 0.2): Joystick input threshold to ignore small movements

### Bluetooth Configuration

Update the UUIDs in `BluetoothManager.swift` to match your hardware:

```swift
private let boosterServiceUUID = CBUUID(string: "YOUR-SERVICE-UUID")
private let motorSpeedCharacteristicUUID = CBUUID(string: "YOUR-SPEED-CHARACTERISTIC-UUID")
```

## Safety Features

### Emergency Stop
- Large, prominent red stop button
- Immediately sets both wheel speeds to zero
- Haptic feedback confirms activation

### Connection Monitoring
- Real-time connection status display
- Automatic reconnection attempts
- Visual and textual status indicators

### Speed Limits
- Configurable maximum speed setting
- Gradual acceleration/deceleration
- Input validation and clamping

## Customization

### Custom Hardware Protocol

To adapt for different hardware, modify the `convertSpeedToData()` method in `BluetoothManager.swift`:

```swift
private func convertSpeedToData(_ speed: Double) -> Data {
    // Your custom protocol implementation
    let customCommand = YourHardwareProtocol.createSpeedCommand(speed)
    return customCommand.toData()
}
```

### Custom UI Styling

The joystick and interface can be customized by modifying the SwiftUI views:

```swift
// Custom joystick colors
JoystickView(joystickInput: $input)
    .accentColor(.purple)          // Custom knob color
    .background(Color.black)       // Custom background
```

## Troubleshooting

### Common Issues

1. **Bluetooth not connecting**:
   - Verify UUIDs match your hardware
   - Check iOS Bluetooth permissions
   - Ensure hardware is in pairing mode

2. **Wheels not responding**:
   - Verify the data format matches hardware expectations
   - Check connection status indicators
   - Try emergency stop and reconnect

3. **Poor steering response**:
   - Adjust steering sensitivity in settings
   - Modify dead zone settings
   - Check joystick calibration

### Debug Logging

Enable detailed logging by setting debug flags in the managers:

```swift
// Add to BluetoothManager for connection debugging
print("📡 Bluetooth Debug: \(message)")

// Add to MotorController for steering debugging  
print("🎮 Motor Debug: Left=\(leftSpeed), Right=\(rightSpeed)")
```

## Testing

### Simulator Testing
The framework includes preview support for testing UI components without hardware:

```swift
#Preview {
    BoosterControlView()
}
```

### Hardware Testing
1. Start with low speed settings (maxSpeedMultiplier = 0.3)
2. Test emergency stop functionality first
3. Gradually increase speed and test steering response
4. Verify battery level reporting

## Requirements

- iOS 14.0+
- Xcode 12.0+
- Swift 5.0+
- Core Bluetooth framework
- SwiftUI

## License

This project is available under the MIT License.

## Contributing

When contributing to this project:

1. Test thoroughly with actual hardware
2. Include safety considerations in any modifications
3. Update documentation for API changes
4. Follow Swift coding conventions

## Hardware Integration Notes

This framework is designed to be hardware-agnostic but assumes:

- BLE-based communication
- Individual motor control for each wheel
- Standard speed control protocol
- Optional battery monitoring

For integration with specific hardware platforms, you may need to customize:
- Bluetooth service/characteristic UUIDs
- Data encoding format
- Connection establishment protocol
- Error handling procedures
