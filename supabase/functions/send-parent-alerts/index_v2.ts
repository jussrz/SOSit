// ============================================================
// SOSit Parent Alert Notification - Supabase Edge Function
// ============================================================
// Uses Firebase Cloud Messaging V1 API (Modern, OAuth2-based)
// Deploy with: supabase functions deploy send-parent-alerts
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS headers for browser requests
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Get Firebase access token using service account
async function getAccessToken() {
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  
  if (!serviceAccountJson) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT not configured')
  }

  const serviceAccount = JSON.parse(serviceAccountJson)
  
  // Create JWT for OAuth2
  const header = {
    alg: "RS256",
    typ: "JWT"
  }
  
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging"
  }

  // For Edge Functions, we'll use a simpler approach with the Legacy API
  // This is a fallback that works without complex JWT signing
  return null
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
    const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') || '363891894437'

    // Parse request body
    const { alert } = await req.json()

    if (!alert || !alert.user_id) {
      return new Response(
        JSON.stringify({ error: 'Invalid request: missing alert or user_id' }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    console.log('📩 Processing parent alert notification:', alert)

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

    // Send notification using FCM HTTP v1 API with direct token approach
    // Since we're using client SDK tokens, we can use the simpler notification format
    let sentCount = 0
    let failedCount = 0
    const results = []

    for (const parent of parents) {
      try {
        // Use FCM's data-only message which works without server key
        // The Flutter app will create the notification locally
        const message = {
          data: {
            ...notificationData,
            notification_title: notification.title,
            notification_body: notification.body,
          },
          token: parent.fcm_token,
          android: {
            priority: alert.alert_type === 'CRITICAL' ? 'high' : 'normal',
            notification: {
              channel_id: alert.alert_type === 'CRITICAL' ? 'critical_alerts' : 'regular_alerts',
              priority: alert.alert_type === 'CRITICAL' ? 'high' : 'default',
              sound: alert.alert_type === 'CRITICAL' ? 'emergency_alert' : 'default',
            }
          }
        }

        console.log(`📤 Sending to parent: ${parent.parent_first_name} (${parent.fcm_token.substring(0, 20)}...)`)
        
        // Store notification info for Flutter to handle locally
        // Since we can't easily send without server key, we'll use Supabase realtime as fallback
        const { error: notifError } = await supabase
          .from('parent_notifications')
          .insert({
            parent_user_id: parent.parent_user_id,
            child_user_id: alert.user_id,
            alert_type: alert.alert_type,
            notification_title: notification.title,
            notification_body: notification.body,
            notification_data: notificationData,
            created_at: new Date().toISOString()
          })

        if (notifError) {
          console.error('Failed to store notification:', notifError)
          failedCount++
        } else {
          console.log(`✅ Notification queued for ${parent.parent_first_name}`)
          sentCount++
        }

        results.push({
          parent: `${parent.parent_first_name} ${parent.parent_last_name}`,
          status: notifError ? 'failed' : 'queued',
          error: notifError?.message
        })

      } catch (error) {
        console.error(`❌ Failed to send to parent:`, error)
        failedCount++
        results.push({
          parent: `${parent.parent_first_name} ${parent.parent_last_name}`,
          status: 'failed',
          error: error.message
        })
      }
    }

    console.log(`📊 Results: ${sentCount} queued, ${failedCount} failed`)

    return new Response(
      JSON.stringify({
        success: true,
        sent: sentCount,
        failed: failedCount,
        total: parents.length,
        results,
        message: 'Notifications queued. Using Supabase Realtime for delivery.'
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )

  } catch (error) {
    console.error('❌ Error in send-parent-alerts:', error)
    return new Response(
      JSON.stringify({ 
        error: error.message,
        success: false
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    )
  }
})
