-- Check what RLS policies actually exist on notifications table

SELECT
    polname AS policy_name,
    polcmd AS command,
    polroles::regrole[] AS roles,
    CASE polpermissive
        WHEN true THEN 'PERMISSIVE'
        WHEN false THEN 'RESTRICTIVE'
    END as policy_type,
    pg_get_expr(polqual, polrelid) AS using_expression,
    pg_get_expr(polwithcheck, polrelid) AS with_check_expression
FROM pg_policy
WHERE polrelid = 'notifications'::regclass
ORDER BY polcmd, polname;
