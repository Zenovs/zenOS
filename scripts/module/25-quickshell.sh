#!/usr/bin/env bash
# 25-quickshell: Quickshell v0.3.1 aus dem Quellcode nach /usr/local (nur wenn der Stempel fehlt oder abweicht)
# shellcheck shell=bash
#
# Quickshell fehlt in den Ubuntu-Paketquellen. Gebaut wird genau der Commit von v0.3.1, geprüft nach dem
# Klonen. Quickshell nutzt private Qt-APIs, deshalb hält der Stempel /usr/local/share/zenos/quickshell.version
# neben Commit und Version auch die Version von libqt6core6t64 fest: Ändert sich Qt, wird neu gebaut.
# Lizenz (GNU LGPL 3): /usr/local/share/doc/quickshell/ mit copyright (Herkunft, Commit, Bauoptionen) und den
# Lizenztexten LICENSE (LGPL 3) und LICENSE-GPL (GPL 3), bei jedem Lauf, auch ohne Neubau. Die Texte kommen aus
# /usr/share/common-licenses (unveränderte Fassungen der FSF): LGPL-3 ist bytegleich mit LICENSE im Quellbaum von
# v0.3.1, GPL-3 hat gegenüber LICENSE-GPL dort nur zusätzlich den Anhang «How to Apply These Terms».
# Die Build-Abhängigkeiten (scripts/pakete/quickshell-bau.txt) bleiben danach installiert, damit ein
# Neubau nach einem Qt-Update ohne neue Downloads auskommt. Der Build-Ordner wird immer gelöscht.
# Läuft auch im --image-Modus.

modul_system() {
  local version=0.3.1 commit=1a4716cde794a59928d9d9fc15f2afc7a95de360
  local stempel=/usr/local/share/zenos/quickshell.version qt grund

  qt=$(_quickshell_qt_version)
  if [[ -n "$qt" ]] && _quickshell_stempel_passt "$stempel" "$commit" "$version" "$qt"; then
    log_info "Quickshell $version vorhanden (Qt $qt)"
    _quickshell_desktop_entfernen
    _quickshell_lizenz "$version" "$commit"
    return 0
  fi

  if [[ ! -x /usr/local/bin/quickshell ]]; then
    grund="noch nicht installiert"
  elif [[ ! -f "$stempel" ]]; then
    grund="ohne Stempel"
  elif ! grep -qxF -- "commit=$commit" "$stempel"; then
    grund="anderer Stand als v$version"
  else
    grund="Qt geändert: $(sed -n 's/^qt=//p' "$stempel" | head -n 1) → ${qt:-?}"
  fi
  log_info "Quickshell wird gebaut ($grund)"

  _quickshell_bauen "$version" "$commit"
  _quickshell_desktop_entfernen

  # Qt-Version erst nach dem Bau lesen: die Build-Abhängigkeiten können Qt aktualisiert haben
  qt=$(_quickshell_qt_version)
  [[ -n "$qt" ]] || abbruch "libqt6core6t64 ist nicht installiert"
  printf 'commit=%s\nversion=%s\nqt=%s\n' "$commit" "$version" "$qt" | datei_schreiben "$stempel" 0644 root:root
  _quickshell_lizenz "$version" "$commit"
}

# Bauoptionen für cmake, je Zeile eine (auch für copyright)
_quickshell_cmake_optionen() { # COMMIT
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DINSTALL_QML_PREFIX=lib/qt6/qml "-DDISTRIBUTOR=zenOS (Quellbau)" "-DGIT_REVISION=$1" -DCRASH_HANDLER=OFF \
    -DHYPRLAND=OFF -DI3=OFF -DX11=OFF
}

