#ifndef MXChipFirebase_H
#define MXChipFirebase_H

#include <Arduino.h>
#include "AZ3166WiFi.h"
#include "Wire.h"

class MXChipFirebase {
public:
    MXChipFirebase();
    bool begin(const char* host, int port);
    bool sendData(float temperature, float humidity);

    // Full payload signature (includes mag + heading + fall fields)
    bool sendSensorData(
        const char* deviceId,
        float temp,        float hum,
        float motionMag,   int sound,
        float accelX,      float accelY,   float accelZ,
        float gyroX,       float gyroY,    float gyroZ,
        float magX,        float magY,     float magZ,
        float xAngle,      float yAngle,   float zAngle,
        float heading,
        int   fall_detected,
        float fall_confidence
    );

    bool sendJSON(const char* jsonData);
    bool isConnected();
    void setDebugMode(bool debug);
    void setPath(const char* path);
    void setDeviceId(const char* deviceId);
    void setUpdateInterval(unsigned long interval);
    const char* getLastError();

private:
    WiFiClient client;
    bool connected;
    bool debugMode;
    const char* host;
    int port;
    const char* path;
    const char* deviceId;
    unsigned long lastSendTime;
    unsigned long updateInterval;
    char lastError[256];
};

#endif