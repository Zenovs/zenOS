#!/usr/bin/env bash
# hilfe: bootsplash [status|aktivieren|deaktivieren] – Bootsplash (Plymouth) anzeigen, einschalten oder ausschalten
# install.sh legt das Theme nur ab (/usr/share/plymouth/themes/zenos). «aktivieren» zeigt jeden Schritt (Pakete
# plymouth und plymouth-label, Standard-Theme, DeviceScale, «quiet splash» in der Boot-Kommandozeile, initramfs),
# sichert die Kommandozeile nach /var/backups/zenos und schaltet erst nach der Eingabe «aktivieren» ein.
# «deaktivieren» nimmt genau das zurück (Eingabe «deaktivieren»); die Pakete bleiben. Auf dem Pi läuft der nächste
# Start danach zweimal: piboot-try prüft die neuen Startdateien und fällt bei einem Fehler auf die bisherigen zurück.
# Boot über GRUB (Bürorechner) kommt später.
# shellcheck shell=bash

# Die lesenden Hilfsfunktionen nutzt auch scripts/doctor.d/42-bootsplash.sh.

_BOOTSPLASH_ORDNER=/usr/share/plymouth/themes/zenos
_BOOTSPLASH_THEME=$_BOOTSPLASH_ORDNER/zenos.plymouth
_BOOTSPLASH_ALTERNATIVE=/usr/share/plymouth/themes/default.plymouth
_BOOTSPLASH_KONF=/etc/plymouth/plymouthd.conf
# Welche Wörter zen bootsplash in welche Kommandozeile gesetzt hat (für «deaktivieren»)
_BOOTSPLASH_ZUSTAND=/var/lib/zenos/bootsplash
_BOOTSPLASH_SICHERUNG=/var/backups/zenos
_BOOTSPLASH_WOERTER=(quiet splash)
# Ohne Label-Plugin stürzt das Modul script von Plymouth 24 beim ersten Bild ab (ply_console_viewer_hide mit NULL)
_BOOTSPLASH_PAKETE=(plymouth plymouth-label)
_BOOTSPLASH_ANFANG='# zenOS-Bootsplash (zen bootsplash): Anfang'
_BOOTSPLASH_ENDE='# zenOS-Bootsplash: Ende'

befehl_bootsplash() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen bootsplash [status|aktivieren|deaktivieren])"
    return 2
  fi
  case "${1:-status}" in
    status) _bootsplash_status ;;
    aktivieren) _bootsplash_aktivieren ;;
    deaktivieren) _bootsplash_deaktivieren ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, aktivieren, deaktivieren)"
      return 2
      ;;
  esac
}

# --- lesen (auch für zen doctor) ---------------------------------------------

# pi-try: Pi mit piboot-try (Ubuntu ab 24.04, Startdateien unter /boot/firmware/current), pi: Kommandozeile direkt in
# /boot/firmware, grub, unbekannt
_bootsplash_art() {
  if [[ -f /boot/firmware/current/cmdline.txt ]]; then
    printf 'pi-try'
  elif [[ -f /boot/firmware/cmdline.txt ]]; then
    printf 'pi'
  elif [[ -f /etc/default/grub ]]; then
    printf 'grub'
  else
    printf 'unbekannt'
  fi
}

_bootsplash_datei() {
  case "$(_bootsplash_art)" in
    pi-try) printf '/boot/firmware/current/cmdline.txt' ;;
    pi) printf '/boot/firmware/cmdline.txt' ;;
    grub) printf '/etc/default/grub' ;;
  esac
}

# Die Kommandozeile: beim Pi die erste Zeile der Datei, bei GRUB GRUB_CMDLINE_LINUX_DEFAULT (nur lesen)
_bootsplash_zeile() { # DATEI
  local -a lesen=()
  [[ -e "$1" ]] || return 0
  if [[ ! -r "$1" ]]; then
    # Nicht lesbar: nur mit sudo ohne Passwort (status und zen doctor fragen nie nach einem)
    sudo -n true 2> /dev/null || return 0
    lesen=(sudo -n)
  fi
  if [[ "$1" == /etc/default/grub ]]; then
    "${lesen[@]}" sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT=//p' -- "$1" | tail -n 1 | tr -d '"'"'"
  else
    "${lesen[@]}" head -n 1 -- "$1" | tr -d '\r'
  fi
}

