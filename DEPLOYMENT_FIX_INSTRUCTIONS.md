# 🚨 URGENT FIX: Parent Notifications Not Working

## Problem
The parent dashboard shows 0 notifications because the Edge Function `send-parent-alerts` is **NOT DEPLOYED** (404 error).

## Error From Logs
```
Error logging emergency: PostgrestException(message: {}, code: 404, details: Not Found, hint: null)
```

---

## ✅ IMMEDIATE FIX (Database Trigger)

**Instead of deploying the Edge Function**, we can use a **database trigger** to automatically create parent notifications.

### Step 1: Go to Supabase Dashboard
1. Open your Supabase project dashboard
2. Go to **SQL Editor** (left sidebar)

### Step 2: Run This SQL Script

```sql
-- ============================================================
-- Auto-create parent notifications via database trigger
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
```

### Step 3: Verify Installation
Run this query to check if the trigger was created:
```sql
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE trigger_name = 'trigger_notify_parents';
```

You should see:
```
trigger_name          | event_manipulation | event_object_table
trigger_notify_parents| INSERT            | panic_alerts
```

---

## ✅ TEST THE FIX

1. **On Child Account**: Press the panic button on your app
2. **Check Database**: Go to Table Editor → `parent_notifications` → you should see a new row
3. **On Parent Account**: The emergency contact dashboard should now show the alert!

---

## 📊 Verify Data

### Check if panic alerts are being created:
```sql
SELECT * FROM panic_alerts ORDER BY timestamp DESC LIMIT 5;
```

### Check if parent notifications are being created:
```sql
SELECT * FROM parent_notifications ORDER BY created_at DESC LIMIT 5;
```

### Check emergency contact relationships:
```sql
SELECT 
    ec.id,
    ec.user_id as child_user_id,
    gm.user_id as parent_user_id,
    gm.relationship
FROM emergency_contacts ec
INNER JOIN group_members gm ON ec.group_member_id = gm.id
WHERE gm.user_id IS NOT NULL;
```

---

## 🔧 ALTERNATIVE: Deploy Edge Function (Optional)

If you want to use the Edge Function instead of the trigger:

### 1. Install Supabase CLI
```bash
brew install supabase/tap/supabase
```

### 2. Login
```bash
supabase login
```

### 3. Link Project
```bash
cd /Users/ferdinandjohndobli/Documents/SOSit
supabase link --project-ref YOUR_PROJECT_REF
```

### 4. Deploy Function
```bash
supabase functions deploy send-parent-alerts
```

### 5. Remove Trigger (if using Edge Function)
```sql
DROP TRIGGER IF EXISTS trigger_notify_parents ON panic_alerts;
DROP FUNCTION IF EXISTS notify_parents_on_panic_alert();
```

---

## 🎯 Summary

**Current Issue**: Edge Function not deployed → 404 error → No parent notifications created

**Fix**: Database trigger automatically creates parent notifications when panic alert is inserted

**Result**: Parent dashboard will show alerts in real-time! 🎉
