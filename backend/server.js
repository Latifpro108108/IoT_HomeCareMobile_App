require('dotenv').config();

const express = require('express');
const axios = require('axios');
const cors = require('cors');
const fs = require('fs');

let admin = null;
let adminInitialized = false;

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use((req, res, next) => {
  console.log('Incoming:', req.method, req.path);
  next();
});

const FIREBASE_URL = process.env.FIREBASE_DATABASE_URL;
const API_KEY = process.env.FIREBASE_API_KEY || '';

if (!FIREBASE_URL) {
  console.error('ERROR: FIREBASE_DATABASE_URL not set in .env');
  process.exit(1);
}

const FIREBASE_AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
let authToken = null;

async function authenticateAnonymously() {
  if (!API_KEY) {
    console.warn('API_KEY not set — skipping anonymous auth');
    return null;
  }
  try {
    const response = await axios.post(FIREBASE_AUTH_URL, { returnSecureToken: true });
    authToken = response.data.idToken;
    console.log('Anonymous auth OK. UID:', response.data.localId);
    return authToken;
  } catch (err) {
    console.warn('Anonymous auth failed:', err.response?.data || err.message);
    return null;
  }
}

authenticateAnonymously()
  .then((token) => {
    if (token) {
      setInterval(async () => {
        console.log('Refreshing auth token...');
        await authenticateAnonymously();
      }, 50 * 60 * 1000);
    }
  })
  .catch((err) => console.warn('Auth init error:', err.message));

// Optional Admin SDK
try {
  const serviceAccountPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS || './serviceAccountKey.json';
  if (fs.existsSync(serviceAccountPath)) {
    admin = require('firebase-admin');
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: FIREBASE_URL,
    });
    adminInitialized = true;
    console.log('Firebase Admin SDK initialized from', serviceAccountPath);
  } else {
    console.log('No service account found — using REST API with anonymous auth.');
  }
} catch (err) {
  console.warn('Firebase Admin SDK init failed:', err.message);
}

// Store last fall detection for persistence
let lastFallData = {
  detected: false,
  confidence: 0.0,
  timestamp: null,
  expiresAt: null
};

