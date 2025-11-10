# Background/Minimized App Notification Fix

## Issue
Police/Tanod accounts not receiving notifications when app is **minimized** or running in **background** (not fully closed).

## Root Cause
Android doesn't show heads-up notifications by default when app is in background. The notification configuration was missing key properties to force display.

## Solution Applied

### 1. Enhanced Notification Display Settings
Added these properties to **both foreground and background** notification handlers:

```dart
// Force heads-up notification display
visibility: NotificationVisibility.public,
showWhen: true,
ticker: title, // Shows in status bar
autoCancel: false, // Don't dismiss on tap
ongoing: type == 'CRITICAL', // Make critical alerts persistent
styleInformation: BigTextStyleInformation(
  body,
  contentTitle: title,
  summaryText: type == 'CRITICAL' ? 'EMERGENCY' : 'Alert',
),
```

### 2. Always Enable Vibration
Changed from:
```dart
enableVibration: type == 'CRITICAL',
```

To:
```dart
enableVibration: true, // Always vibrate for all alerts
```

### 3. Files Modified
- `lib/notifications/firebase_messaging_service.dart`
  - Updated `_showLocalNotification()` (foreground handler)
  - Updated `_showBackgroundNotification()` (background handler)

## Key Improvements

| Feature | Before | After |
|---------|--------|-------|
| Heads-up display | Not guaranteed | ✅ Forced with `visibility: public` |
| Status bar ticker | None | ✅ Shows notification title |
| Auto-dismiss | Yes | ✅ No (requires manual dismiss) |
| Critical alerts | Dismissible | ✅ Persistent (ongoing) |
| Vibration | Critical only | ✅ All alerts |
| Big text style | No | ✅ Expandable notification |

## Testing Instructions

### Test Scenario 1: App Minimized
1. Open SOSit app on police/tanod device
2. Login successfully
3. **Press Home button** (app goes to background)
4. From another device, trigger panic alert
5. **Expected:** Notification appears as heads-up banner at top of screen

### Test Scenario 2: App in Recent Apps
1. Open SOSit app
2. Press **Recent Apps** button (square/overview)
3. Leave app visible in recent apps list
4. Trigger panic alert from another device
5. **Expected:** Notification banner appears over current screen

### Test Scenario 3: Different App in Foreground
1. Open SOSit app on police device
2. Switch to **another app** (e.g., WhatsApp, Browser)
3. Trigger panic alert
4. **Expected:** Notification interrupts current app with heads-up display

### Test Scenario 4: Critical vs Regular Alerts
1. Minimize police app
2. Trigger **REGULAR** alert
   - **Expected:** Notification with sound, vibration, dismissible
3. Trigger **CRITICAL** alert
   - **Expected:** Persistent notification (ongoing), cannot swipe away, max priority

## Notification Appearance

### Regular Alert
```
⚠️ Emergency Alert
Joshua Suarez needs help!
4J8X+PPW, Davao City, Davao Region
~2.5 km away
```

### Critical Alert
```
🚨 CRITICAL Emergency
Joshua Suarez needs help!
4J8X+PPW, Davao City, Davao Region
~2.5 km away

[EMERGENCY] ← Summary text
```

## Debug Logs to Watch

When notification is triggered while app is minimized:

```
I/flutter: 📩 Foreground message received: msg_xxxxx
I/flutter: 📩 Foreground station alert received
I/flutter: 🔔 Showing local notification: ⚠️ Emergency Alert
```

If these logs appear but notification doesn't show:
- Check Android notification settings for the app
- Ensure "Show notifications" is enabled
- Ensure "Override Do Not Disturb" is enabled for critical alerts

## Android Notification Channels

The app uses 3 notification channels:

### 1. Critical Alerts (`critical_alerts`)
- Importance: MAX
- Priority: MAX
- Sound: ✅
- Vibration: ✅
- LED: Red
- Full screen intent: ✅
- Ongoing: ✅ (cannot dismiss)

### 2. Regular Alerts (`regular_alerts`)
- Importance: HIGH
- Priority: HIGH
- Sound: ✅
- Vibration: ✅
- LED: Orange
- Full screen intent: ❌
- Ongoing: ❌ (can dismiss)

### 3. Cancel Alerts (`cancel_alerts`)
- Importance: DEFAULT
- Priority: DEFAULT
- Sound: ✅
- Vibration: ❌
- LED: Green

## Edge Function Deployment

**Important:** You also need to deploy the updated `send-station-alerts` Edge Function:

1. Go to Supabase Dashboard
2. Edge Functions → `send-station-alerts`
3. Replace code with updated version from `supabase/functions/send-station-alerts/index.ts`
4. Click Deploy

The updated Edge Function sends complete data payload:
- `child_id` (not `child_user_id`)
- `child_email`
- `child_phone`
- `parent_names`
- `battery_level`

## Common Issues & Solutions

### Issue: No notification when app is minimized
**Solution:** Check notification permissions in Android Settings → Apps → SOSit → Notifications

### Issue: Notification appears but no sound/vibration
**Solution:** Check notification channel settings, ensure "Alert" and "Vibrate" are enabled

### Issue: Notification disappears immediately
**Solution:** Don't swipe it away! Regular alerts can be dismissed, critical alerts are persistent

### Issue: No notification at all
**Checklist:**
1. ✅ FCM token registered for police/tanod (check `user_fcm_tokens` table)
2. ✅ Edge Function deployed with V1 API
3. ✅ Secrets configured (FIREBASE_SERVICE_ACCOUNT, FIREBASE_PROJECT_ID)
4. ✅ Police/tanod within 5km of panic alert
5. ✅ App has notification permissions

## Next Steps

1. **Rebuild the app** with updated notification handlers:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Test thoroughly** with app in different states:
   - Foreground (app open)
   - Background (app minimized)
   - Terminated (app completely closed)

3. **Deploy Edge Function** with updated data payload

4. **Monitor logs** in both Flutter console and Supabase Edge Function logs

---

**Last Updated:** November 11, 2025
**Status:** ✅ Fixed - Ready for testing
