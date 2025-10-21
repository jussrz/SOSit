-- ============================================================
-- SOSit Parent Tracking Database Setup
-- ============================================================
-- This script creates the necessary database tables and functions
-- for the parent notification tracking feature.
--
-- Run this script in your Supabase SQL Editor.
-- ============================================================

-- ============================================================
-- 1. Create user_fcm_tokens table
-- ============================================================
-- This table stores Firebase Cloud Messaging tokens for each user's device
-- to enable push notifications.

CREATE TABLE IF NOT EXISTS user_fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  device_id TEXT NOT NULL,
  device_name TEXT,
  platform TEXT CHECK (platform IN ('android', 'ios')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, device_id)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_fcm_token ON user_fcm_tokens(fcm_token);
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_platform ON user_fcm_tokens(platform);

-- Add comment
COMMENT ON TABLE user_fcm_tokens IS 'Stores Firebase Cloud Messaging tokens for push notifications';

-- ============================================================
-- 2. Create get_parent_fcm_tokens function
-- ============================================================
-- This function retrieves all FCM tokens for parent accounts
-- associated with a given child user via emergency contacts.

CREATE OR REPLACE FUNCTION get_parent_fcm_tokens(child_user_id UUID)
RETURNS TABLE (
  parent_user_id UUID,
  parent_email TEXT,
  parent_first_name TEXT,
  parent_last_name TEXT,
  parent_phone TEXT,
  fcm_token TEXT,
  device_id TEXT,
  device_name TEXT,
  platform TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    u.id AS parent_user_id,
    u.email AS parent_email,
    u.first_name AS parent_first_name,
    u.last_name AS parent_last_name,
    u.phone AS parent_phone,
    uft.fcm_token,
    uft.device_id,
    uft.device_name,
    uft.platform
  FROM emergency_contacts ec
  INNER JOIN group_members gm ON ec.group_member_id = gm.id
  INNER JOIN "user" u ON gm.user_id = u.id
  INNER JOIN user_fcm_tokens uft ON u.id = uft.user_id
  WHERE ec.user_id = child_user_id
    AND uft.fcm_token IS NOT NULL
    AND uft.fcm_token != '';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION get_parent_fcm_tokens IS 'Retrieves FCM tokens for all parent accounts linked to a child user';

-- ============================================================
-- 3. Create get_child_info function
-- ============================================================
-- Helper function to get child user information for notifications

CREATE OR REPLACE FUNCTION get_child_info(child_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  full_name TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id AS user_id,
    u.email,
    u.first_name,
    u.last_name,
    u.phone,
    CONCAT(u.first_name, ' ', u.last_name) AS full_name
  FROM "user" u
  WHERE u.id = child_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION get_child_info IS 'Retrieves user information for a child account';

-- ============================================================
-- 4. Enable Row Level Security (RLS)
-- ============================================================

-- Enable RLS on user_fcm_tokens table
ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only view their own FCM tokens
CREATE POLICY "Users can view own FCM tokens"
  ON user_fcm_tokens
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Users can insert their own FCM tokens
CREATE POLICY "Users can insert own FCM tokens"
  ON user_fcm_tokens
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own FCM tokens
CREATE POLICY "Users can update own FCM tokens"
  ON user_fcm_tokens
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy: Users can delete their own FCM tokens
CREATE POLICY "Users can delete own FCM tokens"
  ON user_fcm_tokens
  FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 5. Create updated_at trigger
-- ============================================================

-- Create trigger function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add trigger to user_fcm_tokens table
DROP TRIGGER IF EXISTS update_user_fcm_tokens_updated_at ON user_fcm_tokens;
CREATE TRIGGER update_user_fcm_tokens_updated_at
  BEFORE UPDATE ON user_fcm_tokens
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 6. Test Data Query (Optional - for verification)
-- ============================================================

-- Test the get_parent_fcm_tokens function
-- Replace 'YOUR_CHILD_USER_ID' with an actual UUID from your user table
-- SELECT * FROM get_parent_fcm_tokens('YOUR_CHILD_USER_ID');

-- View all FCM tokens (for debugging)
-- SELECT * FROM user_fcm_tokens;

-- ============================================================
-- Setup Complete!
-- ============================================================
-- Next steps:
-- 1. Run this SQL script in Supabase SQL Editor
-- 2. Create the Supabase Edge Function (send-parent-alerts)
-- 3. Deploy the Flutter app with FCM integration
-- ============================================================
