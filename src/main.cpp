#include <Arduino.h>
#include "AZ3166WiFi.h"
#include "Wire.h"
#include "MXChipFirebase.h"
#include "config.h"
#include <math.h>

// ============================================================================
// CONFIG DEFAULTS (overridden by config.h)
// ============================================================================
#ifndef WIFI_SSID
#define WIFI_SSID "YOUR_SSID"
#endif
#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD "YOUR_PASSWORD"
#endif
#ifndef PROXY_SERVER_IP
#define PROXY_SERVER_IP "192.168.1.100"
#endif
#ifndef PROXY_SERVER_PORT
#define PROXY_SERVER_PORT 3000
#endif
#ifndef PROXY_ENDPOINT
#define PROXY_ENDPOINT "/sensor-data"
#endif
#ifndef FIREBASE_HOST
#define FIREBASE_HOST "your-project-default-rtdb.firebaseio.com"
#endif
#ifndef FIREBASE_PROJECT_ID
#define FIREBASE_PROJECT_ID "your-project-id"
#endif
#ifndef DEVICE_ID
#define DEVICE_ID "MXCHIP_001"
#endif
#ifndef FIREBASE_UPDATE_INTERVAL_MS
#define FIREBASE_UPDATE_INTERVAL_MS 2000
#endif

// ============================================================================
// I2C ADDRESSES & REGISTER MAPS
// ============================================================================
#define HTS221_ADDR     0x5F
#define LSM6DS3_ADDR    0x6A

// HTS221
#define HTS221_WHO_AM_I         0x0F
#define HTS221_CTRL_REG1        0x20
#define HTS221_STATUS_REG       0x27
#define HTS221_TEMP_OUT_L       0x2A
#define HTS221_TEMP_OUT_H       0x2B
#define HTS221_HUMIDITY_OUT_L   0x28
#define HTS221_HUMIDITY_OUT_H   0x29
#define HTS221_CALIB_T0_DEGC_X8 0x32
#define HTS221_CALIB_T1_DEGC_X8 0x33
#define HTS221_CALIB_T0_T1_MSB  0x35
#define HTS221_CALIB_T0_OUT_L   0x3C
#define HTS221_CALIB_T0_OUT_H   0x3D
#define HTS221_CALIB_T1_OUT_L   0x3E
#define HTS221_CALIB_T1_OUT_H   0x3F
#define HTS221_CALIB_H0_RH_X2   0x30
#define HTS221_CALIB_H1_RH_X2   0x31
#define HTS221_CALIB_H0_T0_OUT_L 0x36
#define HTS221_CALIB_H0_T0_OUT_H 0x37
#define HTS221_CALIB_H1_T0_OUT_L 0x3A
#define HTS221_CALIB_H1_T0_OUT_H 0x3B

// LSM6DS3
#define LSM6DS3_WHO_AM_I    0x0F
#define LSM6DS3_CTRL1_XL    0x10
#define LSM6DS3_CTRL2_G     0x11
#define LSM6DS3_CTRL3_C     0x12
#define LSM6DS3_OUTX_L_XL   0x28
#define LSM6DS3_OUTX_L_G    0x22

// Microphone
#define MIC_PIN A3

// ============================================================================
// I2C HELPERS
// ============================================================================
void i2cWriteRegister(uint8_t deviceAddr, uint8_t reg, uint8_t value) {
    Wire.beginTransmission(deviceAddr);
    Wire.write(reg);
    Wire.write(value);
    Wire.endTransmission();
}

uint8_t i2cReadRegister(uint8_t deviceAddr, uint8_t reg) {
    Wire.beginTransmission(deviceAddr);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(deviceAddr, (uint8_t)1);
    return Wire.read();
}

void i2cReadRegisters(uint8_t deviceAddr, uint8_t reg, uint8_t* data, uint8_t length) {
    Wire.beginTransmission(deviceAddr);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(deviceAddr, length);
    for (uint8_t i = 0; i < length; i++) {
        data[i] = Wire.read();
    }
}

int16_t i2cRead16Bit(uint8_t deviceAddr, uint8_t regL, uint8_t regH) {
    uint8_t low  = i2cReadRegister(deviceAddr, regL);
    uint8_t high = i2cReadRegister(deviceAddr, regH);
    return (int16_t)((high << 8) | low);
}

// ============================================================================
// EWMA — Exponential Weighted Moving Average
//
// REPLACES the broken simple moving average in the original code.
// The original HTS221_Direct had a single bufferIndex shared across both
// temperature and humidity smoothData() calls, causing each sensor's buffer
// to be written at offset positions. EWMA has no buffer — it requires only
// one float of state, and it's proven in industrial sensor systems.
//
// Alpha guide:
//   0.10 — very smooth, slow to respond (good for temperature)
//   0.15 — smooth (good for humidity)
//   0.30 — moderate (good for sound trends)
//   0.50 — fast response (good for motion display)
//
// Formula: smoothed = alpha * new_value + (1 - alpha) * previous_smoothed
// ============================================================================
class EWMA {
private:
    float alpha;
    float value;
    bool  initialized;

public:
    EWMA(float a) : alpha(a), value(0.0f), initialized(false) {}

    float update(float newValue) {
        if (!initialized) {
            value       = newValue;
            initialized = true;
        } else {
            value = alpha * newValue + (1.0f - alpha) * value;
        }
        return value;
    }

    float get()     const { return value; }
    bool  isReady() const { return initialized; }
};

// ============================================================================
// SOUND CALIBRATION
// Baseline subtraction is valid — keeps the calibrated approach from original.
// ============================================================================
class SoundCalibrator {
private:
    int   baselineValue;
    int   baselinePeakToPeak;
    bool  isCalibrated;
    float smoothedValue;

    const float SMOOTHING   = 0.80f;
    const float SENSITIVITY = 2.0f;

public:
    SoundCalibrator()
        : baselineValue(0), baselinePeakToPeak(0),
          isCalibrated(false), smoothedValue(0.0f) {}

