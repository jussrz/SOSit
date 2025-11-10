# Emergency Alert Fix - User Details and Notifications

## Problem Summary

The emergency alert system was showing incorrect user details:
- **Name** showing as "Unknown User" instead of the actual user who pressed the panic button
- **Parent/Guardian** showing incorrect data
- Police/Tanod not receiving alert notifications

## Root Causes

1. **Missing child_name and parent_names in notification_data**: The `_ensureStationNotificationsExist()` function in `emergency_service.dart` was not fetching and including the child's name and parent/guardian names when creating station notifications.

2. **Missing database functions**: The app was calling database functions that didn't exist:
   - `create_parent_notifications_for_alert_v7`
   - `create_station_notifications_for_alert`

3. **Incorrect user_id usage**: The system was correctly using the authenticated user's ID, but the notification data wasn't being populated with the user's actual details.

## Solution

### 1. Updated `emergency_service.dart`

Modified the `_ensureStationNotificationsExist()` function to:
- Fetch the child user's full name, email, and phone from the database
- Query the `emergency_contacts` table to find parent/guardian information
- Include all this data in the `notification_data` JSONB field when creating station notifications

**File**: `lib/services/emergency_service.dart`

**Key changes**:
- Added child user lookup using `user_id` from panic alert
- Added parent lookup using `emergency_contacts` table (matching by `added_by` email)
- Populated `notification_data` with:
  - `child_name`: Full name of the user who pressed the button
  - `child_phone`: User's phone number
  - `child_email`: User's email
  - `parent_names`: Comma-separated list of parent/guardian names
  - `battery_level`: Device battery level

### 2. Created Database Functions

#### `create_parent_notifications_for_alert_v7`

**File**: `supabase/migrations/create_parent_notifications_for_alert_v7.sql`

This function:
- Takes a panic alert ID as input
- Finds all parents/guardians of the child who triggered the alert
- Creates notification records in `parent_notifications` table
- Returns success status and count of parents notified

**Parent lookup logic**:
```sql
-- Parents are found through emergency_contacts where the child's email is in added_by
SELECT DISTINCT ec.user_id as parent_user_id
FROM emergency_contacts ec
WHERE ec.added_by = v_child_user.email
  AND ec.user_id IS NOT NULL
```

#### `create_station_notifications_for_alert`

**File**: `supabase/migrations/create_station_notifications_for_alert.sql`

This function:
- Takes a panic alert ID as input
- Finds all police and tanod users within 5km of the alert location
- Calculates distance using Haversine formula
- Fetches child and parent information
- Creates notification records in `station_notifications` table
- Returns counts of police and tanod notified

**Distance calculation**:
```sql
-- Haversine formula to calculate distance in kilometers
v_distance_km := (
    6371 * acos(
        cos(radians(latitude1)) * cos(radians(latitude2)) *
        cos(radians(longitude2) - radians(longitude1)) +
        sin(radians(latitude1)) * sin(radians(latitude2))
    )
);
```

## Deployment Instructions

### Step 1: Deploy Database Functions

You need to run the SQL migration files in your Supabase database:

**Option A: Using Supabase Dashboard**
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy and paste the contents of `create_parent_notifications_for_alert_v7.sql`
4. Click **Run**
5. Repeat for `create_station_notifications_for_alert.sql`

**Option B: Using Supabase CLI**
```bash
# Navigate to your project directory
cd c:\Users\USER\Desktop\SOSit

# Push migrations to Supabase
supabase db push
```

### Step 2: Rebuild Flutter App

The Dart code changes are already in place, so you just need to rebuild:

```bash
# Clean the build
flutter clean

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### Step 3: Test the Fix

1. **Test as a regular user (Joshua Suarez - f4ae5fd6-7589-4daa-85a8-2de513674354)**:
   - Log in to the app
   - Press the panic button (REGULAR or CRITICAL)
   - Check that your location is being captured

2. **Test as police/tanod**:
   - Log in with a police or tanod account
   - Ensure location permissions are enabled
   - Wait for the emergency alert notification
   - Open the notification modal
   - Verify:
     - **Name** shows "Joshua Suarez" (not "Unknown User")
     - **Parent/Guardian** shows "Leyden Suarez" (not "Joshua Suarez")
     - Location, time, and distance are correct

3. **Test as parent (Leyden Suarez - 6e379ec8-11ab-44f9-a7ea-c4d1f0194fea)**:
   - Log in to the parent account
   - Wait for notification when Joshua triggers an alert
   - Verify the notification shows correct child information

## Database Schema Relationships

The fix relies on these table relationships:

```
user (Joshua)
  └─> panic_alerts (user_id = Joshua's UUID)
       └─> Creates notifications via functions

emergency_contacts
  ├─> user_id = Leyden's UUID (parent)
  └─> added_by = Joshua's email (child)

station_notifications
  ├─> child_user_id = Joshua's UUID
  ├─> station_user_id = Police/Tanod UUID
  └─> notification_data (JSONB containing all details)
```

## Troubleshooting

### Issue: Still showing "Unknown User"

**Possible causes**:
1. Database functions not deployed - Run the SQL migrations
2. User data not in database - Verify user exists with `SELECT * FROM "user" WHERE id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'`
3. Old notifications in cache - Clear app data and test with a new alert

### Issue: Police/Tanod not receiving notifications

**Possible causes**:
1. Location permissions not granted - Check device settings
2. Police/Tanod location not updated - Ensure `current_latitude` and `current_longitude` are set in the `user` table
3. Distance > 5km - Verify the distance between alert location and station location
4. RLS policies blocking - Check Supabase RLS policies on `station_notifications` table

**Check police/tanod location**:
```sql
SELECT id, first_name, role, current_latitude, current_longitude 
FROM "user" 
WHERE role IN ('police', 'tanod');
```

### Issue: Parent names showing "No parents listed"

**Possible causes**:
1. Emergency contact not properly linked - Check `emergency_contacts` table
2. Wrong `added_by` value - Should be Joshua's email

**Verify emergency contacts**:
```sql
SELECT * FROM emergency_contacts 
WHERE added_by = 'joshua@example.com'; -- Replace with actual email
```

## Testing Checklist

- [ ] Database functions deployed successfully
- [ ] App rebuilt with updated code
- [ ] User can trigger emergency alert
- [ ] Alert shows correct user name (not "Unknown User")
- [ ] Alert shows correct parent/guardian name
- [ ] Police receives notification (if within 5km)
- [ ] Tanod receives notification (if within 5km)
- [ ] Parent receives notification
- [ ] Location data is accurate
- [ ] Distance calculation is correct

## Additional Notes

- The emergency_contacts table uses `added_by` (email) to link children to parents
- The `user_id` in emergency_contacts points to the PARENT's UUID
- The `added_by` field contains the CHILD's email
- Station notifications are only sent to police/tanod within 5km radius
- The CRITICAL alert type triggers immediate notifications
- REGULAR alerts have a 1.5 second delay to allow for potential upgrade to CRITICAL
