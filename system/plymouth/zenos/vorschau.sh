#!/usr/bin/env bash
# vorschau.sh – Bootsplash ohne Bildschirm ansehen (Testcontainer, nie auf dem Pi): plymouthd mit dem x11-Renderer
# unter Xvfb, Bildschirmfotos zu festen Zeitpunkten des Ablaufs, dazu Passwort- und Fragefeld. Das Theme kommt aus
# diesem Ordner über /run/plymouth/themes; es wird nichts eingeschaltet (kein Standard-Theme, kein initramfs).
# Braucht root und plymouth, plymouth-label (ohne stürzt das Modul script ab), plymouth-x11, xvfb, x11-apps, xdotool,
# imagemagick.
#   system/plymouth/zenos/vorschau.sh [--groesse 1920x1080] [--skala N] [--ziel /srv/bilder/bootsplash]
# --skala setzt PLYMOUTH_FORCE_SCALE (wie DeviceScale in plymouthd.conf). Bilder: <ziel>/<zeit>.png, passwort.png,
# passwort-feststelltaste.png (Hinweis erzwungen, der x11-Renderer kennt keine Feststelltaste), frage.png;
# plymouthd.log mit dem Protokoll von Plymouth.

set -euo pipefail

groesse=1920x1080
skala=""
ziel=/srv/bilder/bootsplash
while (( $# > 0 )); do
  case "$1" in
    --groesse) groesse=$2; shift 2 ;;
    --skala) skala=$2; shift 2 ;;
    --ziel) ziel=$2; shift 2 ;;
    -h | --hilfe) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'vorschau.sh: unbekannte Option «%s»\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$groesse" =~ ^[0-9]+x[0-9]+$ ]] || { echo "vorschau.sh: --groesse BREITExHOEHE" >&2; exit 2; }
[[ -z "$skala" || "$skala" =~ ^[12]$ ]] || { echo "vorschau.sh: --skala 1 oder 2" >&2; exit 2; }
(( EUID == 0 )) || { echo "vorschau.sh: läuft als root (nur im Testcontainer)" >&2; exit 2; }
for befehl in plymouthd plymouth Xvfb xwd xdotool convert; do
  command -v "$befehl" > /dev/null || { echo "vorschau.sh: $befehl fehlt" >&2; exit 1; }
done
[[ -f "$(plymouth --get-splash-plugin-path)/label-pango.so" ]] || { echo "vorschau.sh: plymouth-label fehlt" >&2; exit 1; }

quelle=$(cd -- "$(dirname -- "$0")" && pwd -P)
anzeige=:57
laufzeit=/run/plymouth/themes/zenos
mkdir -p -- "$ziel" "$laufzeit"
rm -f -- "$ziel"/*.png

# Theme-Datei mit Pfaden in diesen Ordner; das Skript als Kopie, damit der Hinweis erzwungen werden kann
cp -- "$quelle/zenos.script" "$laufzeit/zenos.script"
sed -e "s|^ImageDir=.*|ImageDir=$quelle/bilder|" -e "s|^ScriptFile=.*|ScriptFile=$laufzeit/zenos.script|" \
  "$quelle/zenos.plymouth" > "$laufzeit/zenos.plymouth"

aufraeumen() {
  plymouth quit 2> /dev/null || true
  [[ -n "${xvfb:-}" ]] && kill "$xvfb" 2> /dev/null
  rm -rf -- "$laufzeit"
}
trap aufraeumen EXIT

Xvfb "$anzeige" -screen 0 "${groesse}x24" -nolisten tcp > /dev/null 2>&1 &
xvfb=$!
sleep 1

foto() { # NAME
  xwd -root -display "$anzeige" -silent -out "$ziel/$1.xwd"
}

# Tasten gehen ohne Fenstermanager an das Fenster unter dem Zeiger
tippen() { # TEXT
  DISPLAY=$anzeige xdotool mousemove 10 10 type --delay 40 "$1"
}

taste() { # NAME
  DISPLAY=$anzeige xdotool key "$1"
}

starten() {
  # Ohne Konsolen: ein privilegierter Container sieht die Konsole der VM (/dev/tty1)
  env DISPLAY="$anzeige" ${skala:+PLYMOUTH_FORCE_SCALE=$skala} plymouthd --mode=boot --debug \
    --debug-file="$ziel/plymouthd.log" --ignore-serial-consoles \
    --kernel-command-line="quiet splash plymouth.splash=zenos plymouth.ignore-serial-consoles" \
    --pid-file=/run/plymouth/vorschau.pid
  for _ in $(seq 1 50); do plymouth --ping && return 0; sleep 0.1; done
  echo "vorschau.sh: plymouthd antwortet nicht (Protokoll: $ziel/plymouthd.log)" >&2
  exit 1
}

# Ablauf: Gleiten bis 0,3 s, Überblenden bis 0,5 s, danach Atmen (weit bei 1,3 s, eng bei 2,9 s)
starten
plymouth show-splash
start=$(date +%s%N)
for ms in 50 150 300 400 600 1300 2900 4500; do
  while (( $(date +%s%N) < start + ms * 1000000 )); do sleep 0.005; done
  foto "$(printf '%04d-ms' "$ms")"
done

plymouth ask-for-password --prompt="Passwort für das Laufwerk" > /dev/null 2>&1 &
sleep 0.5
tippen 'zenOS-vorschau'
sleep 0.4
foto passwort
taste Return
sleep 0.4
plymouth quit
sleep 0.3

# Hinweis zur Feststelltaste erzwingen (Kopie), dann eine Frage mit sichtbarer Antwort
sed -i 's/if (Plymouth.GetCapslockState())/if (1)/' "$laufzeit/zenos.script"
starten
plymouth show-splash
sleep 0.8
plymouth ask-for-password --prompt="Passwort" > /dev/null 2>&1 &
sleep 0.5
tippen 'abc'
sleep 0.4
foto passwort-feststelltaste
taste Return
sleep 0.3
plymouth ask-question --prompt="Frage" > /dev/null 2>&1 &
sleep 0.5
tippen 'ja'
sleep 0.4
foto frage
taste Return
sleep 0.3

for xwd in "$ziel"/*.xwd; do
  convert "xwd:$xwd" "png:${xwd%.xwd}.png"
  rm -f -- "$xwd"
done
ls -- "$ziel"
