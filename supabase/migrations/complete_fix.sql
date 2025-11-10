-- ============================================================
-- COMPLETE FIX - Emergency Alert System
-- Run this script to fix all issues
-- ============================================================

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS create_parent_notifications_for_alert_v7(INTEGER);
DROP FUNCTION IF EXISTS create_station_notifications_for_alert(INTEGER);
DROP FUNCTION IF EXISTS update_user_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION);

-- ============================================================
-- 1. Create update_user_location function
-- ============================================================

CREATE OR REPLACE FUNCTION update_user_location(
    p_user_id UUID,
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION
)
RETURNS VOID AS $$
BEGIN
    UPDATE "user"
    SET 
        current_latitude = p_latitude,
        current_longitude = p_longitude,
        location_updated_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_user_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- ============================================================
-- 2. Create parent notification function
-- ============================================================

CREATE OR REPLACE FUNCTION create_parent_notifications_for_alert_v7(p_panic_alert_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_panic_alert RECORD;
    v_child_user RECORD;
    v_parent_contact RECORD;
    v_parent_count INTEGER := 0;
    v_notification_title TEXT;
    v_notification_body TEXT;
    v_notification_data JSONB;
BEGIN
    SELECT * INTO v_panic_alert FROM panic_alerts WHERE id = p_panic_alert_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Panic alert not found', 'parent_count', 0);
    END IF;

    SELECT id, first_name, last_name, phone, email INTO v_child_user FROM "user" WHERE id = v_panic_alert.user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Child user not found', 'parent_count', 0);
    END IF;

    IF v_panic_alert.alert_level = 'CRITICAL' THEN
        v_notification_title := '🚨 CRITICAL EMERGENCY ALERT';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || ' has triggered a CRITICAL emergency alert!';
    ELSIF v_panic_alert.alert_level = 'CANCEL' THEN
        v_notification_title := '✅ Emergency Cancelled';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || ' has cancelled their emergency alert.';
    ELSE
        v_notification_title := '⚠️ Emergency Alert';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || ' has pressed their emergency alert button.';
    END IF;

    v_notification_data := jsonb_build_object(
        'child_name', COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Unknown User'),
        'child_phone', v_child_user.phone,
        'child_email', v_child_user.email,
        'latitude', v_panic_alert.latitude,
        'longitude', v_panic_alert.longitude,
        'address', v_panic_alert.location,
        'battery_level', v_panic_alert.battery_level,
        'timestamp', v_panic_alert.timestamp
    );

    FOR v_parent_contact IN
        SELECT DISTINCT ec.user_id as parent_user_id
        FROM emergency_contacts ec
        WHERE ec.added_by = v_child_user.email AND ec.user_id IS NOT NULL
    LOOP
        BEGIN
            INSERT INTO parent_notifications (parent_user_id, child_user_id, panic_alert_id, alert_type, notification_title, notification_body, notification_data, created_at)
            VALUES (v_parent_contact.parent_user_id, v_panic_alert.user_id, p_panic_alert_id, v_panic_alert.alert_level, v_notification_title, v_notification_body, v_notification_data, v_panic_alert.timestamp);
            v_parent_count := v_parent_count + 1;
            RAISE NOTICE 'Created parent notification for: %', v_parent_contact.parent_user_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Error creating notification for parent %: %', v_parent_contact.parent_user_id, SQLERRM;
        END;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'parent_count', v_parent_count, 'panic_alert_id', p_panic_alert_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'parent_count', 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_parent_notifications_for_alert_v7(INTEGER) TO authenticated;

-- ============================================================
-- 3. Create station notification function
-- ============================================================

CREATE OR REPLACE FUNCTION create_station_notifications_for_alert(p_panic_alert_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_panic_alert RECORD;
    v_child_user RECORD;
    v_station_user RECORD;
    v_distance_km NUMERIC;
    v_police_count INTEGER := 0;
    v_tanod_count INTEGER := 0;
    v_total_count INTEGER := 0;
    v_notification_title TEXT;
    v_notification_body TEXT;
    v_notification_data JSONB;
    v_parent_names TEXT := 'No parents listed';
    v_parent_record RECORD;
    v_parent_names_array TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get panic alert
    SELECT * INTO v_panic_alert FROM panic_alerts WHERE id = p_panic_alert_id;
    IF NOT FOUND THEN
        RAISE NOTICE '❌ Panic alert % not found', p_panic_alert_id;
        RETURN jsonb_build_object('success', false, 'error', 'Panic alert not found', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    RAISE NOTICE '📍 Panic alert location: (%, %)', v_panic_alert.latitude, v_panic_alert.longitude;

    IF v_panic_alert.latitude IS NULL OR v_panic_alert.longitude IS NULL THEN
        RAISE NOTICE '❌ Panic alert has no location data';
        RETURN jsonb_build_object('success', false, 'error', 'Panic alert has no location data', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    -- Get child user info
    SELECT id, first_name, last_name, phone, email INTO v_child_user FROM "user" WHERE id = v_panic_alert.user_id;
    IF NOT FOUND THEN
        RAISE NOTICE '❌ Child user not found: %', v_panic_alert.user_id;
        RETURN jsonb_build_object('success', false, 'error', 'Child user not found', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    RAISE NOTICE '👤 Child user: % %', v_child_user.first_name, v_child_user.last_name;

    -- Get parent names
    -- The emergency_contacts table stores:
    -- - user_id: The user who ADDED the contact (Joshua in this case)
    -- - emergency_contact_name: The name of the emergency contact (Leyden)
    -- So we need to get emergency contacts WHERE user_id = child's user_id
    BEGIN
        FOR v_parent_record IN
            SELECT DISTINCT ec.emergency_contact_name
            FROM emergency_contacts ec
            WHERE ec.user_id = v_child_user.id
              AND ec.emergency_contact_name IS NOT NULL
              AND TRIM(ec.emergency_contact_name) != ''
        LOOP
            v_parent_names_array := array_append(v_parent_names_array, TRIM(v_parent_record.emergency_contact_name));
        END LOOP;
        IF array_length(v_parent_names_array, 1) > 0 THEN
            v_parent_names := array_to_string(v_parent_names_array, ', ');
        END IF;
        RAISE NOTICE '👨‍👩‍👧 Parent/Guardian names: %', v_parent_names;
    EXCEPTION WHEN OTHERS THEN
        v_parent_names := 'Error loading parents';
        RAISE NOTICE '❌ Error fetching parent names: %', SQLERRM;
    END;

    -- Build notification content
    IF v_panic_alert.alert_level = 'CRITICAL' THEN
        v_notification_title := '🚨 CRITICAL Emergency';
    ELSIF v_panic_alert.alert_level = 'CANCEL' THEN
        v_notification_title := '✅ Alert Cancelled';
    ELSE
        v_notification_title := '⚠️ Emergency Alert';
    END IF;

    v_notification_body := COALESCE(v_panic_alert.location, 'Location updating...');

    v_notification_data := jsonb_build_object(
        'child_id', v_child_user.id,
        'child_name', COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Unknown User'),
        'child_phone', v_child_user.phone,
        'child_email', v_child_user.email,
        'parent_names', v_parent_names,
        'latitude', v_panic_alert.latitude,
        'longitude', v_panic_alert.longitude,
        'address', v_panic_alert.location,
        'battery_level', v_panic_alert.battery_level,
        'timestamp', v_panic_alert.timestamp
    );

    -- Find and notify police/tanod within 5km
    FOR v_station_user IN
        SELECT id, first_name, last_name, role, current_latitude, current_longitude
        FROM "user"
        WHERE (role = 'police' OR role = 'tanod') 
          AND current_latitude IS NOT NULL 
          AND current_longitude IS NOT NULL
    LOOP
        -- Calculate distance
        v_distance_km := (6371 * acos(
            cos(radians(v_panic_alert.latitude::DOUBLE PRECISION)) * 
            cos(radians(v_station_user.current_latitude::DOUBLE PRECISION)) * 
            cos(radians(v_station_user.current_longitude::DOUBLE PRECISION) - radians(v_panic_alert.longitude::DOUBLE PRECISION)) + 
            sin(radians(v_panic_alert.latitude::DOUBLE PRECISION)) * 
            sin(radians(v_station_user.current_latitude::DOUBLE PRECISION))
        ));

        RAISE NOTICE '📏 Distance to % (%) %: %.2f km', v_station_user.first_name, v_station_user.role, v_station_user.id, v_distance_km;

        IF v_distance_km <= 5.0 THEN
            BEGIN
                INSERT INTO station_notifications (
                    station_user_id, 
                    child_user_id, 
                    panic_alert_id, 
                    alert_type, 
                    distance_km, 
                    notification_title, 
                    notification_body, 
                    notification_data, 
                    created_at
                ) VALUES (
                    v_station_user.id, 
                    v_panic_alert.user_id, 
                    p_panic_alert_id, 
                    v_panic_alert.alert_level, 
                    v_distance_km, 
                    v_notification_title, 
                    v_notification_body, 
                    v_notification_data, 
                    v_panic_alert.timestamp
                );

                IF v_station_user.role = 'police' THEN
                    v_police_count := v_police_count + 1;
                ELSIF v_station_user.role = 'tanod' THEN
                    v_tanod_count := v_tanod_count + 1;
                END IF;
                v_total_count := v_total_count + 1;
                
                RAISE NOTICE '✅ Created notification for % % (%) at %.2f km', v_station_user.first_name, v_station_user.last_name, v_station_user.role, v_distance_km;
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE '❌ Error creating notification for %: %', v_station_user.id, SQLERRM;
            END;
        ELSE
            RAISE NOTICE '⏭️ Skipped % (too far: %.2f km)', v_station_user.first_name, v_distance_km;
        END IF;
    END LOOP;

    RAISE NOTICE '📊 Notification summary - Police: %, Tanod: %, Total: %', v_police_count, v_tanod_count, v_total_count;

    RETURN jsonb_build_object(
        'success', true, 
        'police_notified', v_police_count, 
        'tanod_notified', v_tanod_count, 
        'total_notified', v_total_count, 
        'panic_alert_id', p_panic_alert_id
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Fatal error: %', SQLERRM;
    RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_station_notifications_for_alert(INTEGER) TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '✅ All functions created successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Functions created:';
    RAISE NOTICE '  1. update_user_location(user_id, latitude, longitude)';
    RAISE NOTICE '  2. create_parent_notifications_for_alert_v7(panic_alert_id)';
    RAISE NOTICE '  3. create_station_notifications_for_alert(panic_alert_id)';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️ CRITICAL NEXT STEPS:';
    RAISE NOTICE '';
    RAISE NOTICE '1. Run diagnostic_check.sql to verify police/tanod have locations';
    RAISE NOTICE '2. If they dont have locations, update them:';
    RAISE NOTICE '   UPDATE "user" SET current_latitude = YOUR_LAT, current_longitude = YOUR_LON WHERE email = ''police@example.com'';';
    RAISE NOTICE '';
    RAISE NOTICE '3. Test by triggering a panic alert';
    RAISE NOTICE '4. Check logs with: SELECT * FROM station_notifications ORDER BY created_at DESC LIMIT 5;';
    RAISE NOTICE '';
END $$;
