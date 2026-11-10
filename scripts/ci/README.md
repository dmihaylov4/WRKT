# Checks

Run iOS tests and an unsigned Release build with Xcode 27 and an installed iPhone simulator:

```sh
bash scripts/ci/test-ios.sh
```

The script uses the committed package lockfile and selects the newest available iPhone runtime. Override `WRKT_TEST_DESTINATION` for a specific simulator and `WRKT_BUILD_DIR` for build output. Logs and a uniquely named `.xcresult` bundle go in the build directory's `results/` folder. Verbose simulator diagnostic collection is disabled because it stalled local Xcode 27 runs; test failures still fail the command and appear in its normal results.

Run backend checks against an isolated local PostgreSQL container:

```sh
docker run --detach --name wrkt-audit-postgres --network none \
  -e POSTGRES_PASSWORD=wrkt-local-tests-only public.ecr.aws/supabase/postgres:17.6.1.166
docker exec wrkt-audit-postgres pg_isready -h 127.0.0.1 -U postgres
sh scripts/ci/test-backend.sh
```

Wait for TCP readiness before the test command. If using another container, set `WRKT_POSTGRES_CONTAINER`. The runner creates and removes its own database and temporary PostgREST container; it leaves the supplied PostgreSQL container running. It tests the deferred friendship SQL only in this disposable database. It never deploys production migrations.

Push endpoint checks:

```sh
npm exec --yes --package deno@2.9.6 -- deno test --frozen \
  --lock=supabase/functions/send-push/deno.lock supabase/functions/send-push/handler_test.ts
npm exec --yes --package deno@2.9.6 -- deno check --frozen \
  --lock=supabase/functions/send-push/deno.lock supabase/functions/send-push/index.ts
```

GitHub Actions runs these checks on pull requests, pushes to `main` and manual dispatch. The iOS job uses the [official Xcode 27 preview runner](https://github.com/actions/runner-images/issues/14404); backend setup and cleanup are automatic. Results are retained for seven days. Hosted execution has not yet been verified. Signed archives, distribution and physical iPhone/Watch validation remain separate release steps.
