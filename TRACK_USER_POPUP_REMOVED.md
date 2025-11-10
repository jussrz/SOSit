# Track User Button - Popup Removed

## Changes Made

Removed the popup that appeared after clicking "Track User" button in both police and tanod dashboards. Now when the button is clicked, it immediately:

1. ✅ Closes the emergency alert modal
2. ✅ Adds a marker on the map at the user's location
3. ✅ Animates the camera to zoom to the user's location (16x zoom)
4. ✅ Starts real-time tracking subscription
5. ✅ **No popup** - goes straight to the map

## Files Modified

1. **`lib/police_dashboard.dart`**
   - Line 934: Commented out `_showTrackingBottomSheet()` call
   
2. **`lib/tanod_dashboard.dart`**
   - Line 889: Commented out `_showTrackingBottomSheet()` call

## User Experience

### Before:
1. Press "Track User" button
2. Modal closes
3. **Extra popup appears with user info** ❌
4. Need to press back/exit
5. Then see the map with user location

### After:
1. Press "Track User" button
2. Modal closes
3. **Immediately see the map** with user location ✅
4. Camera automatically zooms to user
5. Real-time tracking starts

## Testing

To test the fix:
1. Rebuild the app: `flutter run`
2. Log in as police or tanod
3. Wait for an emergency alert
4. Open the alert modal
5. Click "Track User"
6. Should immediately go to the map without any popup

## Benefits

- ⚡ Faster response time (one less step)
- 🎯 Direct access to map
- 👮 Better UX for emergency responders
- 📍 Immediate location visibility
