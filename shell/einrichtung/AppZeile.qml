import QtQuick
import qs.theme
import qs.komponenten
import qs.einstellungen.teile

// Eine App in der Liste der Einrichtung und der Einstellungen: Häkchen (nur, wenn installierbar),
// Name, Herkunft und rechts Grösse, Version oder der Grund, warum es sie noch nicht gibt.
Item {
    id: root

    // Eintrag aus AppKatalog.apps
    property var app: ({})
    property bool gewaehlt: true
    property bool trennlinie: true

    readonly property bool installierbar: app.verfuegbar === true && app.installiert !== true

    signal umgeschaltet(bool an)

    implicitHeight: 60

    Trenner {
        visible: root.trennlinie
        anchors.top: parent.top
        width: parent.width
    }

    Item {
        id: marke

        x: 16
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter

        Kontrollkaestchen {
            id: kaestchen

            visible: root.installierbar
            anchors.centerIn: parent
            groesse: 18
            an: root.gewaehlt
            Accessible.name: (root.app.name ?? "") + " installieren"
            onUmgeschaltet: an => root.umgeschaltet(an)
        }

        Symbol {
            visible: root.app.installiert === true
            anchors.centerIn: parent
            name: "haken"
            groesse: 16
            strichbreite: 2.4
            farbe: Theme.akzent
        }

        // Noch nicht verfügbar: ein leiser Strich statt eines Häkchens
        Rectangle {
            visible: root.app.installiert !== true && root.app.verfuegbar !== true
            anchors.centerIn: parent
            width: 10
            height: 1.5
            radius: 1
            color: Theme.gedaempft
        }
    }

    Column {
        x: marke.x + marke.width + 14
        width: rechts.x - x - 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: root.app.name ?? ""
            color: root.app.verfuegbar === true || root.app.installiert === true ? Theme.text : Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: 15
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        Text {
            width: parent.width
            text: [root.app.hersteller, root.app.herkunft].filter(t => typeof t === "string" && t.length > 0).join(" · ")
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    Text {
        id: rechts

        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width * 0.4)
        horizontalAlignment: Text.AlignRight
        text: {
            if (root.app.installiert === true)
                return "installiert" + (root.app.version ? " · " + root.app.version : "");
            if (root.app.verfuegbar !== true)
                return root.app.hinweis || "nicht verfügbar";
            return root.app.groesseMb > 0 ? "≈ " + root.app.groesseMb + " MB" : "";
        }
        color: Theme.gedaempft
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
        elide: Text.ElideLeft
        textFormat: Text.PlainText
    }

    // Die ganze Zeile schaltet das Häkchen um
    MouseArea {
        anchors.fill: parent
        enabled: root.installierbar
        cursorShape: Qt.PointingHandCursor
        onClicked: root.umgeschaltet(!root.gewaehlt)
    }
}
