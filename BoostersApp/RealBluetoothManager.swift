//
//  RealBluetoothManager.swift
//  BoostersApp
//
//  Real Bluetooth implementation for golf cart booster wheels
//

import SwiftUI
import CoreBluetooth
import Combine

// MARK: - Bluetooth Constants

struct BluetoothConstants {
    // Golf Cart Service UUIDs - customize these for your hardware
    static let golfCartServiceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    static let leftMotorCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD") 
    static let rightMotorCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABE")
    static let batteryCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABF")
    static let statusCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789AC0")
    
    // Device naming convention
    static let deviceNamePrefix = "GolfCart"
}

// MARK: - Motor Command Protocol

struct MotorBluetoothCommand {
    let wheelPosition: WheelPosition
    let speed: Double // -1.0 to 1.0
    let direction: MotorDirection
    
    enum MotorDirection: UInt8 {
        case forward = 0x01
        case reverse = 0x02
        case stop = 0x00
    }
    
    // Convert to bytes for Bluetooth transmission
    func toData() -> Data {
        let speedByte = UInt8(abs(speed) * 255) // 0-255 speed range
        let directionByte = speed >= 0 ? MotorDirection.forward.rawValue : MotorDirection.reverse.rawValue
        let stopByte: UInt8 = speed == 0 ? MotorDirection.stop.rawValue : directionByte
        
        return Data([
            wheelPosition == .left ? 0x01 : 0x02, // Wheel identifier
            stopByte, // Direction
            speedByte, // Speed magnitude
            0x00 // Checksum placeholder
        ])
    }
}

// MARK: - Device Info

class BoosterDevice: ObservableObject, Identifiable {
    let id = UUID()
    @Published var isConnected: Bool = false
    @Published var batteryLevel: Int = 0
    @Published var signalStrength: Int = 0
    @Published var lastCommandTime: Date?
    
    let peripheral: CBPeripheral
    var motorCharacteristic: CBCharacteristic?
    var batteryCharacteristic: CBCharacteristic?
    var statusCharacteristic: CBCharacteristic?
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
    
    var name: String {
        return peripheral.name ?? "Unknown Device"
    }
    
    var wheelPosition: WheelPosition {
        // Determine wheel position from device name or identifier
        if name.lowercased().contains("left") {
            return .left
        } else if name.lowercased().contains("right") {
            return .right
        } else {
            // Fallback: use identifier to determine position
            return peripheral.identifier.uuidString.hash % 2 == 0 ? .left : .right
        }
    }
}

// MARK: - Real Bluetooth Manager

class RealBluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var discoveredDevices: [BoosterDevice] = []
    @Published var connectedDevices: [BoosterDevice] = []
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    
    // MARK: - Core Bluetooth Properties
    
    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [CBPeripheral] = []
    
    // MARK: - Device Management
    
    @Published var leftBooster: BoosterDevice?
    @Published var rightBooster: BoosterDevice?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is not powered on"
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll()
        
        // Scan for golf cart service or devices with specific name pattern
        let services = [BluetoothConstants.golfCartServiceUUID]
        
        centralManager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        print("🔍 Started scanning for golf cart devices...")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("⏹️ Stopped scanning")
    }
    
    func connect(to device: BoosterDevice) {
        print("🔗 Attempting to connect to: \(device.name)")
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect(from device: BoosterDevice) {
        print("🔌 Disconnecting from: \(device.name)")
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
    
    func disconnectAll() {
        connectedDevices.forEach { device in
            disconnect(from: device)
        }
    }
    
    // MARK: - Motor Control
    
    func sendMotorCommand(_ command: MotorCommand) {
        let bluetoothCommand = MotorBluetoothCommand(
            wheelPosition: command.wheelPosition,
            speed: command.speed,
            direction: command.speed >= 0 ? .forward : .reverse
        )
        
        sendBluetoothCommand(bluetoothCommand)
    }
    
    private func sendBluetoothCommand(_ command: MotorBluetoothCommand) {
        let targetDevice = command.wheelPosition == .left ? leftBooster : rightBooster
        
        guard let device = targetDevice,
              device.isConnected,
              let characteristic = device.motorCharacteristic else {
            print("❌ Cannot send command: Device not connected or characteristic not found")
            return
        }
        
        let data = command.toData()
        device.peripheral.writeValue(
            data,
            for: characteristic,
            type: .withResponse
        )
        
        device.lastCommandTime = Date()
        print("📡 Sent command to \(command.wheelPosition) wheel: speed \(command.speed)")
    }
    
    func emergencyStop() {
        // Send stop commands to both wheels immediately
        let leftStop = MotorBluetoothCommand(wheelPosition: .left, speed: 0, direction: .stop)
        let rightStop = MotorBluetoothCommand(wheelPosition: .right, speed: 0, direction: .stop)
        
        sendBluetoothCommand(leftStop)
        sendBluetoothCommand(rightStop)
        
        print("🚨 EMERGENCY STOP ACTIVATED")
    }
    
    // MARK: - Battery Management
    
    func requestBatteryLevels() {
        connectedDevices.forEach { device in
            if let characteristic = device.batteryCharacteristic {
                device.peripheral.readValue(for: characteristic)
            }
        }
    }
    
    // MARK: - Connection Status Updates
    
    private func updateConnectionStatus() {
        let connectedCount = connectedDevices.count
        
        switch connectedCount {
        case 0:
            connectionStatus = .disconnected
        case 1:
            connectionStatus = .connecting
        case 2:
            connectionStatus = .connected
        default:
            connectionStatus = .connected
        }
        
        // Update individual device assignments
        leftBooster = connectedDevices.first { $0.wheelPosition == .left }
        rightBooster = connectedDevices.first { $0.wheelPosition == .right }
    }
}

// MARK: - CBCentralManagerDelegate

extension RealBluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on")
            lastError = nil
        case .poweredOff:
            print("❌ Bluetooth powered off")
            lastError = "Bluetooth is powered off"
        case .unauthorized:
            print("❌ Bluetooth unauthorized")
            lastError = "Bluetooth access not authorized"
        case .unsupported:
            print("❌ Bluetooth unsupported")
            lastError = "Bluetooth not supported on this device"
        case .resetting:
            print("🔄 Bluetooth resetting")
            lastError = "Bluetooth is resetting"
        case .unknown:
            print("❓ Bluetooth state unknown")
            lastError = "Bluetooth state unknown"
        @unknown default:
            print("❓ Unknown Bluetooth state")
            lastError = "Unknown Bluetooth state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        // Filter for golf cart devices
        guard let name = peripheral.name,
              name.contains(BluetoothConstants.deviceNamePrefix) else {
            return
        }
        
        // Check if we already discovered this device
        let existingDevice = discoveredDevices.first { $0.peripheral.identifier == peripheral.identifier }
        
        if existingDevice == nil {
            let newDevice = BoosterDevice(peripheral: peripheral)
            newDevice.signalStrength = RSSI.intValue
            
            discoveredDevices.append(newDevice)
            print("🔍 Discovered golf cart device: \(name) (RSSI: \(RSSI))")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown")")
        
        // Find the device and update its status
        if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            device.isConnected = true
            
            if !connectedDevices.contains(where: { $0.id == device.id }) {
                connectedDevices.append(device)
            }
        }
        
        // Set up peripheral delegate and discover services
        peripheral.delegate = self
        peripheral.discoverServices([BluetoothConstants.golfCartServiceUUID])
        
        updateConnectionStatus()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect to: \(peripheral.name ?? "Unknown")")
        lastError = "Connection failed: \(error?.localizedDescription ?? "Unknown error")"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("🔌 Disconnected from: \(peripheral.name ?? "Unknown")")
        
        // Update device status
        if let device = connectedDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            device.isConnected = false
            connectedDevices.removeAll { $0.id == device.id }
        }
        
        if let error = error {
            lastError = "Disconnection error: \(error.localizedDescription)"
        }
        
        updateConnectionStatus()
    }
}

// MARK: - CBPeripheralDelegate

extension RealBluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("❌ Service discovery error: \(error!.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BluetoothConstants.golfCartServiceUUID {
                print("🔍 Discovered golf cart service")
                peripheral.discoverCharacteristics([
                    BluetoothConstants.leftMotorCharacteristicUUID,
                    BluetoothConstants.rightMotorCharacteristicUUID,
                    BluetoothConstants.batteryCharacteristicUUID,
                    BluetoothConstants.statusCharacteristicUUID
                ], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("❌ Characteristic discovery error: \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics,
              let device = connectedDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BluetoothConstants.leftMotorCharacteristicUUID, BluetoothConstants.rightMotorCharacteristicUUID:
                device.motorCharacteristic = characteristic
                print("✅ Motor characteristic ready for \(device.name)")
                
            case BluetoothConstants.batteryCharacteristicUUID:
                device.batteryCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("🔋 Battery characteristic ready for \(device.name)")
                
            case BluetoothConstants.statusCharacteristicUUID:
                device.statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("📊 Status characteristic ready for \(device.name)")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              let device = connectedDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        
        switch characteristic.uuid {
        case BluetoothConstants.batteryCharacteristicUUID:
            if let batteryLevel = data.first {
                device.batteryLevel = Int(batteryLevel)
                print("🔋 Battery level for \(device.name): \(batteryLevel)%")
            }
            
        case BluetoothConstants.statusCharacteristicUUID:
            // Parse status data (customize based on your hardware protocol)
            print("📊 Status update for \(device.name): \(data.hexString)")
            
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Write error: \(error.localizedDescription)")
            lastError = "Command send failed: \(error.localizedDescription)"
        } else {
            print("✅ Command sent successfully")
        }
    }
}

// MARK: - Data Extensions

extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
