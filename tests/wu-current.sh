#!/usr/bin/env bash
# Runs scripts/wu-current against a stubbed curl and checks its JSON output.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/stub.sh
source "$root/tests/stub.sh"
run() { WU_API_KEY=${KEY-test} "$root/scripts/wu-current" "$@"; }

out=$(run KXXDEMO1 e)
check "imperial reading" '.ok and .temp == 48.2 and .humidity == 71 and .lat == 45.1' "$out"
check "wind chill when cold" '.feels == 45.0' "$out"

out=$(run KXXDEMO1 m)
check "metric heat index when hot" '.ok and .temp == 30.0 and .feels == 32.5' "$out"

out=$(run KXXDEMO1 h)
check "uk hybrid block with celsius thresholds" '.ok and .temp == 9.0 and .feels == 7.5' "$out"

run kxxdemo1 e >/dev/null
if grep -q 'stationId=KXXDEMO1&' <(tail -1 "$stub/requests"); then echo "ok - station id is upper-cased"; else echo "not ok - station id is upper-cased"; exit 1; fi
if grep -q 'apiKey' "$stub/args"; then echo "not ok - key stays out of argv"; exit 1; else echo "ok - key stays out of argv"; fi

check "missing station" '.code == "no-station" and .error == "No station ID set"' "$(run '' e)"
check "missing key" '.code == "no-key"' "$(KEY='' HOME=$stub XDG_CONFIG_HOME=$stub run KXXDEMO1 e)"
check "rejected key" '.code == "bad-key"' "$(STUB_STATUS=401 run KXXDEMO1 e)"
check "station not reporting" '.code == "no-station" and (.error | test("KXXNOTREAL1"))' "$(run KXXNOTREAL1 e)"
check "offline station falls back to its last report" '.ok and .stale and .temp == 64.4 and .obsTime == "2026-10-20 22:20:00" and .lat == 45.1' "$(run KXXOFFLINE1 e)"
check "current station is not stale" '.stale == false' "$(run KXXDEMO1 e)"
check "network failure" '.code == "network"' "$(STUB_STATUS=000 run KXXDEMO1 e)"
check "server error" '.code == "http" and (.error | test("503"))' "$(STUB_STATUS=503 run KXXDEMO1 e)"
