# Background Notifications Setup

## Overview
The app now properly handles alert notifications when running in the background for all account types:
- **Police/Tanod accounts**: Receive emergency alerts from nearby citizens
- **Parent/Guardian accounts**: Receive alerts from their children
- **User accounts**: Receive emergency-related notifications

## Changes Made

### 1. Firebase Messaging Service (`lib/notifications/firebase_messaging_service.dart`)
- **Background handler** now processes multiple message types:
  - `parent_alert` - Alerts for parent/guardian accounts
  - `station_alert`, `police_alert`, `tanod_alert` - Alerts for police/tanod
  - `emergency_alert` - General emergency notifications
  - Generic notifications

- **Foreground handlers** added for all alert types with:
  - Critical alert vibration patterns
  - Local notifications with appropriate channels
  - Proper notification priorities

- **Helper functions** moved to top-level for background handler access

### 2. Android Manifest (`android/app/src/main/AndroidManifest.xml`)
Added Firebase Cloud Messaging configuration:
- Firebase Messaging Service declaration
- Background message handler service
- Default notification channel (critical_alerts)
- Auto-initialization enabled
- Notification click intent filters
- Screen wake and show when locked for critical alerts

### 3. Edge Functions Updated

#### `send-station-alerts` (Supabase Edge Function)
- Now sends **FCM push notifications** directly to police/tanod devices
- Includes distance information and alert priority
- Falls back to database storage if FCM fails
- Properly formats notifications for background delivery

#### `send-parent-alerts` (Supabase Edge Function)
- Sends **FCM push notifications** to parent devices
- Includes complete alert data and child information
- Database fallback for reliability
- Supports CRITICAL, REGULAR, and CANCEL alert types

## Required Configuration

### Firebase Server Key (Required for Background Notifications)

You need to set the Firebase Server Key in your Supabase project for the Edge Functions to send notifications.

1. **Get Firebase Server Key:**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select your project
   - Go to Project Settings (gear icon) → Cloud Messaging
   - Copy the **Server key** (Legacy)

2. **Set in Supabase:**
   ```bash
   # Install Supabase CLI if not already installed
   npm install -g supabase

   # Login to Supabase
   supabase login

   # Link to your project
   supabase link --project-ref ctsnpupbpcznwbbtqdln

   # Set the Firebase Server Key
   supabase secrets set FIREBASE_SERVER_KEY=your_firebase_server_key_here
   ```

3. **Redeploy Edge Functions:**
   ```bash
   # Deploy parent alerts function
   supabase functions deploy send-parent-alerts

   # Deploy station alerts function
   supabase functions deploy send-station-alerts
   ```

## How It Works

### Background Flow (App Not Open)
1. Emergency alert triggered by user
2. Supabase Edge Function processes the alert
3. Edge Function sends FCM notification to recipient devices
4. Android/iOS receives FCM message in background
5. `firebaseMessagingBackgroundHandler` processes the message
6. Local notification created and displayed
7. User taps notification → app opens with alert details

### Foreground Flow (App Open)
1. Emergency alert triggered
2. FCM message received by foreground handler
3. App processes message by type
4. For parent alerts: Modal dialog shown + notification
5. For station alerts: Local notification shown
6. Vibration triggered for CRITICAL alerts

### Notification Channels (Android)
- **critical_alerts**: Maximum priority, full-screen intent, red LED
- **regular_alerts**: High priority, standard notification
- **cancel_alerts**: Default priority for cancellation notices

## Testing

### Test Background Notifications

1. **Close the app completely** (swipe away from recent apps)
2. Trigger an emergency alert from another device/account
3. Notification should appear even when app is closed
4. Tap notification to open app with alert details

### Test Foreground Notifications

1. **Keep app open** in foreground
2. Trigger an emergency alert
3. Notification + in-app modal should appear (for parent alerts)
4. Vibration should activate for CRITICAL alerts

### Test Critical Alerts

1. Trigger a **CRITICAL** alert (double-press panic button)
2. Verify:
   - Strong vibration pattern
   - High-priority notification
   - Full-screen notification on locked devices
   - Red LED indicator

## Troubleshooting

### Notifications Not Appearing in Background

1. **Check Firebase Server Key:**
   ```bash
   supabase secrets list
   ```
   Verify `FIREBASE_SERVER_KEY` is set

2. **Check FCM Token Registration:**
   - Open app while logged in
   - Check debug logs for "FCM token registered"
   - Verify tokens are stored in `user_fcm_tokens` table

3. **Check Android Notification Permissions:**
   - Settings → Apps → SOSit → Notifications → Enabled
   - Check if "Critical Alerts" channel is enabled

4. **Check Edge Function Logs:**
   ```bash
   supabase functions logs send-parent-alerts
   supabase functions logs send-station-alerts
   ```
   Look for "FCM notification sent successfully"

### Notifications Work in Foreground But Not Background

- This indicates Firebase Server Key is not set correctly
- Background messages require server-side FCM API authentication
- Verify the key in Supabase secrets matches your Firebase project

### CRITICAL Alerts Not Vibrating

- Check Android permissions: Settings → Apps → SOSit → Permissions → Vibrate
- Verify device has vibration hardware
- Test with `hasVibrator()` returning true

## Battery Optimization

For reliable background notifications, users should disable battery optimization:

**Android:**
1. Settings → Apps → SOSit
2. Battery → Unrestricted (or "Don't optimize")

**iOS:**
- Background notifications work automatically
- Ensure "Allow Notifications" is enabled

## Database Tables

### `user_fcm_tokens`
Stores FCM tokens for push notifications:
- `user_id`: User receiving notifications
- `fcm_token`: Firebase Cloud Messaging token
- `device_id`: Unique device identifier
- `platform`: 'android' or 'ios'

### `parent_notifications`
Stores parent alert history:
- `parent_user_id`: Parent receiving alert
- `child_user_id`: Child who triggered alert
- `panic_alert_id`: Reference to panic alert
- `notification_data`: Complete alert payload

### `station_notifications`
Stores police/tanod alert history:
- `station_user_id`: Police/tanod receiving alert
- `child_user_id`: Citizen who triggered alert
- `panic_alert_id`: Reference to panic alert
- `distance_km`: Distance to emergency

## Security Notes

- FCM tokens are stored securely in Supabase
- Server key is kept in environment variables (never in code)
- Notifications are only sent to authorized recipients
- Alert data includes user verification

## Future Improvements

- [ ] Add notification action buttons (Call, Directions, Dismiss)
- [ ] Implement notification grouping for multiple alerts
- [ ] Add notification sound customization
- [ ] Support for wearable device notifications
- [ ] Analytics for notification delivery rates
