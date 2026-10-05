#!/usr/bin/env bash
# 14-kanal: signierter Kanal – Prüfprogramm (root-eigene Kopie), Units, Zustandsordner. Installiert nichts.
# shellcheck shell=bash
#
# - scripts/bin/zenos-kanal als root-eigene Kopie nach /usr/local/libexec/zenos/zenos-kanal: Die Units führen diese
#   Kopie aus, nicht /opt/zenos. So bleibt das Prüfprogramm, auch wenn /opt/zenos gerade umgestellt wird oder ein
#   «zen rollback» auf einen Stand ohne Kanal geht. Ist ein Ordner auf dem Weg nicht nur für root schreibbar,
#   unterbleibt alles (root führt die Datei aus).
# - zenos-kanal-holen.service (ohne Rechte, mit Netz) und zenos-kanal-pruefen.service (root, ohne Netz) nach
#   /etc/systemd/system. Beide sind statisch: kein Timer, kein Start beim Booten, nur «sudo zen kanal pruefen».
# - /var/lib/zenos/kanal (root, 0755) für stand.json, gesehen.json und hoechste.
# Der Anker kommt aus 12-vertrauen.

_KANAL_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal
_KANAL_EINHEITEN=(zenos-kanal-holen.service zenos-kanal-pruefen.service)

modul_system() {
  local einheit
  if ! _kanal_pfad_sicher /usr/local/libexec; then
    log_warnung "/usr/local/libexec oder ein Ordner darüber ist nicht nur für root schreibbar: zenos-kanal bleibt weg"
    return 0
  fi
  ordner_sicherstellen /usr/local/libexec/zenos 0755 root:root
  datei_installieren "$ZENOS_CODE/scripts/bin/zenos-kanal" "$_KANAL_PROGRAMM" 0755 root:root
  for einheit in "${_KANAL_EINHEITEN[@]}"; do
    datei_installieren "$ZENOS_CODE/system/systemd/system/$einheit" "/etc/systemd/system/$einheit" 0644 root:root
  done
  ordner_sicherstellen /var/lib/zenos 0755 root:root
  ordner_sicherstellen /var/lib/zenos/kanal 0755 root:root
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