# Wie systemd (ConditionKernelCommandLine): das Wort allein oder als linke Seite von «wort=…»
_bootsplash_hat_wort() { # ZEILE WORT
  local -a woerter=()
  local w
  read -ra woerter <<< "$1"
  for w in "${woerter[@]}"; do
    [[ "$w" == "$2" || "$w" == "$2="* ]] && return 0
  done
  return 1
}

_bootsplash_fehlend() { # ZEILE → fehlende Wörter aus _BOOTSPLASH_WOERTER, je Zeile eins
  local w
  for w in "${_BOOTSPLASH_WOERTER[@]}"; do
    _bootsplash_hat_wort "$1" "$w" || printf '%s\n' "$w"
  done
}

# Theme, auf das default.plymouth zeigt (leer: keins, Plymouth zeigt dann nur Text)
_bootsplash_standard() {
  { update-alternatives --query default.plymouth 2> /dev/null || true; } | sed -n 's/^Value: //p'
}

# Pakete aus _BOOTSPLASH_PAKETE, die fehlen (je Zeile eins)
_bootsplash_pakete_fehlend() {
  local paket
  for paket in "${_BOOTSPLASH_PAKETE[@]}"; do
    [[ "$(dpkg-query -W -f='${db:Status-Status}' "$paket" 2> /dev/null)" == installed ]] || printf '%s\n' "$paket"
  done
}

# 0, wenn plymouth mit dem Modul script und einem Label-Plugin installiert ist
_bootsplash_paket() {
  local pfad
  [[ -z "$(_bootsplash_pakete_fehlend)" ]] || return 1
  pfad=$(plymouth --get-splash-plugin-path 2> /dev/null) || return 1
  [[ -f "${pfad%/}/script.so" && -f "${pfad%/}/label-pango.so" ]]
}

# zenos: DeviceScale von zen bootsplash, eigen: von Hand gesetzt, frei: nicht gesetzt
_bootsplash_skala() {
  if grep -qxF -- "$_BOOTSPLASH_ANFANG" "$_BOOTSPLASH_KONF" 2> /dev/null; then
    printf 'zenos'
  elif grep -Eq '^[[:space:]]*DeviceScale[[:space:]]*=' "$_BOOTSPLASH_KONF" 2> /dev/null; then
    printf 'eigen'
  else
    printf 'frei'
  fi
}

# Gespeicherter Wert aus _BOOTSPLASH_ZUSTAND (datei, woerter)
_bootsplash_gespeichert() { # SCHLUESSEL
  [[ -r "$_BOOTSPLASH_ZUSTAND" ]] || return 0
  sed -n "s/^$1=//p" -- "$_BOOTSPLASH_ZUSTAND" | tail -n 1
}

_bootsplash_initrd() { printf '/boot/initrd.img-%s' "$(uname -r)"; }

# 0, wenn das initramfs älter ist als Theme, Standard-Theme oder plymouthd.conf (dann fehlt dort der Stand)
_bootsplash_initramfs_alt() {
  local initrd neuer
  initrd=$(_bootsplash_initrd)
  [[ -f "$initrd" ]] || return 1
  # find vergleicht beim Verweis in /etc/alternatives dessen eigene Zeit (wann das Standard-Theme gesetzt wurde)
  neuer=$( {
    find "$_BOOTSPLASH_ORDNER" -type f -newer "$initrd" -print -quit
    find /etc/alternatives/default.plymouth "$_BOOTSPLASH_KONF" -maxdepth 0 -newer "$initrd" -print
  } 2> /dev/null)
  [[ -n "$neuer" ]]
}

# aktiv, vorbereitet, teilweise oder fehlt
_bootsplash_zustand() {
  local datei zeile standard=0 wort=0
  [[ -f "$_BOOTSPLASH_THEME" ]] || { printf 'fehlt'; return 0; }
  [[ "$(_bootsplash_standard)" == "$_BOOTSPLASH_THEME" ]] && standard=1
  datei=$(_bootsplash_datei)
  if [[ -n "$datei" ]]; then
    zeile=$(_bootsplash_zeile "$datei")
    _bootsplash_hat_wort "$zeile" splash && wort=1
  fi
  if (( standard && wort )) && _bootsplash_paket; then
    printf 'aktiv'
  elif (( standard )) || [[ -f "$_BOOTSPLASH_ZUSTAND" || "$(_bootsplash_skala)" == zenos ]]; then
    printf 'teilweise'
  else
    printf 'vorbereitet'
  fi
}

