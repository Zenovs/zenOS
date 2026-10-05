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
#   (root, ohne Netz), zenos-kanal-installieren.service (root, mit Netz, Inhibitor) sind statisch: kein Timer, kein
#   Start beim Booten, nur «zen update», «zen rollback» und «sudo zen kanal pruefen». zenos-kanal-nachstart.service
#   ist aktiviert und läuft beim Start vor greetd, aber nur nach einer unterbrochenen Installation.
# - /var/lib/zenos/kanal (root, 0755) für Stand, Hauptbuch, hoechste, Auftrag und die Bereitstellungen.
# Der Anker kommt aus 12-vertrauen.

_KANAL_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal
_KANAL_EINHEITEN=(zenos-kanal-holen.service zenos-kanal-pruefen.service zenos-kanal-installieren.service
  zenos-kanal-nachstart.service)

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
