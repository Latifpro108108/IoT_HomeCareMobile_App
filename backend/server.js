const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express = require('express');
const axios = require('axios');
const cors = require('cors');
const fs = require('fs');
let admin = null;
let adminInitialized = false;

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use((req, res, next) => {
    console.log('Incoming request:', {
        method: req.method,
        path: req.path,
        headers: req.headers,
        body: req.body
    });
    next();
});

// Firebase configuration - Load from .env file
// See .env.example for template
const FIREBASE_URL = process.env.FIREBASE_DATABASE_URL;
const API_KEY = process.env.FIREBASE_API_KEY || '';

if (!FIREBASE_URL) {
    console.error('❌ ERROR: FIREBASE_DATABASE_URL not set in .env file');
    console.error('   Please copy .env.example to .env and fill in your Firebase credentials');
    process.exit(1);
}
const FIREBASE_AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;

// Store anonymous auth token (will be fetched on startup)
let authToken = null;

// Function to authenticate anonymously with Firebase
async function authenticateAnonymously() {
    if (!API_KEY) {
        console.warn('⚠️  API_KEY not set - skipping anonymous authentication');
        return null;
    }

    try {
        console.log('🔐 Authenticating anonymously with Firebase...');
        const response = await axios.post(FIREBASE_AUTH_URL, {
            returnSecureToken: true
        });

        authToken = response.data.idToken;
        console.log('✅ Anonymous authentication successful!');
        console.log('   User ID:', response.data.localId);
        return authToken;
    } catch (error) {
        const errorDetails = error.response?.data || error.message;
        console.error('❌ Anonymous authentication failed:', JSON.stringify(errorDetails, null, 2));
        console.warn('⚠️  Continuing without auth token - will use database rules');
        console.warn('   Make sure Firebase Realtime Database rules allow writes');
        return null;
    }
}

// Authenticate on startup (non-blocking)
authenticateAnonymously().then(token => {
    if (token) {
        // Refresh token every 50 minutes (tokens expire after 1 hour)
        setInterval(async () => {
            console.log('🔄 Refreshing anonymous auth token...');
            await authenticateAnonymously();
        }, 50 * 60 * 1000);
    }
}).catch(err => {
    console.warn('⚠️  Auth initialization error (non-critical):', err.message);
});

// Optional: initialize Firebase Admin SDK if service account is provided
try {
    // Detect service account via env var or local file
    const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || './serviceAccountKey.json';
    if (fs.existsSync(serviceAccountPath)) {
        admin = require('firebase-admin');
        const serviceAccount = require(serviceAccountPath);
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            databaseURL: FIREBASE_URL
        });
        adminInitialized = true;
        console.log('✅ Firebase Admin SDK initialized using', serviceAccountPath);
    } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        // If env var set but file doesn't exist, try application default credentials
        admin = require('firebase-admin');
        admin.initializeApp({
            credential: admin.credential.applicationDefault(),
            databaseURL: FIREBASE_URL
        });
        adminInitialized = true;
        console.log('✅ Firebase Admin SDK initialized using application default credentials');
    } else {
        console.log('ℹ️  Firebase Admin SDK not initialized (no service account).');
    }
} catch (err) {
    console.warn('⚠️  Could not initialize Firebase Admin SDK:', err.message);
}

console.log('Server configuration:', {
    FIREBASE_URL,
    API_KEY: API_KEY ? '***' + API_KEY.slice(-6) : 'not set (will use default Firebase rules)',
    AUTH_MODE: API_KEY ? 'Anonymous Authentication' : 'Database Rules Only'
});

