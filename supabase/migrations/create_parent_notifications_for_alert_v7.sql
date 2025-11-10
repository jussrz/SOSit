-- ============================================================
-- Function: create_parent_notifications_for_alert_v7
-- Purpose: Creates parent notifications for a panic alert
-- This function finds all parents/guardians of the child who triggered
-- the alert and creates notification records for them
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
    -- Fetch the panic alert details
    SELECT * INTO v_panic_alert
    FROM panic_alerts
    WHERE id = p_panic_alert_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Panic alert not found',
            'parent_count', 0
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
            'parent_count', 0
        );
    END IF;

    -- Build notification content based on alert level
    IF v_panic_alert.alert_level = 'CRITICAL' THEN
        v_notification_title := '🚨 CRITICAL EMERGENCY ALERT';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || 
                              ' has triggered a CRITICAL emergency alert!';
    ELSIF v_panic_alert.alert_level = 'CANCEL' THEN
        v_notification_title := '✅ Emergency Cancelled';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || 
                              ' has cancelled their emergency alert.';
    ELSE -- REGULAR
        v_notification_title := '⚠️ Emergency Alert';
        v_notification_body := COALESCE(v_child_user.first_name || ' ' || v_child_user.last_name, 'Someone') || 
                              ' has pressed their emergency alert button.';
    END IF;

    -- Build notification data
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

    -- Find all parents for this child
    -- Parents are found through emergency_contacts where the child's email is in added_by
    FOR v_parent_contact IN
        SELECT DISTINCT ec.user_id as parent_user_id
        FROM emergency_contacts ec
        WHERE ec.added_by = v_child_user.email
          AND ec.user_id IS NOT NULL
    LOOP
        -- Insert notification for each parent
        BEGIN
            INSERT INTO parent_notifications (
                parent_user_id,
                child_user_id,
                panic_alert_id,
                alert_type,
                notification_title,
                notification_body,
                notification_data,
                created_at
            ) VALUES (
                v_parent_contact.parent_user_id,
                v_panic_alert.user_id,
                p_panic_alert_id,
                v_panic_alert.alert_level,
                v_notification_title,
                v_notification_body,
                v_notification_data,
                v_panic_alert.timestamp
            );

            v_parent_count := v_parent_count + 1;
            
            RAISE NOTICE 'Created parent notification for parent_user_id: %', v_parent_contact.parent_user_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error creating notification for parent %: %', v_parent_contact.parent_user_id, SQLERRM;
        END;
    END LOOP;

    -- Return success response
    RETURN jsonb_build_object(
        'success', true,
        'parent_count', v_parent_count,
        'panic_alert_id', p_panic_alert_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'parent_count', 0
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_parent_notifications_for_alert_v7(INTEGER) TO authenticated;

-- Log the installation
DO $$
BEGIN
    RAISE NOTICE '✅ Function create_parent_notifications_for_alert_v7 created successfully';
END $$;
