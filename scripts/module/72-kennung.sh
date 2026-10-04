#!/usr/bin/env bash
# 72-kennung: Systemkennung zenOS (os-release, Konsole, Begrüssung, Logo), nur mit erlaubter Ubuntu-Sicherheitsquelle
# shellcheck shell=bash
#
# Das System weist sich als zenOS aus (ID=zenos, ID_LIKE="ubuntu debian"), wie Pop!_OS, Mint und elementary. Die
# Arbeit macht scripts/bin/zenos-kennung (Einzelheiten dort und in docs/module/kennung.md). Hier:
# - zenos-kennung als root-eigene Kopie nach /usr/local/sbin (root führt es aus, auch im apt-Hook; die Kopie bleibt
#   bei einem «zen rollback» auf einen Stand ohne Kennung liegen) und der apt-Hook /etc/apt/apt.conf.d/60zenos-kennung.
#   Ist /usr/local/sbin für andere als root schreibbar, unterbleibt beides (und die Umstellung).
# - Version für os-release: /usr/local/share/zenos/version aus «git describe» von /opt/zenos, ohne «v» und «-dirty»
#   (auf dev nach einem Tag ehrlich als «0.1.0-rc2-18-g<commit>», auf einem Tag «0.1.0»).
# - Logo «zenos» (LOGO=zenos) als /usr/local/share/icons/hicolor/scalable/apps/zenos.svg (App-Icon der Bildmarke).
# - Vorab-Prüfung vor jeder Umstellung: die neue os-release zuerst in den Temp-Ordner, dann
#   «LSB_OS_RELEASE=<neu> zenos-sicherheitsquelle». Läuft nach 70-sicherheit, damit 51zenos-ubuntu-quellen schon liegt.
#     Exit 0 → «zenos-kennung einrichten» (idempotent: nur, was fehlt oder veraltet ist).
#     Exit 1 → keine Umstellung, Warnung. Gilt die Kennung zenOS schon, zurück auf Ubuntu (ohne Merker, der nächste
#              Lauf prüft wieder): Sicherheitsupdates gehen vor dem Namen (Manifest 1).
#     Exit 2 (nicht prüfbar) → keine erste Umstellung, Warnung; eine schon geltende Kennung zenOS wird nur
#              nachgezogen. Fehlen vor der ersten Umstellung nur die Paketlisten, einmal «apt-get update» und neu
#              prüfen.
# - «zenos-kennung ubuntu» merkt sich die Wahl (/var/lib/zenos/kennung); dann stellt install.sh nicht um.
# Läuft auch im Image-Modus (chroot): Dort liegen die Paketlisten nach dem apt-get update von 20-pakete vor, und
# image/bauen.sh prüft das Ergebnis danach.

_KENNUNG_PROGRAMM=/usr/local/sbin/zenos-kennung

modul_system() {
  _kennung_werkzeug || return 0
  _kennung_version
  datei_installieren "$ZENOS_CODE/assets/zeichen/zenos-app-icon.svg" \
    /usr/local/share/icons/hicolor/scalable/apps/zenos.svg 0644 root:root
  _kennung_umstellen
}

# Root führt das Programm aus: Jeder Ordner auf dem Weg gehört root und ist nur für root schreibbar
_kennung_pfad_sicher() {
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

_kennung_werkzeug() {
  if ! _kennung_pfad_sicher /usr/local/sbin; then
    log_warnung "/usr/local/sbin oder ein Ordner darüber ist nicht nur für root schreibbar: zenos-kennung und der apt-Hook bleiben weg, die Kennung bleibt Ubuntu"
    return 1
  fi
  datei_installieren "$ZENOS_CODE/scripts/bin/zenos-kennung" "$_KENNUNG_PROGRAMM" 0755 root:root
  datei_installieren "$ZENOS_CODE/system/apt/60zenos-kennung" /etc/apt/apt.conf.d/60zenos-kennung 0644 root:root
}

_kennung_version() {
  local version
  version=$(zenos_version "$ZENOS_CODE")
  version=${version#v}
  version=${version%-dirty}
  if [[ "$version" == unbekannt || ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+~_-]{0,63}$ ]]; then
    log_warnung "Version von zenOS nicht ermittelbar («$version»), /usr/local/share/zenos/version bleibt"
    return 0
  fi
  printf '%s\n' "$version" | datei_schreiben /usr/local/share/zenos/version 0644 root:root
}

# Führt zenos-kennung mit Root-Rechten aus; «geändert: …» zählt als Änderung, alles andere erscheint als Info
_kennung_ausfuehren() { # ARG…
  local ausgabe zeile rc=0
  ausgabe=$($SUDO "$_KENNUNG_PROGRAMM" "$@" 2>&1) || rc=$?
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] || continue
    case "$zeile" in
      "geändert: "*) aenderung "${zeile#geändert: }" ;;
      *) log_info "$zeile" ;;
    esac
  done <<< "$ausgabe"
  return "$rc"
}

