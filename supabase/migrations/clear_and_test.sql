-- ============================================================
-- CLEAR OLD NOTIFICATIONS AND TEST NEW ALERT
-- ============================================================

-- STEP 1: Delete old station notifications to clear cache
DELETE FROM station_notifications 
WHERE child_user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- STEP 2: Verify they're deleted
SELECT 'Old notifications deleted' as status, COUNT(*) as remaining_count
FROM station_notifications
WHERE child_user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- ============================================================
-- Now trigger a NEW panic alert in the app as Joshua
-- Then check the results:
-- ============================================================

-- STEP 3: After triggering new alert, check the latest notification
SELECT 
    'Latest Notification After Fix' as check_type,
    sn.notification_data->>'child_name' as child_name,
    sn.notification_data->>'parent_names' as parent_names,
    sn.created_at
FROM station_notifications sn
WHERE sn.child_user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'
ORDER BY sn.created_at DESC
LIMIT 1;

-- Expected result:
-- child_name: Joshua Suarez
-- parent_names: Leyden Dondon ✅ (NOT Joshua Suarez anymore!)
