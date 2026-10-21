# Shared by wu-current and wu-details: API key loading, requests and errors.
# shellcheck shell=bash

key_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/wunderground.key"
api="https://api.weather.com"

# Prints {ok: false, code, error} and exits. The widget keys its setup hints
# off `code`: no-key, bad-key, no-station, no-data, network, http.
fail() {
  jq -cn --arg c "$1" --arg e "$2" '{ok: false, code: $c, error: $e}'
  exit 0
}

# Reads the API key from $WU_API_KEY or the key file into $key.
load_key() {
  key="${WU_API_KEY:-$(tr -d "[:space:]" 2>/dev/null <"$key_file")}"
  [[ -n $key ]] || fail no-key "No API key set"
}

# Normalizes a station ID; the API only matches upper case.
station_id() {
  tr '[:lower:]' '[:upper:]' <<<"${1:-}" | tr -d '[:space:]'
}

# Units code to the observation block name.
units_block() {
  case $1 in
    m) echo metric ;;
    h) echo uk_hybrid ;;
    *) echo imperial ;;
  esac
}

# GETs $api/$1 with the key appended and prints the body. The URL goes to
# curl as a config file on stdin so the key never appears in the process list.
# Sets $status to the HTTP status (000 when the request did not complete)
# and $body to the response, both for the calling script.
# shellcheck disable=SC2034
request() {
  local out
  out=$(curl -s --max-time 15 -w '\n%{http_code}' -K - <<<"url = \"$api/$1&apiKey=$key\"")
  status=${out##*$'\n'}
  body=${out%$'\n'*}
}

# Fails with a readable message for a non-200 response.
check_status() {
  case $status in
    200) ;;
    401 | 403) fail bad-key "API key was rejected" ;;
    204 | 404) fail "${1:-no-data}" "${2:-No data available}" ;;
    000) fail network "Could not reach api.weather.com" ;;
    *) fail http "Weather.com returned HTTP $status" ;;
  esac
}
