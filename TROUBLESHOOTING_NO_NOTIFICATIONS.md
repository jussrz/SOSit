# TROUBLESHOOTING GUIDE - Police/Tanod Not Receiving Notifications

## The Issue
Police/Tanod accounts are not receiving emergency alert notifications.

## Most Common Cause
**Police/Tanod users don't have their location set in the database!**

The system only sends notifications to police/tanod within 5km of the alert. If they don't have a location, they can't receive notifications.

## Step-by-Step Fix

### STEP 1: Run the Complete Fix Script
Copy and run `complete_fix.sql` in Supabase SQL Editor. This creates all necessary functions with detailed logging.

### STEP 2: Run Diagnostic Check
Copy and run `diagnostic_check.sql` in Supabase SQL Editor to check:
- ✅ If functions exist
- ✅ If police/tanod users have locations
- ✅ Recent panic alerts
- ✅ If notifications were created

### STEP 3: Update Police/Tanod Locations

If the diagnostic shows "❌ NO LOCATION", you need to set their locations.

**Option A: Update in Database Directly**
```sql
-- Replace with actual coordinates near the test location
UPDATE "user" 
SET 
    current_latitude = 7.0731,  -- Example: Davao City latitude
    current_longitude = 125.6128, -- Example: Davao City longitude
    location_updated_at = NOW()
WHERE role = 'police' OR role = 'tanod';
```

**Option B: Use the App**
1. Log in as police/tanod user
2. Grant location permissions
3. Wait for the app to update location (happens every 5 minutes)
4. Or kill and restart the app to force immediate location update

### STEP 4: Test the Alert System

1. **Trigger a test alert** as Joshua Suarez (f4ae5fd6-7589-4daa-85a8-2de513674354)
2. **Check the logs** in Supabase:
```sql
-- Check if panic alert was created
SELECT * FROM panic_alerts ORDER BY timestamp DESC LIMIT 1;

-- Check if station notifications were created
SELECT 
    sn.*,
    u.first_name || ' ' || u.last_name as station_user,
    u.role
FROM station_notifications sn
LEFT JOIN "user" u ON sn.station_user_id = u.id
ORDER BY sn.created_at DESC
LIMIT 5;
```

3. **Check police/tanod dashboard** - Should see the alert appear

### STEP 5: Check Distance Calculation

If notifications still aren't appearing, check the distance:

```sql
-- Calculate distance between alert and police/tanod
-- Replace with actual panic alert latitude/longitude
WITH alert_location AS (
    SELECT 
        7.0731 as alert_lat,  -- Replace with actual alert latitude
        125.6128 as alert_lon  -- Replace with actual alert longitude
)
SELECT 
    u.id,
    u.first_name || ' ' || u.last_name as name,
    u.role,
    u.current_latitude,
    u.current_longitude,
    (6371 * acos(
        cos(radians(a.alert_lat)) * 
        cos(radians(u.current_latitude)) * 
        cos(radians(u.current_longitude) - radians(a.alert_lon)) + 
        sin(radians(a.alert_lat)) * 
        sin(radians(u.current_latitude))
    )) as distance_km,
    CASE 
        WHEN (6371 * acos(
            cos(radians(a.alert_lat)) * 
            cos(radians(u.current_latitude)) * 
            cos(radians(u.current_longitude) - radians(a.alert_lon)) + 
            sin(radians(a.alert_lat)) * 
            sin(radians(u.current_latitude))
        )) <= 5.0 THEN '✅ Within 5km - Should receive notification'
        ELSE '❌ Too far - Will NOT receive notification'
    END as notification_status
FROM "user" u, alert_location a
WHERE (u.role = 'police' OR u.role = 'tanod')
  AND u.current_latitude IS NOT NULL
  AND u.current_longitude IS NOT NULL;
```

## Common Issues & Solutions

### Issue 1: "No notifications created"
**Cause**: Police/Tanod don't have locations
**Solution**: Update their current_latitude and current_longitude in database

### Issue 2: "Notifications created but not showing in app"
**Cause**: Realtime subscription not working
**Solution**: 
- Restart the app
- Check Supabase Realtime is enabled for `station_notifications` table
- Check app console logs for subscription errors

### Issue 3: "Distance shows > 5km"
**Cause**: Police/Tanod are too far from alert location
**Solution**: 
- Update police/tanod location to be within 5km of test alert
- Or trigger alert from location within 5km of police/tanod

### Issue 4: "Functions return error"
**Cause**: Functions not deployed or wrong parameter types
**Solution**: Run `complete_fix.sql` again

## Quick Test Script

Run this after deploying the fix to manually test:

```sql
-- 1. Create a test panic alert (run as the user who will trigger alert)
INSERT INTO panic_alerts (user_id, alert_level, timestamp, latitude, longitude, location, battery_level)
VALUES (
    'f4ae5fd6-7589-4daa-85a8-2de513674354',  -- Joshua's UUID
    'REGULAR',
    NOW(),
    7.0731,   -- Davao City latitude
    125.6128, -- Davao City longitude
    '4J8X+PPW, Davao City, Davao Region',
    100
)
RETURNING id;

-- 2. Note the returned id, then call the function manually
SELECT create_station_notifications_for_alert(YOUR_PANIC_ALERT_ID_HERE);

-- 3. Check if notifications were created
SELECT * FROM station_notifications WHERE panic_alert_id = YOUR_PANIC_ALERT_ID_HERE;
```

## Files You Need

1. **complete_fix.sql** - Main deployment script with all functions
2. **diagnostic_check.sql** - Check system status
3. **Emergency service updated** - Already done in Flutter code

## Expected Behavior

When a panic alert is triggered:
1. ✅ Panic alert inserted into `panic_alerts` table
2. ✅ `create_parent_notifications_for_alert_v7()` called → creates `parent_notifications`
3. ✅ `create_station_notifications_for_alert()` called → creates `station_notifications` for police/tanod within 5km
4. ✅ Realtime subscription fires in police/tanod apps
5. ✅ Notification appears on police/tanod dashboard
6. ✅ Shows correct child name and parent name

## Need More Help?

Check the console logs in:
- Supabase SQL Editor (for RAISE NOTICE logs)
- Flutter app debug console (for realtime subscription logs)
- Look for 🔔, 📍, ✅, ❌ emoji markers in logs
