require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { Auth } = require('@vonage/auth');
const { Verify2 } = require('@vonage/verify2');

const { router: verificationRouter, setVerifyClient } = require('./routes/verification');
const { router: webhookRouter } = require('./routes/webhook');

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Initialize Vonage client only if we have credentials.
// Skipped under test — tests inject a mock via setVerifyClient, and loading
// real credentials here would overwrite it.
if (process.env.NODE_ENV !== 'test'
    && process.env.VONAGE_APPLICATION_ID && process.env.VONAGE_PRIVATE_KEY_PATH) {
  const fs = require('fs');
  const privateKeyPath = process.env.VONAGE_PRIVATE_KEY_PATH;

  try {
    const privateKey = fs.readFileSync(privateKeyPath, 'utf8');
    const credentials = new Auth({
      applicationId: process.env.VONAGE_APPLICATION_ID,
      privateKey
    });

    const verifyClient = new Verify2(credentials);
    setVerifyClient(verifyClient);
    console.log('Vonage credentials loaded');
  } catch (error) {
    console.error('Failed to load Vonage credentials:', error.message);
  }
} else if (process.env.NODE_ENV !== 'test') {
  console.warn('VONAGE_APPLICATION_ID or VONAGE_PRIVATE_KEY_PATH not set');
}

app.use('/', verificationRouter);
app.use('/', webhookRouter);

const PORT = process.env.PORT || 4000;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}

module.exports = app;
