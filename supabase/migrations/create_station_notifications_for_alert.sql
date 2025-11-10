-- ============================================================
-- Function: create_station_notifications_for_alert
-- Purpose: Creates station notifications for nearby police/tanod
-- This function finds all police and tanod users within 5km of the
-- panic alert location and creates notification records for them
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
    -- Fetch the panic alert details
    SELECT * INTO v_panic_alert
    FROM panic_alerts
    WHERE id = p_panic_alert_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Panic alert not found',
            'police_notified', 0,
            'tanod_notified', 0,
            'total_notified', 0
        );
    END IF;

    -- Check if alert has location data
    IF v_panic_alert.latitude IS NULL OR v_panic_alert.longitude IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Panic alert has no location data',
            'police_notified', 0,
            'tanod_notified', 0,
            'total_notified', 0
        );
    END IF;

    -- Get child user information
    SELECT id, first_name, last_name, phone, email
    INTO v_child_user
    FROM "user"
    WHERE id = v_panic_alert.user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Child user not found',
            'police_notified', 0,
            'tanod_notified', 0,
            'total_notified', 0
        );
    END IF;

    -- Fetch parent/guardian names for the child
    -- The emergency_contacts table stores:
    -- - user_id: The user who ADDED the contact (Joshua in this case)
    -- - emergency_contact_name: The name of the emergency contact (Leyden)
    -- So we get emergency contacts WHERE user_id = child's user_id
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
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error fetching parent names: %', SQLERRM;
            v_parent_names := 'Error loading parents';
    END;

    -- Build notification content based on alert level
    IF v_panic_alert.alert_level = 'CRITICAL' THEN
        v_notification_title := '🚨 CRITICAL Emergency';
    ELSIF v_panic_alert.alert_level = 'CANCEL' THEN
        v_notification_title := '✅ Alert Cancelled';
    ELSE
        v_notification_title := '⚠️ Emergency Alert';
    END IF;

    v_notification_body := COALESCE(v_panic_alert.location, 'Location updating...');

    -- Build notification data
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

    -- Find all police and tanod users within 5km
    FOR v_station_user IN
        SELECT id, first_name, role, current_latitude, current_longitude
        FROM "user"
        WHERE (role = 'police' OR role = 'tanod')
          AND current_latitude IS NOT NULL
          AND current_longitude IS NOT NULL
    LOOP
        -- Calculate distance using Haversine formula (in kilometers)
        v_distance_km := (
            6371 * acos(
                cos(radians(v_panic_alert.latitude::DOUBLE PRECISION)) *
                cos(radians(v_station_user.current_latitude::DOUBLE PRECISION)) *
                cos(radians(v_station_user.current_longitude::DOUBLE PRECISION) - radians(v_panic_alert.longitude::DOUBLE PRECISION)) +
                sin(radians(v_panic_alert.latitude::DOUBLE PRECISION)) *
                sin(radians(v_station_user.current_latitude::DOUBLE PRECISION))
            )
        );

        -- Only notify if within 5km
        IF v_distance_km <= 5.0 THEN
            BEGIN
                -- Insert station notification
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

                -- Count by role
                IF v_station_user.role = 'police' THEN
                    v_police_count := v_police_count + 1;
                ELSIF v_station_user.role = 'tanod' THEN
                    v_tanod_count := v_tanod_count + 1;
                END IF;

                v_total_count := v_total_count + 1;

                RAISE NOTICE 'Created station notification for % (%) at %.2f km', 
                    v_station_user.id, v_station_user.role, v_distance_km;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE NOTICE 'Error creating notification for station user %: %', 
                        v_station_user.id, SQLERRM;
            END;
        END IF;
    END LOOP;

    -- Return success response
    RETURN jsonb_build_object(
        'success', true,
        'police_notified', v_police_count,
        'tanod_notified', v_tanod_count,
        'total_notified', v_total_count,
        'panic_alert_id', p_panic_alert_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'police_notified', 0,
            'tanod_notified', 0,
            'total_notified', 0
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_station_notifications_for_alert(INTEGER) TO authenticated;

-- Log the installation
DO $$
BEGIN
    RAISE NOTICE '✅ Function create_station_notifications_for_alert created successfully';
END $$;
