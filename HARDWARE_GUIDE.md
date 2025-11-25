# Golf Cart Booster Hardware Integration Guide

## Hardware Requirements

### 1. Microcontroller Setup (Per Wheel)
```
ESP32 Development Board (recommended)
├── Built-in Bluetooth/WiFi
├── Multiple PWM outputs
├── 3.3V/5V compatible
└── Arduino IDE compatible
```

### 2. Motor Driver Circuit
```
L298N Motor Driver Module
├── Input: 7-12V DC supply
├── Output: Dual motor control
├── PWM speed control
└── Direction control pins
```

### 3. Power System
```
12V Battery Pack
├── Motor power supply
├── Voltage regulator (12V → 5V)
├── Fuse protection
└── Power switch
```

## ESP32 Code Example

```cpp
#include "BluetoothSerial.h"

BluetoothSerial SerialBT;

// Motor driver pins
const int MOTOR_PWM = 2;      // Speed control
const int MOTOR_DIR1 = 4;     // Direction pin 1  
const int MOTOR_DIR2 = 5;     // Direction pin 2
const int ENABLE_PIN = 18;    // Motor enable

// Battery monitoring
const int BATTERY_PIN = 34;   // Analog input for battery voltage

void setup() {
  Serial.begin(115200);
  
  // Initialize Bluetooth with device name
  SerialBT.begin("GolfCart_Left");  // or "GolfCart_Right"
  Serial.println("Golf Cart Booster Ready");
  
  // Setup motor pins
  pinMode(MOTOR_PWM, OUTPUT);
  pinMode(MOTOR_DIR1, OUTPUT);
  pinMode(MOTOR_DIR2, OUTPUT);
  pinMode(ENABLE_PIN, OUTPUT);
  
  digitalWrite(ENABLE_PIN, HIGH);
}

void loop() {
  if (SerialBT.available()) {
    // Read 4-byte command from iPhone app
    uint8_t command[4];
    SerialBT.readBytes(command, 4);
    
    uint8_t wheelId = command[0];    // 0x01 = left, 0x02 = right
    uint8_t direction = command[1];  // 0x00 = stop, 0x01 = forward, 0x02 = reverse
    uint8_t speed = command[2];      // 0-255 speed value
    
    processMotorCommand(direction, speed);
  }
  
  // Send battery level periodically
  static unsigned long lastBatteryCheck = 0;
  if (millis() - lastBatteryCheck > 5000) {  // Every 5 seconds
    sendBatteryLevel();
    lastBatteryCheck = millis();
  }
}

void processMotorCommand(uint8_t direction, uint8_t speed) {
  switch (direction) {
    case 0x00:  // Stop
      digitalWrite(MOTOR_DIR1, LOW);
      digitalWrite(MOTOR_DIR2, LOW);
      analogWrite(MOTOR_PWM, 0);
      Serial.println("Motor STOP");
      break;
      
    case 0x01:  // Forward
      digitalWrite(MOTOR_DIR1, HIGH);
      digitalWrite(MOTOR_DIR2, LOW);
      analogWrite(MOTOR_PWM, speed);
      Serial.printf("Motor FORWARD: %d\\n", speed);
      break;
      
    case 0x02:  // Reverse
      digitalWrite(MOTOR_DIR1, LOW);
      digitalWrite(MOTOR_DIR2, HIGH);
      analogWrite(MOTOR_PWM, speed);
      Serial.printf("Motor REVERSE: %d\\n", speed);
      break;
  }
}

void sendBatteryLevel() {
  int batteryReading = analogRead(BATTERY_PIN);
  uint8_t batteryPercent = map(batteryReading, 0, 4095, 0, 100);
  
  SerialBT.write(batteryPercent);
  Serial.printf("Battery: %d%%\\n", batteryPercent);
}
```

## Wiring Diagram

```
ESP32 → L298N Motor Driver → DC Motor
├── GPIO2  → ENA (Enable A)
├── GPIO4  → IN1 (Input 1)
├── GPIO5  → IN2 (Input 2)
├── 5V     → VCC
└── GND    → GND

L298N → Motor & Power
├── OUT1   → Motor Terminal +
├── OUT2   → Motor Terminal -
├── 12V+   → Battery +
└── GND    → Battery -

ESP32 → Voltage Monitoring
└── GPIO34 → Voltage Divider → Battery +
```

## Bluetooth Service Configuration

### Custom UUIDs (Update in RealBluetoothManager.swift)
```swift
struct BluetoothConstants {
    // Generate your own UUIDs at https://www.uuidgenerator.net/
    static let golfCartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let leftMotorCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rightMotorCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    static let batteryCharacteristicUUID = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")
}
```

## Testing Steps

### 1. Hardware Testing
```bash
# Flash ESP32 with Arduino IDE
# Test motor movement with manual commands
# Verify Bluetooth pairing
```

### 2. iPhone App Testing
```bash
# Build app to physical iPhone
# Scan for "GolfCart_Left" and "GolfCart_Right"
# Test connection and motor commands
# Verify PiP mode works with real hardware
```

## Safety Features

### Emergency Stop Implementation
```cpp
// Hardware emergency stop button
const int EMERGENCY_PIN = 0;  // Boot button on ESP32

void setup() {
  pinMode(EMERGENCY_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(EMERGENCY_PIN), emergencyStop, FALLING);
}

void emergencyStop() {
  digitalWrite(MOTOR_DIR1, LOW);
  digitalWrite(MOTOR_DIR2, LOW);
  analogWrite(MOTOR_PWM, 0);
  digitalWrite(ENABLE_PIN, LOW);  // Disable motor driver
  Serial.println("EMERGENCY STOP ACTIVATED");
}
```

### Watchdog Timer
```cpp
#include "esp_task_wdt.h"

void setup() {
  // Configure watchdog timer for 10 seconds
  esp_task_wdt_init(10, true);
  esp_task_wdt_add(NULL);
}

void loop() {
  // Reset watchdog in main loop
  esp_task_wdt_reset();
  
  // If no commands received for 5 seconds, stop motors
  static unsigned long lastCommandTime = 0;
  if (millis() - lastCommandTime > 5000) {
    processMotorCommand(0x00, 0);  // Stop motors
  }
}
```

## Troubleshooting

### Common Issues
1. **Bluetooth not discoverable**: Check ESP32 power and code upload
2. **Motors not responding**: Verify L298N wiring and power supply
3. **Weak signal**: Reduce distance, check antenna orientation
4. **Battery drain**: Add sleep modes, optimize code efficiency

### Debug Commands
```cpp
// Add debug output to ESP32
void debugMotorStatus() {
  Serial.printf("Motor: Dir1=%d, Dir2=%d, PWM=%d\\n", 
    digitalRead(MOTOR_DIR1), 
    digitalRead(MOTOR_DIR2), 
    analogRead(MOTOR_PWM)
  );
}
```

This hardware setup will give you real Bluetooth control of your golf cart booster wheels with the Picture-in-Picture joystick app!