    void calibrate() {
        Serial.println("Sound: Starting baseline calibration (keep quiet 3s)...");
        long sumAvg = 0, sumPeak = 0;
        const int samples = 30;

        for (int i = 0; i < samples; i++) {
            sumAvg += analogRead(MIC_PIN);
            int lo = 1023, hi = 0;
            for (int j = 0; j < 10; j++) {
                int r = analogRead(MIC_PIN);
                if (r < lo) lo = r;
                if (r > hi) hi = r;
                delayMicroseconds(100);
            }
            sumPeak += (hi - lo);
            delay(100);
        }

        baselineValue      = sumAvg  / samples;
        baselinePeakToPeak = sumPeak / samples;
        smoothedValue      = 0.0f;
        isCalibrated       = true;

        Serial.print("Sound baseline: ");    Serial.print(baselineValue);
        Serial.print(" | Variation: "); Serial.println(baselinePeakToPeak);
        Serial.println("Sound calibration complete.");
    }

    int getCalibratedSoundLevel() {
        if (!isCalibrated) return analogRead(MIC_PIN);

        int rawAvg  = analogRead(MIC_PIN);
        int avgDiff = abs(rawAvg - baselineValue);

        int lo = 1023, hi = 0;
        for (int i = 0; i < 15; i++) {
            int r = analogRead(MIC_PIN);
            if (r < lo) lo = r;
            if (r > hi) hi = r;
            delayMicroseconds(100);
        }
        int relativePeak  = max(0, (hi - lo) - baselinePeakToPeak);
        int amplifiedPeak = (int)(relativePeak * SENSITIVITY);
        int combined      = max(avgDiff, amplifiedPeak);

        smoothedValue = SMOOTHING * smoothedValue + (1.0f - SMOOTHING) * combined;
        return (int)smoothedValue;
    }

    bool isReady() const { return isCalibrated; }
};

SoundCalibrator soundCalibrator;

// ============================================================================
// HTS221 — FIXED
// Original bug: smoothData() used a single bufferIndex for both temperature
// and humidity. Each readData() call advanced the index twice, meaning temp
// wrote to indices 0,2,4,1,3... and humidity wrote to 1,3,0,2,4... — offset
// by one and interleaved. Now each sensor has its own dedicated EWMA instance.
// ============================================================================
struct HTS221_Calibration {
    float   T0_degC, T1_degC;
    int16_t T0_out,  T1_out;
    float   H0_rh,   H1_rh;
    int16_t H0_T0_out, H1_T0_out;
};

class HTS221_Direct {
private:
    uint8_t          address;
    HTS221_Calibration calib;
    EWMA             tempEWMA;  // FIX: dedicated filter for temperature
    EWMA             humEWMA;   // FIX: dedicated filter for humidity

public:
    HTS221_Direct(uint8_t addr = HTS221_ADDR)
        : address(addr), tempEWMA(0.10f), humEWMA(0.15f) {}

    bool begin() {
        Wire.begin();
        if (i2cReadRegister(address, HTS221_WHO_AM_I) != 0xBC) {
            Serial.println("HTS221: Device not found!");
            return false;
        }

        i2cWriteRegister(address, HTS221_CTRL_REG1, 0x85); // 12.5Hz, BDU=1
        delay(100);

        uint8_t T0_x8 = i2cReadRegister(address, HTS221_CALIB_T0_DEGC_X8);
        uint8_t T1_x8 = i2cReadRegister(address, HTS221_CALIB_T1_DEGC_X8);
        uint8_t msb   = i2cReadRegister(address, HTS221_CALIB_T0_T1_MSB);

        calib.T0_degC    = ((msb & 0x03) << 8 | T0_x8) / 8.0f;
        calib.T1_degC    = ((msb & 0x0C) << 6 | T1_x8) / 8.0f;
        calib.T0_out     = i2cRead16Bit(address, HTS221_CALIB_T0_OUT_L, HTS221_CALIB_T0_OUT_H);
        calib.T1_out     = i2cRead16Bit(address, HTS221_CALIB_T1_OUT_L, HTS221_CALIB_T1_OUT_H);
        calib.H0_rh      = i2cReadRegister(address, HTS221_CALIB_H0_RH_X2) / 2.0f;
        calib.H1_rh      = i2cReadRegister(address, HTS221_CALIB_H1_RH_X2) / 2.0f;
        calib.H0_T0_out  = i2cRead16Bit(address, HTS221_CALIB_H0_T0_OUT_L, HTS221_CALIB_H0_T0_OUT_H);
        calib.H1_T0_out  = i2cRead16Bit(address, HTS221_CALIB_H1_T0_OUT_L, HTS221_CALIB_H1_T0_OUT_H);

        Serial.println("HTS221: Initialized.");
        return true;
    }

    void readData(float &temperature, float &humidity) {
        uint8_t status = i2cReadRegister(address, HTS221_STATUS_REG);
        if (!(status & 0x03)) return; // No new data ready

        int16_t temp_raw = i2cRead16Bit(address, HTS221_TEMP_OUT_L, HTS221_TEMP_OUT_H);
        float rawTemp = calib.T0_degC +
                        (float)(temp_raw - calib.T0_out) *
                        (calib.T1_degC - calib.T0_degC) /
                        (float)(calib.T1_out - calib.T0_out);

        int16_t hum_raw = i2cRead16Bit(address, HTS221_HUMIDITY_OUT_L, HTS221_HUMIDITY_OUT_H);
        float rawHum = calib.H0_rh +
                       (float)(hum_raw - calib.H0_T0_out) *
                       (calib.H1_rh - calib.H0_rh) /
                       (float)(calib.H1_T0_out - calib.H0_T0_out);
        rawHum = constrain(rawHum, 0.0f, 100.0f);

        // FIX: separate EWMA per sensor — no shared index
        temperature = tempEWMA.update(rawTemp);
        humidity    = humEWMA.update(rawHum);
    }
};