app.post('/sensor-data', async (req, res) => {
  try {
    const deviceId = req.body.device_id || 'MXCHIP_001';
    const timestamp = parseInt(req.body.timestamp, 10) || Date.now();

    const temperature = parseFloat(req.body.temperature);
    const humidity = parseFloat(req.body.humidity);
    const motionMagnitude = parseFloat(req.body.motion_magnitude) || 0;
    const motionX = parseFloat(req.body.motion_x) || 0;
    const motionY = parseFloat(req.body.motion_y) || 0;
    const motionZ = parseFloat(req.body.motion_z) || 0;
    const gyroX = parseFloat(req.body.gyro_x) || 0;
    const gyroY = parseFloat(req.body.gyro_y) || 0;
    const gyroZ = parseFloat(req.body.gyro_z) || 0;
    const magX = parseFloat(req.body.mag_x) || 0;
    const magY = parseFloat(req.body.mag_y) || 0;
    const magZ = parseFloat(req.body.mag_z) || 0;
    const angleX = parseFloat(req.body.angle_x) || 0;
    const angleY = parseFloat(req.body.angle_y) || 0;
    const angleZ = parseFloat(req.body.angle_z) || 0;
    const heading = parseFloat(req.body.heading) || 0;
    const sound = parseInt(req.body.sound, 10) || 0;

    let fallDetected = parseInt(req.body.fall_detected, 10);
    if (Number.isNaN(fallDetected) || (fallDetected !== 0 && fallDetected !== 1)) {
      fallDetected = 0;
    }

    let fallConfidence = parseFloat(req.body.fall_confidence);
    if (Number.isNaN(fallConfidence) || fallConfidence < 0 || fallConfidence > 1) {
      fallConfidence = 0.0;
    }

    // Update last fall data if a new fall is detected. Allow confidence==0 to capture valid event flags.
    if (fallDetected === 1) {
      lastFallData = {
        detected: true,
        confidence: fallConfidence,
        timestamp: timestamp,
        expiresAt: timestamp + (10 * 60 * 1000) // 10 minutes from now for better visibility
      };
      console.log(`New fall detected: confidence ${fallConfidence}, expires at ${new Date(lastFallData.expiresAt).toISOString()}`);
    }

    // Check if last fall data has expired
    const now = Date.now();
    if (lastFallData.expiresAt && now > lastFallData.expiresAt) {
      lastFallData = {
        detected: false,
        confidence: 0.0,
        timestamp: null,
        expiresAt: null
      };
      console.log('Last fall data expired, resetting');
    }

    if (Number.isNaN(temperature) || Number.isNaN(humidity)) {
      throw new Error('temperature and humidity are required');
    }

    const firebaseData = {
      device_id: deviceId,
      timestamp,
      sensors: {
        motion: {
          magnitude: motionMagnitude,
          x: motionX,
          y: motionY,
          z: motionZ,
          gyro_x: gyroX,
          gyro_y: gyroY,
          gyro_z: gyroZ,
          mag_x: magX,
          mag_y: magY,
          mag_z: magZ,
          angle_x: angleX,
          angle_y: angleY,
          angle_z: angleZ,
          heading,
        },
        sound: { raw: sound },
        temperature,
        humidity,
      },
      fall_detected: fallDetected === 1 ? 1 : 0,
      fall_confidence: fallConfidence,
      fall_detection: {
        detected: fallDetected === 1,
        confidence: fallConfidence,
        timestamp: fallDetected === 1 ? timestamp : null,
      },
      last_fall: {
        detected: lastFallData.detected,
        confidence: lastFallData.confidence,
        timestamp: lastFallData.timestamp,
        time_since: lastFallData.timestamp ? (now - lastFallData.timestamp) : null,
      },
      received_at: new Date().toISOString(),
    };

    if (adminInitialized && admin) {
      await admin.database().ref(`devices/${deviceId}/current`).set(firebaseData);
      await admin.database().ref(`devices/${deviceId}/history/${timestamp}`).set(firebaseData);

      if (fallDetected === 1) {
        await admin.database().ref(`devices/${deviceId}/fall_events/${timestamp}`).set({
          detected: true,
          confidence: fallConfidence,
          timestamp,
          sensor_snapshot: {
            temperature,
            humidity,
            motionMagnitude,
            sound,
            orientation: { x: angleX, y: angleY, z: angleZ },
            magnetometer: { x: magX, y: magY, z: magZ, heading },
          },
        });
      }
    } else {
      const withAuth = (url) => (authToken ? `${url}?auth=${authToken}` : url);

      await axios.put(
        withAuth(`${FIREBASE_URL}/devices/${deviceId}/current.json`),
        firebaseData,
        { headers: { 'Content-Type': 'application/json' } }
      );

      await axios.put(
        withAuth(`${FIREBASE_URL}/devices/${deviceId}/history/${timestamp}.json`),
        firebaseData,
        { headers: { 'Content-Type': 'application/json' } }
      );

      if (fallDetected === 1) {
        await axios.put(
          withAuth(`${FIREBASE_URL}/devices/${deviceId}/fall_events/${timestamp}.json`),
          {
            detected: true,
            confidence: fallConfidence,
            timestamp,
            sensor_snapshot: {
              temperature,
              humidity,
              motionMagnitude,
              sound,
              orientation: { x: angleX, y: angleY, z: angleZ },
              magnetometer: { x: magX, y: magY, z: magZ, heading },
            },
          },
          { headers: { 'Content-Type': 'application/json' } }
        );
      }
    }

    res.json({
      success: true,
      message: 'Data forwarded to Firebase',
      device_id: deviceId,
      timestamp,
    });
  } catch (error) {
    console.error('Error:', error.message);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString(), firebase_url: FIREBASE_URL });
});

app.get('/test-firebase', async (req, res) => {
  try {
    const testUrl = `${FIREBASE_URL}/test.json`;
    if (adminInitialized && admin) {
      await admin.database().ref('test').set({ test: true, timestamp: Date.now() });
      res.json({ success: true, message: 'Admin SDK test OK' });
    } else {
      const response = await axios.put(testUrl, { test: true, timestamp: Date.now() });
      res.json({ success: true, data: response.data });
    }
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log('═══════════════════════════════════════════════════════');
  console.log('  MXChip Firebase Proxy Server');
  console.log('═══════════════════════════════════════════════════════');
  console.log(`Port     : ${port}`);
  console.log(`Firebase : ${FIREBASE_URL}`);
  console.log(`Auth     : ${API_KEY ? 'Anonymous token' : 'Database rules only'}`);
  console.log('Endpoints:');
  console.log('  POST /sensor-data  — Receive from MXChip');
  console.log('  GET  /health       — Health check');
  console.log('  GET  /test-firebase — Test Firebase write');
  console.log('═══════════════════════════════════════════════════════');
});