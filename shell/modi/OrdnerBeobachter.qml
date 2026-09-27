import QtQuick
import Qt.labs.folderlistmodel

// Beobachtet einen Ordner unter ~/.config/zenos (nur *.json) und meldet jede Änderung:
// neue, gelöschte, ersetzte oder bearbeitete Dateien.
// Konfig erzeugt ihn dynamisch; fehlt das Qt-Modul, bleiben die Dienste trotzdem ladbar.
FolderListModel {
    id: root

    property string pfad

    signal geaendert

    // Nach dem Anlegen eines Ordners neu verbinden (für fehlende Ordner meldet das Modell nichts)
    function neuVerbinden(): void {
        folder = "";
        folder = _url;
    }

    readonly property string _url: pfad.length > 0 ? "file://" + pfad : ""

    folder: _url
    nameFilters: ["*.json"]
    showDirs: false
    showDotAndDotDot: false
    showHidden: false

    onRowsInserted: geaendert()
    onRowsRemoved: geaendert()
    onDataChanged: geaendert()
}