// Proxy endpoint for sensor data
app.post('/sensor-data', async (req, res) => {
    try {
        console.log('Raw request body:', req.body);
        
        // Extract data from request
        const deviceId = req.body.device_id || 'MXCHIP_001';
        const timestamp = parseInt(req.body.timestamp) || Date.now();
        const temperature = parseFloat(req.body.temperature);
        const humidity = parseFloat(req.body.humidity);
        const motionMagnitude = parseFloat(req.body.motion_magnitude) || 0;
        const motionX = parseFloat(req.body.motion_x) || 0;
        const motionY = parseFloat(req.body.motion_y) || 0;
        const motionZ = parseFloat(req.body.motion_z) || 0;
        const gyroX = parseFloat(req.body.gyro_x) || 0;
        const gyroY = parseFloat(req.body.gyro_y) || 0;
        const gyroZ = parseFloat(req.body.gyro_z) || 0;
        const angleX = parseFloat(req.body.angle_x) || 0;
        const angleY = parseFloat(req.body.angle_y) || 0;
        const angleZ = parseFloat(req.body.angle_z) || 0;
        const sound = parseInt(req.body.sound) || 0;

        // Validate required fields
        if (isNaN(temperature) || isNaN(humidity) || isNaN(timestamp)) {
            throw new Error('Invalid data format: temperature, humidity, and timestamp are required');
        }

        // Structure data for Firebase
        const firebaseData = {
            device_id: deviceId,
            timestamp: timestamp,
            sensors: {
                motion: {
                    magnitude: motionMagnitude,
                    x: motionX,
                    y: motionY,
                    z: motionZ,
                    gyro_x: gyroX,
                    gyro_y: gyroY,
                    gyro_z: gyroZ,
                    angle_x: angleX,
                    angle_y: angleY,
                    angle_z: angleZ
                },
                sound: {
                    raw: sound
                },
                temperature: temperature,
                humidity: humidity
            },
            received_at: new Date().toISOString()
        };

        console.log('Processed data:', firebaseData);
        
        // Construct Firebase path with authentication
        const firebasePath = `/devices/${deviceId}/current.json`;
        let firebaseUrl = `${FIREBASE_URL}${firebasePath}`;
        
        // Add auth token if available (for anonymous authentication)
        if (authToken) {
            firebaseUrl += `?auth=${authToken}`;
        }
        
        console.log('Sending to Firebase URL:', firebaseUrl.replace(authToken || '', '***'));

        if (adminInitialized && admin) {
            // Use Admin SDK for privileged writes (bypasses DB rules)
            await admin.database().ref(`devices/${deviceId}/current`).set(firebaseData);
            await admin.database().ref(`devices/${deviceId}/history/${timestamp}`).set(firebaseData);
            console.log('Firebase Admin SDK write: OK');
        } else {
            // Forward the data to Firebase using REST PUT (updates the current reading)
            const response = await axios({
                method: 'PUT',
                url: firebaseUrl,
                data: firebaseData,
                headers: {
                    'Content-Type': 'application/json'
                }
            });

            console.log('Firebase response:', response.status, response.statusText);

            // Also store historical data (append to history)
            const historyPath = `/devices/${deviceId}/history/${timestamp}.json`;
            let historyUrl = `${FIREBASE_URL}${historyPath}`;
            
            // Add auth token if available
            if (authToken) {
                historyUrl += `?auth=${authToken}`;
            }
            
            await axios({
                method: 'PUT',
                url: historyUrl,
                data: firebaseData,
                headers: {
                    'Content-Type': 'application/json'
                }
            });
        }

        res.json({
            success: true,
            message: 'Data sent to Firebase successfully',
            device_id: deviceId,
            timestamp: timestamp
        });
    } catch (error) {
        console.error('Error details:', {
            name: error.name,
            message: error.message,
            response: error.response ? {
                status: error.response.status,
                statusText: error.response.statusText,
                data: error.response.data
            } : 'No response data',
            config: error.config ? {
                url: error.config.url,
                method: error.config.method
            } : 'No config data'
        });

        res.status(500).json({
            success: false,
            error: 'Failed to send data to Firebase',
            details: error.message
        });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy',
        timestamp: new Date().toISOString(),
        firebase_url: FIREBASE_URL
    });
});

// Test endpoint for Firebase connection
app.get('/test-firebase', async (req, res) => {
    try {
        const testData = {
            test: true,
            timestamp: Date.now(),
            message: 'Test connection from proxy server'
        };
        
        // Firebase Realtime Database uses database rules, not API key auth
        const testUrl = `${FIREBASE_URL}/test.json`;
        if (adminInitialized && admin) {
            await admin.database().ref('test').set(testData);
            res.json({ success: true, message: 'Firebase Admin SDK test successful' });
        } else {
            const response = await axios({
                method: 'PUT',
                url: testUrl,
                data: testData
            });

            res.json({
                success: true,
                message: 'Firebase connection test successful',
                data: response.data
            });
        }
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message,
            details: error.response ? error.response.data : null
        });
    }
});

// Log when server starts
// Listen on all interfaces (0.0.0.0) so MXChip can connect from network
app.listen(port, '0.0.0.0', () => {
    console.log(`═══════════════════════════════════════════════════════`);
    console.log(`  MXChip Firebase Proxy Server`);
    console.log(`═══════════════════════════════════════════════════════`);
    console.log(`Proxy server running on port ${port}`);
    console.log(`Listening on: 0.0.0.0:${port} (all network interfaces)`);
    console.log(`Firebase URL: ${FIREBASE_URL}`);
    console.log(`API Key: ${API_KEY ? '***' + API_KEY.slice(-6) : 'Not set (using default rules)'}`);
    console.log(`Auth Mode: ${API_KEY ? 'Anonymous Authentication' : 'Database Rules Only'}`);
    console.log(`═══════════════════════════════════════════════════════`);
    console.log(`Endpoints:`);
    console.log(`  POST /sensor-data  - Receive data from MXChip`);
    console.log(`  GET  /health       - Health check`);
    console.log(`  GET  /test-firebase - Test Firebase connection`);
    console.log(`═══════════════════════════════════════════════════════`);
    console.log(`\n📱 MXChip Configuration:`);
    console.log(`   Update PROXY_SERVER_IP to your computer's IP address`);
    console.log(`   Find your IP: ipconfig (Windows) or ifconfig (Mac/Linux)`);
    console.log(`═══════════════════════════════════════════════════════`);
});

