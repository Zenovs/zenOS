#!/usr/bin/env bash
# 00-basis: System, Code-Checkout, Kanal, zen, Log, Speicher, Oberflächen-Link, sudo-Regel
# shellcheck shell=bash

pruefe_basis() {
  _basis_system
  _basis_code
  _basis_installation
}

_basis_system() {
  abschnitt "System"
  local id="" version="" name="" arch modell frei_kb frei
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    id=$(. /etc/os-release && printf '%s' "${ID:-}")
    # shellcheck disable=SC1091
    version=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")
    # shellcheck disable=SC1091
    name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")
  fi
  arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
  if [[ "$id" == ubuntu && "$version" == 26.04 ]]; then
    ok "$name · $arch"
  else
    warnung "Gebaut für Ubuntu 26.04, gefunden: ${name:-unbekannt} · $arch"
  fi
  case "$arch" in
    arm64 | amd64) ;;
    *) warnung "Architektur $arch ist nicht vorgesehen (arm64 oder amd64)" ;;
  esac
  if [[ -r /proc/device-tree/model ]]; then
    modell=$(tr -d '\0' < /proc/device-tree/model)
    [[ -z "$modell" ]] || ok "Gerät: $modell"
  fi
  ok "Kernel $(uname -r)"

  frei_kb=$(df -P -k / 2>/dev/null | awk 'NR == 2 { print $4 }')
  if [[ "$frei_kb" =~ ^[0-9]+$ ]]; then
    frei=$(awk -v k="$frei_kb" 'BEGIN { printf "%.1f", k / 1048576 }' | tr . ,)
    if (( frei_kb < 1048576 )); then
      fehler "Nur $frei GB frei auf /"
    elif (( frei_kb < 3670016 )); then
      warnung "Nur $frei GB frei auf / (ein neuer Quickshell-Bau, etwa nach einem Qt-Update, braucht etwa 3,5 GB in /var/tmp)"
    else
      ok "$frei GB frei auf /"
    fi
  else
    hinweis "Freier Speicher nicht ermittelbar"
  fi

  if [[ ! -x /etc/sudoers.d ]]; then
    hinweis "sudo-Regeln nicht prüfbar (/etc/sudoers.d nicht lesbar)"
  elif [[ -e /etc/sudoers.d/zenos-bau ]]; then
    warnung "Temporäre sudo-Regel aus dem Bau noch aktiv. Nach der Testphase löschen: sudo rm /etc/sudoers.d/zenos-bau"
  else
    ok "Keine temporäre sudo-Regel aus dem Bau"
  fi
}

_basis_git() { git -c safe.directory=/opt/zenos -C /opt/zenos "$@"; }

_basis_code() {
  abschnitt "Code"
  local code=/opt/zenos stand zweig besitz geaendert url host kanal
  if ! _basis_git rev-parse --git-dir >/dev/null 2>&1; then
    fehler "$code fehlt oder ist kein Git-Checkout (./scripts/install.sh im Repo ausführen)"
    return 0
  fi
  stand=$(_basis_git describe --tags --always --dirty 2>/dev/null)
  zweig=$(_basis_git symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [[ -n "$zweig" ]]; then
    ok "$code: $stand · Branch $zweig"
  else
    hinweis "$code: $stand · losgelöst (Rollback-Stand; zen update kehrt zum Kanal zurück)"
  fi

  geaendert=$(_basis_git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$geaendert" == 0 ]]; then
    ok "Checkout sauber"
  else
    hinweis "$geaendert lokale Änderungen im Checkout (aus einem Arbeitsstand übernommen; zen update verwirft sie)"
  fi

  besitz=$(stat -c '%U:%G' -- "$code" 2>/dev/null)
  if [[ "$besitz" == root:root ]]; then
    ok "$code gehört root:root"
  else
    warnung "$code gehört $besitz statt root:root (install.sh korrigiert das)"
  fi

  url=$(_basis_git remote get-url origin 2>/dev/null)
  if [[ -z "$url" ]]; then
    warnung "Kein origin in $code – zen update geht nicht"
  else
    host=$url
    host=${host#*://}
    host=${host#*@}
    host=${host%%[:/]*}
    ok "origin: $host"
  fi

  if [[ -r /etc/xdg/zenos/kanal ]]; then
    kanal=$(head -n 1 /etc/xdg/zenos/kanal | tr -d '[:space:]')
    case "$kanal" in
      dev | main) ok "Kanal $kanal" ;;
      "") fehler "/etc/xdg/zenos/kanal ist leer" ;;
      *) hinweis "Kanal $kanal (üblich sind dev und main)" ;;
    esac
    if [[ -n "$zweig" && -n "$kanal" && "$zweig" != "$kanal" ]]; then
      hinweis "Branch $zweig weicht vom Kanal $kanal ab (Stand aus einem Arbeits-Checkout; zen update wechselt auf $kanal)"
    fi
  else
    warnung "/etc/xdg/zenos/kanal fehlt (zen update nimmt dev)"
  fi
}

_basis_installation() {
  abschnitt "Installation"
  local ziel log zeile datum
  ziel=$(readlink /usr/local/bin/zen 2>/dev/null)
  if [[ "$ziel" == /opt/zenos/scripts/zen ]]; then
    ok "zen → /opt/zenos/scripts/zen"
  elif [[ -e /usr/local/bin/zen || -L /usr/local/bin/zen ]]; then
    warnung "/usr/local/bin/zen zeigt nicht auf /opt/zenos/scripts/zen"
  else
    fehler "/usr/local/bin/zen fehlt"
  fi

  if [[ -d /var/log/zenos ]]; then
    ok "Log-Ordner /var/log/zenos"
  else
    warnung "Log-Ordner /var/log/zenos fehlt"
  fi
  log=/var/log/zenos/install.log
  if [[ ! -r "$log" ]]; then
    hinweis "Install-Log nicht lesbar"
  else
    zeile=$(grep -E '^== Ende .* · (normal|image) · ' "$log" | tail -n 1)
    if [[ -z "$zeile" ]]; then
      hinweis "Noch kein vollständiger Installationslauf im Log"
    else
      datum=$(awk '{ print $3, substr($4, 1, 5) }' <<< "$zeile")
      if [[ "$zeile" == *" · abbruch"* ]]; then
        warnung "Letzte Installation am $datum abgebrochen (siehe $log)"
      else
        ok "Letzte Installation am $datum · ${zeile##* · ok · }"
      fi
    fi
    zeile=$(grep -E '^== Ende .* · benutzer · ' "$log" | tail -n 1)
    if [[ "$zeile" == *" · abbruch"* ]]; then
      warnung "Letzte Einrichtung der Benutzerteile abgebrochen (siehe $log)"
    fi
  fi

  ziel=$(readlink "$HOME/.config/quickshell" 2>/dev/null)
  if [[ "$ziel" == /opt/zenos/shell ]]; then
    ok "$HOME/.config/quickshell → /opt/zenos/shell"
  elif [[ -n "$ziel" ]]; then
    warnung "$HOME/.config/quickshell zeigt auf einen anderen Ort (zen benutzer setzt es zurück)"
  else
    warnung "$HOME/.config/quickshell fehlt (zen benutzer)"
  fi
  if [[ -d "$HOME/.config/zenos" ]]; then
    ok "Ordner $HOME/.config/zenos vorhanden"
  else
    warnung "Ordner $HOME/.config/zenos fehlt (zen benutzer)"
  fi
}
