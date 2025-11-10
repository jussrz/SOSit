-- ============================================================
-- DEPLOYMENT SCRIPT - Run this in Supabase SQL Editor
-- ============================================================
-- This script will create both database functions needed for
-- the emergency alert system to work correctly
-- ============================================================

-- Drop existing functions if they exist (to avoid type conflicts)
-- ============================================================

DROP FUNCTION IF EXISTS create_parent_notifications_for_alert_v7(INTEGER);
DROP FUNCTION IF EXISTS create_station_notifications_for_alert(INTEGER);

-- ============================================================
-- STEP 1: Create parent notification function
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
-- STEP 2: Create station notification function
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
    SELECT * INTO v_panic_alert FROM panic_alerts WHERE id = p_panic_alert_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Panic alert not found', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    IF v_panic_alert.latitude IS NULL OR v_panic_alert.longitude IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Panic alert has no location data', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    SELECT id, first_name, last_name, phone, email INTO v_child_user FROM "user" WHERE id = v_panic_alert.user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Child user not found', 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
    END IF;

    BEGIN
        FOR v_parent_record IN
            SELECT DISTINCT u.first_name, u.last_name
            FROM emergency_contacts ec
            INNER JOIN "user" u ON ec.user_id = u.id
            WHERE ec.added_by = v_child_user.email AND ec.user_id IS NOT NULL
        LOOP
            v_parent_names_array := array_append(v_parent_names_array, TRIM(COALESCE(v_parent_record.first_name, '') || ' ' || COALESCE(v_parent_record.last_name, '')));
        END LOOP;
        IF array_length(v_parent_names_array, 1) > 0 THEN
            v_parent_names := array_to_string(v_parent_names_array, ', ');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_parent_names := 'Error loading parents';
    END;

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

    FOR v_station_user IN
        SELECT id, first_name, role, current_latitude, current_longitude
        FROM "user"
        WHERE (role = 'police' OR role = 'tanod') AND current_latitude IS NOT NULL AND current_longitude IS NOT NULL
    LOOP
        v_distance_km := (6371 * acos(cos(radians(v_panic_alert.latitude::DOUBLE PRECISION)) * cos(radians(v_station_user.current_latitude::DOUBLE PRECISION)) * cos(radians(v_station_user.current_longitude::DOUBLE PRECISION) - radians(v_panic_alert.longitude::DOUBLE PRECISION)) + sin(radians(v_panic_alert.latitude::DOUBLE PRECISION)) * sin(radians(v_station_user.current_latitude::DOUBLE PRECISION))));

        IF v_distance_km <= 5.0 THEN
            BEGIN
                INSERT INTO station_notifications (station_user_id, child_user_id, panic_alert_id, alert_type, distance_km, notification_title, notification_body, notification_data, created_at)
                VALUES (v_station_user.id, v_panic_alert.user_id, p_panic_alert_id, v_panic_alert.alert_level, v_distance_km, v_notification_title, v_notification_body, v_notification_data, v_panic_alert.timestamp);

                IF v_station_user.role = 'police' THEN
                    v_police_count := v_police_count + 1;
                ELSIF v_station_user.role = 'tanod' THEN
                    v_tanod_count := v_tanod_count + 1;
                END IF;
                v_total_count := v_total_count + 1;
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Error creating notification for station user %: %', v_station_user.id, SQLERRM;
            END;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'police_notified', v_police_count, 'tanod_notified', v_tanod_count, 'total_notified', v_total_count, 'panic_alert_id', p_panic_alert_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'police_notified', 0, 'tanod_notified', 0, 'total_notified', 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_station_notifications_for_alert(INTEGER) TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================

-- Test if functions were created successfully
DO $$
BEGIN
    RAISE NOTICE '✅ Both database functions have been created successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Functions created:';
    RAISE NOTICE '  1. create_parent_notifications_for_alert_v7(panic_alert_id INTEGER)';
    RAISE NOTICE '  2. create_station_notifications_for_alert(panic_alert_id INTEGER)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Rebuild your Flutter app (flutter clean && flutter pub get)';
    RAISE NOTICE '  2. Test emergency alert with a real user';
    RAISE NOTICE '  3. Verify police/tanod receive notifications';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️ IMPORTANT: Make sure police/tanod users have their location updated!';
    RAISE NOTICE '   Update location: UPDATE "user" SET current_latitude = X, current_longitude = Y WHERE id = ''uuid'';';
END $$;