# copyright und Lizenztexte (Kopf dieser Datei)
_quickshell_lizenz() {
  local version=$1 commit=$2 ziel=/usr/local/share/doc/quickshell text optionen
  for text in LGPL-3 GPL-3; do
    [[ -f "/usr/share/common-licenses/$text" ]] || { log_warnung "/usr/share/common-licenses/$text fehlt (base-files)"; return 0; }
  done
  datei_installieren /usr/share/common-licenses/LGPL-3 "$ziel/LICENSE" 0644 root:root
  datei_installieren /usr/share/common-licenses/GPL-3 "$ziel/LICENSE-GPL" 0644 root:root
  optionen=$(_quickshell_cmake_optionen "$commit" | sed 's/.* .*/"&"/' | paste -sd ' ' -)
  datei_schreiben "$ziel/copyright" 0644 root:root <<TEXT
Quickshell $version, gebaut von zenOS aus dem unveränderten Quellcode
(scripts/module/25-quickshell.sh) und installiert unter /usr/local.

Quelle:   https://git.outfoxxed.me/quickshell/quickshell
Spiegel:  https://github.com/quickshell-mirror/quickshell
Tag:      v$version
Commit:   $commit
Bau:      cmake $optionen
          danach strip --strip-debug

Lizenz:   GNU Lesser General Public License, Version 3 (LICENSE), die auf der
          GNU General Public License, Version 3 aufbaut (LICENSE-GPL).
          Copyright: die Autorinnen und Autoren von Quickshell (siehe Quelle).

Den Quellcode zu genau diesem Commit gibt es unter der Quelle oben und auf der
Release-Seite jedes Images von zenOS, auch eines Release-Kandidaten
(siehe /usr/local/share/doc/zenos/QUELLEN).
TEXT
}

_quickshell_qt_version() {
  dpkg-query -W -f='${Version}' libqt6core6t64 2>/dev/null || true
}

# 0, wenn Programm und Stempel zum Soll passen
_quickshell_stempel_passt() {
  local stempel=$1 commit=$2 version=$3 qt=$4
  [[ -x /usr/local/bin/quickshell && -f "$stempel" ]] || return 1
  printf 'commit=%s\nversion=%s\nqt=%s\n' "$commit" "$version" "$qt" | cmp -s - "$stempel"
}

# Der Bau installiert einen Starter für Quickshell selbst; im Befehlsfeld hat er nichts zu suchen.
_quickshell_desktop_entfernen() {
  datei_entfernen /usr/local/share/applications/org.quickshell.desktop
}

