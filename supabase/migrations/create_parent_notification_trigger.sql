-- ============================================================
-- Temporary: Auto-create parent notifications via database trigger
-- This is a workaround until the Edge Function is deployed
-- ============================================================

-- Function to create parent notifications when panic alert is created
CREATE OR REPLACE FUNCTION notify_parents_on_panic_alert()
RETURNS TRIGGER AS $$
DECLARE
    parent_contact RECORD;
    child_info RECORD;
    notification_title TEXT;
    notification_body TEXT;
    notification_data JSONB;
BEGIN
    -- Get child user information
    SELECT first_name, last_name, phone, email
    INTO child_info
    FROM "user"
    WHERE id = NEW.user_id;

    -- Set notification content based on alert level
    IF NEW.alert_level = 'CRITICAL' THEN
        notification_title := '🚨 CRITICAL EMERGENCY ALERT';
        notification_body := COALESCE(child_info.first_name || ' ' || child_info.last_name, 'Someone') || 
                           ' has triggered a CRITICAL emergency alert!';
    ELSIF NEW.alert_level = 'CANCEL' THEN
        notification_title := '✅ Emergency Cancelled';
        notification_body := COALESCE(child_info.first_name || ' ' || child_info.last_name, 'Someone') || 
                           ' has cancelled their emergency alert.';
    ELSE -- REGULAR
        notification_title := '⚠️ Emergency Alert';
        notification_body := COALESCE(child_info.first_name || ' ' || child_info.last_name, 'Someone') || 
                           ' has pressed their emergency alert button.';
    END IF;

    -- Build notification data
    notification_data := jsonb_build_object(
        'child_name', COALESCE(child_info.first_name || ' ' || child_info.last_name, 'Unknown User'),
        'child_phone', child_info.phone,
        'child_email', child_info.email,
        'latitude', NEW.latitude,
        'longitude', NEW.longitude,
        'address', NEW.location,
        'battery_level', NEW.battery_level,
        'timestamp', NEW.timestamp
    );

    -- Find all parents (emergency contacts) for this child
    FOR parent_contact IN
        -- Find via emergency_contacts -> group_members -> parent user
        SELECT DISTINCT gm.user_id as parent_user_id
        FROM emergency_contacts ec
        INNER JOIN group_members gm ON ec.group_member_id = gm.id
        WHERE ec.user_id = NEW.user_id
          AND gm.user_id IS NOT NULL
    LOOP
        -- Insert notification for each parent
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
            parent_contact.parent_user_id,
            NEW.user_id,
            NEW.id,
            NEW.alert_level,
            notification_title,
            notification_body,
            notification_data,
            NEW.timestamp
        );

        RAISE NOTICE 'Created parent notification for parent_user_id: %', parent_contact.parent_user_id;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on panic_alerts table
DROP TRIGGER IF EXISTS trigger_notify_parents ON panic_alerts;
CREATE TRIGGER trigger_notify_parents
    AFTER INSERT ON panic_alerts
    FOR EACH ROW
    EXECUTE FUNCTION notify_parents_on_panic_alert();

-- Log the installation
DO $$
BEGIN
    RAISE NOTICE '✅ Parent notification trigger installed successfully';
    RAISE NOTICE '📋 Trigger: trigger_notify_parents on panic_alerts table';
    RAISE NOTICE '🔔 Function: notify_parents_on_panic_alert()';
END $$;
