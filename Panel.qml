import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Popout for the Wunderground widget. The weather view shows current
// conditions from the station (owned by the host widget) plus today's
// summary and the 5-day forecast, fetched here when the panel opens. The
// settings view sets the station, API key and display options, and is where
// the panel opens until the widget is set up.
Panel {
  id: root
  moduleName: "io.github.jeremiahjohnston.wunderground"
  ipcTarget: "io.github.jeremiahjohnston.wunderground"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var details: ({})
  property real detailsFetchedAt: 0
  property string view: "weather"
  property string keyStatus: ""

  readonly property var barIdentity: hostWidget || root
  readonly property var obs: hostWidget && hostWidget.obs ? hostWidget.obs : ({})
  readonly property string units: hostWidget ? hostWidget.units : "e"
  readonly property string stationId: hostWidget ? hostWidget.stationId : ""
  readonly property int decimals: hostWidget ? hostWidget.decimals : 0
  readonly property bool showForecast: hostWidget ? hostWidget.showForecast : true
  readonly property bool hasKey: String(obs.code || "") !== "no-key"
  readonly property string deg: units === "e" ? "°F" : "°C"
  readonly property string speedUnit: units === "m" ? "km/h" : "mph"
  readonly property string rainUnit: units === "e" ? "in" : "mm"
  readonly property string pressureUnit: units === "e" ? "inHg" : "hPa"
  readonly property string detailsScript: localPath(Qt.resolvedUrl("scripts/wu-details"))
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimColor: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.6)
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: Commons.Color.urgent

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function open() {
    view = hostWidget && hostWidget.needsSetup ? "settings" : "weather"
    keyStatus = ""
    root.controller.show()
    if (view === "settings") {
      stationField.text = stationId
      keyField.text = ""
      Qt.callLater(focusSetup)
    }
    // The forecast changes slowly; refetch at most every 15 minutes.
    else if (Date.now() - detailsFetchedAt > 15 * 60 * 1000) Qt.callLater(root.refreshDetails)
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function showSettings() {
    view = "settings"
    stationField.text = stationId
    keyField.text = ""
    keyStatus = ""
    Qt.callLater(focusSetup)
  }

  function showWeather() {
    view = "weather"
    keyCatcher.forceActiveFocus()
    if (!details.ok) refreshDetails()
  }

  // Lands on the first thing still missing.
  function focusSetup() {
    if (stationId === "" || String(obs.code) === "no-station") stationField.forceActiveFocus()
    else if (!hasKey || String(obs.code) === "bad-key") keyField.forceActiveFocus()
  }

  function applySetup() {
    var station = stationField.text.trim().toUpperCase()
    if (hostWidget && station !== stationId) {
      details = ({})
      detailsFetchedAt = 0
      hostWidget.saveSettings({ stationId: station === "" ? null : station })
    }
    if (hostWidget && keyField.text.trim() !== "") {
      hostWidget.saveKey(keyField.text.trim())
      keyField.text = ""
      keyStatus = "Key saved. Checking…"
    } else if (hostWidget) {
      hostWidget.refresh()
      // A station without a key is half done; move on to the key.
      if (!hasKey) keyField.forceActiveFocus()
    }
  }

  function refreshDetails() {
    if (!showForecast || obs.lat === undefined || obs.lon === undefined) return
    if (detailsProcess.running) return
    detailsProcess.command = [detailsScript, stationId, units, String(obs.lat), String(obs.lon)]
    detailsProcess.running = true
  }

  function refreshAll() {
    if (hostWidget) hostWidget.refresh()
    detailsFetchedAt = 0
    refreshDetails()
  }

  function openUrl(url) {
    if (root.bar) root.bar.run("xdg-open '" + url + "'")
    root.close()
  }

  function num(value, digits) {
    if (value === null || value === undefined || value === "") return "–"
    return Number(value).toFixed(digits === undefined ? decimals : digits)
  }

  function compass(deg) {
    if (deg === null || deg === undefined) return ""
    var points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return points[Math.round(Number(deg) / 22.5) % 16]
  }

  function pressureTrend() {
    var trend = details.today ? Number(details.today.pressureTrend) : NaN
    if (!isFinite(trend) || trend === 0) return ""
    return trend > 0 ? " ↑" : " ↓"
  }

  function observedAt() {
    var match = String(obs.obsTime || "").match(/ (\d\d):(\d\d)/)
    if (!match) return ""
    var hour = Number(match[1])
    return (hour % 12 === 0 ? 12 : hour % 12) + ":" + match[2] + (hour < 12 ? " AM" : " PM")
  }

  // One line on where setup stands, shown under the setup fields.
  function setupStatus() {
    if (keyStatus !== "" && !obs.ok && !obs.code) return keyStatus
    if (obs.ok && obs.stale) return "Found " + obs.station + ", but it is offline; last report "
      + observedAt() + "."
    if (obs.ok) return "Connected to " + (obs.neighborhood ? obs.neighborhood + " · " : "") + obs.station
      + " · " + num(obs.temp) + deg
    if (stationId === "") return "Enter a station ID to start."
    if (obs.error) return obs.error
    return keyStatus || "Checking…"
  }

  readonly property var conditionRows: [
    { label: "Feels like", value: num(obs.feels) + deg },
    { label: "Humidity", value: num(obs.humidity, 0) + "%" },
    { label: "Dew point", value: num(obs.dewpt) + deg },
    { label: "Wind", value: (compass(obs.winddir) + " " + num(obs.windSpeed, 0) + " " + speedUnit).trim() },
    { label: "Gust", value: num(obs.windGust, 0) + " " + speedUnit },
    { label: "Pressure", value: num(obs.pressure, units === "e" ? 2 : 0) + " " + pressureUnit + pressureTrend() },
    { label: "Rain today", value: num(obs.precipTotal, units === "e" ? 2 : 1) + " " + rainUnit },
    { label: "UV · Solar", value: num(obs.uv, 0) + " · " + num(obs.solarRadiation, 0) + " W/m²" }
  ]

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(root.view === "settings"
      ? settingsColumn.implicitHeight : weatherColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.view !== "weather") return
        if (text === "r" || text === "R") root.refreshAll()
        else if (text === "o" || text === "O") root.openUrl(root.hostWidget.dashboardUrl)
        else if (text === "s" || text === "S") root.showSettings()
      }

      // ---- Weather view ----
      Column {
        id: weatherColumn
        visible: root.view === "weather"
        width: parent.width
        spacing: Style.space(10)

        // Header: place and station on the left, the reading on the right.
        Item {
          width: parent.width
          height: Math.max(placeColumn.implicitHeight, headerRight.implicitHeight)

          Column {
            id: placeColumn
            anchors.left: parent.left
            anchors.right: headerRight.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: root.obs.neighborhood || root.obs.station || root.stationId
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              // The title already shows the station ID when there is no
              // neighborhood name.
              text: (root.obs.neighborhood ? (root.obs.station || root.stationId) + " · " : "") + (root.observedAt()
                ? (root.obs.stale ? "offline since " : "observed ") + root.observedAt() : "")
              color: root.obs.stale ? root.urgentColor : root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.obs.ok ? root.num(root.obs.temp) + root.deg : "–"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title * 2
              font.bold: true
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Settings (S)"
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onClicked: root.showSettings()
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.obs.ok && !!root.obs.error
          width: parent.width
          wrapMode: Text.Wrap
          text: root.obs.error || ""
          color: root.urgentColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // Today at a glance: station high/low and daylight.
        Row {
          visible: root.showForecast && !!root.details.ok
          spacing: Style.space(16)

          Repeater {
            model: [
              { label: "High", value: root.details.today ? root.num(root.details.today.high) + "°" : "–" },
              { label: "Low", value: root.details.today ? root.num(root.details.today.low) + "°" : "–" },
              { label: "Sunrise", value: root.details.sunrise || "–" },
              { label: "Sunset", value: root.details.sunset || "–" }
            ]

            Column {
              required property var modelData
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                text: modelData.label.toUpperCase()
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.value
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
          }
        }

        Rectangle {
          visible: !!root.obs.ok
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.barForeground
          opacity: 0.12
        }

        // Current conditions, two columns of label/value pairs.
        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(18)
          rowSpacing: Style.space(6)
          visible: !!root.obs.ok

          Repeater {
            model: root.conditionRows

            Item {
              required property var modelData
              width: (parent.width - Style.space(18)) / 2
              height: Style.space(18)

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.value
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Rectangle {
          visible: root.showForecast
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.barForeground
          opacity: 0.12
        }

        Text {
          textFormat: Text.PlainText
          visible: root.showForecast
          text: "FORECAST"
          color: root.accentColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          visible: root.showForecast && !root.details.ok
          width: parent.width
          wrapMode: Text.Wrap
          // The forecast is looked up by the station's location, so it waits
          // for a reading.
          text: !root.obs.ok ? "Waiting for a station reading"
            : (root.details.error && !detailsProcess.running ? root.details.error : "Loading forecast…")
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // First entry is today or tonight; show its narrative in full.
        Text {
          textFormat: Text.PlainText
          visible: root.showForecast && !!root.details.ok && root.details.days.length > 0
          width: parent.width
          wrapMode: Text.Wrap
          text: root.details.ok && root.details.days.length > 0
            ? root.details.days[0].name + ": " + (root.details.days[0].narrative || "")
            : ""
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          visible: root.showForecast && !!root.details.ok
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.details.ok ? root.details.days.slice(1) : []

            Item {
              required property var modelData
              width: parent.width
              height: Style.space(20)

              Text {
                textFormat: Text.PlainText
                id: dayName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(40)
                text: modelData.name
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: dayName.right
                anchors.right: rain.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: modelData.phrase || ""
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                id: rain
                anchors.right: temps.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(36)
                horizontalAlignment: Text.AlignRight
                text: modelData.precipChance ? modelData.precipChance + "%" : ""
                color: Number(modelData.precipChance) >= 30 ? root.accentColor : root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                id: temps
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(64)
                horizontalAlignment: Text.AlignRight
                text: root.num(modelData.high, 0) + "° / " + root.num(modelData.low, 0) + "°"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "R refresh · O open dashboard · S settings"
          color: Qt.darker(root.barForeground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Settings view ----
      Column {
        id: settingsColumn
        visible: root.view === "settings"
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Math.max(settingsTitle.implicitHeight, backButton.height)

          Text {
            textFormat: Text.PlainText
            id: settingsTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Weather Underground"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Button {
            id: backButton
            visible: root.hostWidget && !root.hostWidget.needsSetup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Done"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.showWeather()
          }
        }

        PanelSectionHeader {
          text: "STATION"
          foreground: root.accentColor
          fontFamily: root.fontFamily
        }

        TextField {
          id: stationField
          width: parent.width
          placeholderText: "Station ID, e.g. KCASANFR123"
          foreground: root.barForeground
          font.family: root.fontFamily
          font.capitalization: Font.AllUppercase
          onAccepted: root.applySetup()
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Find a station on the Wundermap, or use your own. The ID is the last part of its "
            + "dashboard address: wunderground.com/dashboard/pws/<b>KCASANFR123</b>"
          // Static markup for the bold example ID. Only literal text belongs
          // here: never put station or API strings in a StyledText element.
          textFormat: Text.StyledText
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSectionHeader {
          text: "API KEY"
          foreground: root.accentColor
          fontFamily: root.fontFamily
        }

        TextField {
          id: keyField
          width: parent.width
          password: true
          placeholderText: root.hasKey ? "Saved (paste a new key to replace it)" : "Paste your API key"
          foreground: root.barForeground
          font.family: root.fontFamily
          onAccepted: root.applySetup()
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          text: "Weather Underground gives free API keys to station owners. Sign in at "
            + "wunderground.com, open Member Settings › API Keys and generate one. It is "
            + "saved to ~/.config/omarchy/wunderground.key, readable only by you."
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Save"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.applySetup()
          }

          Button {
            text: "Wundermap"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.openUrl("https://www.wunderground.com/wundermap")
          }

          Button {
            text: "Get a key"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.openUrl("https://www.wunderground.com/member/api-keys")
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          text: root.setupStatus()
          color: root.obs.ok ? root.accentColor : (root.obs.code ? root.urgentColor : root.dimColor)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.barForeground
          opacity: 0.12
        }

        PanelSectionHeader {
          text: "DISPLAY"
          foreground: root.accentColor
          fontFamily: root.fontFamily
        }

        Repeater {
          model: [
            { key: "units", label: "Units", value: root.hostWidget ? root.hostWidget.unitsSetting : "auto",
              options: [{ value: "auto", label: "Auto" }, { value: "e", label: "°F mph" },
                        { value: "m", label: "°C km/h" }, { value: "h", label: "°C mph" }] },
            { key: "barValue", label: "Bar shows", value: root.hostWidget ? root.hostWidget.barValue : "temp",
              options: [{ value: "temp", label: "Temperature" }, { value: "feels", label: "Feels like" }] },
            { key: "decimals", label: "Precision", value: String(root.decimals),
              options: [{ value: "0", label: "64°" }, { value: "1", label: "64.4°" }] },
            { key: "showUnit", label: "Bar label", value: root.hostWidget && root.hostWidget.showUnit ? "true" : "false",
              options: [{ value: "false", label: "64°" }, { value: "true", label: "64" + root.deg }] },
            { key: "bold", label: "Bar text", value: root.hostWidget && !root.hostWidget.bold ? "false" : "true",
              options: [{ value: "true", label: "Bold" }, { value: "false", label: "Regular" }] },
            { key: "accent", label: "Bar color", value: root.hostWidget && root.hostWidget.accent ? "true" : "false",
              options: [{ value: "false", label: "Bright" }, { value: "true", label: "Accent" }] }
          ]

          Item {
            required property var modelData
            width: settingsColumn.width
            height: Math.max(optionLabel.implicitHeight, optionGroup.implicitHeight)

            Text {
              textFormat: Text.PlainText
              id: optionLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ButtonGroup {
              id: optionGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: modelData.options
              value: modelData.value
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                var change = {}
                if (modelData.key === "decimals") change.decimals = Number(value)
                else if (["showUnit", "bold", "accent"].indexOf(modelData.key) >= 0)
                  change[modelData.key] = value === "true"
                else change[modelData.key] = value
                root.hostWidget.saveSettings(change)
              }
            }
          }
        }

        Item {
          width: parent.width
          height: refreshField.implicitHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Refresh every (minutes)"
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          NumberField {
            id: refreshField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            from: 1
            to: 60
            value: root.hostWidget ? Math.round(root.hostWidget.refreshSeconds / 60) : 5
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onModified: function(value) { root.hostWidget.saveSettings({ refreshSeconds: value * 60 }) }
          }
        }

        Toggle {
          width: parent.width
          label: "Show forecast"
          description: "Today's high and low, sunrise and sunset, and the 5-day forecast"
          checked: root.showForecast
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.hostWidget.saveSettings({ showForecast: !root.showForecast })
        }
      }
    }
  }

  Process {
    id: detailsProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(String(text || "{}"))
          // Keep the last good forecast through a transient failure.
          if (next.ok || !root.details.ok) root.details = next
          if (next.ok) root.detailsFetchedAt = Date.now()
        } catch (error) {
          if (!root.details.ok) root.details = { ok: false, error: "Could not read forecast" }
        }
      }
    }
  }

  // A new reading can arrive after the panel opened (first load, or a
  // station or unit change); fetch the forecast for it.
  onObsChanged: if (opened && view === "weather" && !details.ok && !detailsProcess.running) refreshDetails()
  // Units change the forecast's numbers; drop the old one.
  onUnitsChanged: { details = ({}); detailsFetchedAt = 0 }
}
