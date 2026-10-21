#!/usr/bin/env bash
# Runs scripts/wu-details against a stubbed curl and checks its JSON output.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/stub.sh
source "$root/tests/stub.sh"
run() { env WU_API_KEY=test "$root/scripts/wu-details" "$@"; }

out=$(run KXXDEMO1 e 45.1 -110.2)
check "today from latest summary" '.ok and .today.high == 71.6 and .today.low == 55.6 and .today.precipTotal == 0.12' "$out"
check "sunrise and sunset in 12-hour time" '.sunrise == "7:32 AM" and .sunset == "6:25 PM"' "$out"
check "falls back to tonight" '.days[0] | .name == "Tonight" and .high == null and .low == 49 and .phrase == "Mostly Clear"' "$out"
check "later days use the day part" '.days[1] | .name == "Wed" and .high == 76 and .precipChance == 40' "$out"

out=$(run KXXNOTREAL1 e 45.1 -110.2)
check "forecast without a station summary" '.ok and .today.high == null and (.days | length) == 2' "$out"

check "missing location" '(.ok | not) and .error == "Station location unknown"' "$(run KXXDEMO1 e)"
check "rejected key" '.code == "bad-key"' "$(STUB_STATUS=401 run KXXDEMO1 e 45.1 -110.2)"
