-- ============================================================
-- DEBUG: Check Joshua's Emergency Contacts
-- Run this to see what's actually in the database
-- ============================================================

-- 1. Joshua's user info
SELECT 
    '1. Joshua User Info' as step,
    id,
    first_name,
    last_name,
    email
FROM "user"
WHERE id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- 2. ALL emergency contacts in the table (to understand the structure)
SELECT 
    '2. All Emergency Contacts' as step,
    ec.id,
    ec.user_id,
    u.first_name || ' ' || u.last_name as user_name,
    ec.emergency_contact_name,
    ec.emergency_contact_relationship,
    ec.added_by,
    ec.group_member_id
FROM emergency_contacts ec
LEFT JOIN "user" u ON ec.user_id = u.id
ORDER BY ec.created_at DESC
LIMIT 10;

-- 3. Emergency contacts WHERE user_id = Joshua's UUID (what our code queries)
SELECT 
    '3. Contacts WHERE user_id = Joshua UUID' as step,
    ec.id,
    ec.user_id,
    ec.emergency_contact_name,
    ec.emergency_contact_relationship,
    ec.emergency_contact_phone
FROM emergency_contacts ec
WHERE ec.user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- 4. Emergency contacts WHERE added_by = Joshua's email (old wrong logic)
SELECT 
    '4. Contacts WHERE added_by = Joshua email' as step,
    ec.id,
    ec.user_id,
    u.first_name || ' ' || u.last_name as user_name,
    ec.emergency_contact_name,
    ec.added_by
FROM emergency_contacts ec
LEFT JOIN "user" u ON ec.user_id = u.id
WHERE ec.added_by = (SELECT email FROM "user" WHERE id = 'f4ae5fd6-7589-4daa-85a8-2de513674354');

-- 5. Check the most recent station notification
SELECT 
    '5. Recent Station Notification Data' as step,
    sn.id,
    sn.notification_data->>'child_name' as child_name,
    sn.notification_data->>'parent_names' as parent_names,
    sn.created_at
FROM station_notifications sn
WHERE sn.child_user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'
ORDER BY sn.created_at DESC
LIMIT 1;

-- 6. Test what the function SHOULD return
SELECT 
    '6. Expected Parent Names' as step,
    string_agg(ec.emergency_contact_name, ', ') as expected_parent_names
FROM emergency_contacts ec
WHERE ec.user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'
  AND ec.emergency_contact_name IS NOT NULL
  AND TRIM(ec.emergency_contact_name) != '';