// ============================================================================
// MOTION DATA STRUCTURE — ENHANCED
// ============================================================================
struct MotionData {
    float accelX, accelY, accelZ;   // m/s²
    float gyroX,  gyroY,  gyroZ;   // deg/s
    float magX,   magY,   magZ;    // gauss (magnetic field)
    float motionMagnitude;           // gravity-corrected m/s²
    float xAngle, yAngle, zAngle;   // degrees (complementary filter)
    float heading;                   // degrees (compass heading from magnetometer)
    bool  isMoving;
    bool  sensorWorking;
};

// ============================================================================
// LIS2MDL — 3-Axis Magnetometer (Future Enhancement)
// Provides magnetic field data for improved orientation and heading calculation
// ============================================================================
class LIS2MDL_Direct {
private:
    uint8_t address;
    bool    initialized;

public:
    LIS2MDL_Direct(uint8_t addr = 0x1E) : address(addr), initialized(false) {}

    bool begin() {
        Serial.println("LIS2MDL: Magnetometer initialization (optional)...");

        // Check if magnetometer is present
        uint8_t who_am_i = i2cReadRegister(address, 0x4F); // WHO_AM_I register
        if (who_am_i != 0x40) {
            Serial.println("LIS2MDL: Not found - magnetometer features disabled");
            return false;
        }

        // Configure magnetometer for continuous mode, 10Hz
        i2cWriteRegister(address, 0x60, 0x00); // CFG_REG_A - continuous mode
        i2cWriteRegister(address, 0x61, 0x00); // CFG_REG_B - default
        i2cWriteRegister(address, 0x62, 0x00); // CFG_REG_C - default

        initialized = true;
        Serial.println("LIS2MDL: Magnetometer initialized");
        return true;
    }

    void readData(float& magX, float& magY, float& magZ) {
        if (!initialized) {
            magX = magY = magZ = 0.0f;
            return;
        }

        uint8_t data[6];
        i2cReadRegisters(address, 0x68, data, 6); // OUTX_L to OUTZ_H

        int16_t mx = (int16_t)(data[1] << 8 | data[0]);
        int16_t my = (int16_t)(data[3] << 8 | data[2]);
        int16_t mz = (int16_t)(data[5] << 8 | data[4]);

        // Convert to gauss (LIS2MDL has ±50 gauss range, 16-bit)
        magX = mx * 1.5f / 32768.0f;
        magY = my * 1.5f / 32768.0f;
        magZ = mz * 1.5f / 32768.0f;
    }

    bool isInitialized() const { return initialized; }
};

// ============================================================================
// LSM6DS3 — Enhanced with Magnetometer Integration
// ============================================================================
class LSM6DS3_Direct {
private:
    uint8_t address;
    float   pitch = 0.0f, roll = 0.0f, yaw = 0.0f;
    unsigned long lastAngleUpdate = 0;
    // IMPROVED ALPHA: 0.85 gives better accelerometer weight during impacts
    // Traditional 0.98 was too gyro-heavy; 0.85 (85% gyro + 15% accel) balances motion smoothness with impact detection
    const float ALPHA = 0.85f;

    // Magnetometer integration
    LIS2MDL_Direct magnetometer;

public:
    LSM6DS3_Direct(uint8_t addr = 0x6A) : address(addr), magnetometer(0x1E) {}

    bool begin() {
        Serial.println("LSM6DS3: Initializing...");
        uint8_t deviceId = 0;
        bool    found    = false;

        for (int i = 0; i < 3; i++) {
            deviceId = i2cReadRegister(address, LSM6DS3_WHO_AM_I);
            if (deviceId == 0x69 || deviceId == 0x6A) { found = true; break; }
            delay(100);
        }
        if (!found) {
            address  = 0x6B; // Try alternative address
            deviceId = i2cReadRegister(address, LSM6DS3_WHO_AM_I);
            if (deviceId != 0x69 && deviceId != 0x6A) {
                Serial.println("LSM6DS3: Not found at 0x6A or 0x6B!");
                return false;
            }
            Serial.println("LSM6DS3: Found at alternative address 0x6B.");
        }

        i2cWriteRegister(address, LSM6DS3_CTRL3_C, 0x01); delay(200); // Full reset
        i2cWriteRegister(address, LSM6DS3_CTRL1_XL, 0x50); delay(100); // 100Hz, ±2g
        i2cWriteRegister(address, LSM6DS3_CTRL2_G,  0x50); delay(100); // 100Hz, ±245dps
        i2cWriteRegister(address, LSM6DS3_CTRL3_C,  0x04); delay(100); // BDU=1, IF_INC=1
        delay(500);

        // Initialize magnetometer (optional)
        bool mag_ok = magnetometer.begin();
        if (mag_ok) {
            Serial.println("LSM6DS3: Magnetometer integrated for enhanced orientation");
        }

        Serial.println("LSM6DS3: Initialized.");
        return true;
    }

