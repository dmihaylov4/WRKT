-- Migration: Refresh Real-time Publication After REPLICA IDENTITY Change
-- Description: Re-add tables to publication to ensure real-time events broadcast
-- Date: 2025-12-19

-- ============================================================================
-- PART 1: Remove and Re-add Tables to Publication
-- ============================================================================

-- Sometimes after changing REPLICA IDENTITY, the publication needs to be refreshed
-- Drop tables from publication (ignore errors if not present)
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE friendships;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

-- Wait a moment
SELECT pg_sleep(1);

-- Re-add tables to publication
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- ============================================================================
-- PART 2: Verify Publication Configuration
-- ============================================================================

-- Check that tables are back in the publication
SELECT
    schemaname,
    tablename,
    pubname
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

-- ============================================================================
-- PART 3: Check Replica Identity (Should Be FULL)
-- ============================================================================

SELECT
    c.relname AS table_name,
    CASE c.relreplident
        WHEN 'd' THEN 'DEFAULT'
        WHEN 'f' THEN 'FULL'
        WHEN 'i' THEN 'INDEX'
        WHEN 'n' THEN 'NOTHING'
    END AS replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('notifications', 'friendships')
ORDER BY c.relname;

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Real-time publication refreshed';
  RAISE NOTICE 'After running this, RESTART your app and test again';
END $$;
