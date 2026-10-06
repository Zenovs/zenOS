// Nur für test/container/gesten-e2e.sh: eine Fläche über den ganzen Bildschirm, damit der Zeiger über einem Qt-Client
// liegt. Mit WAYLAND_DEBUG=client steht im Protokoll, was labwc diesem Client schickt (wl_pointer.motion,
// zwp_pointer_gesture_swipe_v1.begin mit der Fingerzahl). Qt bindet zwp_pointer_gestures_v1 selbst.
import Quickshell
import QtQuick

ShellRoot {
    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "black"
    }
}
