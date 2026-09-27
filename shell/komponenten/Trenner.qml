import QtQuick
import qs.theme

// 1-px-Linie, waagrecht (Standard) oder senkrecht.
Rectangle {
    property bool senkrecht: false

    implicitWidth: senkrecht ? 1 : 0
    implicitHeight: senkrecht ? 0 : 1
    color: Theme.trennlinie
}
