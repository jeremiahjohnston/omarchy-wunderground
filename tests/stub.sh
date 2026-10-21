# Shared by the tests: a fake curl on $PATH. The scripts pass the URL as a
# curl config on stdin and append the HTTP status with -w, so the stub reads
# the URL from stdin and answers with a body and a status per endpoint.
# STUB_STATUS overrides the status for every request.
# shellcheck shell=bash

stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT

cat >"$stub/curl" <<'STUB'
#!/usr/bin/env bash
config=$(cat)
printf '%s\n' "$config" >>"$(dirname "$0")/requests"
printf '%s\n' "$*" >>"$(dirname "$0")/args"
respond() { printf '%s\n%s' "$1" "${STUB_STATUS:-$2}"; }
case "$config" in
  *stationId=KXXNOTREAL1*) respond '' 204 ;;
  *current?stationId=KXXOFFLINE1*) respond '' 204 ;;
  *all/1day?stationId=KXXOFFLINE1*) respond '{"observations":[{"stationID":"KXXOFFLINE1","obsTimeLocal":"2026-10-20 21:00:00","humidityAvg":80,"winddirAvg":90,"uvHigh":0,"solarRadiationHigh":0,"lat":45.1,"lon":-110.2,
    "imperial":{"tempAvg":50.0}},{"stationID":"KXXOFFLINE1","obsTimeLocal":"2026-10-20 22:20:00","humidityAvg":59,"winddirAvg":86,"uvHigh":0,"solarRadiationHigh":0,"lat":45.1,"lon":-110.2,
    "imperial":{"tempAvg":64.4,"heatindexAvg":64.4,"windchillAvg":64.4,"dewptAvg":49.8,"windspeedAvg":0.6,"windgustHigh":1.3,"pressureMax":30.22,"precipTotal":0.0}}]}' 200 ;;
  *observations/current*) respond '{"observations":[{"stationID":"KXXDEMO1","obsTimeLocal":"2026-10-20 22:40:00","neighborhood":"Cedar Hollow","humidity":71,"winddir":225,"lat":45.1,"lon":-110.2,
    "imperial":{"temp":48.2,"heatIndex":48.2,"dewpt":39.1,"windChill":45.0,"windSpeed":6.0,"windGust":11.0,"pressure":30.02,"precipTotal":0.0},
    "metric":{"temp":30.0,"heatIndex":32.5,"dewpt":4.0,"windChill":30.0,"windSpeed":9.7,"windGust":17.7,"pressure":1016.6,"precipTotal":0.0},
    "uk_hybrid":{"temp":9.0,"heatIndex":9.0,"dewpt":4.0,"windChill":7.5,"windSpeed":6.0,"windGust":11.0,"pressure":1016.6,"precipTotal":0.0}}]}' 200 ;;
  *dailysummary*) respond '{"summaries":[{"imperial":{"tempHigh":60.1}},{"imperial":{"tempHigh":71.6,"tempLow":55.6,"precipTotal":0.12,"windgustHigh":9.0,"pressureTrend":-0.02}}]}' 200 ;;
  *forecast/daily*) respond '{"dayOfWeek":["Tuesday","Wednesday"],"temperatureMax":[null,76],"temperatureMin":[49,50],
    "sunriseTimeLocal":["2026-10-20T07:32:00-0500","2026-10-21T07:33:00-0500"],
    "sunsetTimeLocal":["2026-10-20T18:25:00-0500","2026-10-21T18:24:00-0500"],
    "daypart":[{"daypartName":[null,"Tonight","Tomorrow","Tomorrow night"],"wxPhraseLong":[null,"Mostly Clear","Partly Cloudy","Clear"],
    "precipChance":[null,7,40,5],"narrative":[null,"Low 49F.","High 76F.","Low 50F."]}]}' 200 ;;
  *) respond '' 000 ;;
esac
STUB
chmod +x "$stub/curl"
export PATH="$stub:$PATH"

check() {
  local name=$1 filter=$2 out=$3
  if jq -e "$filter" <<<"$out" >/dev/null; then echo "ok - $name"; else echo "not ok - $name: $out"; exit 1; fi
}
