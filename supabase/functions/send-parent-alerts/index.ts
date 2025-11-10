// ============================================================
// SOSit Parent Alert Notification - Supabase Edge Function
// ============================================================
// Uses Firebase Cloud Messaging V1 API to send push notifications to parents
// Deploy with: supabase functions deploy send-parent-alerts
// Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FIREBASE_SERVICE_ACCOUNT
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS headers for browser requests
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
          type: 'parent_alert',
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
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get environment variables
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') || 'sosit-64bfe'
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')

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

    // Parse request body
    const { alert } = await req.json()

    if (!alert || !alert.user_id) {
      return new Response(
        JSON.stringify({ error: 'Invalid request: missing alert or user_id' }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    console.log('📩 Processing parent alert notification:', alert)
    
    // Extract panic_alert_id from request
    const panicAlertId = alert.panic_alert_id
    console.log('🆔 Panic Alert ID:', panicAlertId)

    // Create Supabase client with service role
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get child user information
    const { data: childUser, error: childError } = await supabase
      .rpc('get_child_info', { child_user_id: alert.user_id })
      .single()

    if (childError) {
      console.error('Error fetching child user:', childError)
      throw new Error('Failed to fetch child user information')
    }

    const childName = childUser.full_name || `${childUser.first_name} ${childUser.last_name}`
    const childPhone = childUser.phone || ''

    console.log('👶 Child user:', childName)

    // Get parent FCM tokens
    const { data: parents, error: parentsError } = await supabase
      .rpc('get_parent_fcm_tokens', { child_user_id: alert.user_id })

    if (parentsError) {
      console.error('Error fetching parent tokens:', parentsError)
      throw new Error('Failed to fetch parent FCM tokens')
    }

    if (!parents || parents.length === 0) {
      console.log('⚠️ No parent accounts found with FCM tokens')
      return new Response(
        JSON.stringify({ 
          success: true, 
          sent: 0,
          message: 'No parent accounts configured or no FCM tokens registered'
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    console.log(`👨‍👩‍👧‍👦 Found ${parents.length} parent device(s)`)

    // Format timestamp
    const alertDate = new Date(alert.timestamp)
    const formattedDate = alertDate.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    })
    const formattedTime = alertDate.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    })

    // Build notification data for Flutter app to handle
    const notificationData = {
      alert_type: alert.alert_type,
      child_name: childName,
      child_phone: childPhone,
      child_user_id: alert.user_id,
      timestamp: alert.timestamp,
      formatted_date: formattedDate,
      formatted_time: formattedTime,
      latitude: alert.latitude?.toString() || '',
      longitude: alert.longitude?.toString() || '',
      address: alert.address || 'Location updating...',
      panic_alert_id: panicAlertId,
      click_action: 'FLUTTER_NOTIFICATION_CLICK'
    }

    // Build notification based on alert type
    const getNotificationConfig = (alertType: string) => {
      switch (alertType) {
        case 'CRITICAL':
          return {
            title: `🚨 CRITICAL: ${childName} Needs Help!`,
            body: `${formattedDate} at ${formattedTime}\n${alert.address || 'Location updating...'}`,
          }
        case 'REGULAR':
          return {
            title: `⚠️ Alert: ${childName} Pressed Panic Button`,
            body: `${formattedDate} at ${formattedTime}\n${alert.address || 'Location updating...'}`,
          }
        case 'CANCEL':
          return {
            title: `✅ ${childName} Cancelled Alert`,
            body: `Emergency cancelled at ${formattedTime}`,
          }
        default:
          return {
            title: `📱 Alert from ${childName}`,
            body: `${formattedDate} at ${formattedTime}`,
          }
      }
    }

    const notification = getNotificationConfig(alert.alert_type)

    // Send FCM notifications to all parent devices
    let sentCount = 0
    let failedCount = 0
    const results = []

    for (const parent of parents) {
      try {
        console.log(`📤 Sending FCM V1 to parent: ${parent.parent_first_name} (${parent.fcm_token.substring(0, 20)}...)`)
        
        // Send FCM push notification using V1 API
        const fcmResult = await sendFCMNotification(
          parent.fcm_token,
          notification.title,
          notification.body,
          notificationData,
          alert.alert_type,
          firebaseProjectId,
          accessToken
        )

        // Store notification info in database as backup
        const { error: notifError } = await supabase
          .from('parent_notifications')
          .insert({
            parent_user_id: parent.parent_user_id,
            child_user_id: alert.user_id,
            panic_alert_id: panicAlertId,  // Link to panic_alerts table
            alert_type: alert.alert_type,
            notification_title: notification.title,
            notification_body: notification.body,
            notification_data: notificationData,
            created_at: new Date().toISOString()
          })

        if (fcmResult.success) {
          console.log(`✅ FCM notification sent to ${parent.parent_first_name}`)
          sentCount++
          results.push({
            parent: `${parent.parent_first_name} ${parent.parent_last_name}`,
            status: 'sent',
          })
        } else {
          console.log(`⚠️ FCM failed, stored in DB for ${parent.parent_first_name}`)
          failedCount++
          results.push({
            parent: `${parent.parent_first_name} ${parent.parent_last_name}`,
            status: 'db_fallback',
            error: fcmResult.error
          })
        }

      } catch (error) {
        console.error(`❌ Failed to send to parent:`, error)
        failedCount++
        results.push({
          parent: `${parent.parent_first_name} ${parent.parent_last_name}`,
          status: 'failed',
          error: error instanceof Error ? error.message : 'Unknown error'
        })
      }
    }

    console.log(`📊 Results: ${sentCount} sent via FCM, ${failedCount} failed`)

    return new Response(
      JSON.stringify({
        success: true,
        sent: sentCount,
        failed: failedCount,
        total: parents.length,
        results,
        message: sentCount > 0 ? 'FCM notifications sent successfully' : 'Notifications stored in database'
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )

  } catch (error) {
    console.error('❌ Error in send-parent-alerts:', error)
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Unknown error',
        success: false
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    )
  }
})
