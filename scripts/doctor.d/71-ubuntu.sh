#!/usr/bin/env bash
# 71-ubuntu: Ubuntu-Basis – kein Wechsel der Hauptversion (Prompt=never), Paket-Updates über zen update (zenos-basis)
# shellcheck shell=bash
#
# Ein Wechsel der Ubuntu-Basis ist eine neue zenOS-Hauptversion mit neuem Image, kein Update (scripts/module/71-basis.sh,
# docs/image-und-releases.md, «Basiswechsel»). Ob die Basis selbst Ubuntu 26.04 ist, prüft 00-basis, ob ein Neustart
# ansteht 70-sicherheit. Paket-Updates innerhalb von 26.04 bringt zenos-basis: Programm, Units, Timer der Automatik
# (gemeinsamer Notschalter mit dem Kanal), ausstehende Updates (Hinweis) und die letzte Installation. Ohne root, nur
# lesend.

# Ordner des Release-Upgraders, Programm und Units (die Einheitentests setzen andere)
_UBUNTU_ORDNER=/etc/update-manager
_UBUNTU_PROGRAMM=/usr/local/libexec/zenos/zenos-basis
_UBUNTU_QUELLE=/opt/zenos/scripts/bin/zenos-basis
_UBUNTU_UNITS=/etc/systemd/system
_UBUNTU_PYTHON=/usr/bin/python3
_UBUNTU_AUS=/etc/xdg/zenos/kanal-automatik-aus
_UBUNTU_SYSTEMD=/run/systemd/system
_UBUNTU_EINHEITEN=(zenos-basis-pruefen.service zenos-basis-installieren.service zenos-basis-automatik.service
  zenos-basis-automatik.timer zenos-basis-gelegenheit.service zenos-basis-gelegenheit.timer)

pruefe_ubuntu() {
  abschnitt "Ubuntu-Basis"
  _ubuntu_prompt
  _ubuntu_updates
}

