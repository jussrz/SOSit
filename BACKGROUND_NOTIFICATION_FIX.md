# Background Notification Fix - Summary

## Problem
The app was not receiving alert notifications when running in the background for police/tanod, parent, and user accounts.

## Solution
Implemented comprehensive Firebase Cloud Messaging (FCM) background notification support across the entire app.

## Files Modified

### 1. `lib/notifications/firebase_messaging_service.dart`
**Major Changes:**
- ✅ Enhanced `firebaseMessagingBackgroundHandler` to handle multiple message types
- ✅ Added background handlers for:
  - Parent alerts (`parent_alert`)
  - Station alerts (`station_alert`, `police_alert`, `tanod_alert`)
  - Emergency alerts (`emergency_alert`)
  - Generic notifications
- ✅ Added foreground handlers for station and emergency alerts
- ✅ Implemented background notification display with proper channels
- ✅ Added vibration support for CRITICAL alerts in background
- ✅ Moved helper functions to top-level for background handler access

### 2. `android/app/src/main/AndroidManifest.xml`
**Major Changes:**
- ✅ Added Firebase Messaging Service declaration
- ✅ Added background message handler service
- ✅ Set default notification channel to `critical_alerts`
- ✅ Enabled FCM auto-initialization
- ✅ Added notification click intent filters
- ✅ Added `showWhenLocked` and `turnScreenOn` for critical alerts

### 3. `supabase/functions/send-station-alerts/index.ts`
**Major Changes:**
- ✅ Added `sendFCMNotification()` function for direct FCM push
- ✅ Fetches FCM tokens for police/tanod users
- ✅ Sends FCM notifications for each nearby station
- ✅ Includes distance and child name in notifications
- ✅ Falls back to database storage if FCM fails
- ✅ Returns FCM send count in response

### 4. `supabase/functions/send-parent-alerts/index.ts`
**Major Changes:**
- ✅ Replaced OAuth2 approach with Legacy FCM API (simpler, more reliable)
- ✅ Added `sendFCMNotification()` function
- ✅ Sends FCM push notifications to all parent devices
- ✅ Includes complete alert data in notification payload
- ✅ Database fallback for reliability
- ✅ Proper formatting for CRITICAL, REGULAR, and CANCEL alerts

### 5. `BACKGROUND_NOTIFICATIONS_SETUP.md` (New)
**Documentation:**
- Complete setup guide for background notifications
- Firebase Server Key configuration instructions
- Testing procedures
- Troubleshooting guide
- Database schema documentation

## Required Configuration

### ⚠️ IMPORTANT: Set Firebase Server Key in Supabase

The Edge Functions **require** the Firebase Server Key to send push notifications:

```bash
# Get your Firebase Server Key from:
# Firebase Console → Project Settings → Cloud Messaging → Server key (Legacy)

# Then set it in Supabase:
supabase secrets set FIREBASE_SERVER_KEY=your_server_key_here

# Redeploy Edge Functions:
supabase functions deploy send-parent-alerts
supabase functions deploy send-station-alerts
```

## How It Works Now

### Background Mode (App Closed/Minimized)
1. User triggers emergency alert
2. Supabase Edge Function processes alert
3. **Edge Function sends FCM notification** to recipient devices
4. Android receives FCM message → `firebaseMessagingBackgroundHandler` runs
5. **Local notification created and displayed**
6. User taps notification → app opens with alert details

### Foreground Mode (App Open)
1. FCM message received
2. Message type detected (`parent_alert`, `station_alert`, etc.)
3. Appropriate handler processes message
4. **Notification displayed + modal shown (for parent alerts)**
5. **Vibration activated for CRITICAL alerts**

## Notification Types Supported

### For Parents/Guardians
- `parent_alert` - Child emergency notifications
- Shows modal with child location, time, and actions
- Background: Shows notification that opens modal on tap

### For Police/Tanod
- `station_alert` - Nearby emergency notifications
- Includes distance to emergency
- Background: Shows high-priority notification

### For All Users
- `emergency_alert` - General emergency notifications
- CRITICAL alerts trigger full-screen notifications
- Background: Shows notification with alert details

## Alert Priorities

### CRITICAL Alerts
- ⚠️ Maximum priority
- 📳 Continuous vibration pattern
- 🔴 Red LED indicator
- 📱 Full-screen intent (shows even when locked)
- 🔔 Loud notification sound

### REGULAR Alerts
- High priority
- Standard vibration
- Orange LED indicator
- Normal notification

### CANCEL Alerts
- Default priority
- No vibration
- Info notification

## Testing Checklist

- [ ] **Background Test**: Close app → trigger alert → notification appears
- [ ] **Foreground Test**: Open app → trigger alert → modal + notification appear
- [ ] **Critical Alert Test**: Verify vibration and full-screen notification
- [ ] **Parent Alert Test**: Parent receives child emergency notification
- [ ] **Station Alert Test**: Police/tanod receive nearby emergency
- [ ] **Multi-device Test**: Multiple devices receive same alert

## Battery Optimization Notice

Users should disable battery optimization for the app:
- **Android**: Settings → Apps → SOSit → Battery → Unrestricted
- **iOS**: Notifications work automatically

## What Users Will Experience

### Parents/Guardians
- **App closed**: Notification appears → tap to see child's emergency details
- **App open**: Modal appears immediately with child location and actions

### Police/Tanod
- **App closed**: Notification appears with distance to emergency
- **App open**: Notification appears, can tap to view details

### Regular Users
- **App closed**: Emergency-related notifications appear
- **App open**: Notifications and alerts appear immediately

## Next Steps

1. **Deploy to Supabase**: Set Firebase Server Key and redeploy functions
2. **Test thoroughly**: Verify background notifications on real devices
3. **User communication**: Inform users to allow notifications
4. **Monitor logs**: Check Edge Function logs for delivery success

## Benefits

✅ **Reliable**: FCM ensures notifications even when app is closed
✅ **Fast**: Instant delivery via Firebase infrastructure
✅ **Battery-friendly**: Uses efficient push notification system
✅ **Cross-platform**: Works on Android and iOS
✅ **Prioritized**: CRITICAL alerts get maximum priority
✅ **Actionable**: Users can respond immediately to emergencies