    void readData(MotionData &m) {
        uint8_t data[6];

        i2cReadRegisters(address, LSM6DS3_OUTX_L_XL, data, 6);
        int16_t ax = (int16_t)(data[1] << 8 | data[0]);
        int16_t ay = (int16_t)(data[3] << 8 | data[2]);
        int16_t az = (int16_t)(data[5] << 8 | data[4]);
        m.accelX = ax * 0.061f * 0.001f * 9.81f;
        m.accelY = ay * 0.061f * 0.001f * 9.81f;
        m.accelZ = az * 0.061f * 0.001f * 9.81f;

        i2cReadRegisters(address, LSM6DS3_OUTX_L_G, data, 6);
        int16_t gx = (int16_t)(data[1] << 8 | data[0]);
        int16_t gy = (int16_t)(data[3] << 8 | data[2]);
        int16_t gz = (int16_t)(data[5] << 8 | data[4]);
        m.gyroX = gx * 8.75f * 0.001f;
        m.gyroY = gy * 8.75f * 0.001f;
        m.gyroZ = gz * 8.75f * 0.001f;

        // Read magnetometer data (if available)
        if (magnetometer.isInitialized()) {
            magnetometer.readData(m.magX, m.magY, m.magZ);
        } else {
            m.magX = m.magY = m.magZ = 0.0f;
        }

        // Gravity-corrected magnitude for general motion display
        float nx = m.accelX, ny = m.accelY, nz = m.accelZ - 9.81f;
        m.motionMagnitude = sqrt(nx*nx + ny*ny + nz*nz);
        m.isMoving        = (m.motionMagnitude > 0.1f);

        // Complementary filter for angles
        unsigned long now = millis();
        float dt = (lastAngleUpdate > 0) ? (now - lastAngleUpdate) / 1000.0f : 0.01f;
        lastAngleUpdate = now;

        float ax_g = m.accelX / 9.81f;
        float ay_g = m.accelY / 9.81f;
        float az_g = m.accelZ / 9.81f;
        float aRoll  = atan2(ay_g, az_g)                                * 180.0f / 3.14159265f;
        float aPitch = atan2(-ax_g, sqrt(ay_g*ay_g + az_g*az_g))        * 180.0f / 3.14159265f;
        float aYaw   = atan2(ay_g, ax_g)                                * 180.0f / 3.14159265f;

        if (dt > 0 && dt < 1.0f) {
            pitch = ALPHA * (pitch + m.gyroY * dt) + (1.0f - ALPHA) * aPitch;
            roll  = ALPHA * (roll  + m.gyroX * dt) + (1.0f - ALPHA) * aRoll;
            yaw   = ALPHA * (yaw   + m.gyroZ * dt) + (1.0f - ALPHA) * aYaw;
        } else {
            pitch = aPitch; roll = aRoll; yaw = aYaw;
        }

        m.xAngle = roll;
        m.yAngle = pitch;
        m.zAngle = yaw;

        // Calculate compass heading if magnetometer available
        if (magnetometer.isInitialized() && abs(m.magX) > 0.1f && abs(m.magY) > 0.1f) {
            // Tilt-compensated compass heading
            float magX_comp = m.magX * cos(pitch * 3.14159265f / 180.0f) +
                             m.magY * sin(roll * 3.14159265f / 180.0f) * sin(pitch * 3.14159265f / 180.0f) -
                             m.magZ * cos(roll * 3.14159265f / 180.0f) * sin(pitch * 3.14159265f / 180.0f);

            float magY_comp = m.magY * cos(roll * 3.14159265f / 180.0f) +
                             m.magZ * sin(roll * 3.14159265f / 180.0f);

            m.heading = atan2(magY_comp, magX_comp) * 180.0f / 3.14159265f;
            if (m.heading < 0) m.heading += 360.0f;
        } else {
            m.heading = 0.0f;
        }

        m.sensorWorking = true;
    }
};

// ============================================================================
// ENHANCED FALL DETECTION — Multi-Sensor Approach
//
// IMPROVED: Now considers orientation, angular velocity, and multiple fall patterns
// No longer relies on sound as primary corroboration
//
// FALL CHARACTERISTICS:
// 1. Free-fall phase: Acceleration drops, orientation may change rapidly
// 2. Impact phase: High acceleration spike, orientation stabilizes
// 3. Post-fall phase: Person remains still, device often horizontal
//
// MULTI-SENSOR APPROACH:
// - Acceleration magnitude (existing)
// - Orientation changes (pitch/roll angles)
// - Angular velocity (gyroscope)
// - Fall pattern recognition via angle changes + impact
// ============================================================================
class FallDetector {
public:
    enum FallType { UNKNOWN, FORWARD_FALL, BACKWARD_FALL, SIDEWAYS_FALL, SLIP_TRIP };

    // ====== FAST FALL (impact + rapid angle) ======
    static constexpr float RAPID_ANGLE_CHANGE_THRESHOLD = 80.0f;    // degrees/second (LOWERED for slow falls)
    static constexpr float IMPACT_THRESHOLD = 12.0f;                // m/s² trig for impact detection
    static constexpr float MIN_IMPACT_FOR_FALL = 16.0f;             // m/s² (LOWERED to catch lighter falls)
    
    // ====== SLOW FALL (sustained high angle + minimal motion) ======
    static constexpr float SLOW_FALL_ANGLE_THRESHOLD = 65.0f;       // degrees absolute (person nearly horizontal)
    static constexpr float SLOW_FALL_ANGLE_CHANGE = 35.0f;          // deg/s (smooth tilt toward ground)
    static constexpr float SLOW_FALL_ACCEL_MAX = 11.0f;             // m/s² (low energy fall)
    static constexpr unsigned long SLOW_FALL_WINDOW_MS = 800;       // time to confirm slow fall (ms)
    
    // ====== DOWNWARD DETECTION (for forward/backward falls) ======
    static constexpr float DOWNWARD_PITCH_THRESHOLD = 50.0f;        // degrees of pitch change (tipping forward/back)
    static constexpr float DOWNWARD_ROLL_THRESHOLD = 45.0f;         // degrees of roll change (tipping sideways)
    
    // ====== GENERAL ======
    static constexpr float SOUND_THRESHOLD = 55;                    // ADC units
    static constexpr float CONFIDENCE_MIN = 0.55f;                  // 55% minimum (LOWERED for sensitivity)
    static constexpr unsigned long FALL_COOLDOWN_MS = 1800;         // avoid repeated triggers
    static constexpr unsigned long FALL_CONFIRM_WAIT_MS = 500;      // stillness window
    static constexpr unsigned long FALL_CANDIDATE_TIMEOUT_MS = 1200; // INCREASED for slow falls
    
    // ====== POST-FALL STILLNESS (person on ground) ======
    static constexpr float POST_FALL_ACCEL_MIN = 5.0f;              // m/s² (LOWERED for still person)
    static constexpr float POST_FALL_ACCEL_MAX = 11.0f;             // m/s²
    static constexpr float POST_FALL_ANGLE_RATE_MAX = 30.0f;        // deg/s (very still, LOWERED)
    
    static constexpr int SOUND_SPIKE_LEVEL = 50;                    // For reporting to fall detector

private:
    FallType  fallType;
    bool      _fallDetected;
    float     _fallConfidence;
    
