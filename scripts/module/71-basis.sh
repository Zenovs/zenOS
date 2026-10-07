#!/usr/bin/env bash
# 71-basis: Ubuntu-Basis – Paket-Updates über zen update (zenos-basis), kein Wechsel der Hauptversion (Prompt=never)
# shellcheck shell=bash
#
# Paket-Updates innerhalb von Ubuntu 26.04 LTS bringt zenos-basis (scripts/bin/zenos-basis, docs/image-und-releases.md,
# «Basis-Updates»):
# - scripts/bin/zenos-basis als root-eigene Kopie nach /usr/local/libexec/zenos/zenos-basis (wie zenos-kanal: Die Units
#   führen diese Kopie aus, nicht /opt/zenos). Ist ein Ordner auf dem Weg nicht nur für root schreibbar, unterbleibt
#   das (root führt die Datei aus).
# - Units nach /etc/systemd/system, statisch: zenos-basis-pruefen.service (apt-get update und Auswertung) und
#   zenos-basis-installieren.service (apt-get full-upgrade mit Inhibitor, danach install.sh). «zen update», die
#   Einstellungen (zenos-kanal-bedienen, polkit-Aktionen in org.zenos.kanal.policy aus 14-kanal) und die Automatik
#   starten sie.
# - Automatik: zenos-basis-automatik.timer (alle 6 h prüfen, nach dem Zeitpunkt installieren) und
#   zenos-basis-gelegenheit.timer (alle 15 Min., nur wenn eine Liste bereit ist) sind ab Werk an (Entscheid Zeno),
#   ausser der gemeinsame Notschalter /etc/xdg/zenos/kanal-automatik-aus ist gesetzt (sudo zen kanal automatik aus):
#   dann schaltet install.sh sie nicht ein, sondern aus, wie 14-kanal die Timer des Kanals.
# - /var/lib/zenos/basis (root, 0755) für Stand, letzte Installation, Auftrag und den letzten Lauf der Automatik.
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
# Ziele (die Einheitentests setzen andere)
_BASIS_LIBEXEC=/usr/local/libexec
_BASIS_UNITS=/etc/systemd/system
_BASIS_ZUSTAND=/var/lib/zenos
_BASIS_EINHEITEN=(zenos-basis-pruefen.service zenos-basis-installieren.service zenos-basis-automatik.service
  zenos-basis-automatik.timer zenos-basis-gelegenheit.service zenos-basis-gelegenheit.timer)
_BASIS_AUTOMATIK=(zenos-basis-automatik.timer zenos-basis-gelegenheit.timer)
_BASIS_AUS=/etc/xdg/zenos/kanal-automatik-aus

modul_system() {
  datei_installieren "$ZENOS_CODE/system/update-manager/zenos.cfg" "$_BASIS_DROPIN" 0644 root:root
  _basis_hinweis_leeren
  _basis_programm
}

_basis_hinweis_leeren() {
  [[ -f "$_BASIS_HINWEIS" && ! -L "$_BASIS_HINWEIS" && -s "$_BASIS_HINWEIS" ]] || return 0
  : | datei_schreiben "$_BASIS_HINWEIS" 0644 root:root
}

_basis_programm() {
  local einheit
  if ! _basis_pfad_sicher "$_BASIS_LIBEXEC"; then
    log_warnung "$_BASIS_LIBEXEC oder ein Ordner darüber ist nicht nur für root schreibbar: zenos-basis bleibt weg"
    return 0
  fi
  ordner_sicherstellen "$_BASIS_LIBEXEC/zenos" 0755 root:root
  datei_installieren "$ZENOS_CODE/scripts/bin/zenos-basis" "$_BASIS_LIBEXEC/zenos/zenos-basis" 0755 root:root
  for einheit in "${_BASIS_EINHEITEN[@]}"; do
    datei_installieren "$ZENOS_CODE/system/systemd/system/$einheit" "$_BASIS_UNITS/$einheit" 0644 root:root
  done
  ordner_sicherstellen "$_BASIS_ZUSTAND" 0755 root:root
  ordner_sicherstellen "$_BASIS_ZUSTAND/basis" 0755 root:root
  for einheit in "${_BASIS_AUTOMATIK[@]}"; do
    if [[ -e "$_BASIS_AUS" ]]; then
      _basis_timer_aus "$einheit"
    else
      _basis_timer_an "$einheit"
    fi
  done
}

# Timer aktivieren und, wenn systemd läuft (nicht im Image), gleich starten (wie _kanal_timer_an in 14-kanal)
_basis_timer_an() {
  local timer=$1
  dienst_aktivieren "$timer"
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  systemctl --quiet is-active "$timer" 2>/dev/null && return 0
  systemd_neu_laden
  if $SUDO systemctl start "$timer"; then
    aenderung "Timer gestartet: $timer"
  else
    log_warnung "$timer liess sich nicht starten (systemctl status $timer)"
  fi
}

# Notschalter gesetzt: Timer aus und gestoppt (ein laufender Lauf endet von selbst)
_basis_timer_aus() {
  local timer=$1 zustand
  zustand=$(systemctl is-enabled "$timer" 2>/dev/null) || true
  if [[ "$zustand" == enabled ]]; then
    $SUDO systemctl disable --quiet "$timer"
    aenderung "Timer ausgeschaltet (Notschalter $_BASIS_AUS): $timer"
  fi
  if [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] && systemctl --quiet is-active "$timer" 2>/dev/null; then
    $SUDO systemctl stop "$timer"
    aenderung "Timer gestoppt (Notschalter): $timer"
  fi
}

# Gehört jeder vorhandene Ordner auf dem Weg root, und ist keiner für andere schreibbar? (wie 14-kanal)
_basis_pfad_sicher() {
  local pfad=$1 rechte
  while [[ "$pfad" != / ]]; do
    if [[ -e "$pfad" ]]; then
      rechte=$(stat -c '%u %a' -- "$pfad") || return 1
      [[ "${rechte%% *}" == 0 ]] || return 1
      (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    fi
    pfad=$(dirname -- "$pfad")
  done
}