# Wert von Prompt im Abschnitt [DEFAULT] einer Datei des Release-Upgraders, klein geschrieben; leer, wenn er fehlt.
# Wie configparser: Schlüssel am Zeilenanfang, «=» oder «:», Gross- und Kleinschreibung egal.
_ubuntu_prompt_wert() { # DATEI
  awk '
    /^\[/ { abschnitt = $0; sub(/^\[[ \t]*/, "", abschnitt); sub(/[ \t]*\].*$/, "", abschnitt); next }
    abschnitt == "DEFAULT" && tolower($0) ~ /^prompt[ \t]*[=:]/ {
      sub(/^[^=:]*[=:][ \t]*/, ""); sub(/[ \t\r]+$/, ""); wert = tolower($0)
    }
    END { print wert }
  ' "$1" 2>/dev/null
}

# Wie ubuntu-release-upgrader (MetaRelease.py): zuerst release-upgrades, danach jede *.cfg in release-upgrades.d in
# Namensreihenfolge; der letzte Wert zählt. Ohne Wert gilt «normal».
_ubuntu_prompt() {
  local LC_ALL=C datei wert="" quelle="" w text
  local dropin="$_UBUNTU_ORDNER/release-upgrades.d/zenos.cfg"
  for datei in "$_UBUNTU_ORDNER/release-upgrades" "$_UBUNTU_ORDNER"/release-upgrades.d/*.cfg; do
    [[ -f "$datei" && -r "$datei" ]] || continue
    w=$(_ubuntu_prompt_wert "$datei")
    if [[ -n "$w" ]]; then
      wert=$w
      quelle=$datei
    fi
  done
  case "$wert" in
    never | no)
      ok "Kein Wechsel der Ubuntu-Hauptversion: Prompt=never ($quelle)"
      ;;
    *)
      text="Prompt ist «${wert:-normal}», nicht «never»: do-release-upgrade könnte auf eine neue Ubuntu-Version wechseln, das ist eine neue zenOS-Hauptversion mit neuem Image"
      if [[ ! -f "$dropin" ]]; then
        warnung "$text ($dropin fehlt, install.sh legt ihn an)"
      elif [[ ! "$(_ubuntu_prompt_wert "$dropin")" =~ ^(never|no)$ ]]; then
        warnung "$text ($dropin weicht ab, install.sh stellt ihn wieder her)"
      else
        warnung "$text ($quelle gilt nach $dropin)"
      fi
      ;;
  esac
}

# zenos-basis: Programm (root-eigen, wie in /opt/zenos), Units, letzte Prüfung (stand.json) und letzte Installation
_ubuntu_updates() {
  local einheit zeile zustand text
  if [[ ! -f "$_UBUNTU_PROGRAMM" ]]; then
    hinweis "Basis-Updates noch nicht eingerichtet ($_UBUNTU_PROGRAMM fehlt; install.sh richtet es ein)"
    return 0
  fi
  if ! _ubuntu_nur_root "$_UBUNTU_PROGRAMM"; then
    fehler "$_UBUNTU_PROGRAMM oder ein Ordner darüber ist nicht nur für root schreibbar – root führt es aus (install.sh)"
  elif [[ -r "$_UBUNTU_QUELLE" ]] && ! cmp -s "$_UBUNTU_PROGRAMM" "$_UBUNTU_QUELLE"; then
    warnung "$_UBUNTU_PROGRAMM weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi
  for einheit in "${_UBUNTU_EINHEITEN[@]}"; do
    [[ -f "$_UBUNTU_UNITS/$einheit" ]] || warnung "$einheit fehlt (install.sh)"
  done
  _ubuntu_automatik

  zeile=$("$_UBUNTU_PYTHON" -I "$_UBUNTU_PROGRAMM" status --kurz 2>/dev/null | head -n 1) || zeile=""
  zustand=${zeile%% *}
  text=${zeile#* }
  case "$zustand" in
    ungeprueft | "") hinweis "Basis-Updates noch nie geprüft (zen update)" ;;
    aktuell) ok "Basis-Updates: keine ausstehend" ;;
    bereit | zustimmung) hinweis "Basis-Updates ausstehend: $text (zen update)" ;;
    # Seit der Prüfung änderten sich Pakete (meist unattended-upgrades): Was ansteht, weiss erst eine neue Prüfung
    veraltet) hinweis "Basis-Updates: letzte Prüfung $text; neu prüfen: zen update" ;;
    laeuft) hinweis "Ein Basis-Update läuft gerade" ;;
    gesperrt) warnung "Basis-Updates gesperrt: $text (apt-get -s full-upgrade)" ;;
    fehler) warnung "Basis-Updates: $text" ;;
    *) warnung "Basis-Updates: unbekannter Zustand «$zustand»" ;;
  esac

  zeile=$("$_UBUNTU_PYTHON" -I "$_UBUNTU_PROGRAMM" status --installation 2>/dev/null | head -n 1) || zeile=""
  zustand=${zeile%% *}
  text=${zeile#* }
  case "$zustand" in
    keine | "") ;;
    installiert) ok "Letztes Basis-Update $text" ;;
    kaputt) fehler "Letztes Basis-Update kaputt $text (behoben? sudo $_UBUNTU_PROGRAMM quittieren)" ;;
    behoben) ok "Letztes Basis-Update $text" ;;
    fehler) warnung "Letztes Basis-Update brach ab $text" ;;
    *) warnung "Letztes Basis-Update: unbekanntes Ergebnis «$zustand»" ;;
  esac
}

# Timer der Automatik: aktiviert und aktiv, ausser der gemeinsame Notschalter ist gesetzt (wie 15-kanal)
_ubuntu_automatik() {
  local timer zustand
  [[ -f "$_UBUNTU_UNITS/zenos-basis-automatik.timer" ]] || return 0
  if [[ -e "$_UBUNTU_AUS" ]]; then
    hinweis "Basis-Updates nur von Hand: Automatik aus (Notschalter $_UBUNTU_AUS, gilt auch für den Kanal)"
    return 0
  fi
  for timer in zenos-basis-automatik.timer zenos-basis-gelegenheit.timer; do
    zustand=$(systemctl is-enabled "$timer" 2>/dev/null) || true
    if [[ "$zustand" != enabled ]]; then
      warnung "$timer ist nicht aktiviert (${zustand:-unbekannt}): Basis-Updates kommen nicht automatisch (install.sh)"
    elif [[ -d "$_UBUNTU_SYSTEMD" ]] && ! systemctl --quiet is-active "$timer" 2>/dev/null; then
      warnung "$timer ist aktiviert, läuft aber nicht (sudo systemctl start $timer)"
    fi
  done
}

# Gehört PFAD und jeder Ordner darüber root, und ist nichts davon für andere schreibbar?
_ubuntu_nur_root() {
  local pfad=$1 rechte
  while [[ -n "$pfad" && "$pfad" != / ]]; do
    rechte=$(stat -c '%u %a' -- "$pfad" 2>/dev/null) || return 1
    [[ "${rechte%% *}" == 0 ]] || return 1
    (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    pfad=$(dirname -- "$pfad")
  done
}
