#!/usr/bin/env bash
# 71-basis: Ubuntu-Basis – kein Wechsel der Hauptversion (Prompt=never), keine Hinweise auf neue Ubuntu-Versionen
# shellcheck shell=bash
#
# Ein Wechsel der Ubuntu-Basis (etwa 26.04 auf 28.04) ist eine neue zenOS-Hauptversion mit neuem Image, kein Update
# (docs/image-und-releases.md, «Basiswechsel»). Zwei Stellen halten das:
# - Hier: Prompt=never für den Release-Upgrader über den Drop-in /etc/update-manager/release-upgrades.d/zenos.cfg
#   (aus system/update-manager/zenos.cfg). ubuntu-release-upgrader liest nach release-upgrades jede *.cfg in diesem
#   Ordner in Namensreihenfolge, der letzte Wert zählt (MetaRelease.py, im Container mit 1:26.04.25 geprüft). Danach
#   lehnt do-release-upgrade ab (auch -d), und check-new-release, die Begrüssung 91-release-upgrade und
#   update-notifier-motd.timer bleiben still, ohne changelogs.ubuntu.com zu fragen. Die Conffile
#   /etc/update-manager/release-upgrades bleibt unberührt: Eine geänderte Conffile hielte unattended-upgrades bei
#   einem Update des Pakets an (wie /etc/default/motd-news in 70-sicherheit). Der Drop-in liegt auch ohne das Paket
#   (kommt es später, gilt er sofort).
# - In zenos-kanal: Ein Stand für eine andere Ubuntu-Version (system/basis) ist nie ein Ziel.
# Ein Hinweis auf eine neue Version, den 91-release-upgrade vor Prompt=never zwischengespeichert hat, wird geleert
# (sonst stünde er noch bis zu einem Tag in der Begrüssung). 91-release-upgrade selbst bleibt, wie es 72-kennung
# einrichtet: Mit Prompt=never ist es ohnehin still, und so schalten 71 und 72 nie gegeneinander hin und her.
# Läuft auch im Image-Modus (chroot).

_BASIS_DROPIN=/etc/update-manager/release-upgrades.d/zenos.cfg
_BASIS_HINWEIS=/var/lib/ubuntu-release-upgrader/release-upgrade-available

modul_system() {
  datei_installieren "$ZENOS_CODE/system/update-manager/zenos.cfg" "$_BASIS_DROPIN" 0644 root:root
  _basis_hinweis_leeren
}

_basis_hinweis_leeren() {
  [[ -f "$_BASIS_HINWEIS" && ! -L "$_BASIS_HINWEIS" && -s "$_BASIS_HINWEIS" ]] || return 0
  : | datei_schreiben "$_BASIS_HINWEIS" 0644 root:root
}
