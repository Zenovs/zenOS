#!/usr/bin/env bash
# starten.sh <name> – startet einen Testcontainer aus zenos-test:basis (systemd als PID 1) und legt den
# Arbeitsstand dieses Repos unter /home/tester/zenOS an (Git-Repo, gleicher Branch und Commit, dazu
# nicht committete und neue Dateien). Läuft der Container schon, wird nur der Arbeitsstand aufgefrischt.
# Läuft auf dem Mac. Der Name muss mit «zenos-» beginnen (fremde Container bleiben unberührt).
#
#   test/container/starten.sh zenos-m1-test
#   ZENOS_TESTBILD=zenos-test:basis (Standard)

set -euo pipefail

if (( $# != 1 )) || [[ "$1" == -h || "$1" == --hilfe ]]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
name=$1
if [[ ! "$name" =~ ^zenos-[a-z0-9][a-z0-9-]*$ ]]; then
  echo "starten.sh: Der Name muss mit «zenos-» beginnen (nur a-z, 0-9, -)" >&2
  exit 2
fi

repo=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
bild=${ZENOS_TESTBILD:-zenos-test:basis}

if docker container inspect "$name" >/dev/null 2>&1; then
  if [[ "$(docker container inspect -f '{{.State.Running}}' "$name")" != true ]]; then
    docker start "$name" >/dev/null
  fi
  echo "Container $name läuft schon, frische den Arbeitsstand auf."
else
  docker run -d --name "$name" --hostname zenos-test --privileged --cgroupns=host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v "$repo:/repo:ro" "$bild" >/dev/null
  echo "Container $name gestartet ($bild)."
fi

# Warten, bis systemd hochgefahren ist
zustand=""
for _ in $(seq 1 60); do
  zustand=$(docker exec "$name" systemctl is-system-running 2>/dev/null || true)
  case "$zustand" in running | degraded) break ;; esac
  sleep 1
done
case "$zustand" in
  running | degraded) ;;
  *) echo "starten.sh: systemd ist nach 60 s nicht bereit (Zustand: ${zustand:-unbekannt})" >&2; exit 1 ;;
esac

# Ablage für Bilder und Protokolle (/tmp ist im Container ein tmpfs, docker cp sieht es nicht)
docker exec "$name" install -d -o tester -g tester /srv/bilder /srv/oberflaeche
docker exec -u tester -w /home/tester "$name" bash /repo/test/container/arbeitsstand.sh

cat <<EOF

Bereit. Als tester arbeiten:
  docker exec -it -u tester -w /home/tester/zenOS $name bash
Oberfläche (im Container): test/container/oberflaeche.sh start
Bilder holen (auf dem Mac): test/container/holen.sh $name <ziel-ordner>
Aufräumen: docker rm -f $name
EOF
