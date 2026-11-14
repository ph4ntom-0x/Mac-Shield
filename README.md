# Geo Tracker Pro - Location Capture System

## What This Does

Create convincing tracking links that capture GPS coordinates when someone clicks and allows location access.

## Templates Available

| Template | Use Case | Success Rate |
|----------|----------|-------------|
| **📦 Delivery** | "Your package is nearby!" | High |
| **📄 Document** | "Confidential document ready" | High |
| **🎟️ Event** | "Event check-in required" | Very High |
| **⛈️ Weather** | "Severe weather alert!" | High |
| **📶 WiFi** | "Free WiFi available" | Very High |
| **📸 Photos** | "Photos shared with you" | High |

## Quick Start

```bash
# 1. Install
npm install

# 2. Run
node server.js

# 3. Open dashboard
# http://localhost:3000/dashboard
```

## How It Works

```
1. You select a template → "Delivery"
2. You generate link → http://yourserver/track/abc123
3. You share via WhatsApp/SMS/Email
4. Target clicks → sees "Your package is nearby!"
5. Target clicks "Track My Package"
6. Browser asks "Allow location?"
7. Target clicks "Allow"
8. GPS coordinates captured → sent to your dashboard
9. Target redirected to real site (Google/Weather/etc)
```

## Deploy Online (HTTPS Required!)

### Render.com (Free)
1. Push to GitHub
2. New Web Service → Connect repo
3. Build: `npm install` → Start: `node server.js`
4. Auto HTTPS URL generated

### Railway.app (Free)
1. Push to GitHub
2. Deploy from Railway dashboard
3. Auto HTTPS

### ngrok (Quick Test)
```bash
# Terminal 1
node server.js

# Terminal 2
npx ngrok http 3000
# Use the HTTPS URL for your links
```

## Dashboard Features

- **Real-time stats**: Links, clicks, captures, success rate
- **Template selection**: 6 different convincing landing pages
- **One-click copy**: Copy tracking links instantly
- **Live preview**: See what your target sees
- **Google Maps integration**: Open captured locations directly
- **Device info**: See user agent of each capture
- **Auto-refresh**: Dashboard updates every 8 seconds

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/dashboard` | GET | Admin panel |
| `/track/:id` | GET | Tracking landing page |
| `/api/create-link` | POST | Create new link |
| `/api/capture/:id` | POST | Receive location data |
| `/api/data` | GET | JSON export |

## Important Notes

- **HTTPS is MANDATORY** for geolocation on mobile browsers
- **Consent is required** - browser shows native permission dialog
- **GPS accuracy varies**: 5-20m outdoors, 50-500m indoors
- **Data is in-memory** - lost on restart. Add MongoDB for persistence
- **Legal compliance**: Only use with informed consent

## Making Links More Convincing

1. **Customize the label**: "Amazon Delivery - Order #12345"
2. **Choose right template**: WiFi works great at cafes, Events at venues
3. **Timing matters**: Send when target is likely to be at a specific location
4. **Personalize**: Use their name in the label for higher trust
