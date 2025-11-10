-- ============================================================
-- VERIFY EMERGENCY CONTACTS SETUP
-- Run this to check if Joshua's emergency contacts are correct
-- ============================================================

-- 1. Check Joshua Suarez's details
SELECT 
    'Joshua Suarez User Info' as check_type,
    id,
    first_name,
    last_name,
    email,
    role
FROM "user"
WHERE id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- 2. Check emergency contacts that Joshua added
SELECT 
    'Emergency Contacts Joshua Added' as check_type,
    ec.id,
    ec.user_id,
    u.first_name || ' ' || u.last_name as user_who_added_contact,
    ec.emergency_contact_name as contact_name,
    ec.emergency_contact_relationship as relationship,
    ec.emergency_contact_phone as contact_phone,
    ec.added_by
FROM emergency_contacts ec
LEFT JOIN "user" u ON ec.user_id = u.id
WHERE ec.user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';

-- 3. Check Leyden Suarez's details
SELECT 
    'Leyden Suarez User Info' as check_type,
    id,
    first_name,
    last_name,
    email,
    role
FROM "user"
WHERE id = '6e379ec8-11ab-44f9-a7ea-c4d1f0194fea';

-- 4. Expected result:
-- Joshua (f4ae5fd6-7589-4daa-85a8-2de513674354) should have emergency contacts
-- where emergency_contact_name = 'Leyden Suarez' (or similar)
-- 
-- When Joshua triggers an alert:
-- - Name: Joshua Suarez ✅
-- - Parent/Guardian: Leyden Suarez ✅ (from emergency_contact_name)

-- 5. If emergency_contact_name is empty or wrong, fix it:
-- UPDATE emergency_contacts 
-- SET emergency_contact_name = 'Leyden Suarez',
--     emergency_contact_relationship = 'Parent'
-- WHERE user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354';