# Theme-Dateien, die unter QUELLE anders sind als installiert: «fehlt DATEI», «anders DATEI», «übrig DATEI»
_bootsplash_abweichungen() { # QUELLE
  local quelle=$1 rel
  local -A soll=()
  while IFS= read -r rel; do
    soll[$rel]=1
    if [[ ! -f "$_BOOTSPLASH_ORDNER/$rel" ]]; then
      printf 'fehlt %s\n' "$rel"
    elif ! cmp -s -- "$quelle/$rel" "$_BOOTSPLASH_ORDNER/$rel"; then
      printf 'anders %s\n' "$rel"
    fi
  done < <(find "$quelle" -type f \( -name '*.plymouth' -o -name '*.script' -o -name '*.png' \) -printf '%P\n' 2> /dev/null)
  [[ -d "$_BOOTSPLASH_ORDNER" ]] || return 0
  while IFS= read -r rel; do
    [[ -n "${soll[$rel]:-}" ]] || printf 'übrig %s\n' "$rel"
  done < <(find "$_BOOTSPLASH_ORDNER" -type f -printf '%P\n')
}

# --- status ------------------------------------------------------------------

_bootsplash_status() {
  local zustand art datei zeile standard skala laufend fehlend
  zustand=$(_bootsplash_zustand)
  art=$(_bootsplash_art)
  datei=$(_bootsplash_datei)
  case "$zustand" in
    aktiv) printf 'Bootsplash: aktiv\n' ;;
    vorbereitet) printf 'Bootsplash: vorbereitet, nicht aktiv\n' ;;
    teilweise) printf 'Bootsplash: teilweise eingeschaltet\n' ;;
    fehlt) printf 'Bootsplash: Theme fehlt (install.sh ausführen)\n' ;;
  esac

  if [[ -f "$_BOOTSPLASH_THEME" ]]; then
    _bootsplash_punkt Theme "installiert ($_BOOTSPLASH_ORDNER)"
  else
    _bootsplash_punkt Theme "fehlt unter $_BOOTSPLASH_ORDNER"
  fi
  if _bootsplash_paket; then
    _bootsplash_punkt Plymouth "installiert, mit den Modulen script und label-pango"
  else
    fehlend=$(_bootsplash_pakete_fehlend | tr '\n' ' ')
    fehlend=${fehlend% }
    _bootsplash_punkt Plymouth "es fehlt ${fehlend:-das Modul script oder label-pango} (aktivieren installiert es)"
  fi
  standard=$(_bootsplash_standard)
  case "$standard" in
    "$_BOOTSPLASH_THEME") _bootsplash_punkt Standard-Theme "zenos" ;;
    "") _bootsplash_punkt Standard-Theme "keins (Plymouth zeigt nur Text)" ;;
    *) _bootsplash_punkt Standard-Theme "$(basename -- "$standard" .plymouth) ($standard)" ;;
  esac
  skala=$(_bootsplash_skala)
  case "$skala" in
    zenos) _bootsplash_punkt Bildschirmpixel "DeviceScale=1 von zen bootsplash ($_BOOTSPLASH_KONF)" ;;
    eigen) _bootsplash_punkt Bildschirmpixel "DeviceScale von Hand gesetzt ($_BOOTSPLASH_KONF)" ;;
    frei) _bootsplash_punkt Bildschirmpixel "nicht festgelegt (ab 2880 × 1620 vergrössert Plymouth selbst)" ;;
  esac

  case "$art" in
    pi-try | pi | grub)
      zeile=$(_bootsplash_zeile "$datei")
      if _bootsplash_hat_wort "$zeile" splash; then
        _bootsplash_punkt Kommandozeile "$datei mit «splash»"
      else
        _bootsplash_punkt Kommandozeile "$datei ohne «splash»"
      fi
      ;;
    *) _bootsplash_punkt Kommandozeile "nicht gefunden" ;;
  esac
  laufend=$(cat /proc/cmdline 2> /dev/null || true)
  if _bootsplash_hat_wort "$laufend" splash; then
    _bootsplash_punkt "Laufender Start" "mit «splash»"
  else
    _bootsplash_punkt "Laufender Start" "ohne «splash»"
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" ]]; then
    if _bootsplash_initramfs_alt; then
      _bootsplash_punkt initramfs "älter als das Theme (zen bootsplash aktivieren baut es neu)"
    elif [[ -f "$(_bootsplash_initrd)" ]]; then
      _bootsplash_punkt initramfs "enthält das Theme ($(_bootsplash_initrd))"
    fi
  fi
  if [[ "$art" == pi-try && "$(cat /boot/firmware/new/state 2> /dev/null)" == unknown ]]; then
    _bootsplash_punkt Startdateien "neue in /boot/firmware/new, der nächste Start läuft zweimal"
  fi

  printf '\n'
  case "$zustand" in
    aktiv) printf 'Ausschalten: zen bootsplash deaktivieren\n' ;;
    vorbereitet) printf 'Einschalten: zen bootsplash aktivieren\n' ;;
    teilweise) printf 'Ganz einschalten: zen bootsplash aktivieren · zurück: zen bootsplash deaktivieren\n' ;;
  esac
}