# Gilt die Kennung zenOS (Umlenkung von /usr/lib/os-release vorhanden)?
_kennung_aktiv() {
  [[ "$(dpkg-divert --truename /usr/lib/os-release 2>/dev/null)" == /usr/lib/os-release.ubuntu ]]
}

_kennung_umstellen() {
  local stand rc=0 neu ausgabe pruefer="$ZENOS_CODE/scripts/bin/zenos-sicherheitsquelle"

  stand=$("$_KENNUNG_PROGRAMM" pruefen 2>&1) || rc=$?
  if (( rc == 3 )); then
    log_info "Kennung bleibt Ubuntu: ${stand%%$'\n'*}"
    return 0
  fi

  # Vorab-Prüfung: Liesse unattended-upgrades mit der neuen os-release die Ubuntu-Sicherheitsquelle noch zu?
  neu="$ZENOS_TMP/os-release.zenos"
  if ! ausgabe=$("$_KENNUNG_PROGRAMM" erzeugen 2>&1 > "$neu"); then
    log_warnung "Neue os-release liess sich nicht erzeugen: ${ausgabe#zenos-kennung: } – Kennung unverändert"
    return 0
  fi
  rc=0
  if [[ -x "$pruefer" ]]; then
    ausgabe=$(LSB_OS_RELEASE=$neu "$pruefer" 2>&1) || rc=$?
    # Vor der ersten Umstellung fehlen womöglich nur die Paketlisten (frisches System, Image ohne Listen): einmal
    # holen und noch einmal prüfen
    if (( rc == 2 )) && [[ "$ausgabe" == *"keine Paketliste"* ]] && ! _kennung_aktiv; then
      log_info "Paketlisten aktualisieren für die Vorab-Prüfung der Kennung"
      if apt_ausfuehren update -qq; then
        rc=0
        ausgabe=$(LSB_OS_RELEASE=$neu "$pruefer" 2>&1) || rc=$?
      fi
    fi
  else
    ausgabe="$pruefer fehlt"
    rc=2
  fi
  ausgabe=${ausgabe%%$'\n'*}

  case "$rc" in
    0) ;;
    1)
      # Ohne die Liste der erlaubten Quellen (steht in der vollen Ausgabe von zenos-sicherheitsquelle)
      ausgabe=${ausgabe#nicht erlaubt: }
      [[ "$ausgabe" != *"; erlaubt sind:"* ]] || ausgabe="${ausgabe%%; erlaubt sind:*})"
      if _kennung_aktiv; then
        log_warnung "Mit der Kennung zenOS liesse unattended-upgrades die Ubuntu-Sicherheitsquelle nicht zu: $ausgabe. Zurück auf die Kennung von Ubuntu; der nächste Lauf prüft wieder (zen doctor)."
        apt_warten || true
        _kennung_ausfuehren ubuntu --ohne-merker || log_warnung "zenos-kennung ubuntu ist gescheitert (sudo zenos-kennung ubuntu)"
      else
        log_warnung "Kennung bleibt Ubuntu: Mit zenOS liesse unattended-upgrades die Ubuntu-Sicherheitsquelle nicht zu: $ausgabe (zen doctor)"
      fi
      return 0
      ;;
    2)
      if ! _kennung_aktiv; then
        log_warnung "Kennung bleibt vorerst Ubuntu, Sicherheitsquelle nicht prüfbar: ${ausgabe#nicht prüfbar: }. Nach «sudo apt update» stellt der nächste Lauf um."
        return 0
      fi
      log_info "Sicherheitsquelle nicht prüfbar: ${ausgabe#nicht prüfbar: }. Die Kennung zenOS bleibt und wird nachgezogen."
      ;;
    *)
      log_warnung "zenos-sicherheitsquelle ist gescheitert (Exit $rc: $ausgabe) – Kennung unverändert"
      return 0
      ;;
  esac

  # Schon eingerichtet und aktuell: nichts zu tun (stand von oben, vor der Prüfung)
  [[ "$stand" != eingerichtet:* ]] || return 0
  apt_warten || true
  if ! _kennung_ausfuehren einrichten; then
    log_warnung "zenos-kennung einrichten ist gescheitert (Einzelheiten oben; sudo zenos-kennung pruefen)"
  fi
}
