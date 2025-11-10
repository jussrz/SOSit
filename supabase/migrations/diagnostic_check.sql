-- ============================================================
-- DIAGNOSTIC SCRIPT - Check Emergency Alert System Status
-- Run this in Supabase SQL Editor to diagnose issues
-- ============================================================

-- 1. Check if database functions exist
-- ============================================================
SELECT 
    'Function Check' as check_type,
    proname as function_name,
    pg_get_function_result(oid) as return_type
FROM pg_proc
WHERE proname IN ('create_parent_notifications_for_alert_v7', 'create_station_notifications_for_alert', 'update_user_location')
ORDER BY proname;

-- 2. Check police/tanod users and their locations
-- ============================================================
SELECT 
    'Police/Tanod Location Check' as check_type,
    id,
    first_name || ' ' || last_name as full_name,
    email,
    role,
    current_latitude,
    current_longitude,
    CASE 
        WHEN current_latitude IS NULL OR current_longitude IS NULL THEN '❌ NO LOCATION'
        ELSE '✅ Has Location'
    END as location_status,
    location_updated_at
FROM "user"
WHERE role IN ('police', 'tanod')
ORDER BY role, first_name;

-- 3. Check recent panic alerts
-- ============================================================
SELECT 
    'Recent Panic Alerts' as check_type,
    pa.id,
    pa.user_id as child_user_id,
    u.first_name || ' ' || u.last_name as child_name,
    pa.alert_level,
    pa.latitude,
    pa.longitude,
    pa.location,
    pa.timestamp,
    pa.acknowledged
FROM panic_alerts pa
LEFT JOIN "user" u ON pa.user_id = u.id
ORDER BY pa.timestamp DESC
LIMIT 5;

-- 4. Check if station_notifications were created for recent alerts
-- ============================================================
SELECT 
    'Station Notifications' as check_type,
    sn.id,
    sn.panic_alert_id,
    sn.station_user_id,
    su.first_name || ' ' || su.last_name as station_user_name,
    su.role as station_role,
    sn.child_user_id,
    cu.first_name || ' ' || cu.last_name as child_name,
    sn.alert_type,
    sn.distance_km,
    sn.notification_data->>'child_name' as notif_child_name,
    sn.notification_data->>'parent_names' as notif_parent_names,
    sn.read,
    sn.created_at
FROM station_notifications sn
LEFT JOIN "user" su ON sn.station_user_id = su.id
LEFT JOIN "user" cu ON sn.child_user_id = cu.id
ORDER BY sn.created_at DESC
LIMIT 10;

-- 5. Check parent_notifications
-- ============================================================
SELECT 
    'Parent Notifications' as check_type,
    pn.id,
    pn.panic_alert_id,
    pn.parent_user_id,
    pu.first_name || ' ' || pu.last_name as parent_name,
    pn.child_user_id,
    cu.first_name || ' ' || cu.last_name as child_name,
    pn.alert_type,
    pn.notification_data->>'child_name' as notif_child_name,
    pn.read,
    pn.created_at
FROM parent_notifications pn
LEFT JOIN "user" pu ON pn.parent_user_id = pu.id
LEFT JOIN "user" cu ON pn.child_user_id = cu.id
ORDER BY pn.created_at DESC
LIMIT 10;

-- 6. Check emergency_contacts relationships
-- ============================================================
SELECT 
    'Emergency Contacts' as check_type,
    ec.id,
    ec.user_id as parent_user_id,
    pu.first_name || ' ' || pu.last_name as parent_name,
    pu.email as parent_email,
    ec.emergency_contact_name as child_name,
    ec.added_by as child_email,
    cu.id as child_user_id,
    cu.first_name || ' ' || cu.last_name as actual_child_name
FROM emergency_contacts ec
LEFT JOIN "user" pu ON ec.user_id = pu.id
LEFT JOIN "user" cu ON ec.added_by = cu.email
ORDER BY ec.created_at DESC
LIMIT 10;

-- 7. Summary Statistics
-- ============================================================
SELECT 
    'Summary' as info_type,
    (SELECT COUNT(*) FROM "user" WHERE role = 'police') as total_police,
    (SELECT COUNT(*) FROM "user" WHERE role = 'police' AND current_latitude IS NOT NULL) as police_with_location,
    (SELECT COUNT(*) FROM "user" WHERE role = 'tanod') as total_tanod,
    (SELECT COUNT(*) FROM "user" WHERE role = 'tanod' AND current_latitude IS NOT NULL) as tanod_with_location,
    (SELECT COUNT(*) FROM panic_alerts WHERE timestamp > NOW() - INTERVAL '1 hour') as alerts_last_hour,
    (SELECT COUNT(*) FROM station_notifications WHERE created_at > NOW() - INTERVAL '1 hour') as station_notifs_last_hour,
    (SELECT COUNT(*) FROM parent_notifications WHERE created_at > NOW() - INTERVAL '1 hour') as parent_notifs_last_hour;
