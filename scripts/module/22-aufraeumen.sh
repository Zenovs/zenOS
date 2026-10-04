#!/usr/bin/env bash
# 22-aufraeumen: snapd und landscape-common entfernen, snapd per apt-Pin fernhalten
# shellcheck shell=bash
#
# Warum (CLAUDE.md, Regel 8): snapd ist Store-Software, die von selbst ins Netz geht (Snaps aktualisieren, beim Store
# nachfragen), und zenOS braucht sie nicht. landscape-common trägt nur die Marke Landscape (Systeminfo bei der
# Anmeldung) und hat ohne Landscape-Konto keine Funktion. Beide bringt ubuntu-server als Empfehlung mit; das Metapaket
# bleibt installiert und führt sie danach nur noch als Empfehlung.
#
# Läuft nach 20-pakete: Dort sind alle zenOS-Pakete schon als manuell installiert markiert. Dieses Modul ruft nie
# «apt autoremove» auf; was landscape-common mitgebracht hat (bc, python3-twisted …), bleibt liegen.
#
# Ablauf, je Paket nur, wenn es installiert ist:
# - Nur, was apt als «automatisch installiert» führt (so kommen beide mit ubuntu-server). Wer eines bewusst mit
#   «apt install» installiert hat (Rückweg, docs/module/m11.md), dem lässt zenOS es.
# - Schutz für snapd: Sind Snaps ausser dem Grundbestand installiert (snapd, core*, bare; scripts/lib/aufraeumen.sh),
#   bleibt snapd, mit einer Warnung samt Namen und Weg (zen doctor: Hinweis). Lässt sich das nicht feststellen,
#   bleibt es ebenfalls. landscape-common geht trotzdem.
# - Erst «apt-get -s purge» als Probelauf, je Paket und dann zusammen: Ginge dabei mehr weg als die Ziele und
#   automatisch installierte Pakete aus demselben Quellpaket (etwa ein ubuntu-*-Metapaket, ein zenOS-Paket oder sonst
#   ein manuell installiertes), bleibt dieses Ziel (Warnung). Ein gesperrtes Ziel hält das andere nicht auf.
# - Dann «apt-get purge -y», ohne die policy-rc.d von pakete_sicherstellen: snapd hält beim Entfernen seine Dienste
#   und Einhängepunkte an, das soll es dürfen. Das purge von snapd löscht nur Systemordner (/var/lib/snapd samt Seed,
#   /var/snap, /snap, /var/cache/snapd), nie ~/snap.
# - Pin /etc/apt/preferences.d/zenos-ohne-snapd (Pin-Priority -10), genau solange snapd nicht installiert ist: apt
#   bringt snapd dann nie zurück, auch nicht als Empfehlung bei einem Update. Bleibt snapd installiert, kommt der Pin
#   weg; er hielte snapd sonst auf seiner Version fest, ohne Sicherheitsupdates.
# Im Image-Modus (chroot, image/bauen.sh) läuft dasselbe. Dort ist noch kein Snap installiert (state.json fehlt), das
# purge räumt den Seed unter /var/lib/snapd/seed mit weg, und apt_warten wartet nicht.

# shellcheck source=../lib/aufraeumen.sh
source "$ZENOS_QUELLE/scripts/lib/aufraeumen.sh"

