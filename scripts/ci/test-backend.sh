#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
container="${WRKT_POSTGRES_CONTAINER:-wrkt-audit-postgres}"
database="wrkt_security_test_$$"

cleanup() { docker exec "$container" dropdb -U postgres --if-exists "$database" >/dev/null; }
trap cleanup EXIT
docker exec "$container" createdb -U postgres "$database"

apply_sql() { docker exec -i "$container" psql -X -U postgres -d "$database" -v ON_ERROR_STOP=1 -q < "$1"; }
apply_sql supabase/tests/security_fixture.sql
apply_sql supabase/tests/notification_fixture.sql
apply_sql supabase/migrations/20260930145812_secure_device_token_registration.sql
apply_sql supabase/migrations/20260930145835_enforce_friendship_consent.sql
apply_sql supabase/migrations/20260930145841_shared_post_optional_arguments.sql
apply_sql supabase/migrations/20260930145918_dedicated_push_dispatch_credential.sql
apply_sql supabase/migrations/20260930151440_secure_virtual_run_results.sql
apply_sql supabase/migrations/20260930151446_restrict_avatar_mutations.sql
apply_sql supabase/migrations/20260930152340_trusted_notifications.sql
# Expand the one relative include before streaming this transaction into Docker.
{
    sed '/^\\ir /,$d' supabase/tests/legacy_consent_regressions.sql
    cat supabase/deferred/20260930153324_require_legacy_friendship_reconfirmation.sql
    sed '1,/^\\ir /d' supabase/tests/legacy_consent_regressions.sql
} | docker exec -i "$container" psql -X -U postgres -d "$database" -v ON_ERROR_STOP=1 -q
apply_sql supabase/deferred/20260930153324_require_legacy_friendship_reconfirmation.sql
apply_sql supabase/tests/security_regressions.sql
apply_sql supabase/tests/shared_post_regressions.sql
apply_sql supabase/tests/virtual_run_regressions.sql
apply_sql supabase/tests/avatar_regressions.sql
apply_sql supabase/tests/notification_regressions.sql
python3 scripts/ci/test-shared-post-api.py "$container" "$database"
