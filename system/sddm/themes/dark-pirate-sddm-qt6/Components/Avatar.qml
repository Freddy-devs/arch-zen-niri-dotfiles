import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Item {
    id: avatarContainer
    width: 120
    height: 120

    property string username: "default"

    Image {
        id: avatarImage
        source: "file:///var/lib/AccountsService/icons/" + username + ".face"
        width: parent.width
        height: parent.height
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
        // Si el usuario no tiene imagen propia, usar la genérica
        onStatusChanged: if (status === Image.Error) source = "file:///var/lib/AccountsService/icons/default.face"
    }

    OpacityMask {
        anchors.fill: avatarImage
        source: avatarImage
        maskSource: Rectangle {
            width: avatarImage.width
            height: avatarImage.height
            radius: width/2
            visible: false
        }
    }
}