modul_system() {
  local paket
  local -a ziele=()
  for paket in "${_AUFRAEUMEN_ZIELE[@]}"; do
    if _aufraeumen_soll_weg "$paket"; then ziele+=("$paket"); fi
  done
  if (( ${#ziele[@]} > 0 )); then _aufraeumen_entfernen "${ziele[@]}"; fi
  _aufraeumen_pin
}

# 0, wenn PAKET weg soll: installiert, automatisch installiert und bei snapd ohne eigene Snaps
_aufraeumen_soll_weg() { # PAKET
  local paket=$1 manuell eigene rc=0
  paket_installiert "$paket" || return 1
  manuell=$(apt-mark showmanual "$paket" 2>/dev/null) || manuell=""
  if [[ -n "$manuell" ]]; then
    log_info "$paket ist als manuell installiert markiert und bleibt (entfernen: sudo apt-mark auto $paket, dann zen update)"
    return 1
  fi
  [[ "$paket" == snapd ]] || return 0

  eigene=$(_aufraeumen_eigene_snaps) || rc=$?
  if (( rc != 0 )); then
    log_warnung "snapd bleibt: Welche Snaps installiert sind, liess sich nicht feststellen (/var/lib/snapd/state.json nicht lesbar)"
    return 1
  fi
  if [[ -n "$eigene" ]]; then
    # Namen von snapd, nur [a-z0-9_-] (geprüft in scripts/lib/aufraeumen.sh)
    local -a namen=()
    mapfile -t namen <<< "$eigene"
    log_warnung "snapd bleibt, weil eigene Snaps installiert sind: $(_aufraeumen_liste "${namen[@]}"). Selbst erledigen:" \
      "Daten aus ~/snap/<name> sichern, je Snap «sudo snap remove <name>», dann zen update. zenOS löscht ~/snap nie."
    return 1
  fi
  return 0
}

# Eigene Snaps (ohne Grundbestand), je Zeile einer. Quellen: state.json von snapd (nur root lesbar; fehlt sie, hat
# snapd noch nie einen Snap installiert, etwa im Image vor dem ersten Start), die Snap-Dateien unter
# /var/lib/snapd/snaps und, nur wenn snapd gerade läuft, «snap list». Nicht allein snap list: Ruht snapd, startete ein
# Aufruf es über snapd.socket. Exit 1, wenn state.json da, aber nicht lesbar ist.
_aufraeumen_eigene_snaps() {
  local state=/var/lib/snapd/state.json gefunden="" teil
  if $SUDO test -e "$state"; then
    teil=$($SUDO cat -- "$state" | _aufraeumen_state_liste) || return 1
    gefunden+=$teil$'\n'
  fi
  teil=$({ $SUDO find /var/lib/snapd/snaps -maxdepth 1 ! -type d -name '*.snap' -printf '%f\n' 2>/dev/null || true; } |
    _aufraeumen_snap_dateien)
  gefunden+=$teil$'\n'
  if [[ "$ZENOS_SYSTEMD" == 1 ]] && systemctl --quiet is-active snapd.service 2>/dev/null; then
    teil=$({ LC_ALL=C timeout 60 snap list 2>/dev/null || true; } | _aufraeumen_snap_liste)
    gefunden+=$teil$'\n'
  fi
  printf '%s' "$gefunden" | _aufraeumen_eigene
}

# Alle Pakete aus scripts/pakete/*.txt (auch die Build-Abhängigkeiten von Quickshell), je Zeile eines
_aufraeumen_zenos_pakete() {
  local datei
  for datei in "$ZENOS_CODE"/scripts/pakete/*.txt; do
    [[ -f "$datei" ]] || continue
    sed 's/#.*//' "$datei" | tr -s '[:space:]' '\n'
  done | sed '/^$/d'
}

# Probelauf «apt-get -s purge ZIEL…» (braucht kein root) und Prüfung (scripts/lib/aufraeumen.sh). Nie autoremove,
# auch dann nicht, wenn es jemand in apt.conf eingeschaltet hat. Geschützt sind die festen Ubuntu-Pakete, die
# zenOS-Pakete und alles, was als manuell installiert gilt (auch ein bewusst installiertes landscape-client). 0, wenn
# nur die Ziele und ihre eigenen Teile gingen; sonst eine Warnung und 1.
_aufraeumen_probe() { # ZIEL…
  local tmp rc=0 pruefung
  local -a befund=()
  tmp=$(mktemp -d "${ZENOS_TMP:-${TMPDIR:-/tmp}}/zenos-aufraeumen.XXXXXX")
  LC_ALL=C apt-get -s -o APT::Get::AutomaticRemove=false purge "$@" > "$tmp/probe" 2>&1 || rc=$?
  if (( rc != 0 )); then
    log_warnung "Probelauf «apt-get -s purge $*» ist gescheitert (Exit $rc), nichts entfernt: $(tail -n 1 -- "$tmp/probe")"
    rm -rf -- "$tmp"
    return 1
  fi
  { dpkg-query -W -f='${db:Status-Status} ${Package} ${source:Package}\n' 2>/dev/null || true; } |
    awk '$1 == "installed" { print $2, $3 }' > "$tmp/quellen"
  {
    _aufraeumen_geschuetzt
    _aufraeumen_zenos_pakete
    apt-mark showmanual 2>/dev/null || true
  } > "$tmp/geschuetzt"
  rc=0
  pruefung=$(_aufraeumen_simulation_pruefen "$tmp/probe" "$tmp/quellen" "$tmp/geschuetzt" "$@") || rc=$?
  rm -rf -- "$tmp"
  (( rc != 0 )) || return 0
  mapfile -t befund < <(sed -e 's/^mehr: /ginge mit: /' -e 's/^geschuetzt: /ginge mit, ist aber geschützt: /' \
    -e 's/^installiert: /würde installiert: /' -e 's/^fehlt: /bliebe installiert: /' <<< "$pruefung")
  log_warnung "apt-get purge $* nähme mehr mit als freigegeben, nichts entfernt ($(_aufraeumen_liste "${befund[@]}"))." \
    "Prüfen: apt-get -s purge $*"
  return 1
}

# Erst jedes Paket für sich im Probelauf (ein gesperrtes hält das andere nicht auf), dann beide zusammen
_aufraeumen_entfernen() { # PAKET…
  local rc=0 paket
  local -a frei=() weg=() uebrig=()
  apt_warten || true
  for paket in "$@"; do
    if _aufraeumen_probe "$paket"; then frei+=("$paket"); fi
  done
  (( ${#frei[@]} > 0 )) || return 0
  if (( ${#frei[@]} > 1 )) && ! _aufraeumen_probe "${frei[@]}"; then return 0; fi

  log_info "Entfernen mit apt-get purge: ${frei[*]}"
  apt_ausfuehren purge -y -q -o APT::Get::AutomaticRemove=false "${frei[@]}" || rc=$?
  for paket in "${frei[@]}"; do
    if paket_installiert "$paket"; then uebrig+=("$paket"); else weg+=("$paket"); fi
  done
  if (( ${#weg[@]} > 0 )); then aenderung "Entfernt (apt-get purge): ${weg[*]}"; fi
  if (( rc != 0 || ${#uebrig[@]} > 0 )); then
    log_warnung "apt-get purge ist gescheitert (Exit $rc)${uebrig[*]:+, noch installiert: ${uebrig[*]}}." \
      "Einzelheiten in /var/log/apt/term.log; der nächste Lauf versucht es wieder."
  fi
}

# Pin genau dann, wenn snapd nicht installiert ist (Kopf dieser Datei)
_aufraeumen_pin() {
  if paket_installiert snapd; then
    if [[ -e "$_AUFRAEUMEN_PIN" || -L "$_AUFRAEUMEN_PIN" ]]; then
      datei_entfernen "$_AUFRAEUMEN_PIN"
      log_info "snapd bleibt installiert: Pin entfernt, sonst bekäme es keine Updates mehr"
    fi
    return 0
  fi
  datei_installieren "$ZENOS_CODE/system/apt/zenos-ohne-snapd" "$_AUFRAEUMEN_PIN"
}
