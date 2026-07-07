# SilentAuthDemo

A companion iOS app for the Vonage developer-blog tutorial **"Behind the Scenes: Visualizing Silent Auth in an iOS App."**

This demo app shows **invisible phone-number login** using Vonage Verify v2: Silent Authentication as the primary factor, with automatic SMS and voice fallback. A **Dev Mode** toggle reveals a live console of every API call, webhook, device event, and cellular request — making an otherwise invisible auth flow visible for a developer audience.

The app runs on iOS 16+ (iPhone and iPad), backed by a Node.js server that handles Vonage Verify v2 API calls and manages webhook callbacks. All phone numbers and OTP codes are redacted in logs by default to protect PII.

![SilentAuthDemo App](./ios/SilentAuthDemo/Resources/Assets.xcassets/AppIcon.appiconset/icon.png)

## Repo Structure

```
.
├── server/              # Node.js + Express backend (Vonage Verify v2 integration)
│   ├── server.js        # Express server + middleware
│   ├── routes/
│   │   ├── verification.js
│   │   ├── webhook.js
│   │   └── ...
│   ├── __tests__/       # Backend tests (Jest)
│   └── package.json
├── ios/                 # SwiftUI app (iOS 16+)
│   ├── SilentAuthDemo.xcodeproj
│   └── SilentAuthDemo/
│       ├── App/
│       ├── Features/
│       ├── Networking/
│       ├── Models/
│       ├── Theme/
│       └── ...
├── tasks/               # Planning & implementation notes
├── scripts/             # Xcode project generation
└── README.md
```

## Prerequisites

