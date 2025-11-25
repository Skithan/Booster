# Golf Cart Booster - Core Design Specifications

## Universal Clamp Dimensions
```
Total Unit Dimensions: 8" L x 4" W x 6" H
Weight: 2.2 lbs per unit
Material: 6061 Aluminum housing, ABS plastic covers

Clamp Specifications:
- Adjustable jaw opening: 12mm - 25mm diameter
- Clamp force: 50-100 lbs (adjustable)
- Rubber padding: Prevents axle damage
```

## Drive Wheel Assembly
```
Motor: 180W Brushless DC Motor
- RPM Range: 0-3000 RPM
- Torque: 0.5 Nm continuous
- Efficiency: 85%+
- Quiet operation: <40dB

Drive Wheel:
- Diameter: 3" (76mm)
- Material: High-grip rubber compound
- Spring tension: Adjustable contact pressure
```

## Electronics Housing
```
Weatherproof Rating: IP65 (rain resistant)
Controller: ESP32-S3 with built-in Bluetooth
Motor Driver: BLDC ESC with regenerative braking
Battery: 12V 4Ah Lithium Iron Phosphate (LiFePO4)
Charging: USB-C PD 45W input
Indicators: LED status lights (power, connection, battery)
```

## Safety Features
```
Automatic Disengagement:
- If cart tips or lifts (accelerometer)
- If Bluetooth connection lost (5 second timeout)
- If battery voltage drops too low
- Manual emergency stop button

Speed Limiting:
- Maximum 5 mph (walking pace)
- Gradual acceleration/deceleration
- Anti-rollback on slopes
```
