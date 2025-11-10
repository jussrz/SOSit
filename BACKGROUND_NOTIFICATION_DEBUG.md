# Background Notification Debugging Guide for Police/Tanod

## Issue: No notifications on police/tanod accounts when app is in background

### Checklist to Debug

#### 1. Verify Edge Function is Deployed ✅
- Go to Supabase Dashboard → Edge Functions
- Confirm `send-station-alerts` shows "Deployed" status
- Check deployment date is recent (after your latest update)

#### 2. Verify FCM Tokens are Registered for Police/Tanod
**Critical Step:** Police/Tanod users MUST have FCM tokens in the database

**How to Check:**
1. Login to Supabase Dashboard
2. Go to Table Editor → `user_fcm_tokens`
3. Look for rows where `user_id` matches police/tanod account IDs
4. Verify `fcm_token` column has a long token string (starts with letters/numbers)

**If NO tokens found:**
- Police/Tanod users need to **login to the app** on their device
- The app will automatically register FCM token on login
- Background notifications WON'T work without FCM tokens!

#### 3. Check Edge Function Logs
**How to View Logs:**
1. Supabase Dashboard → Edge Functions
2. Click `send-station-alerts`
3. Go to "Logs" tab
4. Trigger a panic alert from test account
5. Look for these log messages:

**Expected Success Logs:**
```
🔑 Getting Firebase access token...
✅ Access token obtained
✅ FCM V1 notification sent successfully
```

**Error Logs to Watch For:**
```
❌ FIREBASE_SERVICE_ACCOUNT not configured
❌ FCM V1 send failed: {...}
⚠️ No nearby stations within 5km
```

#### 4. Verify Panic Alert Triggers Edge Function
**Check emergency_service.dart execution:**
1. Enable debug mode in Flutter app
2. Trigger panic alert
3. Look for console logs:
```
🚀 Invoking Edge Function: send-station-alerts
📬 Edge Function response: {...}
```

**If you DON'T see these logs:**
- Edge Function is not being called
- Check `emergency_service.dart` line 769-778

#### 5. Verify Police/Tanod Location is Set
**Edge Function only notifies police/tanod within 5km radius**

Check in Supabase:
1. Table Editor → `user` table
2. Find police/tanod accounts
3. Verify `current_latitude` and `current_longitude` are NOT NULL
4. Verify they are within 5km of test panic alert location

**Calculate distance:**
- Use Google Maps to check if police/tanod location is within 5km of panic alert
- If > 5km, Edge Function will skip sending notification

#### 6. Test Background Handler
**Verify Flutter background handler is working:**

Add this debug code to test:
```dart
// In main.dart, after Firebase.initializeApp()
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

// Send test FCM message from Firebase Console
// Go to Firebase Console → Cloud Messaging → Send test message
// Use police/tanod FCM token
```

Expected console output:
```
🔔 Background message received: msg_xxxxx
📩 Background station alert: {alert_type: REGULAR, child_name: ...}
✅ Background notification shown: ⚠️ Emergency Alert
```

#### 7. Android Notification Channels
**Verify channels are created:**

Check in `firebase_messaging_service.dart` initialization:
```dart
// Critical alerts channel MUST exist
const AndroidNotificationChannel criticalChannel = AndroidNotificationChannel(
  'critical_alerts',
  'Critical Alerts',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const AndroidNotificationChannel regularChannel = AndroidNotificationChannel(
  'regular_alerts',
  'Regular Alerts', 
  importance: Importance.high,
  playSound: true,
);
```

#### 8. Test Data Payload Format
**Edge Function sends this data:**
```json
{
  "type": "station_alert",
  "alert_type": "REGULAR",
  "child_name": "Test User",
  "child_user_id": "uuid-xxx",
  "address": "Location...",
  "latitude": "14.5995",
  "longitude": "120.9842",
  "distance_km": "2.5",
  "timestamp": "2025-11-11T...",
  "panic_alert_id": "uuid-xxx"
}
```

Background handler checks:
```dart
final messageType = message.data['type'] ?? '';
if (messageType == 'station_alert' || 
    messageType == 'police_alert' || 
    messageType == 'tanod_alert') {
  await _handleStationAlertBackground(message, localNotifications);
}
```

---

## Quick Fix Steps

### Step 1: Ensure Police/Tanod Have FCM Tokens
**MOST COMMON ISSUE:**
1. Login to police/tanod account on a physical device
2. Wait 5 seconds for FCM token registration
3. Check debug console for: `✅ FCM token saved successfully`
4. Verify in Supabase `user_fcm_tokens` table

### Step 2: Test with Close Proximity
1. Set police/tanod location to SAME coordinates as test panic
2. Trigger alert
3. Should see notification even in background

### Step 3: Check Edge Function Logs Immediately
1. Trigger panic alert
2. Open Supabase Edge Function logs within 30 seconds
3. Look for errors or success messages

### Step 4: Verify Secrets Are Set
```bash
# In Supabase Dashboard → Project Settings → Edge Functions → Secrets
FIREBASE_SERVICE_ACCOUNT = {full JSON content}
FIREBASE_PROJECT_ID = sosit-64bfe
```

---

## Expected Flow (When Working)

1. User triggers panic alert
2. `emergency_service.dart` calls Edge Function `send-station-alerts`
3. Edge Function:
   - Gets Firebase OAuth2 token
   - Queries police/tanod within 5km
   - Fetches their FCM tokens from `user_fcm_tokens`
   - Sends FCM V1 notifications
   - Inserts rows into `station_notifications`
4. FCM delivers notification to police/tanod devices
5. `firebaseMessagingBackgroundHandler` receives message
6. `_handleStationAlertBackground` processes it
7. `_showBackgroundNotification` displays notification

---

## Still Not Working?

### Enable Verbose Logging

Add to `send-station-alerts/index.ts`:
```typescript
// After getting FCM tokens
console.log('🔍 FCM Tokens found:', fcmTokens.length)
console.log('📱 Tokens:', fcmTokens.map(t => t.fcm_token.substring(0, 20)))
```

### Test FCM Token Manually

Use this cURL command to test FCM token directly:
```bash
# Get access token first (from Edge Function logs)
curl -X POST https://fcm.googleapis.com/v1/projects/sosit-64bfe/messages:send \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "token": "POLICE_FCM_TOKEN_HERE",
      "notification": {
        "title": "Test Alert",
        "body": "Testing background notification"
      },
      "data": {
        "type": "station_alert",
        "alert_type": "REGULAR"
      }
    }
  }'
```

If this works, problem is in Edge Function logic.
If this fails, problem is FCM token or Firebase setup.
