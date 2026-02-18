-- Database Indexes for Query Optimization
-- Created: 2025-12-11
-- Purpose: Optimize frequently used queries with strategic indexes

-- ============================================================================
-- WORKOUT_POSTS Indexes
-- ============================================================================

-- Index for feed queries (ordered by created_at DESC, filtered by visibility)
CREATE INDEX IF NOT EXISTS idx_workout_posts_feed
ON workout_posts(created_at DESC, visibility)
WHERE visibility IN ('public', 'friends');

COMMENT ON INDEX idx_workout_posts_feed IS 'Optimize feed queries with created_at DESC and visibility filter';

-- Index for user's posts
CREATE INDEX IF NOT EXISTS idx_workout_posts_user
ON workout_posts(user_id, created_at DESC);

COMMENT ON INDEX idx_workout_posts_user IS 'Optimize queries for specific user posts';

-- Index for cursor-based pagination
CREATE INDEX IF NOT EXISTS idx_workout_posts_pagination
ON workout_posts(created_at DESC, id);

COMMENT ON INDEX idx_workout_posts_pagination IS 'Optimize cursor-based pagination queries';

-- ============================================================================
-- POST_LIKES Indexes
-- ============================================================================

-- Composite index for checking if user liked a post
CREATE INDEX IF NOT EXISTS idx_post_likes_user_post
ON post_likes(user_id, post_id);

COMMENT ON INDEX idx_post_likes_user_post IS 'Optimize checking if user liked specific posts';

-- Index for post likes (for fetching who liked a post)
CREATE INDEX IF NOT EXISTS idx_post_likes_post
ON post_likes(post_id, created_at DESC);

COMMENT ON INDEX idx_post_likes_post IS 'Optimize fetching likes for a post';

-- Index for user's likes (for activity feed)
CREATE INDEX IF NOT EXISTS idx_post_likes_user
ON post_likes(user_id, created_at DESC);

COMMENT ON INDEX idx_post_likes_user IS 'Optimize fetching user activity';

-- ============================================================================
-- POST_COMMENTS Indexes
-- ============================================================================

-- Index for post comments (ordered by created_at)
CREATE INDEX IF NOT EXISTS idx_post_comments_post
ON post_comments(post_id, created_at DESC);

COMMENT ON INDEX idx_post_comments_post IS 'Optimize fetching comments for a post';

-- Index for user's comments
CREATE INDEX IF NOT EXISTS idx_post_comments_user
ON post_comments(user_id, created_at DESC);

COMMENT ON INDEX idx_post_comments_user IS 'Optimize fetching user comment activity';

-- ============================================================================
-- NOTIFICATIONS Indexes
-- ============================================================================

-- Primary index for user notifications (filtered by read status)
CREATE INDEX IF NOT EXISTS idx_notifications_user_read
ON notifications(user_id, read, created_at DESC);

COMMENT ON INDEX idx_notifications_user_read IS 'Optimize fetching unread notifications for user';

-- Index for notification type filtering
CREATE INDEX IF NOT EXISTS idx_notifications_type
ON notifications(user_id, type, created_at DESC);

COMMENT ON INDEX idx_notifications_type IS 'Optimize filtering notifications by type';

-- Index for actor's notifications (for activity tracking)
CREATE INDEX IF NOT EXISTS idx_notifications_actor
ON notifications(actor_id, created_at DESC);

COMMENT ON INDEX idx_notifications_actor IS 'Optimize fetching notifications created by actor';

-- ============================================================================
-- FRIENDSHIPS Indexes
-- ============================================================================

-- Index for user's friends (filtered by status)
CREATE INDEX IF NOT EXISTS idx_friendships_user_status
ON friendships(user_id, status);

COMMENT ON INDEX idx_friendships_user_status IS 'Optimize fetching friends by status';

-- Index for friend's friendships (reverse lookup)
CREATE INDEX IF NOT EXISTS idx_friendships_friend_status
ON friendships(friend_id, status);

COMMENT ON INDEX idx_friendships_friend_status IS 'Optimize reverse friend lookup';

