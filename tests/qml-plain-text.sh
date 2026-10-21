#!/usr/bin/env bash
# Every QML Text must set textFormat explicitly. Qt's default (AutoText)
# renders strings that look like markup as rich text, so station names and
# forecast text from the API could inject markup, including remote images.
# StyledText is allowed only for static strings: no property bindings.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
status=0

for file in "$root"/*.qml; do
  # Prints "line:format:dynamic" for each Text element, where format is the
  # element's own textFormat (or "none") and dynamic is 1 when its text
  # references anything other than string literals.
  while IFS=: read -r line format dynamic; do
    name="$(basename "$file"):$line"
    if [[ $format == none ]]; then
      echo "not ok - $name: Text without textFormat"
      status=1
    elif [[ $format != Text.PlainText && $dynamic == 1 ]]; then
      echo "not ok - $name: $format with non-literal text"
      status=1
    fi
  done < <(awk '
    function finish() {
      if (start) print start ":" (format ? format : "none") ":" dynamic
      start = 0
    }
    /^[[:space:]]*Text \{[[:space:]]*$/ { finish(); start = NR; depth = 0; format = ""; dynamic = 0; intext = 0 }
    start && /^[[:space:]]*\/\// { next }
    start {
      # Only properties directly on this element (depth 1) count.
      if (depth == 1 && $1 == "textFormat:") format = $2
      if (depth == 1 && $1 == "text:") intext = 1
      else if (depth == 1 && $1 ~ /^[a-zA-Z.]+:$/) intext = 0
      if (intext) {
        line = $0
        sub(/^[[:space:]]*text:/, "", line)
        gsub(/"([^"\\]|\\.)*"/, "", line)
        gsub(/[[:space:]+]/, "", line)
        if (line != "") dynamic = 1
      }
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0) finish()
    }
  ' "$file")
done

if (( status == 0 )); then echo "ok - every Text sets textFormat; StyledText is static"; fi
exit $status
