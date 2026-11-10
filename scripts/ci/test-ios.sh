#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

build_dir="${WRKT_BUILD_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wrkt-ci}"
mkdir -p "$build_dir/results"
result_bundle="$build_dir/results/tests-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"

if [ -n "${WRKT_TEST_DESTINATION:-}" ]; then
    destination="$WRKT_TEST_DESTINATION"
else
    simulator_id=$(python3 - <<'PY'
import json, subprocess
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
candidates = []
for runtime, entries in devices['devices'].items():
    if '.iOS-' not in runtime:
        continue
    version = tuple(map(int, runtime.split('.iOS-')[1].split('-')))
    for device in entries:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            candidates.append((version, device['name'], device['udid']))
if not candidates:
    raise SystemExit('No available iPhone simulator; install an iOS runtime or set WRKT_TEST_DESTINATION.')
print(max(candidates)[2])
PY
)
    destination="platform=iOS Simulator,id=$simulator_id"
fi

xcodebuild -version
xcodebuild -resolvePackageDependencies -project WRKT.xcodeproj -scheme WRKT \
    -derivedDataPath "$build_dir" -onlyUsePackageVersionsFromResolvedFile \
    | tee "$build_dir/results/packages.log"

xcodebuild test -project WRKT.xcodeproj -scheme WRKT -destination "$destination" \
    -derivedDataPath "$build_dir" -disableAutomaticPackageResolution \
    -onlyUsePackageVersionsFromResolvedFile -only-testing:WRKTTests \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -resultBundlePath "$result_bundle" CODE_SIGNING_ALLOWED=NO \
    | tee "$build_dir/results/tests.log"

xcodebuild build -project WRKT.xcodeproj -scheme WRKT -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$build_dir" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO \
    | tee "$build_dir/results/release.log"
