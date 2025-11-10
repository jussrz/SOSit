// @ts-nocheck
// ============================================================
// SOSit Station Alert Notification - Supabase Edge Function
// ============================================================
// Creates station_notifications rows for nearby police/tanod users
// AND sends FCM V1 API push notifications for background delivery
// Deploy with: supabase functions deploy send-station-alerts
// Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FIREBASE_SERVICE_ACCOUNT
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Base64 encode for JWT
function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}

// Create JWT for Google OAuth2
async function createJWT(serviceAccount: any): Promise<string> {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const unsignedToken = `${encodedHeader}.${encodedPayload}`

  // Import the private key
  const privateKey = serviceAccount.private_key
  const keyData = privateKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')

  const binaryKey = Uint8Array.from(atob(keyData), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  )

  const encodedSignature = base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signature))
  )

  return `${unsignedToken}.${encodedSignature}`
}

// Get OAuth2 access token
async function getAccessToken(serviceAccount: any): Promise<string> {
  const jwt = await createJWT(serviceAccount)

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const data = await response.json()
  
  if (!data.access_token) {
    throw new Error('Failed to get access token: ' + JSON.stringify(data))
  }

  return data.access_token
}

// Send FCM notification using V1 API
async function sendFCMNotification(
  fcmToken: string,
  title: string,
  body: string,
  data: any,
  alertType: string,
  projectId: string,
  accessToken: string
) {
  try {
    const message = {
      message: {
        token: fcmToken,
        notification: {
          title: title,
          body: body,
        },
        data: {
          ...data,
          type: 'station_alert',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: alertType === 'CRITICAL' ? 'high' : 'normal',
          notification: {
            channel_id: alertType === 'CRITICAL' ? 'critical_alerts' : 'regular_alerts',
            sound: 'default',
            notification_priority: alertType === 'CRITICAL' ? 'PRIORITY_MAX' : 'PRIORITY_HIGH',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              'interruption-level': alertType === 'CRITICAL' ? 'critical' : 'active',
            },
          },
        },
      },
    }

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(message),
      }
    )

    const result = await response.json()

    if (response.ok) {
      console.log('✅ FCM V1 notification sent successfully')
      return { success: true }
    } else {
      console.error('❌ FCM V1 send failed:', result)
      return { success: false, error: result }
    }
  } catch (error) {
    console.error('❌ FCM V1 send error:', error)
    return { success: false, error: error }
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') || 'sosit-64bfe'
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({ error: 'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (!serviceAccountJson) {
      console.error('❌ FIREBASE_SERVICE_ACCOUNT not configured')
      return new Response(
        JSON.stringify({ error: 'Firebase service account not configured' }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const serviceAccount = JSON.parse(serviceAccountJson)

    // Get OAuth2 access token for FCM V1 API
    console.log('🔑 Getting Firebase access token...')
    const accessToken = await getAccessToken(serviceAccount)
    console.log('✅ Access token obtained')

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

    // Fetch users with role police or tanod and location with FCM tokens
    const { data: stations, error: stationsErr } = await supabase
      .from('user')
      .select('id, first_name, last_name, current_latitude, current_longitude, role')
      .or('role.eq.police,role.eq.tanod')

    if (stationsErr) {
      console.error('Failed to fetch station users:', stationsErr)
      return new Response(JSON.stringify({ error: 'Failed to fetch station users', details: stationsErr }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Get child user info with all details needed for police modal
    const { data: childUser, error: childErr } = await supabase
      .from('user')
      .select('first_name, last_name, email, phone, battery_level')
      .eq('id', childUserId)
      .single()

    const childName = childUser ? `${childUser.first_name} ${childUser.last_name}` : 'Citizen'
    const childEmail = childUser?.email || ''
    const childPhone = childUser?.phone || ''
    const batteryLevel = childUser?.battery_level || 0

    // Get parent names for child
    let parentNames = ''
    try {
      const { data: parentData } = await supabase
        .rpc('get_parent_names', { child_user_id: childUserId })
        .single()
      parentNames = parentData?.parent_names || ''
    } catch (e) {
      console.log('⚠️ Could not fetch parent names (function may not exist):', e)
    }

    console.log(`👶 Child info: ${childName}, Email: ${childEmail}, Phone: ${childPhone}, Parents: ${parentNames}`)

    const inserts = []
    let fcmSentCount = 0

    for (const s of stations || []) {
      const sLat = s.current_latitude
      const sLon = s.current_longitude
      if (sLat == null || sLon == null) continue

      const dist = distanceKm(latitude, longitude, sLat, sLon)
      if (dist <= 5.0) {
        let title = alertType === 'CRITICAL' ? '🚨 CRITICAL Emergency' : '⚠️ Emergency Alert'
        if (alertType === 'CANCEL') title = '✅ Alert Cancelled'
        
        const body = `${childName} needs help!\n${panic.location || 'Location updating...'}\n~${dist.toFixed(1)} km away`
        
        inserts.push({
          station_user_id: s.id,
          child_user_id: childUserId,
          panic_alert_id: panic_alert_id,
          alert_type: alertType,
          distance_km: dist,
          notification_title: title,
          notification_body: body,
          notification_data: {
            child_id: childUserId,
            child_name: childName,
            child_email: childEmail,
            child_phone: childPhone,
            address: panic.location,
            latitude: latitude,
            longitude: longitude,
            timestamp: panic.timestamp,
            distance_km: dist.toFixed(1),
            parent_names: parentNames,
            battery_level: batteryLevel
          },
          created_at: new Date().toISOString()
        })

        // Get FCM tokens for this station user and send notifications
        const { data: fcmTokens, error: fcmErr } = await supabase
          .from('user_fcm_tokens')
          .select('fcm_token')
          .eq('user_id', s.id)

        if (fcmTokens && fcmTokens.length > 0) {
          console.log(`📱 Found ${fcmTokens.length} FCM token(s) for station user ${s.first_name} ${s.last_name}`)
          for (const tokenRow of fcmTokens) {
            const fcmData = {
              alert_type: alertType,
              child_name: childName,
              child_id: childUserId,
              child_email: childEmail,
              child_phone: childPhone,
              address: panic.location || 'Location updating...',
              latitude: latitude.toString(),
              longitude: longitude.toString(),
              distance_km: dist.toFixed(1),
              timestamp: panic.timestamp,
              panic_alert_id: panic_alert_id,
              parent_names: parentNames,
              battery_level: batteryLevel.toString()
            }
            
            console.log(`📤 Sending FCM to ${s.first_name} (token: ${tokenRow.fcm_token.substring(0, 20)}...)`)
            console.log(`📦 FCM Data:`, JSON.stringify(fcmData))
            
            const fcmResult = await sendFCMNotification(
              tokenRow.fcm_token,
              title,
              body,
              fcmData,
              alertType,
              firebaseProjectId,
              accessToken
            )
            
            if (fcmResult.success) {
              fcmSentCount++
              console.log(`✅ FCM sent successfully to ${s.first_name}`)
            } else {
              console.error(`❌ FCM failed for ${s.first_name}:`, fcmResult.error)
            }
          }
        } else {
          console.log(`⚠️ No FCM tokens found for station user ${s.first_name} ${s.last_name} (${s.id})`)
        }
      }
    }

    if (inserts.length === 0) {
      return new Response(JSON.stringify({ success: true, inserted: 0, fcm_sent: 0, message: 'No nearby stations within 5km' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: inserted, error: insertErr } = await supabase
      .from('station_notifications')
      .insert(inserts)

    if (insertErr) {
      console.error('Failed to insert station_notifications:', insertErr)
      return new Response(JSON.stringify({ success: false, error: insertErr }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

  return new Response(JSON.stringify({ 
    success: true, 
    inserted_count: inserted.length, 
    fcm_sent: fcmSentCount,
    inserted_rows: inserted 
  }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error('send-station-alerts error:', error)
    return new Response(JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Unknown error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
