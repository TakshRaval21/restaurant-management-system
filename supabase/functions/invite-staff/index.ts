// supabase/functions/invite-staff/index.ts
//
// Deploy with: supabase functions deploy invite-staff
//
// This Edge Function uses the SERVICE ROLE KEY (kept secret on server)
// to call Supabase Admin API and invite the user.
// The anon key in the Flutter app cannot do this — that's why we need this.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email, full_name, role, restaurant_id, redirect_to } = await req.json()

    if (!email || !full_name || !role || !restaurant_id) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Create admin client with SERVICE ROLE KEY (secret — never expose to client)
    const supabaseAdmin = createClient(
      'https://sikcimlkhkzhkopujhhl.supabase.co',
      Deno.env.get('SERVICE_ROLE_KEY') ?? '',
    )

    // Invite user — Supabase sends magic link email automatically
    const { data, error } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
      redirectTo: 'staffapp://login-callback',
      data: {
        full_name,       // stored in user_metadata — staff app reads this
        role,
        restaurant_id,
        password_set: false,  // staff app shows SetPasswordScreen until true
      },
    })

    if (error) {
      console.error('Invite error:', error)
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    return new Response(JSON.stringify({ success: true, user_id: data.user.id }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})