    // Angle tracking for change rate
    float prevPitch = 0.0f, prevRoll = 0.0f, prevYaw = 0.0f;
    unsigned long lastAngleUpdateTime = 0;
    float smoothedAngleChangeRate = 0.0f;
    
    // Downward movement tracking (pitch/roll absolute angles)
    float pitchDirection = 0.0f;  // +1 = forward (pitch increasing), -1 = backward
    float rollDirection = 0.0f;   // +1 = right, -1 = left
    unsigned long downwardStartTime = 0;

    // Smoothed acceleration
    float smoothedAccelMagnitude = 9.81f;
    
    // Recent impact tracking
    struct ImpactRecord {
        float accel;
        unsigned long timestamp;
    };
    ImpactRecord recentImpacts[3];
    int impactIndex = 0;
    
    // Sound spike tracking
    bool hadRecentSoundSpike = false;
    unsigned long soundSpikeTime = 0;

    // Anti-bounce cooldown
    unsigned long lastFallAt = 0;

    // Candidate confirmation staging
    unsigned long fallCandidateAt = 0;
    float        candidateConfidence = 0.0f;

public:
    FallDetector() : fallType(UNKNOWN), _fallDetected(false), _fallConfidence(0.0f), 
                     lastFallAt(0), fallCandidateAt(0), candidateConfidence(0.0f),
                     pitchDirection(0.0f), rollDirection(0.0f), downwardStartTime(0) {
        memset(recentImpacts, 0, sizeof(recentImpacts));
    }

    void reportSoundSpike(unsigned long now) {
        hadRecentSoundSpike = true;
        soundSpikeTime = now;
    }

