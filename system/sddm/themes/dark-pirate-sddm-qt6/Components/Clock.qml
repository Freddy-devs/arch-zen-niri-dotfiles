 

import QtQuick
import QtQuick.Controls

Column {
    id: clock
    spacing: 0
    width: parent.width / 2
    anchors.top: parent.top
    anchors.topMargin: parent.height / 5
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: config.HeaderText !== ""
        font.pointSize: root.font.pointSize * 4
        font.bold: true
        color: root.palette.text
        renderType: Text.QtRendering
        text: config.HeaderText
    }

    Label {
        id: timeLabel
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: root.font.pointSize * 4
        font.bold: true
        color: root.palette.text
        renderType: Text.QtRendering
        function updateTime() {
            text = new Date().toLocaleTimeString(Qt.locale(config.Locale), config.HourFormat == "long" ? Locale.LongFormat : config.HourFormat !== "" ? config.HourFormat : Locale.ShortFormat)
        }
    }

    Label {
        id: dateLabel
        anchors.horizontalCenter: parent.horizontalCenter
        color: root.palette.text
        renderType: Text.QtRendering
        function updateTime() {
            var loc = config.Locale !== "" ? Qt.locale(config.Locale) : Qt.locale()
            text = loc.toString(new Date(), loc.dateFormat(Locale.LongFormat))
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            dateLabel.updateTime()
            timeLabel.updateTime()
        }
    }

    Component.onCompleted: {
        dateLabel.updateTime()
        timeLabel.updateTime()
    }
}
