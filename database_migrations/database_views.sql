-- Database Views for Query Optimization
-- Created: 2025-12-11
-- Purpose: Pre-join frequently accessed data to reduce query complexity

-- ============================================================================
-- View: v_feed_posts
-- Purpose: Pre-joined workout posts with author profiles and counts
-- Usage: SELECT * FROM v_feed_posts WHERE visibility IN ('public', 'friends')
-- ============================================================================

CREATE OR REPLACE VIEW v_feed_posts AS
SELECT
    p.id,
    p.user_id,
    p.workout_data,
    p.caption,
    p.image_urls,
    p.visibility,
    p.created_at,
    p.updated_at,
    p.likes_count,
    p.comments_count,
    -- Author profile data
    u.username as author_username,
    u.display_name as author_display_name,
    u.avatar_url as author_avatar_url,
    u.is_private as author_is_private
FROM workout_posts p
INNER JOIN profiles u ON p.user_id = u.id
ORDER BY p.created_at DESC;

COMMENT ON VIEW v_feed_posts IS 'Pre-joined posts with author profiles for feed queries';

-- ============================================================================
-- View: v_notifications_with_actors
-- Purpose: Pre-joined notifications with actor profiles
-- Usage: SELECT * FROM v_notifications_with_actors WHERE user_id = ?
-- ============================================================================

CREATE OR REPLACE VIEW v_notifications_with_actors AS
SELECT
    n.id,
    n.user_id,
    n.actor_id,
    n.type,
    n.target_id,
    n.read,
    n.created_at,
    -- Actor profile data
    a.username as actor_username,
    a.display_name as actor_display_name,
    a.avatar_url as actor_avatar_url
FROM notifications n
INNER JOIN profiles a ON n.actor_id = a.id
ORDER BY n.created_at DESC;

COMMENT ON VIEW v_notifications_with_actors IS 'Pre-joined notifications with actor profiles';

-- ============================================================================
-- View: v_friends_list
-- Purpose: Pre-joined friendships with friend profiles (accepted only)
-- Usage: SELECT * FROM v_friends_list WHERE user_id = ?
-- ============================================================================

CREATE OR REPLACE VIEW v_friends_list AS
SELECT
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    f.created_at,
    f.updated_at,
    -- Friend profile data
    p.username as friend_username,
    p.display_name as friend_display_name,
    p.avatar_url as friend_avatar_url,
    p.is_private as friend_is_private
FROM friendships f
INNER JOIN profiles p ON f.friend_id = p.id
WHERE f.status = 'accepted'
ORDER BY p.display_name ASC;

COMMENT ON VIEW v_friends_list IS 'Accepted friendships with friend profiles';

-- ============================================================================
-- View: v_friend_requests_incoming
-- Purpose: Incoming friend requests with requester profiles
-- Usage: SELECT * FROM v_friend_requests_incoming WHERE friend_id = ?
-- ============================================================================

CREATE OR REPLACE VIEW v_friend_requests_incoming AS
SELECT
    f.id,
    f.user_id as requester_id,
    f.friend_id as recipient_id,
    f.status,
    f.created_at,
    -- Requester profile data
    p.username as requester_username,
    p.display_name as requester_display_name,
    p.avatar_url as requester_avatar_url
FROM friendships f
INNER JOIN profiles p ON f.user_id = p.id
WHERE f.status = 'pending'
ORDER BY f.created_at DESC;

COMMENT ON VIEW v_friend_requests_incoming IS 'Pending incoming friend requests with requester profiles';

-- ============================================================================
-- View: v_friend_requests_outgoing
-- Purpose: Outgoing friend requests with recipient profiles
-- Usage: SELECT * FROM v_friend_requests_outgoing WHERE user_id = ?
-- ============================================================================

CREATE OR REPLACE VIEW v_friend_requests_outgoing AS
SELECT
    f.id,
    f.user_id as requester_id,
    f.friend_id as recipient_id,
    f.status,
    f.created_at,
    -- Recipient profile data
    p.username as recipient_username,
    p.display_name as recipient_display_name,
    p.avatar_url as recipient_avatar_url
FROM friendships f
INNER JOIN profiles p ON f.friend_id = p.id
WHERE f.status = 'pending'
ORDER BY f.created_at DESC;

COMMENT ON VIEW v_friend_requests_outgoing IS 'Pending outgoing friend requests with recipient profiles';

