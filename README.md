# Health Care Monitoring System - MXChip AZ3166 IoT Device

## 🎯 Project Overview

This project implements a **non-intrusive, wearable IoT device** for mental health monitoring using the MXChip AZ3166 development board. The system combines behavioral and environmental observables to signal the onset of mental or emotional distress, providing real-time alerts to caregivers and mental health professionals.

### 🏥 Problem Statement

With a fast-aging global population, we can expect that older adults will be on the rise. At present, the number of people over 60 years of age is set to double to 2.1 billion by 2050 and places extraordinary strain upon both home and long-term care systems everywhere. In parallel to this aging population, an estimated 1.3 billion individuals have some form of disability such as physical handicaps and Autism Spectrum Disorder (ASD), and many of these people require close supervision and environmental control to keep them safe and make them comfortable at home patients and people with physical disabilities have a shared vulnerability: they often cannot express distress or respond to environmental dangers by themselves, making caregiver responsiveness crucial for their quality of life.


- **Non-intrusive monitoring** without compromising privacy
- **Real-time data collection** from multiple sensors
- **Intelligent pattern recognition** for early intervention
- **Caregiver dashboard integration** for immediate response

### 🎯 Project Objectives

1. **Design a Wearable Device** with MXChip AZ3166 to monitor motion, sound, temperature, and humidity
2. **Implement secure data streaming** to Firebase cloud database
3. **Create a caregiver dashboard** for monitoring, alerting, and analysis
4. **Develop pattern recognition algorithms** for emotional stress detection
5. **Ensure ethical compliance** regarding privacy, consent, and data security

---

## 🔧 Hardware Architecture

### MXChip AZ3166 Specifications

- **Microcontroller**: STM32F412ZGT6 (ARM Cortex-M4)
- **Clock Speed**: 100 MHz
- **Memory**: 256KB RAM, 1MB Flash
- **Connectivity**: WiFi 802.11 b/g/n
- **Power**: 3.3V operation, Li-Po battery support

### Onboard Sensors

#### 1. HTS221 - Temperature & Humidity Sensor
- **Interface**: I2C (Address: 0x5F)
- **Temperature Range**: -40°C to +120°C
- **Humidity Range**: 0% to 100%
- **Accuracy**: ±0.5°C, ±3% RH
- **Purpose**: Environmental comfort monitoring

#### 2. LSM6DS3 - 6-Axis Motion Sensor
- **Interface**: I2C (Address: 0x6A)
- **Accelerometer**: ±2g, ±4g, ±8g, ±16g
- **Gyroscope**: ±125, ±245, ±500, ±1000, ±2000 dps
- **Purpose**: Activity level and movement pattern detection

#### 3. MP34DT05 - Digital Microphone
- **Interface**: I2S (Analog input via ADC)
- **Frequency Response**: 100Hz - 10kHz
- **Purpose**: Sound level monitoring and audio pattern detection

#### 4. LPS22HB - Barometric Pressure Sensor
- **Interface**: I2C (Address: 0x5C)
- **Pressure Range**: 260-1260 hPa
- **Purpose**: Environmental pressure monitoring (future implementation)

#### 5. LIS2MDL - 3-Axis Magnetometer
- **Interface**: I2C (Address: 0x1E)
- **Magnetic Field Range**: ±50 gauss
- **Purpose**: Orientation and movement direction (future implementation)

---

## 💻 Software Implementation

### Direct Hardware Access Approach

This project implements **direct hardware control** instead of using high-level libraries for maximum reliability and performance. This approach provides:

- **Precise sensor control** through direct register manipulation
- **Optimized performance** with minimal overhead
- **Better error handling** and debugging capabilities
- **Assembly-level precision** for critical timing requirements

### Key Technical Features

#### 1. I2C Communication
```cpp
// Direct I2C Write - Single Register
void i2cWriteRegister(uint8_t deviceAddr, uint8_t reg, uint8_t value) {
    Wire.beginTransmission(deviceAddr);
    Wire.write(reg);
    Wire.write(value);
    Wire.endTransmission();
}

// Direct I2C Read - Single Register
uint8_t i2cReadRegister(uint8_t deviceAddr, uint8_t reg) {
    Wire.beginTransmission(deviceAddr);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(deviceAddr, (uint8_t)1);
    return Wire.read();
}
```

#### 2. Sensor Initialization
Each sensor is initialized with a robust sequence:
- **Device identification** verification
- **Configuration register** setup
- **Data production** testing
- **Fallback mechanisms** for reliability

#### 3. Data Processing
- **30-second averaging** for stable readings
- **Change detection** algorithms
- **Professional formatting** for medical-grade output
- **Intelligent analysis** with threshold-based alerts

---

## 📊 Data Collection Strategy

### Sampling Parameters
- **Raw Sampling**: Every 1 second
- **Display Update**: Every 5 seconds
- **Analysis Window**: Every 10 seconds
- **Averaging Window**: 30 seconds

### Thresholds and Classifications

#### Sound Level Thresholds
- **Silence**: 0-50 units
- **Low**: 51-100 units
- **Medium**: 101-200 units
- **High**: 201-400 units
- **Dangerous**: 400+ units

