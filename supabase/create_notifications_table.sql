-- Create Notifications Table for Activity Feed
-- Run this in Supabase Dashboard → SQL Editor

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('friend_request', 'friend_accepted', 'post_like', 'post_comment', 'comment_reply', 'comment_mention')),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    target_id UUID, -- ID of the post, friendship, etc.
    read BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON notifications(user_id);
CREATE INDEX IF NOT EXISTS notifications_read_idx ON notifications(read);
CREATE INDEX IF NOT EXISTS notifications_created_at_idx ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_type_idx ON notifications(type);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can only see their own notifications
CREATE POLICY "Users can view their own notifications"
    ON notifications FOR SELECT
    USING (auth.uid() = user_id);

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update their own notifications"
    ON notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- System can insert notifications for any user
-- (This will be used by database triggers)
CREATE POLICY "System can insert notifications"
    ON notifications FOR INSERT
    WITH CHECK (true);

-- Users can delete their own notifications
CREATE POLICY "Users can delete their own notifications"
    ON notifications FOR DELETE
    USING (auth.uid() = user_id);

-- Function to create friend request notification
CREATE OR REPLACE FUNCTION create_friend_request_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Only create notification for new pending friendships
    IF NEW.status = 'pending' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.friend_id, 'friend_request', NEW.user_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for friend request notifications
DROP TRIGGER IF EXISTS on_friend_request_created ON friendships;
CREATE TRIGGER on_friend_request_created
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_request_notification();

-- Function to create friend accepted notification
CREATE OR REPLACE FUNCTION create_friend_accepted_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Only create notification when friendship is accepted
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        -- Notify the original requester that their request was accepted
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.user_id, 'friend_accepted', NEW.friend_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for friend accepted notifications
DROP TRIGGER IF EXISTS on_friend_request_accepted ON friendships;
CREATE TRIGGER on_friend_request_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_accepted_notification();

-- Function to create post like notification
CREATE OR REPLACE FUNCTION create_post_like_notification()
RETURNS TRIGGER AS $$
DECLARE
    post_author_id UUID;
BEGIN
    -- Get the post author's user_id
    SELECT user_id INTO post_author_id
    FROM workout_posts
    WHERE id = NEW.post_id;

    -- Only create notification if someone else liked your post (not yourself)
    IF post_author_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (post_author_id, 'post_like', NEW.user_id, NEW.post_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for post like notifications
DROP TRIGGER IF EXISTS on_post_liked ON post_likes;
CREATE TRIGGER on_post_liked
    AFTER INSERT ON post_likes
    FOR EACH ROW
    EXECUTE FUNCTION create_post_like_notification();

-- Function to create comment notification
CREATE OR REPLACE FUNCTION create_comment_notification()
RETURNS TRIGGER AS $$
DECLARE
    post_author_id UUID;
BEGIN
    -- Get the post author's user_id
    SELECT user_id INTO post_author_id
    FROM workout_posts
    WHERE id = NEW.post_id;

    -- Only create notification if someone else commented (not yourself)
    IF post_author_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (post_author_id, 'post_comment', NEW.user_id, NEW.post_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for comment notifications
DROP TRIGGER IF EXISTS on_post_commented ON post_comments;
CREATE TRIGGER on_post_commented
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION create_comment_notification();

-- Verify the table was created
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'notifications'
ORDER BY ordinal_position;

-- Verify triggers were created
SELECT
    trigger_name,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('friendships', 'post_likes', 'post_comments');
