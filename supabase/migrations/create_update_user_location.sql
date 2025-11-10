-- ============================================================
-- Function: update_user_location
-- Purpose: Update user's current location (latitude/longitude)
-- This is called by police/tanod apps to update their location
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
    
    RAISE NOTICE 'Updated location for user %: (%, %)', p_user_id, p_latitude, p_longitude;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_user_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- Log the installation
DO $$
BEGIN
    RAISE NOTICE '✅ Function update_user_location created successfully';
END $$;
