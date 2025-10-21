// ============================================================
// SOSit Parent Alert Notification - Supabase Edge Function
// ============================================================
// This function sends push notifications to parent accounts when
// their child presses the panic button.
//
// Deploy with: supabase functions deploy send-parent-alerts
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS headers for browser requests
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
    const fcmServerKey = Deno.env.get('FCM_SERVER_KEY')

    if (!fcmServerKey) {
      throw new Error('FCM_SERVER_KEY is not configured in Supabase secrets')
    }

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

    // Build notification configuration based on alert type
    const getNotificationConfig = (alertType: string) => {
      switch (alertType) {
        case 'CRITICAL':
          return {
            title: `🚨 CRITICAL: ${childName} Needs Help!`,
            body: `${formattedDate} at ${formattedTime}\n${alert.address || 'Location updating...'}`,
            priority: 'high',
            ttl: 0, // No expiration
            sound: 'emergency_alert',
            channelId: 'critical_alerts'
          }
        case 'REGULAR':
          return {
            title: `⚠️ Alert: ${childName} Pressed Panic Button`,
            body: `${formattedDate} at ${formattedTime}\n${alert.address || 'Location updating...'}`,
            priority: 'high',
            ttl: 60,
            sound: 'default',
            channelId: 'regular_alerts'
          }
        case 'CANCEL':
          return {
            title: `✅ ${childName} Cancelled Alert`,
            body: `Emergency cancelled at ${formattedTime}`,
            priority: 'normal',
            ttl: 120,
            sound: 'default',
            channelId: 'cancel_alerts'
          }
        default:
          return {
            title: `📱 Alert from ${childName}`,
            body: `${formattedDate} at ${formattedTime}`,
            priority: 'normal',
            ttl: 60,
            sound: 'default',
            channelId: 'regular_alerts'
          }
      }
    }

    const notification = getNotificationConfig(alert.alert_type)

    // Send notification to each parent device
    const sendPromises = parents.map(async (parent) => {
      const message = {
        to: parent.fcm_token,
        priority: notification.priority,
        time_to_live: notification.ttl,
        notification: {
          title: notification.title,
          body: notification.body,
          sound: notification.sound,
          badge: '1',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        data: {
          type: 'parent_alert',
          alert_id: alert.id?.toString() || '',
          alert_type: alert.alert_type,
          child_user_id: alert.user_id,
          child_name: childName,
          child_phone: childPhone,
          timestamp: alert.timestamp,
          latitude: alert.latitude?.toString() || '',
          longitude: alert.longitude?.toString() || '',
          address: alert.address || '',
          formatted_date: formattedDate,
          formatted_time: formattedTime,
          battery_level: alert.battery_level?.toString() || '',
          status: alert.status || 'ACTIVE',
        },
        android: {
          priority: notification.priority,
          notification: {
            channel_id: notification.channelId,
            sound: notification.sound,
            default_vibrate_timings: alert.alert_type === 'CRITICAL',
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: notification.title,
                body: notification.body,
              },
              sound: notification.sound,
              badge: 1,
              'content-available': 1,
            },
          },
        },
      }

      console.log(`📤 Sending to ${parent.parent_first_name} ${parent.parent_last_name} (${parent.platform})`)

      try {
        const response = await fetch('https://fcm.googleapis.com/fcm/send', {
          method: 'POST',
          headers: {
            'Authorization': `key=${fcmServerKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(message),
        })

        const result = await response.json()

        if (result.success === 1) {
          console.log(`✅ Sent to ${parent.parent_first_name} ${parent.parent_last_name}`)
        } else {
          console.error(`❌ Failed to send to ${parent.parent_first_name}:`, result)
        }

        return {
          parent_name: `${parent.parent_first_name} ${parent.parent_last_name}`,
          parent_email: parent.parent_email,
          device_id: parent.device_id,
          platform: parent.platform,
          success: result.success === 1,
          result: result,
        }
      } catch (error) {
        console.error(`❌ Error sending to ${parent.parent_first_name}:`, error)
        return {
          parent_name: `${parent.parent_first_name} ${parent.parent_last_name}`,
          parent_email: parent.parent_email,
          device_id: parent.device_id,
          platform: parent.platform,
          success: false,
          error: error.message,
        }
      }
    })

    // Wait for all notifications to complete
    const results = await Promise.all(sendPromises)
    const successCount = results.filter(r => r.success).length

    console.log(`✅ Sent ${successCount}/${parents.length} notifications successfully`)

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        total: parents.length,
        alert_type: alert.alert_type,
        child_name: childName,
        results: results,
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    )
  } catch (error) {
    console.error('❌ Error in send-parent-alerts function:', error)
    return new Response(
      JSON.stringify({ 
        success: false,
        error: error.message 
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    )
  }
})
