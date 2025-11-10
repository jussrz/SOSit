-- ============================================================
-- TEST THE FIX - Simulate what the function will return
-- This tests the parent/guardian lookup logic
-- ============================================================

-- Test for Joshua Suarez (f4ae5fd6-7589-4daa-85a8-2de513674354)
WITH child_info AS (
    SELECT 
        id,
        first_name,
        last_name,
        email,
        first_name || ' ' || last_name as full_name
    FROM "user"
    WHERE id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'
),
emergency_contacts_for_child AS (
    SELECT 
        ec.emergency_contact_name,
        ec.emergency_contact_relationship,
        ec.emergency_contact_phone
    FROM emergency_contacts ec
    WHERE ec.user_id = 'f4ae5fd6-7589-4daa-85a8-2de513674354'
      AND ec.emergency_contact_name IS NOT NULL
      AND TRIM(ec.emergency_contact_name) != ''
)
SELECT 
    '🧪 TEST RESULT' as test_type,
    ci.full_name as child_name,
    ci.email as child_email,
    COALESCE(
        string_agg(ec.emergency_contact_name, ', '),
        'No parents listed'
    ) as parent_guardian_names,
    CASE 
        WHEN string_agg(ec.emergency_contact_name, ', ') = 'Leyden Suarez' 
        THEN '✅ CORRECT - Shows Leyden Suarez'
        WHEN string_agg(ec.emergency_contact_name, ', ') IS NULL
        THEN '❌ WRONG - No emergency contacts found'
        ELSE '⚠️ CHECK - Found: ' || string_agg(ec.emergency_contact_name, ', ')
    END as validation
FROM child_info ci
LEFT JOIN emergency_contacts_for_child ec ON true
GROUP BY ci.full_name, ci.email;

-- Expected result:
-- child_name: Joshua Suarez
-- parent_guardian_names: Leyden Suarez
-- validation: ✅ CORRECT - Shows Leyden Suarez