-- Composite index for checking friendship existence
CREATE INDEX IF NOT EXISTS idx_friendships_pair
ON friendships(user_id, friend_id, status);

COMMENT ON INDEX idx_friendships_pair IS 'Optimize checking friendship status between two users';

-- Index for pending requests
CREATE INDEX IF NOT EXISTS idx_friendships_pending
ON friendships(created_at DESC)
WHERE status = 'pending';

COMMENT ON INDEX idx_friendships_pending IS 'Optimize fetching recent pending requests';

-- ============================================================================
-- PROFILES Indexes
-- ============================================================================

-- Index for username search (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_profiles_username_search
ON profiles(LOWER(username) text_pattern_ops);

COMMENT ON INDEX idx_profiles_username_search IS 'Optimize case-insensitive username search';

-- Index for display name search (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_profiles_display_name_search
ON profiles(LOWER(display_name) text_pattern_ops);

COMMENT ON INDEX idx_profiles_display_name_search IS 'Optimize case-insensitive display name search';

-- Index for non-private profiles (for search)
CREATE INDEX IF NOT EXISTS idx_profiles_public
ON profiles(created_at DESC)
WHERE is_private = false;

COMMENT ON INDEX idx_profiles_public IS 'Optimize searching public profiles';

-- ============================================================================
-- Performance Analysis Queries
-- ============================================================================

-- Check index usage
-- SELECT
--     schemaname,
--     tablename,
--     indexname,
--     idx_scan as index_scans,
--     idx_tup_read as tuples_read,
--     idx_tup_fetch as tuples_fetched
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'public'
-- ORDER BY idx_scan DESC;

-- Find unused indexes
-- SELECT
--     schemaname,
--     tablename,
--     indexname,
--     idx_scan
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'public'
-- AND idx_scan = 0
-- AND indexname NOT LIKE '%_pkey'
-- ORDER BY relname, indexname;

-- Table sizes
-- SELECT
--     tablename,
--     pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
-- FROM pg_tables
-- WHERE schemaname = 'public'
-- ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ============================================================================
-- Index Maintenance
-- ============================================================================

-- Analyze tables to update statistics (run periodically)
-- ANALYZE workout_posts;
-- ANALYZE post_likes;
-- ANALYZE post_comments;
-- ANALYZE notifications;
-- ANALYZE friendships;
-- ANALYZE profiles;

-- Reindex if indexes become bloated (run if performance degrades)
-- REINDEX TABLE workout_posts;
-- REINDEX TABLE post_likes;
-- REINDEX TABLE post_comments;
-- REINDEX TABLE notifications;
-- REINDEX TABLE friendships;
-- REINDEX TABLE profiles;

-- ============================================================================
-- Query Examples Using Indexes
-- ============================================================================

-- Example 1: Feed query (uses idx_workout_posts_feed)
-- EXPLAIN ANALYZE
-- SELECT * FROM workout_posts
-- WHERE visibility IN ('public', 'friends')
-- AND created_at < '2025-12-11T10:00:00Z'
-- ORDER BY created_at DESC
-- LIMIT 20;

-- Example 2: Check if user liked posts (uses idx_post_likes_user_post)
-- EXPLAIN ANALYZE
-- SELECT post_id FROM post_likes
-- WHERE user_id = 'user-uuid'
-- AND post_id IN ('post1-uuid', 'post2-uuid', 'post3-uuid');

-- Example 3: Fetch unread notifications (uses idx_notifications_user_read)
-- EXPLAIN ANALYZE
-- SELECT * FROM notifications
-- WHERE user_id = 'user-uuid'
-- AND read = false
-- ORDER BY created_at DESC
-- LIMIT 50;

-- Example 4: Check friendship status (uses idx_friendships_pair)
-- EXPLAIN ANALYZE
-- SELECT status FROM friendships
-- WHERE user_id = 'user1-uuid'
-- AND friend_id = 'user2-uuid';

-- Example 5: Search usernames (uses idx_profiles_username_search)
-- EXPLAIN ANALYZE
-- SELECT * FROM profiles
-- WHERE LOWER(username) LIKE LOWER('john%')
-- AND is_private = false
-- LIMIT 20;
