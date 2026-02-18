-- Real-time Diagnostics for Supabase
-- Run this to check why real-time events aren't being received

-- ============================================================================
-- 1. Check if tables are in the real-time publication
-- ============================================================================
SELECT
    tablename,
    schemaname
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

-- Expected: Should show 'notifications' and 'friendships'

-- ============================================================================
-- 2. Check REPLICA IDENTITY settings
-- ============================================================================
SELECT
    c.relname AS table_name,
    c.relreplident AS replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('notifications', 'friendships')
ORDER BY c.relname;

-- Expected: replica_identity should be 'f' (FULL)
-- If it shows:
--   'd' = DEFAULT (only primary key) - This won't work with filters!
--   'f' = FULL (all columns) - This is what we need!

-- ============================================================================
-- 3. Check WAL level
-- ============================================================================
SHOW wal_level;

-- Expected: 'logical' (required for real-time)

-- ============================================================================
-- 4. Check RLS policies on notifications
-- ============================================================================
SELECT
    polname AS policy_name,
    polcmd AS command,
    CASE polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        WHEN '*' THEN 'ALL'
    END AS command_type,
    pg_get_expr(polqual, polrelid) AS using_expression,
    pg_get_expr(polwithcheck, polrelid) AS with_check_expression
FROM pg_policy
WHERE polrelid = 'notifications'::regclass
ORDER BY polname;

-- Expected: Should see INSERT policies that allow authenticated users

-- ============================================================================
-- 5. Check recent notifications
-- ============================================================================
SELECT
    id,
    user_id,
    type,
    actor_id,
    created_at,
    read
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

-- ============================================================================
-- 6. Check if any real-time subscriptions exist (from Supabase side)
-- ============================================================================
SELECT
    slot_name,
    plugin,
    slot_type,
    database,
    active
FROM pg_replication_slots
WHERE slot_name LIKE '%supabase%';

-- Expected: Should show active replication slots

-- ============================================================================
-- DIAGNOSIS:
-- ============================================================================

-- If REPLICA IDENTITY is 'd' (DEFAULT):
--   → Run migration 010_fix_realtime_replica_identity.sql
--   → This is the MOST LIKELY cause

-- If wal_level is NOT 'logical':
--   → Contact Supabase support - this should be configured by default

-- If notifications table is NOT in pg_publication_tables:
--   → Run migration 008_enable_realtime_notifications.sql

-- If RLS policies are blocking:
--   → Run migration 009_fix_notification_rls_policy.sql
