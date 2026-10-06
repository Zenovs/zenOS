# Testumgebung für zenOS auf dem Mac: Ubuntu 26.04 arm64 mit systemd.
# Gleiche Architektur wie der Pi 5. Kein Ersatz für den Test auf echter Hardware
# (kein GPU-Beschleuniger, kein VT, kein I2C/GPIO).
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Man-Seiten wie auf dem Pi (Ubuntu Server ist nicht minimiert; «?» im Terminal liest Optionen daraus).
# Wie «unminimize», aber nur für Man-Seiten: die Ausschlüsse von dpkg entfernen, die Pakete des
# Basis-Images mit Man-Seiten neu installieren und den Platzhalter für /usr/bin/man aufheben.
# Danach das Grundsystem wie Ubuntu Server: systemd, dbus und sudo (sudo-rs wie Ubuntu Server 26.04:
# «sudo» empfiehlt sudo-rs nur, mit --no-install-recommends fehlte es; update-alternatives macht sudo-rs
# zum Standard für /usr/bin/sudo).
RUN set -e; \
    rm -f /etc/dpkg/dpkg.cfg.d/excludes; \
    apt-get update -qq; \
    dpkg -S /usr/share/man/ | sed 's|, |\n|g; s|: [^:]*$||' | sort -u \
      | xargs apt-get install -y -qq --reinstall --no-install-recommends; \
    if [ "$(dpkg-divert --truename /usr/bin/man)" = /usr/bin/man.REAL ]; then \
      rm -f /usr/bin/man; dpkg-divert --quiet --remove --rename /usr/bin/man; \
    fi; \
    apt-get install -y -qq --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session sudo sudo-rs locales ca-certificates \
      git curl gnupg less file procps psmisc iproute2 kmod udev \
      man-db manpages manpages-de; \
    rm -rf /var/lib/apt/lists/*

# Laufzeit, Build-Abhängigkeiten von Quickshell und Prüfwerkzeuge.
# Die Liste ist bewusst grösser als nötig, damit Modul-Tests schnell sind;
# install.sh muss trotzdem alles selbst sicherstellen.
# Dazu Testwerkzeuge: expect und tmux (interaktive Abläufe wie zen firewall), wtype (Tastatureingaben in
# die Sitzung, z. B. Passwort in die Sperre), wlrctl (Zeiger bewegen, z. B. einen dunklen Bildschirm wecken),
# foot (zweites Terminal), nodejs (Einheitentests, pruefen.sh), rsync (wie auf Ubuntu Server; Beispiel im
# Test von «?»), python3-libevdev (virtuelles Touchpad in gesten-e2e.sh), libinput-tools und python3-yaml
# (libinput debug-events, record und replay, z. B. eine Aufnahme vom Touchpad des Geräts).
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      labwc kitty fish greetd pipewire wireplumber pipewire-pulse \
      xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
      grim slurp wl-clipboard swayidle wlopm kanshi wlr-randr hyprpicker xwayland \
      python3 python3-jsonschema python3-gi jq adwaita-icon-theme fonts-dejavu-core \
      libnotify-bin xdg-utils gsettings-desktop-schemas dconf-cli dconf-service libglib2.0-bin \
      qt6-wayland qt6-svg-plugins qt6-gtk-platformtheme qt6-xdgdesktopportal-platformtheme \
      qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
      qml6-module-qtquick-shapes qml6-module-qtquick-effects qml6-module-qt-labs-folderlistmodel \
      qml6-module-qtqml-workerscript qml6-module-qtquick-window qml6-module-qtquick-templates \
      qml6-module-qtqml qml6-module-qtqml-models libjemalloc2 \
      build-essential cmake ninja-build pkg-config \
      qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
      qt6-shadertools-dev qt6-wayland-dev qt6-svg-dev spirv-tools libcli11-dev libjemalloc-dev \
      libdrm-dev libgbm-dev libegl-dev libvulkan-dev libwayland-dev wayland-protocols \
      libpipewire-0.3-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libglib2.0-dev \
      eza bat zoxide fzf tealdeer \
      unattended-upgrades ufw i2c-tools python3-smbus python3-libgpiod \
      shellcheck gitleaks qt6-declarative-dev-tools \
      expect tmux wtype wlrctl foot nodejs rsync python3-libevdev python3-yaml libinput-tools \
    && rm -rf /var/lib/apt/lists/*

# Quickshell v0.3.1, vorgebaut (gleicher Stand wie scripts/module/25-quickshell.sh)
ADD cache/usr-local.tar /usr/

# Testbenutzer mit derselben temporären sudo-Regel wie auf dem Pi während des Baus
# (Das Ubuntu-Image bringt einen Benutzer «ubuntu» mit UID 1000 mit; er wird ersetzt.)
# linger: docker exec erzeugt keine logind-Sitzung. Ohne linger liefe keine systemd-Benutzerinstanz (kein
# Sitzungsbus, kein PipeWire, kein «oberflaeche.sh start --sitzung»). Auf dem Pi läuft sie nur während
# einer Anmeldung (Login oder SSH).
RUN set -e; if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi; \
    useradd -m -u 1000 -s /bin/bash tester; \
    echo 'tester:tester' | chpasswd; \
    echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/zenos-bau; \
    chmod 0440 /etc/sudoers.d/zenos-bau; \
    mkdir -p /var/lib/systemd/linger; touch /var/lib/systemd/linger/tester

# systemd im Container: keine Getty, keine Hardware-Dienste
# greetd wird vom Paket sofort aktiviert; im Test soll es wie auf einem frischen Pi aus sein.
# Zuletzt die Docker-eigene /usr/sbin/policy-rc.d («exit 101») weg: Sie verbietet jeden Dienststart durch apt,
# und pakete_sicherstellen liesse sie als fremde Datei stehen. Ohne sie setzt es wie auf dem Pi die eigene
# Richtlinie (greetd startet nicht, «dbus reload» bleibt erlaubt). Bis hierher hat sie den Bau geschützt.
# rtkit (kommt mit install.sh) ohne seine Prozessgrenze: Container desselben Images teilen sich die UID von
# rtkit, der Kernel zählt die Grenze über alle Container, und ab dem zweiten hängt rtkit (README, «rtkit in
# Testcontainern»). starten.sh legt dieselbe Datei auch in Containern älterer Images an.
RUN systemctl mask getty@tty1.service serial-getty@ttyS0.service systemd-udevd.service \
      systemd-networkd-wait-online.service 2>/dev/null || true; \
    systemctl disable greetd.service 2>/dev/null || true; rm -f /etc/systemd/system/display-manager.service; \
    mkdir -p /etc/systemd/system/rtkit-daemon.service.d; \
    printf '%s\n' '# Nur im Testcontainer, siehe test/container/README.md (rtkit in Testcontainern)' \
      '[Service]' 'ExecStart=' 'ExecStart=/usr/libexec/rtkit-daemon --no-limit-resources' \
      > /etc/systemd/system/rtkit-daemon.service.d/zenos-test.conf; \
    rm -f /usr/sbin/policy-rc.d

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
