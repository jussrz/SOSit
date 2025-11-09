// @ts-nocheck
// ============================================================
// SOSit Station Alert Notification - Supabase Edge Function
// ============================================================
// Creates station_notifications rows for nearby police/tanod users
// Deploy with: supabase functions deploy send-station-alerts
// Requires environment variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({ error: 'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { panic_alert_id } = await req.json()
    if (!panic_alert_id) {
      return new Response(JSON.stringify({ error: 'Missing panic_alert_id' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Fetch panic alert details
    const { data: panic, error: panicErr } = await supabase
      .from('panic_alerts')
      .select('*')
      .eq('id', panic_alert_id)
      .single()

    if (panicErr || !panic) {
      console.error('Failed to fetch panic alert:', panicErr)
      return new Response(JSON.stringify({ error: 'Panic alert not found', details: panicErr }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const latitude = panic.latitude
    const longitude = panic.longitude
    const childUserId = panic.user_id
    const alertType = panic.alert_level || 'REGULAR'

    if (latitude == null || longitude == null) {
      return new Response(JSON.stringify({ success: false, message: 'Panic alert has no coordinates' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Helper to compute Haversine distance
    function toRad(deg: number) { return deg * Math.PI / 180 }
    function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number) {
      const R = 6371
      const dLat = toRad(lat2 - lat1)
      const dLon = toRad(lon2 - lon1)
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon/2) * Math.sin(dLon/2)
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
      return R * c
    }

    // Fetch users with role police or tanod and location
    const { data: stations, error: stationsErr } = await supabase
      .from('user')
      .select('id, first_name, current_latitude, current_longitude, role')
      .or('role.eq.police,role.eq.tanod')

    if (stationsErr) {
      console.error('Failed to fetch station users:', stationsErr)
      return new Response(JSON.stringify({ error: 'Failed to fetch station users', details: stationsErr }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const inserts = []

    for (const s of stations || []) {
      const sLat = s.current_latitude
      const sLon = s.current_longitude
      if (sLat == null || sLon == null) continue

      const dist = distanceKm(latitude, longitude, sLat, sLon)
      if (dist <= 5.0) {
        let title = alertType === 'CRITICAL' ? '🚨 CRITICAL Emergency' : '⚠️ Emergency Alert'
        if (alertType === 'CANCEL') title = '✅ Alert Cancelled'
        inserts.push({
          station_user_id: s.id,
          child_user_id: childUserId,
          panic_alert_id: panic_alert_id,
          alert_type: alertType,
          distance_km: dist,
          notification_title: title,
          notification_body: panic.location || 'Location updating...',
          notification_data: {
            child_id: childUserId,
            address: panic.location,
            latitude: latitude,
            longitude: longitude,
            timestamp: panic.timestamp
          },
          created_at: new Date().toISOString()
        })
      }
    }

    if (inserts.length === 0) {
      return new Response(JSON.stringify({ success: true, inserted: 0, message: 'No nearby stations within 5km' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: inserted, error: insertErr } = await supabase
      .from('station_notifications')
      .insert(inserts)

    if (insertErr) {
      console.error('Failed to insert station_notifications:', insertErr)
      return new Response(JSON.stringify({ success: false, error: insertErr }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

  return new Response(JSON.stringify({ success: true, inserted_count: inserted.length, inserted_rows: inserted }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error('send-station-alerts error:', error)
    return new Response(JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Unknown error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