_quickshell_bauen() {
  local version=$1 commit=$2 bau url ist jobs frei start zeile
  local -a abh=() woerter=() cmake_optionen
  local dauer

  # Build-Abhängigkeiten
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    read -ra woerter <<< "${zeile%%#*}"
    abh+=("${woerter[@]}")
  done < "$ZENOS_CODE/scripts/pakete/quickshell-bau.txt"
  pakete_sicherstellen "${abh[@]}"

  # Gebaut wird ohne Root-Rechte (im Image-Modus als root) in /var/tmp (auf der Platte, nicht im RAM).
  frei=$(df -P -k /var/tmp | awk 'NR == 2 { print $4 }')
  if [[ "$frei" =~ ^[0-9]+$ ]] && (( frei < 3670016 )); then
    abbruch "Zu wenig Platz in /var/tmp für den Quickshell-Bau (nötig etwa 3,5 GB, frei $(( frei / 1024 )) MB)"
  fi
  bau=$(mktemp -d /var/tmp/zenos-quickshell.XXXXXX)
  if [[ -n "$SUDO" ]]; then
    aufraeumen_bei_ende "$SUDO" rm -rf -- "$bau"
  else
    aufraeumen_bei_ende rm -rf -- "$bau"
  fi

  for url in https://git.outfoxxed.me/quickshell/quickshell https://github.com/quickshell-mirror/quickshell; do
    if git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "v$version" \
      -- "$url" "$bau/quelle" 2>"$bau/klonen.log"; then
      log_info "Quelle: $url (v$version)"
      break
    fi
    log_info "Quelle nicht erreichbar: $url"
    rm -rf -- "$bau/quelle"
  done
  [[ -d "$bau/quelle" ]] || abbruch "Quickshell-Quelle nicht erreichbar ($(tail -n 1 "$bau/klonen.log"))"
  ist=$(git -C "$bau/quelle" rev-parse --verify 'HEAD^{commit}')
  [[ "$ist" == "$commit" ]] || abbruch "Quickshell v$version zeigt auf $ist statt auf $commit – Quelle nicht vertrauenswürdig, Abbruch"

  # Parallelität nach Kernen und freiem Speicher (etwa 1,2 GB je Job)
  jobs=$(nproc 2>/dev/null || printf '1')
  local mem_kb
  mem_kb=$(_quickshell_speicher_kb)
  if [[ "$mem_kb" =~ ^[0-9]+$ ]] && (( mem_kb / 1200000 < jobs )); then jobs=$(( mem_kb / 1200000 )); fi
  (( jobs >= 1 )) || jobs=1

  mapfile -t cmake_optionen < <(_quickshell_cmake_optionen "$commit")
  log_info "Quickshell $version bauen mit $jobs Job(s) – auf dem Pi dauert das eine Weile"
  start=$SECONDS
  if ! cmake -S "$bau/quelle" -B "$bau/build" "${cmake_optionen[@]}" > "$bau/bau.log" 2>&1 ||
    ! cmake --build "$bau/build" --parallel "$jobs" >> "$bau/bau.log" 2>&1; then
    tail -n 40 -- "$bau/bau.log" >&2
    abbruch "Quickshell-Bau fehlgeschlagen (letzte Zeilen oben)"
  fi
  dauer=$(( SECONDS - start ))

  # Alte Installation entfernen (ein laufendes Programm behält seine Datei) und neu installieren
  $SUDO rm -f -- /usr/local/bin/quickshell /usr/local/bin/qs
  $SUDO rm -rf -- /usr/local/lib/qt6/qml/Quickshell
  $SUDO cmake --install "$bau/build" > "$bau/installieren.log" 2>&1 || {
    tail -n 20 -- "$bau/installieren.log" >&2
    abbruch "Quickshell-Installation fehlgeschlagen"
  }
  # Debug-Informationen entfernen (etwa 190 MB → 10 MB), Symbole bleiben für lesbare Absturzmeldungen
  $SUDO strip --strip-debug /usr/local/bin/quickshell
  while IFS= read -r -d '' zeile; do
    $SUDO strip --strip-debug -- "$zeile"
  done < <(find /usr/local/lib/qt6/qml/Quickshell -type f -name '*.so*' -print0 2>/dev/null)

  "/usr/local/bin/quickshell" --version >/dev/null 2>&1 || abbruch "Das gebaute Quickshell startet nicht (quickshell --version)"
  $SUDO rm -rf -- "$bau"
  aenderung "Quickshell $version gebaut und installiert ($(( dauer / 60 )) min $(( dauer % 60 )) s)"
}

# Freier Speicher in kB: MemAvailable, begrenzt durch memory.max der eigenen cgroup und ihrer Eltern
# (Container, CI). Für den Pi ohne Grenze gilt MemAvailable.
_quickshell_speicher_kb() {
  local frei rel pfad max akt
  frei=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null)
  [[ "$frei" =~ ^[0-9]+$ ]] || return 0
  rel=$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null | head -n 1)
  pfad=/sys/fs/cgroup${rel%/}
  while [[ -n "$rel" && -d "$pfad" ]]; do
    max=$(cat -- "$pfad/memory.max" 2>/dev/null) || max=""
    akt=$(cat -- "$pfad/memory.current" 2>/dev/null) || akt=""
    if [[ "$max" =~ ^[0-9]+$ && "$akt" =~ ^[0-9]+$ ]] && (( (max - akt) / 1024 < frei )); then
      frei=$(( (max - akt) / 1024 ))
    fi
    [[ "$pfad" != /sys/fs/cgroup ]] || break
    pfad=$(dirname -- "$pfad")
  done
  printf '%s' "$frei"
}