    // ENHANCED FALL DETECTION WITH SLOW-FALL SUPPORT
    void update(const MotionData& m, unsigned long now) {
        _fallDetected = false;
        _fallConfidence = 0.0f;

        // Calculate acceleration magnitude
        float svm = sqrt(m.accelX * m.accelX + m.accelY * m.accelY + m.accelZ * m.accelZ);
        smoothedAccelMagnitude = 0.2f * svm + 0.8f * smoothedAccelMagnitude;

        // ====== ANGLE CHANGE RATE (for rapid/slow falls) ======
        unsigned long timeDiff = (lastAngleUpdateTime > 0) ? (now - lastAngleUpdateTime) : 10;
        float dt = timeDiff / 1000.0f;
        if (dt < 0.001f) dt = 0.01f;
        
        float pitchChangeRate = abs(m.yAngle - prevPitch) / dt;
        float rollChangeRate = abs(m.xAngle - prevRoll) / dt;
        float yawChangeRate = abs(m.zAngle - prevYaw) / dt;
        
        float maxAngleChangeRate = max(pitchChangeRate, max(rollChangeRate, yawChangeRate));
        smoothedAngleChangeRate = 0.25f * maxAngleChangeRate + 0.75f * smoothedAngleChangeRate;

        // ====== DOWNWARD MOVEMENT DETECTION ======
        // Track if pitch/roll is moving toward extreme angles (lying down)
        if (m.yAngle > DOWNWARD_PITCH_THRESHOLD) {
            pitchDirection = 1.0f;  // Forward tilt
        } else if (m.yAngle < -DOWNWARD_PITCH_THRESHOLD) {
            pitchDirection = -1.0f; // Backward tilt
        }
        
        if (m.xAngle > DOWNWARD_ROLL_THRESHOLD) {
            rollDirection = 1.0f;   // Right tilt
        } else if (m.xAngle < -DOWNWARD_ROLL_THRESHOLD) {
            rollDirection = -1.0f;  // Left tilt
        }
        
        // Check if entering downward phase (first time exceeding threshold)
        bool isExtremeAngle = (abs(m.yAngle) > DOWNWARD_PITCH_THRESHOLD || abs(m.xAngle) > DOWNWARD_ROLL_THRESHOLD);
        if (isExtremeAngle && downwardStartTime == 0 && smoothedAngleChangeRate > SLOW_FALL_ANGLE_CHANGE) {
            downwardStartTime = now;
        }

        // Hardened filter: only zero out truly trivial motion
        if (smoothedAngleChangeRate < 25.0f) {
            smoothedAngleChangeRate = 0.0f;
        }

        // DEBUG: Log every 2 seconds
        static unsigned long lastDebugTime = 0;
        if (now - lastDebugTime > 2000) {
            Serial.print("FallDetector: Angle=");
            Serial.print(m.yAngle, 1); Serial.print("°(pitch) ");
            Serial.print(m.xAngle, 1); Serial.print("°(roll) | Rate=");
            Serial.print(smoothedAngleChangeRate, 1);
            Serial.print("°/s | Accel=");
            Serial.print(smoothedAccelMagnitude, 1);
            Serial.println(" m/s²");
            lastDebugTime = now;
        }
        
        prevPitch = m.yAngle;
        prevRoll = m.xAngle;
        prevYaw = m.zAngle;
        lastAngleUpdateTime = now;

        // ====== IMPACT DETECTION ======
        if (smoothedAccelMagnitude > IMPACT_THRESHOLD) {
            recentImpacts[impactIndex].accel = smoothedAccelMagnitude;
            recentImpacts[impactIndex].timestamp = now;
            impactIndex = (impactIndex + 1) % 3;
        }

        bool hadRecentImpact = false;
        float maxRecentAccel = 0.0f;
        for (int i = 0; i < 3; i++) {
            if (now - recentImpacts[i].timestamp < 300 && recentImpacts[i].accel > 0.0f) {
                hadRecentImpact = true;
                maxRecentAccel = max(maxRecentAccel, recentImpacts[i].accel);
            }
        }

        // ====== FALL CONFIRMATION FROM CANDIDATE ======
        if (fallCandidateAt > 0) {
            unsigned long candidateAge = now - fallCandidateAt;
            if (candidateAge >= FALL_CONFIRM_WAIT_MS) {
                // Post-fall: person must be still and tilted (on ground)
                bool postFallStill = (smoothedAccelMagnitude >= POST_FALL_ACCEL_MIN &&
                                      smoothedAccelMagnitude <= POST_FALL_ACCEL_MAX &&
                                      smoothedAngleChangeRate <= POST_FALL_ANGLE_RATE_MAX);
                
                // OR: extreme angle + low acceleration (lying down after slow fall)
                bool postFallExtreme = (isExtremeAngle && smoothedAccelMagnitude < SLOW_FALL_ACCEL_MAX);
                
                if (postFallStill || postFallExtreme) {
                    _fallDetected = true;
                    _fallConfidence = candidateConfidence;
                    lastFallAt = now;
                    Serial.print("FallDetector: ✓ FALL CONFIRMED (");
                    Serial.print(_fallConfidence * 100, 1);
                    Serial.print("%) - Type: ");
                    switch (fallType) {
                        case FORWARD_FALL:  Serial.print("FORWARD"); break;
                        case BACKWARD_FALL: Serial.print("BACKWARD"); break;
                        case SIDEWAYS_FALL: Serial.print("SIDEWAYS"); break;
                        case SLIP_TRIP:     Serial.print("SLIP/TRIP"); break;
                        default:            Serial.print("UNKNOWN"); break;
                    }
                    Serial.print(" | FinalAngle=");
                    Serial.print(m.yAngle, 1); Serial.print("° | Still=");
                    Serial.print(postFallStill); Serial.print(" | Extreme=");
                    Serial.println(postFallExtreme);

                    fallCandidateAt = 0;
                    candidateConfidence = 0.0f;
                    downwardStartTime = 0;
                    return;
                } else if (candidateAge > FALL_CANDIDATE_TIMEOUT_MS) {
                    Serial.println("FallDetector: Candidate timeout, discarding.");
                    fallCandidateAt = 0;
                    candidateConfidence = 0.0f;
                    downwardStartTime = 0;
                }
            }
            if (fallCandidateAt > 0) return;
        }

        // ====== DEBOUNCE ======
        if (now - lastFallAt < FALL_COOLDOWN_MS) {
            return;
        }

        // ====== PATH 1: RAPID FALL (angle + impact) ======
        if (smoothedAngleChangeRate > RAPID_ANGLE_CHANGE_THRESHOLD && hadRecentImpact && maxRecentAccel >= MIN_IMPACT_FOR_FALL) {
            // Classify based on dominant angle
            if (pitchChangeRate > rollChangeRate && pitchChangeRate > yawChangeRate) {
                fallType = (pitchDirection > 0) ? FORWARD_FALL : BACKWARD_FALL;
            } else if (rollChangeRate > pitchChangeRate) {
                fallType = SIDEWAYS_FALL;
            } else {
                fallType = SLIP_TRIP;
            }

            // Confidence: angle (primary) + impact (secondary) + sound (bonus)
            float angleScore = min(smoothedAngleChangeRate / 150.0f, 0.40f);
            float impactScore = min((maxRecentAccel - MIN_IMPACT_FOR_FALL) / 15.0f, 0.35f);
            float soundScore = (hadRecentSoundSpike && (now - soundSpikeTime) < 500) ? 0.20f : 0.0f;

            _fallConfidence = angleScore + impactScore + soundScore;
            if (fallType == SLIP_TRIP) _fallConfidence *= 0.85f;

            if (_fallConfidence >= CONFIDENCE_MIN) {
                fallCandidateAt = now;
                candidateConfidence = _fallConfidence;

                Serial.print("🔴 FALL CANDIDATE (rapid) ");
                Serial.print(_fallConfidence * 100, 1);
                Serial.print("% - Angle: ");
                Serial.print(smoothedAngleChangeRate, 1);
                Serial.print("°/s | Impact: ");
                Serial.println(maxRecentAccel, 1);
                return;
            }
        }

        // ====== PATH 2: SLOW FALL (downward angle change without hard impact) ======
        if (downwardStartTime > 0 && (now - downwardStartTime) >= SLOW_FALL_WINDOW_MS) {
            bool hasSlowDownwardAngle = (smoothedAngleChangeRate >= SLOW_FALL_ANGLE_CHANGE && 
                                         smoothedAngleChangeRate < RAPID_ANGLE_CHANGE_THRESHOLD &&
                                         isExtremeAngle);
            
            if (hasSlowDownwardAngle) {
                fallType = UNKNOWN;  // Classify later
                if (pitchDirection != 0.0f) fallType = (pitchDirection > 0) ? FORWARD_FALL : BACKWARD_FALL;
                else if (rollDirection != 0.0f) fallType = SIDEWAYS_FALL;

                float slowAngleScore = min(smoothedAngleChangeRate / 100.0f, 0.38f);
                float slowAccelScore = 0.32f;  // Slow falls have moderate scoring
                float slowSoundScore = (hadRecentSoundSpike && (now - soundSpikeTime) < 600) ? 0.20f : 0.0f;

                _fallConfidence = slowAngleScore + slowAccelScore + slowSoundScore;

                if (_fallConfidence >= CONFIDENCE_MIN) {
                    fallCandidateAt = now;
                    candidateConfidence = _fallConfidence;

                    Serial.print("🟡 FALL CANDIDATE (slow) ");
                    Serial.print(_fallConfidence * 100, 1);
                    Serial.print("% - Sustained Angle: ");
                    Serial.print(m.yAngle, 1); Serial.print("° | ChangeRate: ");
                    Serial.println(smoothedAngleChangeRate, 1);
                    downwardStartTime = 0;
                    return;
                }
            }
        }

        // Reset downward tracking if angle normalizes
        if (!isExtremeAngle) {
            downwardStartTime = 0;
        }

        hadRecentSoundSpike = false;
    }

    bool  fallDetected()   const { return _fallDetected; }
    float fallConfidence() const { return _fallConfidence; }
    FallType getFallType() const { return fallType; }

    void clearFall() { 
        _fallDetected = false; 
        _fallConfidence = 0.0f; 
        fallType = UNKNOWN; 
        downwardStartTime = 0;
    }
};