#### Motion Intensity Thresholds
- **Calm**: 0-2 m/s²
- **Normal**: 2-5 m/s²
- **Active**: 5-10 m/s²
- **Violent**: 10+ m/s²

#### Environmental Thresholds
- **Temperature Comfortable**: 18-26°C
- **Temperature Uncomfortable**: 26-30°C
- **Temperature Dangerous**: 30+°C
- **Humidity Comfortable**: 30-70%
- **Humidity Uncomfortable**: 70-85%
- **Humidity Dangerous**: 85+%

### Fall Detection
-**Gyroscope**: Angles 
-**Accelerometr**: Speed


---

## 🚀 Getting Started

### Prerequisites

1. **Hardware Requirements**:
   - MXChip AZ3166 development board
   - USB cable for programming
   - Computer with Windows/Linux/macOS

2. **Software Requirements**:
   - PlatformIO IDE or Arduino IDE
   - Git for version control
   - Serial monitor for debugging

### Backend (MXChip Proxy → Firebase) Configuration
The Node.js proxy server (in `backend/`) forwards sensor packets from the MXChip to Firebase Realtime Database.

1. **Install dependencies**
   ```bash
   cd backend
   npm install
   ```
2. **Configure environment variables**
   ```bash
   cp .env.example .env
   ```
   Required variables:
   - `FIREBASE_DATABASE_URL`: your Firebase Realtime Database URL
   - `PORT`: proxy port (default `3000`)
   - `FIREBASE_API_KEY` (optional): enables anonymous auth for REST writes (if omitted, the system relies on RTDB rules)
   - `GOOGLE_APPLICATION_CREDENTIALS` (optional): path to `serviceAccountKey.json` if you want the proxy to use Firebase Admin SDK

3. **Start the server**
   ```bash
   npm start
   ```

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Latifpro108108/FinalYearIoTHardwarereadings.git
   cd FinalYearIoTHardwarereadings
   ```

2. **Open in PlatformIO**:
   - Install PlatformIO IDE
   - Open the project folder
   - Wait for dependencies to install

3. **Upload to MXChip**:
   ```bash
   platformio run -t upload --environment mxchip_az3166
   ```

4. **Monitor output**:
   ```bash
   platformio device monitor --environment mxchip_az3166
   ```


## 🔬 Technical Challenges & Solutions

### Challenge 1: Sensor Initialization Issues
**Problem**: LSM6DS3 motion sensor detected but not producing data
**Solution**: 
- Implemented comprehensive initialization sequence
- Added device reset with proper delays
- Created fallback configuration mechanisms
- Enhanced debugging with detailed output

### Challenge 2: Device ID Compatibility
**Problem**: LSM6DS3 returning Device ID 0x6A instead of expected 0x69
**Solution**:
- Updated validation to accept both 0x69 and 0x6A
- Added alternative address testing (0x6B)
- Implemented robust device detection

### Challenge 3: Data Display Clarity
**Problem**: Fast-scrolling, unreadable output
**Solution**:
- Created CleanDisplay class with professional formatting
- Implemented 30-second averaging for stability
- Added change detection algorithms
- Designed medical-grade output format

---


## 🎓 Academic Significance

### Research Contribution

1. **Demonstrating feasibility** of wearable devices for mental health assessment
2. **Implementing direct hardware control** for maximum reliability
3. **Providing real-time analysis** with intelligent pattern recognition
4. **Ensuring ethical compliance** with privacy and consent requirements

### Alignment with UN Sustainable Development Goals
- **SDG 3**: Good Health and Well-being
- **SDG 9**: Industry, Innovation, and Infrastructure
- **SDG 10**: Reduced Inequalities
- **SDG 11**: Sustainable Cities and Communities

---

## 🔮 Future Enhancements

### Immediate Next Steps
1. **Firebase Integration**: Real-time cloud data streaming
2. **Caregiver Dashboard**: Web-based monitoring interface
3. **Alert System**: SMS/email notifications for caregivers
4. **Pattern Recognition**: Machine learning for behavior analysis

### Advanced Features
1. **LPS22HB Integration**: Barometric pressure monitoring
2. **LIS2MDL Integration**: Magnetic field and orientation
3. **Battery Management**: Power optimization and monitoring
4. **Data Encryption**: Secure transmission to cloud



## 📚 Technical References

1. **HTS221 Datasheet**: STMicroelectronics
2. **LSM6DS3 Datasheet**: STMicroelectronics
3. **MXChip AZ3166 Reference Manual**: Microsoft
4. **STM32F412 Reference Manual**: STMicroelectronics
5. **I2C Communication Protocol**: NXP Semiconductors

---

## 👥 Contributing

This project is part of a final year thesis. For contributions or questions:

1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Submit a pull request**

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 📞 Contact

**Project Author**: [Dabone Abdoul Latif]
                    [Famous Akpovogbeta]
                    [Maureen Amago M.A]
**Institution**: [Academic City University]
**Email**: [dabone.latif@acity.edu.gh]
**Project Repository**: [https://github.com/Latifpro108108/FinalYearIoTHardwarereadings.git](https://github.com/Latifpro108108/FinalYearIoTHardwarereadings.git)

---

*This project represents a significant contribution to IoT-based health monitoring, demonstrating the potential of wearable devices for early intervention and improved patient care.*