-- ============================================================================
-- View: v_post_details
-- Purpose: Complete post details with author, likes, comments for detail view
-- Usage: SELECT * FROM v_post_details WHERE id = ?
-- ============================================================================

CREATE OR REPLACE VIEW v_post_details AS
SELECT
    p.id,
    p.user_id,
    p.workout_data,
    p.caption,
    p.image_urls,
    p.visibility,
    p.created_at,
    p.updated_at,
    p.likes_count,
    p.comments_count,
    -- Author profile
    u.username as author_username,
    u.display_name as author_display_name,
    u.avatar_url as author_avatar_url,
    u.is_private as author_is_private,
    -- Aggregated data
    COALESCE(
        (
            SELECT json_agg(json_build_object(
                'user_id', pl.user_id,
                'username', pu.username,
                'display_name', pu.display_name,
                'avatar_url', pu.avatar_url
            ))
            FROM post_likes pl
            INNER JOIN profiles pu ON pl.user_id = pu.id
            WHERE pl.post_id = p.id
            LIMIT 10
        ),
        '[]'::json
    ) as recent_likes
FROM workout_posts p
INNER JOIN profiles u ON p.user_id = u.id;

COMMENT ON VIEW v_post_details IS 'Complete post details with author and recent likes for detail view';

-- ============================================================================
-- Materialized View: v_user_stats (Refresh manually for performance)
-- Purpose: Pre-calculated user statistics
-- Usage: SELECT * FROM v_user_stats WHERE user_id = ?
-- Note: Requires manual refresh: REFRESH MATERIALIZED VIEW v_user_stats;
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS v_user_stats AS
SELECT
    u.id as user_id,
    u.username,
    u.display_name,
    u.avatar_url,
    -- Post count
    COALESCE(
        (SELECT COUNT(*) FROM workout_posts WHERE user_id = u.id),
        0
    ) as posts_count,
    -- Friend count (accepted only)
    COALESCE(
        (
            SELECT COUNT(*)
            FROM friendships
            WHERE (user_id = u.id OR friend_id = u.id)
            AND status = 'accepted'
        ),
        0
    ) as friends_count,
    -- Total likes received
    COALESCE(
        (
            SELECT COUNT(*)
            FROM post_likes pl
            INNER JOIN workout_posts p ON pl.post_id = p.id
            WHERE p.user_id = u.id
        ),
        0
    ) as total_likes_received,
    -- Last post date
    (
        SELECT MAX(created_at)
        FROM workout_posts
        WHERE user_id = u.id
    ) as last_post_date
FROM profiles u;

CREATE UNIQUE INDEX IF NOT EXISTS v_user_stats_user_id_idx ON v_user_stats(user_id);

COMMENT ON MATERIALIZED VIEW v_user_stats IS 'Pre-calculated user statistics (refresh manually)';

-- ============================================================================
-- Functions for materialized view refresh
-- ============================================================================

-- Function to refresh user stats (call this after major changes)
CREATE OR REPLACE FUNCTION refresh_user_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY v_user_stats;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_user_stats() IS 'Refresh user statistics materialized view';

-- ============================================================================
-- Grants (ensure RLS policies still apply)
-- ============================================================================

GRANT SELECT ON v_feed_posts TO authenticated;
GRANT SELECT ON v_notifications_with_actors TO authenticated;
GRANT SELECT ON v_friends_list TO authenticated;
GRANT SELECT ON v_friend_requests_incoming TO authenticated;
GRANT SELECT ON v_friend_requests_outgoing TO authenticated;
GRANT SELECT ON v_post_details TO authenticated;
GRANT SELECT ON v_user_stats TO authenticated;

-- ============================================================================
-- Usage Examples
-- ============================================================================

-- Example 1: Fetch feed with authors (replaces join in client)
-- SELECT * FROM v_feed_posts
-- WHERE visibility IN ('public', 'friends')
-- AND created_at < '2025-12-11T10:00:00Z'
-- ORDER BY created_at DESC
-- LIMIT 20;

-- Example 2: Fetch notifications with actors (replaces join in client)
-- SELECT * FROM v_notifications_with_actors
-- WHERE user_id = 'user-uuid-here'
-- AND read = false
-- ORDER BY created_at DESC;

-- Example 3: Fetch friends list (replaces join in client)
-- SELECT * FROM v_friends_list
-- WHERE user_id = 'user-uuid-here';

-- Example 4: Get user stats (instant, pre-calculated)
-- SELECT * FROM v_user_stats WHERE user_id = 'user-uuid-here';
