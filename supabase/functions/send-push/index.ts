// Supabase Edge Function to send APNs Push Notifications
// Deploy with: supabase functions deploy send-push --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// APNs configuration from environment variables
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!          // 623J5TADK8
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!        // DB7FM5537W
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY')! // Contents of .p8 file
const BUNDLE_ID = Deno.env.get('BUNDLE_ID') || 'com.dmihaylov.trak'

// APNs endpoints
const APNS_HOST_PRODUCTION = 'api.push.apple.com'
const APNS_HOST_SANDBOX = 'api.sandbox.push.apple.com'

interface PushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, unknown>
  badge?: number
  sound?: string
}

interface DeviceToken {
  id: string
  token: string
  environment: 'sandbox' | 'production'
}

// Generate JWT token for APNs authentication
async function generateAPNsToken(): Promise<string> {
  const header = {
    alg: 'ES256',
    kid: APNS_KEY_ID,
  }

  const now = Math.floor(Date.now() / 1000)
  const claims = {
    iss: APNS_TEAM_ID,
    iat: now,
  }

  // Import the private key
  const pemContents = APNS_PRIVATE_KEY
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')

  const keyData = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  // Create JWT
  const encoder = new TextEncoder()
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const claimsB64 = btoa(JSON.stringify(claims)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const unsignedToken = `${headerB64}.${claimsB64}`

  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    encoder.encode(unsignedToken)
  )

  // Convert signature from DER to raw format expected by APNs
  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')

  return `${unsignedToken}.${signatureB64}`
}

// Send push notification to a single device
async function sendToDevice(
  token: string,
  environment: 'sandbox' | 'production',
  payload: {
    title: string
    body: string
    data?: Record<string, unknown>
    badge?: number
    sound?: string
  },
  apnsToken: string
): Promise<{ success: boolean; error?: string }> {
  const host = environment === 'production' ? APNS_HOST_PRODUCTION : APNS_HOST_SANDBOX

  const apnsPayload = {
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      badge: payload.badge,
      sound: payload.sound || 'default',
      'mutable-content': 1,
    },
    ...payload.data,
  }

  try {
    const response = await fetch(`https://${host}/3/device/${token}`, {
      method: 'POST',
      headers: {
        'authorization': `bearer ${apnsToken}`,
        'apns-topic': BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-expiration': '0',
        'content-type': 'application/json',
      },
      body: JSON.stringify(apnsPayload),
    })

    if (response.ok) {
      return { success: true }
    } else {
      const errorBody = await response.text()
      console.error(`APNs error for token ${token.substring(0, 10)}...: ${response.status} ${errorBody}`)

      // If token is invalid, we should remove it from the database
      if (response.status === 410 || response.status === 400) {
        return { success: false, error: `invalid_token: ${errorBody}` }
      }

      return { success: false, error: `${response.status}: ${errorBody}` }
    }
  } catch (error) {
    console.error(`Failed to send to device: ${error}`)
    return { success: false, error: String(error) }
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // Validate required environment variables
    if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY) {
      throw new Error('Missing APNs configuration. Set APNS_KEY_ID, APNS_TEAM_ID, and APNS_PRIVATE_KEY.')
    }

    // Parse request body
    const { user_id, title, body, data, badge, sound } = await req.json() as PushRequest

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: user_id, title, body' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Fetch device tokens for the user
    const { data: tokens, error: fetchError } = await supabase
      .from('device_tokens')
      .select('id, token, environment')
      .eq('user_id', user_id)

    if (fetchError) {
      console.error('Failed to fetch device tokens:', fetchError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch device tokens', details: fetchError }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    if (!tokens || tokens.length === 0) {
      console.log(`No device tokens found for user ${user_id}`)
      return new Response(
        JSON.stringify({ success: true, sent: 0, message: 'No device tokens registered' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Generate APNs JWT token
    const apnsToken = await generateAPNsToken()

    // Send to all user's devices
    const results = await Promise.all(
      (tokens as DeviceToken[]).map(async (deviceToken) => {
        const result = await sendToDevice(
          deviceToken.token,
          deviceToken.environment,
          { title, body, data, badge, sound },
          apnsToken
        )

        // Remove invalid tokens
        if (!result.success && result.error?.startsWith('invalid_token')) {
          console.log(`Removing invalid token ${deviceToken.id}`)
          await supabase.from('device_tokens').delete().eq('id', deviceToken.id)
        }

        return { token_id: deviceToken.id, ...result }
      })
    )

    const successCount = results.filter(r => r.success).length
    const failedCount = results.filter(r => !r.success).length

    console.log(`Push notification sent to user ${user_id}: ${successCount} success, ${failedCount} failed`)

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        failed: failedCount,
        results,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in send-push function:', error)
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
