# Push Notifications Setup Guide

This guide explains how to set up APNs push notifications for WRKT.

## Prerequisites

- APNs Key (`.p8` file) from Apple Developer Portal
- Key ID: `623J5TADK8`
- Team ID: `DB7FM5537W`
- Supabase project with Edge Functions enabled

## Step 1: Run Database Migration

In Supabase Dashboard → SQL Editor, run the migration file:

```
database_migrations/010_device_tokens_and_push.sql
```

This creates:
- `device_tokens` table to store APNs tokens
- `upsert_device_token` function for upserting tokens
- `send_push_notification` function (trigger-ready)

## Step 2: Deploy Supabase Edge Function

### 2.1 Install Supabase CLI (if not already installed)

```bash
brew install supabase/tap/supabase
```

### 2.2 Login to Supabase

```bash
supabase login
```

### 2.3 Link to your project

```bash
cd /Users/dimitarmihaylov/dev/WRKT
supabase link --project-ref YOUR_PROJECT_REF
```

### 2.4 Set APNs secrets

```bash
# Read your .p8 key file content
APNS_KEY=$(cat AuthKey_623J5TADK8.p8)

# Set secrets
supabase secrets set APNS_KEY_ID=623J5TADK8
supabase secrets set APNS_TEAM_ID=DB7FM5537W
supabase secrets set APNS_PRIVATE_KEY="$APNS_KEY"
supabase secrets set BUNDLE_ID=com.dmihaylov.trak
```

### 2.5 Deploy the function

```bash
supabase functions deploy send-push --no-verify-jwt
```

## Step 3: Enable pg_net Extension (for database triggers)

In Supabase Dashboard → SQL Editor:

```sql
-- Enable pg_net extension for HTTP calls from triggers
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
```

## Step 4: Configure Database Settings

In Supabase Dashboard → SQL Editor:

```sql
-- Set the Edge Function URL
ALTER DATABASE postgres SET "app.settings.push_function_url" = 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push';

-- Set the service role key (get from Supabase Dashboard → Settings → API)
ALTER DATABASE postgres SET "app.settings.service_role_key" = 'YOUR_SERVICE_ROLE_KEY';
```

## Step 5: Create the Notification Trigger

In Supabase Dashboard → SQL Editor:

```sql
-- Create trigger to send push notifications when notifications are created
DROP TRIGGER IF EXISTS on_notification_created_send_push ON notifications;
CREATE TRIGGER on_notification_created_send_push
    AFTER INSERT ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION send_push_notification();
```

## Step 6: Test Push Notifications

### Manual Test via Edge Function

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "YOUR_USER_UUID",
    "title": "Test Notification",
    "body": "This is a test push notification"
  }'
```

### Check Device Tokens

```sql
SELECT * FROM device_tokens ORDER BY created_at DESC LIMIT 10;
```

## Troubleshooting

### No device token registered
- Make sure the app has notification permissions
- Check that the user is logged in
- Look for "Registered for remote notifications" in app logs

### Push not delivered
- Check the Edge Function logs in Supabase Dashboard
- Verify the APNs environment (sandbox vs production)
- For TestFlight/Dev builds, use `sandbox` environment
- For App Store builds, use `production` environment

### Invalid token errors
- Token may be expired or from wrong environment
- The system automatically cleans up invalid tokens

## iOS Build Settings

The app needs the Push Notifications capability enabled:

1. In Xcode → Select WRKT target
2. Signing & Capabilities → + Capability
3. Add "Push Notifications"

The entitlement file should have:
```xml
<key>aps-environment</key>
<string>development</string>
```

For production builds, Xcode automatically changes this to `production`.

## Architecture Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   iOS App   │───▶│  Supabase   │───▶│    APNs     │
│             │    │   Database  │    │   (Apple)   │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       │ 1. Register      │ 3. Trigger       │ 4. Push
       │    token         │    Edge Fn       │    notification
       ▼                  ▼                  ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   device_   │    │   send-push │    │   User's    │
│   tokens    │    │   function  │───▶│   Device    │
└─────────────┘    └─────────────┘    └─────────────┘
```

1. iOS app registers with APNs and saves device token to `device_tokens` table
2. When a notification is created (friend request, like, etc.), database trigger fires
3. Trigger calls `send-push` Edge Function via HTTP
4. Edge Function sends push to APNs
5. APNs delivers to user's device