// ============================================================================
// GLOBAL INSTANCES
// ============================================================================
HTS221_Direct  hts221;
LSM6DS3_Direct lsm6ds3;
FallDetector   fallDetector;
MXChipFirebase firebaseClient;
MotionData     motion;

// EWMA filters for Firebase-bound values
// HTS221 already smooths internally; soundFilter and motionFilter act on
// values that come from faster-changing raw sources.
EWMA soundFilter(0.30f);   // Moderate — trends matter, fast spikes for fall detection only
EWMA motionFilter(0.40f);  // Faster — motion display needs reasonable responsiveness

// ============================================================================
// TIMING
// ============================================================================
#define FALL_SAMPLE_INTERVAL_MS   50UL    // Accelerometer for fall detection
#define SLOW_SENSOR_INTERVAL_MS   1000UL  // Temp / humidity / sound
#define FIREBASE_SEND_INTERVAL_MS 2000UL  // Firebase packet rate
#define WIFI_CHECK_INTERVAL_MS    30000UL // Reconnection check
#define SERIAL_PRINT_INTERVAL_MS  2000UL  // Serial readout

// ============================================================================
// WIFI RECONNECTION
// Original code had no recovery if WiFi dropped mid-session.
// ============================================================================
void checkAndReconnectWiFi() {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi lost. Reconnecting...");
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
        int attempts = 0;
        while (WiFi.status() != WL_CONNECTED && attempts < 20) {
            delay(500);
            Serial.print(".");
            attempts++;
        }
        Serial.println();
        if (WiFi.status() == WL_CONNECTED) {
            Serial.print("WiFi reconnected. IP: ");
            Serial.println(WiFi.localIP());
        } else {
            Serial.println("WiFi reconnection failed. Will retry in 30s.");
        }
    }
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    Serial.begin(115200);
    while (!Serial);

    Serial.println("========================================================");
    Serial.println("  Wearable IoT System — Environmental & Activity Monitor");
    Serial.println("  Academic City University College, Ghana (2026)");
    Serial.println("========================================================");

    Wire.begin();
    Serial.println("Scanning I2C bus...");
    int found = 0;
    for (uint8_t addr = 0x08; addr < 0x78; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.print("  I2C device at 0x");
            Serial.println(addr, 16);
            found++;
        }
    }
    Serial.print("I2C scan done. Devices: "); Serial.println(found);
    Serial.println();

    bool hts_ok = hts221.begin();
    bool lsm_ok = lsm6ds3.begin();
    soundCalibrator.calibrate();

    Serial.println("--- Sensor Init ---");
    Serial.print("HTS221  (Temp/Humidity) : "); Serial.println(hts_ok ? "OK" : "FAILED");
    Serial.print("LSM6DS3 (Accel/Gyro)   : "); Serial.println(lsm_ok ? "OK" : "FAILED");
    Serial.print("Microphone (Sound)     : "); Serial.println(soundCalibrator.isReady() ? "OK" : "FAILED");
    Serial.println();

    if (!hts_ok && !lsm_ok) {
        Serial.println("FATAL: No sensors responding. Check hardware.");
        while (1);
    }

    Serial.print("Connecting to WiFi: "); Serial.println(WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int wAttempts = 0;
    while (WiFi.status() != WL_CONNECTED && wAttempts < 20) {
        delay(500); Serial.print("."); wAttempts++;
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.print("WiFi connected. IP: "); Serial.println(WiFi.localIP());

        firebaseClient.setDebugMode(false);  // Set true to debug proxy responses
        firebaseClient.setPath(PROXY_ENDPOINT);
        firebaseClient.setDeviceId(DEVICE_ID);
        firebaseClient.setUpdateInterval(FIREBASE_UPDATE_INTERVAL_MS);

        if (firebaseClient.begin(PROXY_SERVER_IP, PROXY_SERVER_PORT)) {
            Serial.print("Firebase proxy connected: ");
            Serial.print(PROXY_SERVER_IP); Serial.print(":"); Serial.println(PROXY_SERVER_PORT);
        } else {
            Serial.print("Firebase proxy failed: "); Serial.println(firebaseClient.getLastError());
        }
    } else {
        Serial.println("WiFi connection failed. Sensor data will not be sent.");
    }

    Serial.println("========================================================");
    Serial.println("System running.");
}

// ============================================================================
// LOOP — Non-blocking millis()-based timing
//
// Original used delay(1000) which blocked everything. This prevented any
// sampling faster than 1Hz — making fall detection impossible at the
// firmware level. The restructured loop runs all tasks on independent timers:
//
//   - Fall detection samples at 50ms (20Hz) — captures the 80-500ms free-fall
//   - Slow sensors (temp/hum/sound) at 1s — their physical change rate
//   - Firebase send at 2s — proxy server rate
//   - WiFi check at 30s — low overhead reconnection guard
// ============================================================================
unsigned long lastFallSample   = 0;
unsigned long lastSlowRead     = 0;
unsigned long lastFirebaseSend = 0;
unsigned long lastWiFiCheck    = 0;
unsigned long lastSerialPrint  = 0;

static float smoothedTemp   = 0.0f;
static float smoothedHum    = 0.0f;
static float smoothedMotion = 0.0f;
static float smoothedSound  = 0.0f;

static bool fallActive = false;
static unsigned long fallStartTime = 0;
static float fallConfidenceHold = 0.0f;
static FallDetector::FallType fallTypeHold = FallDetector::UNKNOWN;

static const unsigned long FALL_BROADCAST_WINDOW_MS = 15000UL; // 15s - increased for app visibility
static bool lsm_working = true;

