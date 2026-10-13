# Bluetooth

Bluetooth im System-Menü oben rechts, wie das WLAN: ein- und ausschalten, Geräte koppeln, verbinden, trennen und
vergessen. zenOS bedient dabei nur BlueZ, den Bluetooth-Stack von Ubuntu, und baut keinen eigenen.

## Was gebaut ist

- **Paket `bluez`** (`scripts/pakete/bluetooth.txt`, ohne Empfehlungen; bringt nur `libdw1t64` mit). Modul
  `scripts/module/36-bluetooth.sh`: zieht das Paket nach und startet `bluetooth.service` nach der ersten Installation,
  wenn er aktiviert ist und in diesem Start noch nie lief (während apt hält policy-rc.d jeden Start auf). Hat Zeno den
  Dienst gestoppt, deaktiviert oder maskiert, bleibt er so. Keine eigene Konfiguration.
- **`shell/leiste/BluetoothQuelle.qml`:** Brücke zu BlueZ über `Quickshell.Bluetooth` (D-Bus). Leiste.qml lädt sie
  erst, wenn `bluetooth.service` läuft, wie WlanQuelle erst mit NetworkManager. Nach aussen nur einfache Werte (Kopf
  der Datei); die Adresse ist nur ein Schlüssel.
- **`shell/leiste/BluetoothAbschnitt.qml`:** der Abschnitt im System-Menü, unter dem WLAN. Logik ohne QML in
  `shell/leiste/bluetooth.js` (Symbol je Gerätetyp, Namen, Akku, Reihenfolge, Texte). Zeilen sind `WlanZeile`, damit
  WLAN und Bluetooth gleich aussehen und gleich zu bedienen sind.
- **Symbole** `bluetooth`, `bluetooth-aus`, `maus`, `tastatur`, `kopfhoerer` (`shell/komponenten/symbole.js`).
- **`zenos-ipc leiste menue bluetooth`:** System-Menü mit aufgeklappter Liste.
- **`zen doctor`**, Abschnitt «Bluetooth» (`scripts/doctor.d/41-bluetooth.sh`): Gerät, Paket, Dienst, rfkill, Adapter
  an, nicht sichtbar für andere, Anzahl gekoppelter und verbundener Geräte (nie Namen oder Adressen).

## Bedienung

| Zeile | Was sie zeigt | Was sie tut |
|---|---|---|
| Bluetooth | Symbol, Schalter (bei rfkill «gesperrt») | nur der Schalter schaltet den Adapter (BlueZ `Powered`) |
| verbundenes Gerät | Symbol nach Typ, Name, Akku («81 %»), Haken | Klick fragt «trennen?», der zweite trennt; «x» vergisst nach Nachfrage |
| Weitere Geräte | Pfeil | klappt die Liste auf; solange sie offen ist, sucht der Adapter |
| gekoppeltes Gerät | «gekoppelt» | Klick verbindet |
| gefundenes Gerät | Name | Klick koppelt, vertraut (`Trusted`) und verbindet |

- Reihenfolge: verbundene, gekoppelte, gefundene, jeweils nach Namen (klein, ohne Akzente; die QML-Engine kennt
  `localeCompare` mit Sprache nicht). Fremde Geräte ohne Namen (BlueZ meldet dann die Adresse) fehlen.
- Ein Versuch, auf den das Gerät 30 s nicht antwortet, bricht ab: «Keine Antwort. Ist das Gerät an und in der Nähe?».
  Scheitert das Koppeln: «Koppeln hat nicht geklappt. Ist das Gerät im Kopplungsmodus?».
- Bildschirmfreigabe: keine Gerätenamen, keine Suche, die Liste bleibt zu.
- Gestaltung in `docs/design.md`, «Bluetooth im System-Menü».

## Entscheidungen

- **Quickshell.Bluetooth statt eines eigenen Dienstes:** Das Modul von Quickshell spricht BlueZ direkt über D-Bus
  (Adapter, Geräte, Koppeln, Verbinden, Akku). Kein Hilfsprogramm, keine Rechte: Die D-Bus-Regel von BlueZ erlaubt das
  jedem lokalen Benutzer.
- **Kein eigener Agent:** Ohne Agent koppelt BlueZ mit «NoInputNoOutput» (Just Works). Mäuse, Kopfhörer und die meisten
  Tastaturen gehen so, Geräte mit PIN-Eingabe nicht. Ein Agent mit Passkey-Dialog kann später kommen, wenn ein Gerät
  ihn braucht.
- **Nie sichtbar für andere:** zenOS fasst `Discoverable` nicht an. Koppeln geht nur von hier aus.
- **An nach dem Neustart:** BlueZ schaltet den Adapter beim Start ein (`AutoEnable`, Ubuntu-Standard), sonst ginge
  eine Bluetooth-Maus erst nach einem Klick im Menü. Dauerhaft aus: `rfkill block bluetooth`.
- **Kein Symbol in der Leiste:** Ruhe. Bluetooth erscheint nur im Menü.

## Am Gerät geprüft

- Argon ONE UP (Compute Module 5): Adapter `hci0`, BlueZ 5.85. Die Sitzung darf BlueZ bedienen, eine Suche
  von 15 s fand 7 Geräte in der Nähe (eines mit Namen).
- Headless (labwc, Quickshell aus dem Checkout): Abschnitt aufgeklappt mit einem gefundenen Gerät, hell und dunkel;
  Start-Test von `scripts/pruefen.sh` mit `leiste menue bluetooth` ohne Befund.
- Offen: Koppeln, Verbinden, Trennen und Akku mit einem echten Bluetooth-Gerät (Testliste in `ANLEITUNG.md`).

## Rückweg

Ein `zen rollback` auf einen Stand ohne Bluetooth lässt `bluez` installiert; das Menü zeigt dann einfach keinen
Abschnitt. Entfernen: `sudo apt purge bluez`.