- **macOS + Xcode 15+** (to build the iOS app)
- **Node.js 20+** (for the backend server)
- **A [Vonage account](https://ui.idp.vonage.com/ui/auth/registration)** with active API credentials
- **[ngrok](https://ngrok.com)** (to expose your local backend to Vonage webhooks during development)
- **iOS device or simulator** (iOS 16+)

## Quick Start (10 Minutes)

### Step 1: Create a Vonage Application

1. Go to [dashboard.nexmo.com → Applications](https://dashboard.nexmo.com/applications) and click **Create a new application**.
2. Name it (e.g., "SilentAuthDemo").
3. Under **Capabilities**, enable:
   - **Verify** (primary SMS/voice capabilities)
   - **Network Registry** (unlocks Silent Authentication)
4. Click **Generate public and private key** and download `private.key`.
5. Save `private.key` to `server/private.key` (it's already in `.gitignore`).
6. Copy your **Application ID** — you'll need it in the next step.

> **Note:** Do not commit `private.key` to version control.

### Step 2: Start the Backend Server

```bash
cd server
cp .env.example .env
```

Edit `.env` and fill in:
```env
VONAGE_APPLICATION_ID=your_application_id_from_step_1
VONAGE_PRIVATE_KEY_PATH=./private.key
PORT=4000
CHANNEL_TIMEOUT_SECONDS=60
```

Then:
```bash
npm install
npm run dev
```

The backend is now running on `http://localhost:4000`.

### Step 3: Expose the Backend to Vonage Webhooks

Open a **new terminal** and run:
```bash
ngrok http 4000
```

You'll see an HTTPS URL like `https://abc123.ngrok.io`. Copy this URL.

In your [Vonage Dashboard](https://dashboard.nexmo.com/applications), open your application's **Verify capability** settings and update the **Callback URL** to:
```
https://abc123.ngrok.io/callback
```

Save the changes.

### Step 4: Run the iOS App

1. Open `ios/SilentAuthDemo.xcodeproj` in Xcode.
2. Copy `ios/Config.xcconfig` to `ios/Config.local.xcconfig`:
   ```bash
   cp ios/Config.xcconfig ios/Config.local.xcconfig
   ```
3. Edit `ios/Config.local.xcconfig` and set `BASE_URL` to your ngrok URL (no trailing slash):
   ```
   BASE_URL = https://abc123.ngrok.io
   ```
   (This file is gitignored — never commit it.)
4. Select your target device/simulator in Xcode.
5. Press **Cmd+R** to build and run.

### Step 5: Test the Flow

1. Enter a phone number (see **Testing without a real SIM** below for sandbox numbers).
2. Toggle **Dev Mode** to see the live console of every API call, webhook, and device event.
3. Follow the on-screen prompts (Silent Auth → SMS code → verify).

---

## Testing

### Run Backend Tests
```bash
cd server
npm test
```

### Run iOS Tests
```bash
xcodebuild test -project ios/SilentAuthDemo.xcodeproj \
  -scheme SilentAuthDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Testing without a Real SIM (Vonage Playground)

Use Vonage's **Network Registry Playground** with test numbers starting with `+990`:

| Last Digit | Outcome              |
|------------|----------------------|
| **even**   | ✓ Silent Auth completes |
| **odd**    | ✗ Silent Auth rejected (falls back to SMS) |
| **99**     | ✗ Silent Auth failed (falls back to SMS) |

**Example test numbers:**
- `+99012345670` — Silent Auth succeeds, verified immediately
- `+99012345671` — Silent Auth fails, SMS code required
- `+99012345699` — Silent Auth fails hard, SMS required

---

## How It Works

### The Auth Flow

1. **Phone Entry** → User enters phone number in E.164 format (e.g., `+14155551234`)
2. **Silent Auth (Primary)** → App makes a cellular-forced network request to a Vonage-provided `check_url`. The network identifies the SIM; if available, Vonage verifies without any user action.
   - ✓ If Silent Auth completes → User is verified immediately
   - ✗ If Silent Auth unavailable or times out → Falls through to SMS
3. **SMS (Secondary Fallback)** → Vonage sends a one-time code by text message
4. **Voice (Tertiary Fallback)** → If SMS also times out, Vonage calls and reads the code aloud
5. **Verification** → User enters the SMS or voice code, app calls `/check-code`, and backend verifies with Vonage

### Dev Mode Console

Toggle **Dev Mode** at the bottom of the login form to see a real-time, grouped timeline of:

- **Merged Server + Device Logs** — Every backend API call, webhook delivery, and on-device cellular request
- **Channel Tracker** — Visual progress through Silent Auth → SMS → Voice stages
- **Redaction** — Phone numbers masked (last 4 digits only), OTP codes truncated (last 2 digits only)
- **Stage Headers** — Events grouped by channel with outcome labels (completed, failed, in progress, fell through)

**Log Sources:**
- **Server** (plum badge) — Vonage API responses, webhook callbacks, timeout events
- **Device** (purple badge) — Cellular check attempts, code submission, fallback triggers

The app polls the backend for new logs every 1.5 seconds. This polling approach avoids conflicts with the cellular network isolation that the Silent Auth SDK requires.

---

## Security & Privacy

### Phone Number Redaction
- All phone numbers are masked **server-side** before reaching the UI
- Only the last 4 digits are visible in logs and exports (e.g., `+1•••••1234`)
- PII is never exposed in screenshots or screen recordings used for the blog tutorial

### OTP Code Masking
- Full SMS/voice codes are **never** logged
- Only the last 2 digits are visible in Dev Mode logs (e.g., `code ends in 23`)

### Message Content Protection
- Message bodies are not logged by default
- Even if logged, redaction ensures only non-sensitive metadata appears

> **Best Practice:** If you take screenshots or screen recordings of Dev Mode for sharing, the redaction ensures PII is already hidden by default.

---

## Architecture

### Backend (`server/`)

- **Express.js** with CORS and JSON middleware
- **Vonage Verify v2 SDK** (`@vonage/verify2`, `@vonage/auth`) for JWT-based API calls
- **In-memory request store** mapping `requestId → { phone, workflow, status, logs, checkUrl, ... }`
- **Webhook handler** that validates incoming callbacks from Vonage and appends to the request's log buffer
- **Channel timeout mirror** — server-side timers that advance the verification workflow when channels timeout (since Vonage doesn't send webhooks for SMS/voice timeouts)
- **Log redaction helpers** — mask phone numbers and codes before storing

### iOS App (`ios/SilentAuthDemo/`)

- **SwiftUI** with adaptive layouts for iPhone (375pt–430pt) and iPad (768pt+)
- **State machine** (`VerificationState` enum) tracking the auth flow: idle → enteringPhone → awaitingSilentAuth → enteringSmsCode → verified (or fallback paths)
- **Networking layer** (`APIClient`, `CellularAuthClient`) wrapping backend REST + Vonage's cellular SDK
- **Vonage ClientLibrary** (`VGCellularRequestClient`) for forced-cellular network requests required by Silent Auth
- **Polling loop** for live log updates from the backend (every 1.5s)
- **Dev Mode console** with grouped log timeline, channel tracker, and redaction
- **Vonage brand styling** (Purple #871FFF primary, Plum headlines, Magenta/Orange stage accents)

---

## Notes

- **Phone numbers in the workflow:** Refer to test numbers (e.g. `+990` playground) during development. For production, use real E.164 numbers.
- **Vonage application credentials:** Store them in `.env` (never committed). Use `private.key` for JWT signing (also never committed).
- **ngrok URL changes:** If ngrok restarts with a new URL, update both your `.env` (`NGROK_URL`) and the Vonage Dashboard callback URL.
- **Rate limiting:** Not implemented in this demo. See `// TODO: add rate limiting` in `server/routes/verification.js`.
- **Production readiness:** This is an educational demo. For production:
  - Add rate limiting, proper database persistence, session management, and error recovery
  - Use environment-based configuration
  - Implement CSRF protection and request signing
  - Monitor and log all requests for compliance

---

## Extending the App

Some ideas for variations:

- **Biometric fallback** — Add Face ID / Touch ID before SMS/voice (would become tertiary)
- **WhatsApp fallback** — Vonage Verify v2 supports WhatsApp Codeless; add it as a channel
- **Real-time call simulator** — Trigger test calls from Dev Mode to see live call logs
- **Persistent auth** — Add local keychain storage to remember verified users
- **Multi-language support** — Localize prompts and Dev Mode labels
- **Analytics dashboard** — Track success rates across channels and time of day
- **Rate limiting UI** — Show remaining verification attempts and cooldown timers

---

## Troubleshooting

**"The connection to the backend failed"**
- Check that `BASE_URL` in `Config.local.xcconfig` is correct and matches your ngrok URL
- Ensure the backend is running (`npm run dev`) and ngrok is forwarding traffic
- Verify firewall rules allow outbound HTTPS

**"Verification failed — invalid code"**
- Check that the code you entered is correct (last 2 digits visible in Dev Mode logs)
- In Dev Mode, look for the actual code in the server logs to debug

**"Silent Auth didn't trigger (went straight to SMS)"**
- On simulator: this is expected — Silent Auth requires a real SIM (cellular data)
- On device: verify you're on cellular, not Wi-Fi (the SDK forces cellular, but some carriers may not support Silent Auth)
- Check Dev Mode logs for Vonage's response to the `check_url` request

**"ngrok URL keeps changing"**
- Use ngrok's paid tier for persistent domains, or
- Automate the dashboard update after each `ngrok http` call

---

## License

MIT

---

## Related

- [Vonage Verify v2 Documentation](https://developer.vonage.com/en/verify/overview)
- [Vonage ClientLibrary for iOS](https://github.com/Vonage/vonage-ios-client-library)
- [Blog Post](https://developer.vonage.com/en/blog/) *(link to be added when published)*