void loop() {
    unsigned long now = millis();

    // ------------------------------------------------------------------
    // 1. FAST: Accelerometer read + Fall detection (every 50ms)
    // ------------------------------------------------------------------
    if (now - lastFallSample >= FALL_SAMPLE_INTERVAL_MS) {
        lastFallSample = now;

        if (lsm_working) {
            lsm6ds3.readData(motion);
            if (!motion.sensorWorking) {
                lsm_working = false;
                Serial.println("LSM6DS3: Failed during operation — using fallback values.");
            } else {
                fallDetector.update(motion, now);

                // Capture falls immediately after update to avoid losing transient detection
                if (fallDetector.fallDetected()) {
                    fallActive = true;
                    fallStartTime = now;
                    fallConfidenceHold = fallDetector.fallConfidence();
                    fallTypeHold = fallDetector.getFallType();
                    Serial.print("FALL DETECTED (latched): confidence=");
                    Serial.println(fallConfidenceHold, 2);
                    fallDetector.clearFall();
                }
            }
        } else {
            // Fallback: report gravity only (device stationary, no fall detection)
            motion.accelX         = 0.0f;
            motion.accelY         = 0.0f;
            motion.accelZ         = 9.81f;
            motion.motionMagnitude = 0.0f;
            motion.xAngle = motion.yAngle = motion.zAngle = 0.0f;
            motion.sensorWorking  = false;
        }
    }

    // ------------------------------------------------------------------
    // 2. SLOW: Temperature, Humidity, Sound (every 1s)
    // ------------------------------------------------------------------
    if (now - lastSlowRead >= SLOW_SENSOR_INTERVAL_MS) {
        lastSlowRead = now;

        // HTS221 applies its own EWMA internally — values are already smoothed
        hts221.readData(smoothedTemp, smoothedHum);

        // Sound: calibrated reading then EWMA for trend tracking
        int rawSound  = soundCalibrator.getCalibratedSoundLevel();
        smoothedSound = soundFilter.update((float)rawSound);

        // Motion magnitude: EWMA on gravity-corrected value for display/discomfort
        smoothedMotion = motionFilter.update(motion.motionMagnitude);

        // Report sound spike to fall detector for confidence boosting
        if (rawSound > FallDetector::SOUND_SPIKE_LEVEL) {
            fallDetector.reportSoundSpike(now);
        }
    }

    // ------------------------------------------------------------------
    // 3. Firebase send (every 2s)
    // ------------------------------------------------------------------
    if (now - lastFirebaseSend >= FIREBASE_SEND_INTERVAL_MS) {
        lastFirebaseSend = now;

        // Read and clear fall state atomically
        if (fallDetector.fallDetected()) {
            // Set fall detected immediately for the next data send
            if (!fallActive) {
                fallActive = true;
                fallStartTime = now;
                fallConfidenceHold = fallDetector.fallConfidence();
                fallTypeHold = fallDetector.getFallType();
                Serial.print("FALL DETECTED: confidence=");
                Serial.print(fallConfidenceHold, 2);
                Serial.print(", timestamp=");
                Serial.println(fallStartTime);
            }
            fallDetector.clearFall();
        }

        bool fallNowForPublish = false;
        float fallConfForPublish = 0.0f;

if (fallActive) {
    unsigned long elapsed = now - fallStartTime;
    if (elapsed <= FALL_BROADCAST_WINDOW_MS) {
        fallNowForPublish = true;
        fallConfForPublish = fallConfidenceHold;
        Serial.print("FALL BROADCAST: Active - elapsed=");
        Serial.print(elapsed);
        Serial.print("ms, confidence=");
        Serial.println(fallConfForPublish, 2);
    } else {
        fallActive = false;
        fallConfidenceHold = 0.0f;
        Serial.println("FALL BROADCAST: Window expired, resetting fall state");
    }
} else {
    Serial.println("FALL BROADCAST: No active fall");
}

        if (WiFi.status() == WL_CONNECTED && firebaseClient.isConnected()) {
            Serial.print("SENDING DATA: fall_detected=");
            Serial.print(fallNowForPublish ? 1 : 0);
            Serial.print(", confidence=");
            Serial.println(fallConfForPublish, 2);
            
            firebaseClient.sendSensorData(
                DEVICE_ID,
                smoothedTemp,
                smoothedHum,
                smoothedMotion,
                (int)smoothedSound,
                motion.accelX,  motion.accelY,  motion.accelZ,
                motion.gyroX,   motion.gyroY,   motion.gyroZ,
                motion.magX,    motion.magY,    motion.magZ,
                motion.xAngle,  motion.yAngle,  motion.zAngle,
                motion.heading,
                fallNowForPublish ? 1 : 0,
                fallConfForPublish
            );
        }
    }

    // ------------------------------------------------------------------
    // 4. WiFi reconnection check (every 30s)
    // ------------------------------------------------------------------
    if (now - lastWiFiCheck >= WIFI_CHECK_INTERVAL_MS) {
        lastWiFiCheck = now;
        checkAndReconnectWiFi();
    }

    // ------------------------------------------------------------------
    // 5. Serial output (every 2s)
    // ------------------------------------------------------------------
    if (now - lastSerialPrint >= SERIAL_PRINT_INTERVAL_MS) {
        lastSerialPrint = now;
        Serial.print("Temp: ");   Serial.print(smoothedTemp, 1);   Serial.print("C  ");
        Serial.print("Hum: ");    Serial.print(smoothedHum,  1);   Serial.print("%  ");
        Serial.print("Motion: "); Serial.print(smoothedMotion, 2); Serial.print(" m/s2  ");
        Serial.print("Sound: ");  Serial.print((int)smoothedSound);
        Serial.print("  Status: ");

        if (fallActive) {
            Serial.print("FALL DETECTED! Confidence: ");
            Serial.print(fallConfidenceHold * 100, 0);
            Serial.print("% | Type: ");
        } else {
            Serial.print("MONITORING | Fall Type: ");
        }

        FallDetector::FallType currentFallType = fallActive ? fallTypeHold : fallDetector.getFallType();
        switch (currentFallType) {
            case FallDetector::FORWARD_FALL:  Serial.print("FORWARD");  break;
            case FallDetector::BACKWARD_FALL: Serial.print("BACKWARD"); break;
            case FallDetector::SIDEWAYS_FALL: Serial.print("SIDEWAYS"); break;
            case FallDetector::SLIP_TRIP:     Serial.print("SLIP/TRIP"); break;
            default: Serial.print("NONE"); break;
        }

        Serial.println();
    }
}