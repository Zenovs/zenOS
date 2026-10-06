#!/usr/bin/env bash
# 12-vertrauen: Vertrauensanker /etc/zenos/vertrauen für den signierten Kanal, mit Schlüsseln gefüllt nur im Image
# shellcheck shell=bash
#
# Der Anker (release, wurzel, widerrufen, serie; Format in docs/image-und-releases.md, «Signierte Releases») sagt dem
# Gerät, welchen Signaturen es glaubt. zenos-kanal liest ihn nur von hier, nie aus /opt/zenos. Danach ändert ihn nur
# noch zenos-kanal selbst (ein gültiger Tag vertrauen/NNNN) oder Zeno von Hand («sudo zen kanal anker ORDNER»).
#
# Dieses Modul überschreibt einen Anker deshalb nie, und es füllt ihn nur beim Image-Bau (--image) aus dem Repo:
# - Fehlt /etc/zenos/vertrauen, legt es den Ordner an. Im Image kommt der Anker aus system/vertrauen des gebauten
#   Stands. Sonst nur, solange system/vertrauen noch keine Schlüssel hat (dann sind es leere Dateien).
# - Ist der Anker leer (nur Kommentare, wie im Repo vor Serie 1) und hat system/vertrauen
#   inzwischen Schlüssel, übernimmt es sie nicht von selbst: Dieser Stand kam womöglich ungeprüft (dev mit «ja»), und
#   ein untergeschobener Anker gälte danach für jedes signierte Release. Es sagt, wie es von Hand geht: «sudo zen kanal
#   anker /opt/zenos/system/vertrauen» mit den Fingerabdrücken aus einer vertrauenswürdigen Quelle.
# - Sonst bleibt der Inhalt, wie er ist. Nur Besitz und Rechte (root, 0755 bzw. 0644) stellt es wieder her.
# Unvollständig oder ungültig gibt es eine Warnung: Der Kanal gilt dann als «Anker fehlt» und installiert nichts.

_VERTRAUEN_ZIEL=/etc/zenos/vertrauen

modul_system() {
  local quelle=$ZENOS_CODE/system/vertrauen ziel=$_VERTRAUEN_ZIEL zustand

  ordner_sicherstellen /etc/zenos 0755 root:root
  if [[ -L "$ziel" ]] || { [[ -e "$ziel" ]] && [[ ! -d "$ziel" ]]; }; then
    log_warnung "$ziel ist kein Ordner: Der Kanal gilt als «Anker fehlt» (von Hand prüfen)"
    return 0
  fi
  if [[ ! -e "$ziel" ]]; then
    ordner_sicherstellen "$ziel" 0755 root:root
    if [[ "$ZENOS_IMAGE" == 1 || "$(_vertrauen_zustand "$quelle")" != vollständig* ]]; then
      _vertrauen_kopieren "$quelle" "$ziel"
      log_info "Vertrauensanker angelegt: $(_vertrauen_zustand "$ziel")"
    else
      _vertrauen_von_hand
    fi
    return 0
  fi

  ordner_sicherstellen "$ziel" 0755 root:root
  _vertrauen_rechte "$ziel"
  zustand=$(_vertrauen_zustand "$ziel")
  case "$zustand" in
    vollständig*) ;;
    leer*)
      if [[ "$(_vertrauen_zustand "$quelle")" != vollständig* ]]; then
        log_info "Vertrauensanker noch ohne Schlüssel: Signiertes gibt es nicht, zen update nur auf dev und mit «ja»"
      elif [[ "$ZENOS_IMAGE" == 1 ]]; then
        _vertrauen_kopieren "$quelle" "$ziel"
        log_info "Vertrauensanker aus dem Image-Stand: $(_vertrauen_zustand "$ziel")"
      else
        _vertrauen_von_hand
      fi
      ;;
    *)
      log_warnung "Vertrauensanker $ziel: $zustand. Der Kanal installiert nichts (von Hand: sudo zen kanal anker ORDNER)"
      ;;
  esac
}

# Schlüssel im Repo, Anker leer: nur ein Hinweis, übernommen wird von Hand
_vertrauen_von_hand() {
  log_info "system/vertrauen hat Schlüssel, der Anker des Geräts noch nicht. Einmal von Hand übernehmen"
  log_info "(Fingerabdrücke aus einer vertrauenswürdigen Quelle eintippen, etwa docs/image-und-releases.md auf GitHub):"
  log_info "sudo zen kanal anker $ZENOS_CODE/system/vertrauen"
}

# Inhalt prüfen mit zenos-kanal: «vollständig: …», «leer: …» oder «ungültig: …»
_vertrauen_zustand() {
  local ordner=$1 ausgabe
  ausgabe=$($SUDO /usr/bin/python3 -I "$ZENOS_CODE/scripts/bin/zenos-kanal" anker --pruefen "$ordner" 2>&1) || true
  printf '%s' "${ausgabe:-ungültig: nicht prüfbar}"
}

# Dateien des Ankers aus QUELLE, die Serie zuletzt (erst mit ihr ist der Anker vollständig)
_vertrauen_kopieren() {
  local quelle=$1 ziel=$2 name
  for name in widerrufen wurzel release serie; do
    [[ -f "$quelle/$name" ]] || abbruch "Vertrauensanker im Repo unvollständig: $quelle/$name fehlt"
    datei_installieren "$quelle/$name" "$ziel/$name" 0644 root:root
  done
}

# Besitz und Rechte der vorhandenen Dateien, ohne den Inhalt anzufassen
_vertrauen_rechte() {
  local ziel=$1 name datei ist
  for name in release wurzel widerrufen serie; do
    datei=$ziel/$name
    if $SUDO test -L "$datei"; then
      log_warnung "$datei ist ein Verweis: Der Kanal gilt als «Anker fehlt»"
      continue
    fi
    $SUDO test -f "$datei" || continue
    ist=$($SUDO stat -c '%a %U:%G' -- "$datei")
    if [[ "$ist" != "644 root:root" ]]; then
      $SUDO chown root:root -- "$datei"
      $SUDO chmod 0644 -- "$datei"
      aenderung "$datei (0644 root:root)"
    fi
  done
}