_bootsplash_punkt() { printf '  %-17s %s\n' "$1" "$2"; }

# --- schreiben ---------------------------------------------------------------

# Kopie nach /var/backups/zenos, Name aus dem Pfad und der Zeit
_bootsplash_sichern() { # DATEI → Pfad der Sicherung
  local datei=$1 name ziel
  name=${datei#/}
  name=${name//\//-}
  ziel="$_BOOTSPLASH_SICHERUNG/$name.$(date +%Y%m%d-%H%M%S)"
  $SUDO install -d -m 0755 -- "$_BOOTSPLASH_SICHERUNG" || return 1
  $SUDO cp -p -- "$datei" "$ziel" || return 1
  printf '%s' "$ziel"
}

# Ersetzt die erste Zeile, alles andere bleibt (auch ein fehlender Zeilenumbruch am Ende). Über eine neue Datei
# daneben und mv, damit nie eine halbe Kommandozeile auf der Karte steht. Rechte wie vorher (auf FAT ohne Wirkung).
_bootsplash_zeile_schreiben() { # DATEI ZEILE
  local datei=$1 zeile=$2 tmp umbrueche modus
  tmp=$(mktemp) || return 1
  chmod 0644 -- "$tmp"
  modus=$($SUDO stat -c '%a' -- "$datei") || modus=644
  umbrueche=$($SUDO wc -l -- "$datei" | awk '{ print $1 }')
  if [[ ! "$umbrueche" =~ ^[0-9]+$ ]] || ! {
    printf '%s' "$zeile"
    if (( umbrueche > 0 )); then printf '\n'; fi
    $SUDO tail -n +2 -- "$datei"
  } > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! $SUDO cp -- "$tmp" "$datei.zenos-neu" || ! $SUDO mv -f -- "$datei.zenos-neu" "$datei"; then
    rm -f -- "$tmp"
    $SUDO rm -f -- "$datei.zenos-neu"
    return 1
  fi
  $SUDO chmod "$modus" -- "$datei" 2> /dev/null || true
  rm -f -- "$tmp"
}

# Hängt Wörter mit je einem Leerzeichen an bzw. nimmt sie wieder weg (je das letzte Vorkommen als ganzes Wort,
# samt Leerzeichen davor); der Rest der Zeile bleibt Zeichen für Zeichen, wie er war
_bootsplash_woerter_dazu() { # ZEILE WORT…
  local zeile=$1 w
  shift
  for w in "$@"; do zeile+=" $w"; done
  printf '%s' "$zeile"
}

_bootsplash_woerter_weg() { # ZEILE WORT…
  local zeile=$1 w
  shift
  for w in "$@"; do
    if [[ "$zeile" =~ ^(.*)[[:space:]]"$w"([[:space:]].*)?$ ]]; then
      zeile=${BASH_REMATCH[1]}${BASH_REMATCH[2]}
    elif [[ "$zeile" =~ ^"$w"([[:space:]]+(.*))?$ ]]; then
      zeile=${BASH_REMATCH[2]}
    fi
  done
  printf '%s' "$zeile"
}

_bootsplash_konf_schreiben() { # Inhalt von stdin
  local tmp
  tmp=$(mktemp) || return 1
  cat > "$tmp"
  $SUDO install -d -m 0755 -- "${_BOOTSPLASH_KONF%/*}" && $SUDO install -m 0644 -- "$tmp" "$_BOOTSPLASH_KONF"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

# DeviceScale=1 zwischen Markierungen: in einen vorhandenen Abschnitt [Daemon], sonst mit eigenem Abschnitt am Ende
_bootsplash_skala_setzen() {
  local konf=$_BOOTSPLASH_KONF
  if [[ -f "$konf" ]] && grep -Eq '^[[:space:]]*\[Daemon\][[:space:]]*$' "$konf"; then
    awk -v a="$_BOOTSPLASH_ANFANG" -v e="$_BOOTSPLASH_ENDE" '
      { print }
      !fertig && /^[[:space:]]*\[Daemon\][[:space:]]*$/ { print a; print "DeviceScale=1"; print e; fertig = 1 }
    ' "$konf" | _bootsplash_konf_schreiben
  else
    {
      if [[ -s "$konf" ]]; then
        cat -- "$konf"
        [[ -z "$(tail -c 1 -- "$konf")" ]] || printf '\n'
      fi
      printf '%s\n[Daemon]\nDeviceScale=1\n%s\n' "$_BOOTSPLASH_ANFANG" "$_BOOTSPLASH_ENDE"
    } | _bootsplash_konf_schreiben
  fi
}

_bootsplash_skala_entfernen() {
  awk -v a="$_BOOTSPLASH_ANFANG" -v e="$_BOOTSPLASH_ENDE" '
    $0 == a { weg = 1; next }
    weg && $0 == e { weg = 0; next }
    !weg { print }
  ' "$_BOOTSPLASH_KONF" | _bootsplash_konf_schreiben
}

# update-initramfs; auf dem Pi schreibt flash-kernel danach /boot/firmware/new/ mit einer Kopie der Kommandozeile
_bootsplash_initramfs() {
  printf '\ninitramfs wird neu gebaut …\n'
  $SUDO update-initramfs -u
}

# Kommandozeile in /boot/firmware/new an current angleichen (flash-kernel kopiert sie, hier nur zur Sicherheit)
_bootsplash_new_angleichen() { # dazu|weg WORT…
  local art=$1 neu=/boot/firmware/new/cmdline.txt zeile ziel
  shift
  [[ -f "$neu" ]] || return 0
  zeile=$(_bootsplash_zeile "$neu")
  if [[ "$art" == dazu ]]; then
    local -a fehlend=()
    local w
    for w in "$@"; do _bootsplash_hat_wort "$zeile" "$w" || fehlend+=("$w"); done
    (( ${#fehlend[@]} > 0 )) || return 0
    ziel=$(_bootsplash_woerter_dazu "$zeile" "${fehlend[@]}")
  else
    ziel=$(_bootsplash_woerter_weg "$zeile" "$@")
    [[ "$ziel" != "$zeile" ]] || return 0
  fi
  _bootsplash_zeile_schreiben "$neu" "$ziel" && printf '%s angepasst\n' "$neu"
}

_bootsplash_zustand_schreiben() { # DATEI WOERTER
  local tmp
  tmp=$(mktemp) || return 1
  printf '# zen bootsplash: in die Boot-Kommandozeile gesetzt (für «zen bootsplash deaktivieren»)\ndatei=%s\nwoerter=%s\n' \
    "$1" "$2" > "$tmp"
  $SUDO install -d -m 0755 -- "${_BOOTSPLASH_ZUSTAND%/*}" && $SUDO install -m 0644 -- "$tmp" "$_BOOTSPLASH_ZUSTAND"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_bootsplash_bestaetigen() { # WORT
  local antwort=""
  read -r -p "Zum Fortfahren «$1» eintippen (alles andere bricht ab): " antwort || antwort=""
  [[ "$antwort" == "$1" ]]
}

# --- aktivieren --------------------------------------------------------------

_bootsplash_aktivieren() {
  local art datei zeile neu skala standard initramfs=0 n=1 w sicherung bisher
  local -a fehlend=() gesetzt=() pakete=()
  art=$(_bootsplash_art)
  case "$art" in
    pi-try | pi) ;;
    grub)
      zen_fehler "Dieser Rechner startet über GRUB. Das kann zen bootsplash noch nicht (kommt mit dem Bürorechner); es bleibt alles, wie es ist."
      return 1
      ;;
    *)
      zen_fehler "Keine Boot-Kommandozeile gefunden (/boot/firmware/current/cmdline.txt oder /boot/firmware/cmdline.txt); es bleibt alles, wie es ist."
      return 1
      ;;
  esac
  if [[ ! -f "$_BOOTSPLASH_THEME" ]]; then
    zen_fehler "Das Theme fehlt unter $_BOOTSPLASH_ORDNER (install.sh ausführen)"
    return 1
  fi
  if ! befehl_vorhanden update-initramfs; then
    zen_fehler "update-initramfs fehlt (dracut); es bleibt alles, wie es ist."
    return 1
  fi

  datei=$(_bootsplash_datei)
  zeile=$(_bootsplash_zeile "$datei")
  if [[ -z "${zeile//[[:space:]]/}" ]]; then
    zen_fehler "$datei ist leer; es bleibt alles, wie es ist."
    return 1
  fi
  mapfile -t fehlend < <(_bootsplash_fehlend "$zeile")
  neu=$(_bootsplash_woerter_dazu "$zeile" "${fehlend[@]}")
  mapfile -t pakete < <(_bootsplash_pakete_fehlend)
  skala=$(_bootsplash_skala)
  standard=$(_bootsplash_standard)

  if (( ${#pakete[@]} == 0 && ${#fehlend[@]} == 0 )) && [[ "$skala" != frei && "$standard" == "$_BOOTSPLASH_THEME" ]]; then
    if ! _bootsplash_initramfs_alt; then
      printf 'Der Bootsplash ist schon eingeschaltet.\n\n'
      _bootsplash_status
      return 0
    fi
    initramfs=1
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen bootsplash aktivieren braucht eine Bestätigung im Terminal (Eingabe «aktivieren»)"
    return 2
  fi

  if (( initramfs )); then
    printf 'Der Bootsplash ist eingeschaltet, das initramfs aber älter als das Theme:\n\n'
  else
    printf 'zen bootsplash aktivieren schaltet den Bootsplash von zenOS ein:\n\n'
  fi
  if (( ${#fehlend[@]} > 0 )); then
    printf '  %d. Boot-Kommandozeile %s: «%s» anhängen, sonst nichts\n' "$n" "$datei" "${fehlend[*]}"
    printf '     vorher:  %s\n     nachher: %s\n' "$zeile" "$neu"
    printf '     Sicherung vorher nach %s/\n' "$_BOOTSPLASH_SICHERUNG"
    n=$((n + 1))
  fi
  if (( ${#pakete[@]} > 0 )); then
    printf '  %d. Pakete installieren: %s (apt-get, mit Abhängigkeiten)\n' "$n" "${pakete[*]}"
    printf '     plymouth-label setzt Text; ohne stürzt das Modul script von Plymouth ab.'
    if [[ " ${pakete[*]} " == *" plymouth "* ]]; then
      printf ' plymouth stösst selbst update-initramfs an.'
    fi
    printf '\n'
    n=$((n + 1))
  fi
  if [[ "$standard" != "$_BOOTSPLASH_THEME" ]]; then
    printf '  %d. Standard-Theme: default.plymouth → %s (update-alternatives, bisher: %s)\n' "$n" "$_BOOTSPLASH_THEME" \
      "${standard:-keins}"
    n=$((n + 1))
  fi
  if [[ "$skala" == frei ]]; then
    printf '  %d. %s: DeviceScale=1 – Plymouth zeichnet in Bildschirmpixeln, das Theme nimmt ab 2880 × 1620 die\n' \
      "$n" "$_BOOTSPLASH_KONF"
    printf '     doppelt grossen Bilder (sonst vergrössert Plymouth selbst und die Kanten werden weich)\n'
    n=$((n + 1))
  fi
  printf '  %d. initramfs neu bauen (update-initramfs -u)' "$n"
  if [[ "$art" == pi-try ]]; then
    printf ';\n     flash-kernel legt die Startdateien nach /boot/firmware/new/. Der nächste Start läuft zweimal:\n'
    printf '     piboot-try prüft sie und fällt bei einem Fehler auf die bisherigen zurück.\n'
  else
    printf '\n'
  fi
  printf '\nNeu starten erst danach und nach Absprache. Zurück: zen bootsplash deaktivieren\n\n'

  if ! _bootsplash_bestaetigen aktivieren; then
    printf 'Abgebrochen. Es bleibt alles, wie es ist.\n'
    return 1
  fi
  printf '\n'

  # Die Kommandozeile zuerst: flash-kernel kopiert sie bei jedem initramfs (auch dem aus dem Paket) nach new/
  if (( ${#fehlend[@]} > 0 )); then
    sicherung=$(_bootsplash_sichern "$datei") || { zen_fehler "Sicherung von $datei gescheitert, nichts geändert"; return 1; }
    printf 'Gesichert: %s\n' "$sicherung"
    _bootsplash_zeile_schreiben "$datei" "$neu" || { zen_fehler "$datei liess sich nicht schreiben"; return 1; }
    # Frühere Einträge bleiben (zweites «aktivieren» nach einem teilweisen Lauf)
    bisher=$(_bootsplash_gespeichert woerter)
    read -ra gesetzt <<< "$bisher"
    for w in "${fehlend[@]}"; do
      [[ " $bisher " == *" $w "* ]] || gesetzt+=("$w")
    done
    _bootsplash_zustand_schreiben "$datei" "${gesetzt[*]}" || zen_fehler "$_BOOTSPLASH_ZUSTAND liess sich nicht schreiben"
    printf '%s: «%s» angehängt\n' "$datei" "${fehlend[*]}"
  fi
  if (( ${#pakete[@]} > 0 )); then
    apt_ausfuehren update -qq || { zen_fehler "apt-get update ist gescheitert"; return 1; }
    apt_ausfuehren install -y -q --no-install-recommends "${pakete[@]}" ||
      { zen_fehler "${pakete[*]} liess sich nicht installieren"; return 1; }
  fi
  if [[ "$standard" != "$_BOOTSPLASH_THEME" ]]; then
    if ! $SUDO update-alternatives --install "$_BOOTSPLASH_ALTERNATIVE" default.plymouth "$_BOOTSPLASH_THEME" 100 ||
      ! $SUDO update-alternatives --set default.plymouth "$_BOOTSPLASH_THEME"; then
      zen_fehler "Standard-Theme liess sich nicht setzen"
      return 1
    fi
  fi
  if [[ "$skala" == frei ]]; then
    _bootsplash_skala_setzen || { zen_fehler "$_BOOTSPLASH_KONF liess sich nicht schreiben"; return 1; }
    printf '%s: DeviceScale=1\n' "$_BOOTSPLASH_KONF"
  fi
  _bootsplash_initramfs || { zen_fehler "update-initramfs ist gescheitert (zen bootsplash status, zurück: zen bootsplash deaktivieren)"; return 1; }
  if [[ "$art" == pi-try ]]; then
    _bootsplash_new_angleichen dazu "${_BOOTSPLASH_WOERTER[@]}" || zen_fehler "/boot/firmware/new/cmdline.txt liess sich nicht anpassen"
  fi

  printf '\nDer Bootsplash ist eingeschaltet und erscheint beim nächsten Start.\n'
  if [[ "$art" == pi-try ]]; then
    printf 'Der Pi startet dabei zweimal (piboot-try prüft die neuen Startdateien).\n'
  fi
}

# --- deaktivieren ------------------------------------------------------------

_bootsplash_deaktivieren() {
  local art datei="" zeile="" neu="" standard skala gespeichert_datei n=1 w sicherung
  local -a gespeichert=() weg=()
  art=$(_bootsplash_art)
  standard=$(_bootsplash_standard)
  skala=$(_bootsplash_skala)
  gespeichert_datei=$(_bootsplash_gespeichert datei)
  read -ra gespeichert <<< "$(_bootsplash_gespeichert woerter)"

  datei=""
  if [[ -n "$gespeichert_datei" && -f "$gespeichert_datei" ]]; then
    datei=$gespeichert_datei
    zeile=$(_bootsplash_zeile "$datei")
    for w in "${gespeichert[@]}"; do
      _bootsplash_hat_wort "$zeile" "$w" && weg+=("$w")
    done
    neu=$(_bootsplash_woerter_weg "$zeile" "${weg[@]}")
  fi

  if (( ${#weg[@]} == 0 )) && [[ "$standard" != "$_BOOTSPLASH_THEME" && "$skala" != zenos && ! -f "$_BOOTSPLASH_ZUSTAND" ]]; then
    printf 'Der Bootsplash von zenOS ist nicht eingeschaltet, es gibt nichts zurückzunehmen.\n'
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen bootsplash deaktivieren braucht eine Bestätigung im Terminal (Eingabe «deaktivieren»)"
    return 2
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" || "$skala" == zenos ]] && ! befehl_vorhanden update-initramfs; then
    zen_fehler "update-initramfs fehlt (dracut); es bleibt alles, wie es ist."
    return 1
  fi

  printf 'zen bootsplash deaktivieren nimmt zurück, was «aktivieren» eingeschaltet hat:\n\n'
  if (( ${#weg[@]} > 0 )); then
    printf '  %d. Boot-Kommandozeile %s: «%s» wieder weg\n' "$n" "$datei" "${weg[*]}"
    printf '     vorher:  %s\n     nachher: %s\n' "$zeile" "$neu"
    printf '     Sicherung vorher nach %s/\n' "$_BOOTSPLASH_SICHERUNG"
    n=$((n + 1))
  elif _bootsplash_hat_wort "$(_bootsplash_zeile "$(_bootsplash_datei)")" splash; then
    printf '  · «splash» in der Boot-Kommandozeile stammt nicht von zen bootsplash und bleibt\n'
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" ]]; then
    printf '  %d. Standard-Theme zenos austragen (update-alternatives --remove)\n' "$n"
    n=$((n + 1))
  fi
  if [[ "$skala" == zenos ]]; then
    printf '  %d. %s: DeviceScale von zen bootsplash wieder weg\n' "$n" "$_BOOTSPLASH_KONF"
    n=$((n + 1))
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" || "$skala" == zenos ]]; then
    printf '  %d. initramfs neu bauen (update-initramfs -u)' "$n"
    if [[ "$art" == pi-try ]]; then
      printf '; der nächste Start läuft zweimal (piboot-try)\n'
    else
      printf '\n'
    fi
  fi
  printf '\nplymouth und plymouth-label bleiben installiert, das Theme bleibt unter %s liegen.\n\n' "$_BOOTSPLASH_ORDNER"

  if ! _bootsplash_bestaetigen deaktivieren; then
    printf 'Abgebrochen. Es bleibt alles, wie es ist.\n'
    return 1
  fi
  printf '\n'

  if (( ${#weg[@]} > 0 )); then
    sicherung=$(_bootsplash_sichern "$datei") || { zen_fehler "Sicherung von $datei gescheitert, nichts geändert"; return 1; }
    printf 'Gesichert: %s\n' "$sicherung"
    _bootsplash_zeile_schreiben "$datei" "$neu" || { zen_fehler "$datei liess sich nicht schreiben"; return 1; }
    printf '%s: «%s» entfernt\n' "$datei" "${weg[*]}"
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" ]]; then
    $SUDO update-alternatives --remove default.plymouth "$_BOOTSPLASH_THEME" ||
      { zen_fehler "Standard-Theme liess sich nicht austragen"; return 1; }
  fi
  if [[ "$skala" == zenos ]]; then
    _bootsplash_skala_entfernen || { zen_fehler "$_BOOTSPLASH_KONF liess sich nicht schreiben"; return 1; }
    printf '%s: DeviceScale entfernt\n' "$_BOOTSPLASH_KONF"
  fi
  if [[ "$standard" == "$_BOOTSPLASH_THEME" || "$skala" == zenos ]]; then
    _bootsplash_initramfs || { zen_fehler "update-initramfs ist gescheitert (sudo update-initramfs -u)"; return 1; }
  fi
  if [[ "$art" == pi-try && ${#weg[@]} -gt 0 ]]; then
    _bootsplash_new_angleichen weg "${weg[@]}" || zen_fehler "/boot/firmware/new/cmdline.txt liess sich nicht anpassen"
  fi
  $SUDO rm -f -- "$_BOOTSPLASH_ZUSTAND"

  printf '\nDer Bootsplash ist ausgeschaltet.\n'
  if [[ "$art" == pi-try ]] && [[ "$standard" == "$_BOOTSPLASH_THEME" || "$skala" == zenos ]]; then
    printf 'Der Pi startet beim nächsten Mal zweimal (piboot-try prüft die neuen Startdateien).\n'
  fi
}
