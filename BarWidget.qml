import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Shows the current temperature from a Weather Underground PWS.
// Left click opens the detail panel (or setup, until a station and API key
// are set), right click opens the station dashboard, middle click refreshes.
// Settings live in this widget's shell.json entry and are edited from the
// panel's settings view; see README.md for the keys.
BarWidget {
  id: root
  moduleName: "io.github.jeremiahjohnston.wunderground"

  property var obs: ({})

  readonly property string stationId: String(setting("stationId", "")).trim().toUpperCase()
  readonly property string unitsSetting: String(setting("units", "auto"))
  readonly property string units: ["e", "m", "h"].indexOf(unitsSetting) >= 0 ? unitsSetting : localeUnits()
  readonly property string barValue: setting("barValue", "temp") === "feels" ? "feels" : "temp"
  readonly property int decimals: Number(setting("decimals", 0)) === 1 ? 1 : 0
  readonly property bool showUnit: setting("showUnit", false) === true
  readonly property bool showForecast: setting("showForecast", true) !== false
  readonly property bool bold: setting("bold", true) !== false
  readonly property bool accent: setting("accent", false) === true
  readonly property int refreshSeconds: Math.max(60, Math.min(3600, Number(setting("refreshSeconds", 300)) || 300))

  readonly property string deg: units === "e" ? "°F" : "°C"
  readonly property string speedUnit: units === "m" ? "km/h" : "mph"
  // Missing station or key, or one the API rejected: the click goes to setup.
  readonly property bool needsSetup: stationId === ""
    || ["no-key", "bad-key", "no-station"].indexOf(String(obs.code || "")) >= 0
  readonly property string script: localPath(Qt.resolvedUrl("scripts/wu-current"))
  readonly property string dashboardUrl: "https://www.wunderground.com/dashboard/pws/" + stationId

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  // US locales get °F/mph, the UK °C/mph, everywhere else °C/km/h.
  function localeUnits() {
    var system = Qt.locale().measurementSystem
    if (system === Locale.ImperialUSSystem) return "e"
    if (system === Locale.ImperialUKSystem) return "h"
    return "m"
  }

  function refresh() {
    if (stationId === "") {
      obs = { ok: false, code: "no-station", error: "No station ID set" }
      return
    }
    if (fetcher.running) return
    // Set here rather than bound: a binding can lag the change handler that
    // calls refresh(), which would start the fetch with the old station.
    fetcher.command = [script, stationId, units]
    fetcher.running = true
  }

  function formatTemp(value, digits) {
    if (value === null || value === undefined || value === "") return "–"
    return Number(value).toFixed(digits === undefined ? decimals : digits)
  }

  function compass(deg) {
    if (deg === null || deg === undefined) return ""
    var points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return points[Math.round(Number(deg) / 45) % 8]
  }

  function label() {
    if (needsSetup) return vertical ? "WU" : "WU setup"
    if (!obs.ok) return obs.error ? "–°" : ""
    // A vertical bar is too narrow for the degree sign on three digits.
    var suffix = vertical ? "" : (showUnit ? deg : "°")
    return formatTemp(obs[barValue]) + suffix
  }

  function tooltip() {
    if (needsSetup) return "Weather Underground: click to set up"
      + (obs.error ? "\n" + obs.error : "")
    if (!obs.ok) return obs.error ? stationId + ": " + obs.error : "Loading " + stationId + "…"
    var lines = [
      (obs.neighborhood ? obs.neighborhood + " · " : "") + obs.station
        + (obs.stale ? " (offline)" : ""),
      "Temp " + formatTemp(obs.temp) + deg + " · feels " + formatTemp(obs.feels) + deg,
      "Humidity " + formatTemp(obs.humidity, 0) + "% · dew point " + formatTemp(obs.dewpt) + deg,
      "Wind " + compass(obs.winddir) + " " + formatTemp(obs.windSpeed, 0) + " " + speedUnit
        + " · gust " + formatTemp(obs.windGust, 0) + " " + speedUnit,
      (obs.stale ? "Last report " : "Updated ") + String(obs.obsTime || "").replace(/^\d{4}-\d\d-\d\d /, "")
    ]
    return lines.join("\n")
  }

  // Merges `changes` into this widget's shell.json entry; a null value
  // removes the key so the default applies.
  function saveSettings(changes) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var change in changes) {
      if (changes[change] === null || changes[change] === undefined) delete entry[change]
      else entry[change] = changes[change]
    }
    // Applied locally first so the widget reacts at once; the shell.json
    // write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveKey(key) {
    keySaver.environment = { WU_NEW_KEY: String(key || "") }
    keySaver.running = true
  }

  function openDashboard() {
    if (root.bar && stationId !== "") root.bar.run("xdg-open '" + dashboardUrl + "'")
  }

  // Shape contract for the bar's panel routing (open/close/opened on the
  // bar-widget root), forwarded to Panel.qml.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  // A new station or unit system makes the current reading stale.
  onStationIdChanged: { obs = ({}); refresh() }
  onUnitsChanged: { obs = ({}); refresh() }
  Component.onCompleted: refresh()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label()
    // WidgetButton's own label can't be bold, so it is hidden and drawn
    // below instead; the button still provides the slot, hover and clicks.
    labelVisible: false
    hasVisualContent: text !== ""
    fixedWidth: root.vertical ? -1 : reading.implicitWidth + Style.spaceReal(horizontalMargin) * 2
    // Dimmed when there's no current reading, including an offline
    // station's last report, so a dead station shows at a glance.
    dimmed: !root.obs.ok || root.obs.stale === true

    Text {
      id: reading
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.text
      color: root.accent && !!root.obs.ok && !root.needsSetup ? Commons.Color.accent : button.foreground
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      font.bold: root.bold && !root.needsSetup
      renderType: Text.NativeRendering
    }
    // The panel is the detail view; the tooltip covers the hover-only case.
    tooltipText: root.opened ? "" : root.tooltip()

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.openDashboard()
      else root.toggle()
    }
  }

  Process {
    id: fetcher

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(String(text || "{}"))
          // Keep the last good reading through a transient failure, but not
          // through a setup problem, which the user needs to see.
          var setupProblem = ["no-key", "bad-key", "no-station"].indexOf(String(next.code || "")) >= 0
          // The offline fallback has no neighborhood; keep the one we had.
          if (next.ok && !next.neighborhood && root.obs.station === next.station)
            next.neighborhood = root.obs.neighborhood
          if (next.ok || !root.obs.ok || setupProblem) root.obs = next
        } catch (error) {
          if (!root.obs.ok) root.obs = { ok: false, error: "Could not read station data" }
        }
      }
    }
  }

  Process {
    id: keySaver
    command: [root.localPath(Qt.resolvedUrl("scripts/wu-save-key"))]
    onExited: root.refresh()
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: root.stationId !== ""
    repeat: true
    onTriggered: root.refresh()
  }
}
