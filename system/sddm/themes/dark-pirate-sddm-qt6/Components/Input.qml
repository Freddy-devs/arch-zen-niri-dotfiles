//
// This file is part of Sugar Dark, a theme for the Simple Display Desktop Manager.
//
// Copyright 2018 Marian Arlt
//
// Sugar Dark is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sugar Dark is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Sugar Dark. If not, see <https://www.gnu.org/licenses/>.
//

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Column {
    id: inputContainer
    Layout.fillWidth: true

    property Item exposeLogin: loginButton
    property alias usernameText: username.text
    property bool failed
    property color mainColor: config.MainColor ? config.MainColor : root.palette.highlight
    property color accentColor: config.AccentColor ? config.AccentColor : root.palette.text

    // USERNAME INPUT
    Item {
        id: usernameField

        height: root.font.pointSize * 4.5
        width: parent.width / 2
        anchors.horizontalCenter: parent.horizontalCenter

        Rectangle {
            id: userSelectContainer
            anchors.fill: parent
            anchors.margins: 0
            radius: config.RoundCorners || 0
            color: "transparent"
            border.color: mainColor
            border.width: config.HideUserList != "true" ? 1 : 0
            visible: config.HideUserList != "true"
            z: 1
        }

        ComboBox {

            id: selectUser 
            width: parent.width
            height: parent.height
            anchors.left: parent.left
            z: 2
            visible: config.HideUserList != "true"
            leftPadding: usernameIcon.width + (selectUser.height * 0.25)
            rightPadding: selectUser.height * 0.25
            font.bold: true
            font.pointSize: root.font.pointSize * 1.2

            model: userModel
            currentIndex: model.lastIndex
            textRole: "name"
            hoverEnabled: true
            onActivated: {
                username.text = currentText
            }

            contentItem: Item {
                anchors.fill: parent
                clip: true
                Text {
                    text: selectUser.currentText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: selectUser.leftPadding
                    elide: Text.ElideRight
                    font.pointSize: root.font.pointSize * 1.2
                    font.bold: true
                    color: accentColor
                }
            }

            delegate: ItemDelegate {
                padding: 8
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                contentItem: Text {
                    text: model.realName != "" ? model.realName : model.name
                    font.pointSize: root.font.pointSize * 1.0
                    font.bold: true
                    font.capitalization: Font.Capitalize 
                    color: accentColor  
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
                highlighted: parent.highlightedIndex === index
                background: Rectangle {
                    radius: height / 2  
                    color: selectUser.highlightedIndex === index ? Qt.darker(mainColor, 1.6) : "transparent"
                }
            }

            indicator: Button {
                    id: usernameIcon
                    width: selectUser.height * 0.8
                    height: parent.height
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: selectUser.height * 0.125
                    icon.height: parent.height * 0.25
                    icon.width: parent.height * 0.25
                    enabled: false
                    icon.color: accentColor
                    icon.source: Qt.resolvedUrl("../Assets/User.svgz")
                    background: Item {}   // Qt6: sin fondo (antes salía negro por la paleta "disabled")
            }

            background: Rectangle {
                color: "transparent"
                border.color: "transparent"
                border.width: 0
                radius: 0
            }

            popup: Popup {
                y: parent.height - username.height / 3
                rightMargin: config.ForceRightToLeft == "true" ? root.padding + usernameField.width / 2 : undefined
                width: usernameField.width
                implicitHeight: contentItem.implicitHeight
                padding: 10

                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight + 20
                    model: selectUser.popup.visible ? selectUser.delegateModel : null
                    currentIndex: selectUser.highlightedIndex
                    ScrollIndicator.vertical: ScrollIndicator { }
                }

                background: Rectangle {
                    radius: config.RoundCorners / 2
                    color: mainColor
                    opacity: 0.6
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 0
                        radius: 100
                        samples: 201
                        cached: true
                        color: "#88000000"
                    }
                }

                enter: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1 }
                }
            }

            states: [
                State {
                    name: "pressed"
                    when: selectUser.down
                    PropertyChanges {
                        target: usernameIcon
                        icon.color: accentColor
                    }
                },
                State {
                    name: "hovered"
                    when: selectUser.hovered
                    PropertyChanges {
                        target: usernameIcon
                        icon.color: accentColor
                    }
                },
                State {
                    name: "focused"
                    when: selectUser.visualFocus
                    PropertyChanges {
                        target: usernameIcon
                        icon.color: accentColor
                    }
                }
            ]

            transitions: [
                Transition {
                    PropertyAnimation {
                        properties: "color, border.color, icon.color"
                        duration: 150
                    }
                }
            ]

        }

        TextField {
            id: username
            text: config.HideUserList != "true" ? selectUser.currentText : (config.ForceLastUser == "true" ? selectUser.currentText : null)
            font.capitalization: Font.Capitalize
            anchors.centerIn: parent
            font.pointSize: root.font.pointSize * 1.2
            font.bold: true
            height: root.font.pointSize * 3
            width: parent.width
            placeholderText: config.TranslateUsernamePlaceholder || textConstants.userName
            placeholderTextColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.55)   // placeholder en el color del tema, no negro
            selectByMouse: true
            horizontalAlignment: TextInput.AlignLeft
            renderType: Text.QtRendering
            visible: config.HideUserList == "true"
            background: Rectangle {
                color: "transparent"
                border.color: mainColor
                border.width: parent.activeFocus ? 2 : 1
                radius: config.RoundCorners || 0
            }
            Keys.onReturnPressed: loginButton.clicked()
            KeyNavigation.down: password
            z: 1

            states: [
                State {
                    name: "focused"
                    when: username.activeFocus
                    PropertyChanges {
                        target: username.background
                        border.color: mainColor
                    }
                    PropertyChanges {
                        target: username
                        color: mainColor
                    }
                }
            ]
        }

    }

    Item {
        height: root.font.pointSize
        width: 1
    }

    // PASSWORD INPUT
    Item {
        id: passwordField
        height: root.font.pointSize * 4.5
        width: parent.width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        
        Rectangle {
            id: passwordContainer
            anchors.fill: parent
            radius: config.RoundCorners || 0
            color: "transparent"
            border.color: mainColor
            border.width: 1
            z: 1
        }

        Button {
            id: passwordIcon
            width: passwordField.height * 0.8
            height: parent.height
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: passwordField.height * 0.125
            icon.height: parent.height * 0.25
            icon.width: parent.height * 0.25
            enabled: false
            icon.color: password.color
            icon.source: Qt.resolvedUrl("../Assets/Lock.svg")
            background: Item {}   // Qt6: sin fondo (antes salía negro por la paleta "disabled")
            z: 2
        }

        TextField {
            id: password
            anchors.centerIn: parent
            font.pointSize: root.font.pointSize * 1.2
            font.bold: true
            height: root.font.pointSize * 3
            width: parent.width
            focus: config.ForcePasswordFocus == "true" ? true : false
            selectByMouse: true
            echoMode: revealSecret.checked ? TextInput.Normal : TextInput.Password
            placeholderText: config.TranslatePasswordPlaceholder || textConstants.password
            placeholderTextColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.55)   // placeholder en el color del tema, no negro
            horizontalAlignment: TextInput.AlignLeft
            passwordCharacter: "•"
            passwordMaskDelay: config.ForceHideCompletePassword == "true" ? undefined : 1000
            renderType: Text.QtRendering
            leftPadding: passwordIcon.width + (passwordField.height * 0.25)
            rightPadding: password.height * 0.25
            color: accentColor
            background: Rectangle {
                color: "transparent"
                border.color: "transparent"
                border.width: 0
                radius: 0
            }
            Keys.onReturnPressed: loginButton.clicked()
            KeyNavigation.down: revealSecret
        }

        states: [
            State {
                name: "focused"
                when: password.activeFocus
                PropertyChanges {
                    target: password.background
                    border.color: mainColor
                }
                PropertyChanges {
                    target: password
                    color: mainColor
                }
            }
        ]

        transitions: [
            Transition {
                PropertyAnimation {
                    properties: "color, border.color"
                    duration: 150
                }
            }
        ]
    }

    // SHOW/HIDE PASS
    Item {
        id: secretCheckBox
        height: root.font.pointSize * 7
        width: parent.width / 2
        anchors.horizontalCenter: parent.horizontalCenter

        CheckBox {
            id: revealSecret
            width: parent.width
            hoverEnabled: true

            indicator: Rectangle {
                id: indicator
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 5
                anchors.leftMargin: 4
                implicitHeight: root.font.pointSize
                implicitWidth: root.font.pointSize
                color: "transparent"
                border.color: accentColor
                border.width: parent.visualFocus ? 2 : 1
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    implicitHeight: parent.width - 6
                    implicitWidth: parent.width - 6
                    color: accentColor
                    opacity: revealSecret.checked ? 1 : 0
                }
            }

            contentItem: Text {
                id: indicatorLabel
                text: config.TranslateShowPassword || "Show Password"
                anchors.verticalCenter: indicator.verticalCenter
                anchors.verticalCenterOffset: 0
                horizontalAlignment: Text.AlignLeft
                anchors.left: indicator.right
                anchors.topMargin: 8
                anchors.leftMargin: indicator.width / 2
                font.pointSize: root.font.pointSize * 0.8
                color: accentColor
            }

            Keys.onReturnPressed: toggle()
            KeyNavigation.down: loginButton

            background: Rectangle {
                color: "transparent"
                border.width: parent.visualFocus ? 1 : 0
                border.color: parent.visualFocus ? accentColor : "transparent"
                height: parent.visualFocus ? 2 : 0
                width: (indicator.width + indicatorLabel.contentWidth + indicatorLabel.anchors.leftMargin + 2)
                anchors.top: indicatorLabel.bottom
                anchors.left: parent.left
                anchors.leftMargin: 3
                anchors.topMargin: 8
            }
        }

        states: [
            State {
                name: "pressed"
                when: revealSecret.down
                PropertyChanges {
                    target: revealSecret.contentItem
                    color: Qt.darker(mainColor, 1.1)
                }
                PropertyChanges {
                    target: dot
                    color: Qt.darker(mainColor, 1.1)
                }
                PropertyChanges {
                    target: indicator
                    border.color: Qt.darker(mainColor, 1.1)
                }
                PropertyChanges {
                    target: revealSecret.background
                    border.color: Qt.darker(mainColor, 1.1)
                }
            },
            State {
                name: "hovered"
                when: revealSecret.hovered
                PropertyChanges {
                    target: indicatorLabel
                    color: Qt.lighter(mainColor, 1.1)
                }
                PropertyChanges {
                    target: indicator
                    border.color: Qt.lighter(mainColor, 1.1)
                }
                PropertyChanges {
                    target: dot
                    color: Qt.lighter(mainColor, 1.1)
                }
                PropertyChanges {
                    target: revealSecret.background
                    border.color: Qt.lighter(mainColor, 1.1)
                }
            },
            State {
                name: "focused"
                when: revealSecret.visualFocus
                PropertyChanges {
                    target: indicatorLabel
                    color: mainColor
                }
                PropertyChanges {
                    target: indicator
                    border.color: mainColor
                }
                PropertyChanges {
                    target: dot
                    color: mainColor
                }
                PropertyChanges {
                    target: revealSecret.background
                    border.color: mainColor
                }
            }
        ]

        transitions: [
            Transition {
                PropertyAnimation {
                    properties: "color, border.color, opacity"
                    duration: 150
                }
            }
        ]

    }

    // ERROR FIELD
    Item {
        height: root.font.pointSize * 2.3
        width: parent.width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        Label {
            id: errorMessage
            width: parent.width
            text: failed ? config.TranslateLoginFailed || textConstants.loginFailed + "!" : keyboard.capsLock ? textConstants.capslockWarning : null
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: root.font.pointSize * 0.8
            font.italic: true
            color: accentColor
            opacity: 0
            states: [
                State {
                    name: "fail"
                    when: failed
                    PropertyChanges {
                        target: errorMessage
                        opacity: 1
                    }
                },
                State {
                    name: "capslock"
                    when: keyboard.capsLock
                    PropertyChanges {
                        target: errorMessage
                        opacity: 1
                    }
                }
            ]
            transitions: [
                Transition {
                    PropertyAnimation {
                        properties: "opacity"
                        duration: 100
                    }
                }
            ]
        }
    }

    // LOGIN BUTTON
    Item {
        id: login
        height: root.font.pointSize * 3
        width: parent.width / 2
        anchors.horizontalCenter: parent.horizontalCenter

        Button {
            id: loginButton
            anchors.horizontalCenter: parent.horizontalCenter
            text: config.TranslateLogin || textConstants.login
            height: root.font.pointSize * 3
            implicitWidth: parent.width
            enabled: username.text != "" && password.text != "" ? true : false
            hoverEnabled: true

            contentItem: Text {
                text: parent.text
                color: Qt.darker(accentColor, 1.6)
                font.pointSize: root.font.pointSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 0.85
            }

            background: Rectangle {
                id: buttonBackground
                color: accentColor
                opacity: 0.2
                radius: config.RoundCorners || 0
            }

            states: [
                State {
                    name: "pressed"
                    when: loginButton.down
                    PropertyChanges {
                        target: buttonBackground
                        color: Qt.darker(mainColor, 1.1)
                        opacity: 1
                    }
                    PropertyChanges {
                        target: loginButton.contentItem
                        color: Qt.darker(accentColor, 1.6)
                    }
                },
                State {
                    name: "hovered"
                    when: loginButton.hovered
                    PropertyChanges {
                        target: buttonBackground
                        color: mainColor
                        opacity: 1
                    }
                    PropertyChanges {
                        target: loginButton.contentItem
                        opacity: 1
                        color: Qt.darker(accentColor, 1.6)
                    }
                },
                State {
                    name: "focused"
                    when: loginButton.visualFocus
                    PropertyChanges {
                        target: buttonBackground
                        color: mainColor
                        opacity: 1
                    }
                    PropertyChanges {
                        target: loginButton.contentItem
                        opacity: 1
                        color: Qt.darker(accentColor, 1.6)
                    }
                },
                State {
                    name: "disabled"
                    when: !loginButton.enabled
                    PropertyChanges {
                        target: buttonBackground
                        color: mainColor
                        opacity: 0.5
                    }
                    PropertyChanges {
                        target: loginButton.contentItem
                        opacity: 0.95
                        color: accentColor
                    }
                },
                State {
                    name: "enabled"
                    when: loginButton.enabled
                    PropertyChanges {
                        target: buttonBackground;
                        color: accentColor;
                        opacity: 1
                    }
                    PropertyChanges {
                        target: loginButton.contentItem;
                        opacity: 1
                    }
                }
            ]

            transitions: [
                Transition {
                    from: ""; to: "enabled"
                    PropertyAnimation {
                        properties: "opacity, color";
                        duration: 500
                    }
                },
                Transition {
                    from: "enabled"; to: ""
                    PropertyAnimation {
                        properties: "opacity, color";
                        duration: 300
                    }
                }
            ]

            Keys.onReturnPressed: clicked()
            onClicked: sddm.login(username.text, password.text, sessionSelect.selectedSession)
        }
    }

    // SESSION SELECT
    SessionButton {
        id: sessionSelect
        textConstantSession: textConstants.session
    }

    Connections {
        target: sddm
        function onLoginSucceeded() {}
        function onLoginFailed() {
            failed = true
            resetError.running ? resetError.stop() && resetError.start() : resetError.start()
        }
    }

    Timer {
        id: resetError
        interval: 2000
        onTriggered: failed = false
        running: false
    }
}
