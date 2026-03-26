#include "MXChipFirebase.h"

MXChipFirebase::MXChipFirebase() {
    connected      = false;
    debugMode      = false;
    host           = "192.168.1.100";
    port           = 3000;
    path           = "/sensor-data";
    deviceId       = "MXCHIP_001";
    lastSendTime   = 0;
    updateInterval = 5000;
    strcpy(lastError, "");
}

bool MXChipFirebase::begin(const char* host, int port) {
    this->host = host;
    this->port = port;
    connected  = (WiFi.status() == WL_CONNECTED);
    if (debugMode) {
        Serial.print("MXChipFirebase: proxy = ");
        Serial.print(host);
        Serial.print(":");
        Serial.println(port);
    }
    return connected;
}

bool MXChipFirebase::sendData(float temperature, float humidity) {
    if (!connected) return false;

    if (client.connect(host, port)) {
        char payload[128];
        snprintf(payload, sizeof(payload),
                 "{\"temperature\":%.2f,\"humidity\":%.1f,\"timestamp\":%lu}",
                 temperature, humidity, millis());

        char request[256];
        snprintf(request, sizeof(request),
                 "POST %s HTTP/1.1\r\n"
                 "Host: %s\r\n"
                 "Content-Type: application/json\r\n"
                 "Connection: close\r\n"
                 "Content-Length: %d\r\n"
                 "\r\n"
                 "%s",
                 path, host, strlen(payload), payload);

        client.print(request);

        unsigned long timeout = millis();
        while (client.available() == 0) {
            if (millis() - timeout > 5000) {
                strcpy(lastError, "Client Timeout");
                client.stop();
                return false;
            }
            delay(10);
        }

        while (client.available()) client.read();
        client.stop();
        return true;
    }

    strcpy(lastError, "Failed to connect");
    return false;
}

bool MXChipFirebase::sendJSON(const char* jsonData) {
    if (!connected || WiFi.status() != WL_CONNECTED) {
        strcpy(lastError, "WiFi not connected");
        return false;
    }

    if (client.connect(host, port)) {
        char request[1500];
        int contentLength = strlen(jsonData);

        snprintf(request, sizeof(request),
                 "POST %s HTTP/1.1\r\n"
                 "Host: %s:%d\r\n"
                 "Content-Type: application/json\r\n"
                 "Connection: close\r\n"
                 "Content-Length: %d\r\n"
                 "\r\n"
                 "%s",
                 path, host, port, contentLength, jsonData);

        if (debugMode) {
            Serial.println("Sending to proxy:");
            Serial.println(request);
        }

        client.print(request);

        unsigned long timeout = millis();
        while (client.available() == 0) {
            if (millis() - timeout > 5000) {
                strcpy(lastError, "Client Timeout");
                client.stop();
                return false;
            }
            delay(10);
        }

        bool success = false;
        String response = "";
        while (client.available()) {
            char c = client.read();
            response += c;
            if (debugMode) Serial.write(c);
        }

        success = (response.indexOf("200 OK") >= 0 ||
                   response.indexOf("200") >= 0 ||
                   response.indexOf("success") >= 0);

        client.stop();

        if (!success) strcpy(lastError, "No success confirmation from proxy");
        return success;
    }

    strcpy(lastError, "Failed to connect to proxy");
    if (debugMode) {
        Serial.print("Could not connect to ");
        Serial.print(host);
        Serial.print(":");
        Serial.println(port);
    }
    return false;
}

bool MXChipFirebase::sendSensorData(
    const char* deviceId,
    float temp,      float hum,
    float motionMag, int sound,
    float accelX,    float accelY,    float accelZ,
    float gyroX,     float gyroY,     float gyroZ,
    float magX,      float magY,      float magZ,
    float xAngle,    float yAngle,    float zAngle,
    float heading,
    int   fall_detected,
    float fall_confidence
) {
    if (!connected || WiFi.status() != WL_CONNECTED) {
        strcpy(lastError, "WiFi not connected");
        return false;
    }

    unsigned long now = millis();
    if (now - lastSendTime < updateInterval) return true;
    lastSendTime = now;

    char jsonPayload[1200];
    unsigned long timestamp = now / 1000;

    snprintf(jsonPayload, sizeof(jsonPayload),
        "{"
        "\"device_id\":\"%s\","
        "\"timestamp\":%lu,"
        "\"temperature\":%.2f,"
        "\"humidity\":%.2f,"
        "\"motion_magnitude\":%.3f,"
        "\"motion_x\":%.3f,"
        "\"motion_y\":%.3f,"
        "\"motion_z\":%.3f,"
        "\"gyro_x\":%.3f,"
        "\"gyro_y\":%.3f,"
        "\"gyro_z\":%.3f,"
        "\"mag_x\":%.4f,"
        "\"mag_y\":%.4f,"
        "\"mag_z\":%.4f,"
        "\"angle_x\":%.2f,"
        "\"angle_y\":%.2f,"
        "\"angle_z\":%.2f,"
        "\"heading\":%.1f,"
        "\"sound\":%d,"
        "\"fall_detected\":%d,"
        "\"fall_confidence\":%.2f"
        "}",
        deviceId ? deviceId : this->deviceId,
        timestamp,
        temp, hum,
        motionMag, accelX, accelY, accelZ,
        gyroX, gyroY, gyroZ,
        magX, magY, magZ,
        xAngle, yAngle, zAngle,
        heading,
        sound,
        fall_detected,
        fall_confidence
    );

    return sendJSON(jsonPayload);
}

void MXChipFirebase::setDebugMode(bool debug)            { debugMode = debug; }
void MXChipFirebase::setPath(const char* p)              { path = p; }
void MXChipFirebase::setDeviceId(const char* id)         { deviceId = id; }
void MXChipFirebase::setUpdateInterval(unsigned long ms) { updateInterval = ms; }
bool MXChipFirebase::isConnected()                       { return connected; }
const char* MXChipFirebase::getLastError()               { return lastError; }