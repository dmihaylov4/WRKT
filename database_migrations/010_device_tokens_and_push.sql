-- Device Tokens Table for APNs Push Notifications
-- Run this in Supabase Dashboard → SQL Editor

-- Table to store APNs device tokens
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
    environment TEXT NOT NULL DEFAULT 'production' CHECK (environment IN ('sandbox', 'production')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,

    -- Each user can have multiple devices, but each token should be unique
    UNIQUE(token)
);

-- Indexes
CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx ON device_tokens(user_id);
CREATE INDEX IF NOT EXISTS device_tokens_token_idx ON device_tokens(token);

-- Enable RLS
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view their own device tokens
CREATE POLICY "Users can view their own device tokens"
    ON device_tokens FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own device tokens
CREATE POLICY "Users can insert their own device tokens"
    ON device_tokens FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own device tokens
CREATE POLICY "Users can update their own device tokens"
    ON device_tokens FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can delete their own device tokens
CREATE POLICY "Users can delete their own device tokens"
    ON device_tokens FOR DELETE
    USING (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_device_token_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update timestamp
DROP TRIGGER IF EXISTS update_device_tokens_timestamp ON device_tokens;
CREATE TRIGGER update_device_tokens_timestamp
    BEFORE UPDATE ON device_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_device_token_timestamp();

-- Function to upsert device token (insert or update if exists)
CREATE OR REPLACE FUNCTION upsert_device_token(
    p_user_id UUID,
    p_token TEXT,
    p_platform TEXT DEFAULT 'ios',
    p_environment TEXT DEFAULT 'production'
)
RETURNS UUID AS $$
DECLARE
    result_id UUID;
BEGIN
    INSERT INTO device_tokens (user_id, token, platform, environment)
    VALUES (p_user_id, p_token, p_platform, p_environment)
    ON CONFLICT (token) DO UPDATE SET
        user_id = p_user_id,
        platform = p_platform,
        environment = p_environment,
        updated_at = timezone('utc'::text, now())
    RETURNING id INTO result_id;

    RETURN result_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add metadata column to notifications table for push notification content
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Function to send push notification via Edge Function
-- This will be called by triggers when notifications are created
CREATE OR REPLACE FUNCTION send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    actor_name TEXT;
    notification_title TEXT;
    notification_body TEXT;
BEGIN
    -- Get actor's display name
    SELECT COALESCE(display_name, username, 'Someone') INTO actor_name
    FROM profiles
    WHERE id = NEW.actor_id;

    -- Build notification content based on type
    CASE NEW.type
        WHEN 'friend_request' THEN
            notification_title := 'New Friend Request';
            notification_body := actor_name || ' sent you a friend request';
        WHEN 'friend_accepted' THEN
            notification_title := 'Friend Request Accepted';
            notification_body := actor_name || ' accepted your friend request';
        WHEN 'post_like' THEN
            notification_title := 'New Like';
            notification_body := actor_name || ' liked your workout';
        WHEN 'post_comment' THEN
            notification_title := 'New Comment';
            notification_body := actor_name || ' commented on your workout';
        WHEN 'comment_reply' THEN
            notification_title := 'New Reply';
            notification_body := actor_name || ' replied to your comment';
        WHEN 'comment_mention' THEN
            notification_title := 'You were mentioned';
            notification_body := actor_name || ' mentioned you in a comment';
        ELSE
            notification_title := 'WRKT';
            notification_body := 'You have a new notification';
    END CASE;

    -- Call Edge Function to send push notification
    -- The Edge Function URL will be configured as a database secret
    PERFORM net.http_post(
        url := current_setting('app.settings.push_function_url', true),
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
            'user_id', NEW.user_id,
            'title', notification_title,
            'body', notification_body,
            'data', jsonb_build_object(
                'type', NEW.type,
                'notification_id', NEW.id,
                'actor_id', NEW.actor_id,
                'target_id', NEW.target_id
            )
        )
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the trigger
        RAISE WARNING 'Failed to send push notification: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: The trigger for send_push_notification will be created after
-- the Edge Function is deployed and the database secrets are configured.
--
-- To enable push notifications, run:
--
-- 1. Set database secrets:
--    ALTER DATABASE postgres SET "app.settings.push_function_url" = 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push';
--    ALTER DATABASE postgres SET "app.settings.service_role_key" = 'YOUR_SERVICE_ROLE_KEY';
--
-- 2. Enable the pg_net extension (for HTTP calls):
--    CREATE EXTENSION IF NOT EXISTS pg_net;
--
-- 3. Create the trigger:
--    CREATE TRIGGER on_notification_created_send_push
--        AFTER INSERT ON notifications
--        FOR EACH ROW
--        EXECUTE FUNCTION send_push_notification();

-- Verify tables
SELECT 'device_tokens table created' AS status
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_tokens');
