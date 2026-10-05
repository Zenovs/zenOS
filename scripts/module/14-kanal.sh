#!/usr/bin/env bash
# 14-kanal: signierter Kanal – Programm (root-eigene Kopie), Units, Zustandsordner
# shellcheck shell=bash
#
# - scripts/bin/zenos-kanal als root-eigene Kopie nach /usr/local/libexec/zenos/zenos-kanal: Die Units und zen update
#   führen diese Kopie aus, nicht /opt/zenos. So bleibt das Programm, auch wenn /opt/zenos gerade umgestellt wird oder
#   ein «zen rollback» auf einen Stand ohne Kanal geht. Ist ein Ordner auf dem Weg nicht nur für root schreibbar,
#   unterbleibt alles (root führt die Datei aus). Die bisherige Fassung bleibt als zenos-kanal.vorher: Hat die neue
#   einen Fehler, den ihr Selbsttest nicht fängt, holt sie der Notweg zurück (ANLEITUNG F).
# - Units nach /etc/systemd/system: zenos-kanal-holen.service (ohne Rechte, mit Netz), zenos-kanal-pruefen.service
#   (root, ohne Netz), zenos-kanal-installieren.service (root, mit Netz, Inhibitor) sind statisch: «zen update»,
#   «zen rollback», «sudo zen kanal pruefen», die Einstellungen und die Automatik starten sie.
#   zenos-kanal-nachstart.service ist aktiviert und läuft beim Start vor greetd, aber nur nach einer unterbrochenen
#   Installation. zenos-kanal-jetzt.service und zenos-kanal-zustimmen@.service (statisch) startet nur die Oberfläche
#   über scripts/bin/zenos-kanal-bedienen: «Jetzt installieren» und «Zustimmen …» in Einstellungen › System › Updates.
# - Automatik: zenos-kanal.timer (alle 6 h holen, prüfen, nach dem Zeitpunkt installieren) und
#   zenos-kanal-gelegenheit.timer (alle 15 Min., nur wenn etwas bereit ist) sind ab Werk an (Entscheid Zeno), ausser
#   der Notschalter /etc/xdg/zenos/kanal-automatik-aus ist gesetzt (sudo zen kanal automatik aus): dann schaltet
#   install.sh sie nicht ein, sondern aus. zenos-kanal-bestaetigen.timer (2 Min. nach dem Start) ist immer an; seine
#   Unit läuft nur, wenn ein automatisch installierter Stand auf die Bestätigung wartet.
# - polkit-Aktionen für diesen Helfer (system/polkit/org.zenos.kanal.policy): prüfen, jetzt installieren und den
#   Zeitpunkt setzen ohne Passwort, zustimmen jedes Mal mit Passwort; alles nur in der aktiven Sitzung am Gerät.
# - /var/lib/zenos/kanal (root, 0755) für Stand, Hauptbuch, hoechste, Auftrag und die Bereitstellungen.
# Der Anker kommt aus 12-vertrauen.

_KANAL_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal
_KANAL_EINHEITEN=(zenos-kanal-holen.service zenos-kanal-pruefen.service zenos-kanal-installieren.service
  zenos-kanal-nachstart.service zenos-kanal-jetzt.service zenos-kanal-zustimmen@.service
  zenos-kanal-automatik.service zenos-kanal.timer zenos-kanal-gelegenheit.service zenos-kanal-gelegenheit.timer
  zenos-kanal-bestaetigen.service zenos-kanal-bestaetigen.timer)
_KANAL_AUTOMATIK=(zenos-kanal.timer zenos-kanal-gelegenheit.timer)
_KANAL_AUS=/etc/xdg/zenos/kanal-automatik-aus

modul_system() {
  local einheit
  if ! _kanal_pfad_sicher /usr/local/libexec; then
    log_warnung "/usr/local/libexec oder ein Ordner darüber ist nicht nur für root schreibbar: zenos-kanal bleibt weg"
    return 0
  fi
  ordner_sicherstellen /usr/local/libexec/zenos 0755 root:root
  if [[ -f "$_KANAL_PROGRAMM" && ! -L "$_KANAL_PROGRAMM" ]] &&
    ! cmp -s -- "$ZENOS_CODE/scripts/bin/zenos-kanal" "$_KANAL_PROGRAMM"; then
    datei_installieren "$_KANAL_PROGRAMM" "$_KANAL_PROGRAMM.vorher" 0755 root:root
  fi
  datei_installieren "$ZENOS_CODE/scripts/bin/zenos-kanal" "$_KANAL_PROGRAMM" 0755 root:root
  for einheit in "${_KANAL_EINHEITEN[@]}"; do
    datei_installieren "$ZENOS_CODE/system/systemd/system/$einheit" "/etc/systemd/system/$einheit" 0644 root:root
  done
  ordner_sicherstellen /var/lib/zenos 0755 root:root
  ordner_sicherstellen /var/lib/zenos/kanal 0755 root:root
  dienst_aktivieren zenos-kanal-nachstart.service
  _kanal_timer_an zenos-kanal-bestaetigen.timer
  for einheit in "${_KANAL_AUTOMATIK[@]}"; do
    if [[ -e "$_KANAL_AUS" ]]; then
      _kanal_timer_aus "$einheit"
    else
      _kanal_timer_an "$einheit"
    fi
  done
  # Einstellungen › System › Updates: pkexec mit scripts/bin/zenos-kanal-bedienen (pkexec aus pakete/sicherheit.txt)
  datei_installieren "$ZENOS_CODE/system/polkit/org.zenos.kanal.policy" \
    /usr/share/polkit-1/actions/org.zenos.kanal.policy
}

# Timer aktivieren und, wenn systemd läuft (nicht im Image), gleich starten: dienst_aktivieren allein griffe erst nach
# dem nächsten Start
_kanal_timer_an() {
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
_kanal_timer_aus() {
  local timer=$1 zustand
  zustand=$(systemctl is-enabled "$timer" 2>/dev/null) || true
  if [[ "$zustand" == enabled ]]; then
    $SUDO systemctl disable --quiet "$timer"
    aenderung "Timer ausgeschaltet (Notschalter $_KANAL_AUS): $timer"
  fi
  if [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] && systemctl --quiet is-active "$timer" 2>/dev/null; then
    $SUDO systemctl stop "$timer"
    aenderung "Timer gestoppt (Notschalter): $timer"
  fi
}

# Gehört jeder vorhandene Ordner auf dem Weg root, und ist keiner für andere schreibbar?
_kanal_pfad_sicher() {
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
