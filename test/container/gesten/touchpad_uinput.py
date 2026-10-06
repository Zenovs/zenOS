#!/usr/bin/env python3
"""Virtuelle Eingabegeräte für gesten-e2e.sh (nur im Testcontainer, als root, braucht python3-libevdev und /dev/uinput).

  touchpad_uinput.py <fifo> [--art touchpad|tastatur|touchpad-tasten] [--slots N]

Legt das Gerät an, schreibt «geraet /dev/input/eventN /sys/…» und liest dann Befehle zeilenweise aus der FIFO:
  swipe3|swipe4|scroll2 hoch|runter|links|rechts [mm]   Finger nebeneinander, 0,3 s
  pfad <finger> <dx_mm> <dy_mm> <dauer_s>              beliebiger Weg, z. B. schräg oder langsam
  zeiger1 [mm]                                        ein Finger nach rechts (Zeiger)
  tippen3                                             drei Finger kurz auflegen (Mittelklick)
  ende                                                Gerät entfernen und beenden
Nach jedem Befehl «fertig <befehl>» auf stdout.

Arten:
  touchpad         reines Touchpad wie am Gerät: BTN_TOOL_FINGER bis QUINTTAP, ABS_MT_SLOT, keine Tasten
  tastatur         Tastatur mit allen Buchstaben und Ziffern (ID_INPUT_KEYBOARD)
  touchpad-tasten  Touchpad, das auf demselben Knoten auch Tasten meldet (ID_INPUT_KEY): bleibt für zenos-gesten zu
Die Fingerzahl meldet BTN_TOOL_*, Slots bekommen nur die ersten N Finger (wie echte Touchpads mit wenigen Slots).
12 Einheiten je mm, 100 Hz. Positionen gehen nur an den Kernel, nichts davon wird ausgegeben.
"""

import os
import sys
import time

import libevdev
from libevdev import EV_ABS, EV_KEY, EV_SYN, INPUT_PROP_BUTTONPAD, INPUT_PROP_POINTER, InputAbsInfo, InputEvent

RES = 12
WIDTH_MM = 100
HEIGHT_MM = 60
XMAX = WIDTH_MM * RES
YMAX = HEIGHT_MM * RES
TICK = 0.010

TOOLS = {1: EV_KEY.BTN_TOOL_FINGER, 2: EV_KEY.BTN_TOOL_DOUBLETAP, 3: EV_KEY.BTN_TOOL_TRIPLETAP,
         4: EV_KEY.BTN_TOOL_QUADTAP, 5: EV_KEY.BTN_TOOL_QUINTTAP}
KEYBOARD_KEYS = [getattr(EV_KEY, f"KEY_{name}") for name in
                 ("ESC", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "MINUS", "EQUAL", "BACKSPACE", "TAB",
                  "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "LEFTBRACE", "RIGHTBRACE", "ENTER", "LEFTCTRL",
                  "A", "S", "D", "F", "G", "H", "J", "K", "L", "SEMICOLON", "APOSTROPHE", "GRAVE", "LEFTSHIFT",
                  "BACKSLASH", "Z", "X", "C", "V", "B", "N", "M", "COMMA", "DOT", "SLASH", "RIGHTSHIFT", "SPACE")]
DIRECTIONS = {"hoch": (0, -1), "runter": (0, 1), "links": (-1, 0), "rechts": (1, 0)}
tracking = [100]


def create(kind, slots):
    device = libevdev.Device()
    device.id = {"bustype": 0x03, "vendor": 0x1234, "product": 0x5678, "version": 1}
    if kind == "tastatur":
        device.name = "zenOS Test Tastatur"
        for key in KEYBOARD_KEYS:
            device.enable(key)
        return device.create_uinput_device()
    device.name = "zenOS Test Touchpad" if kind == "touchpad" else "zenOS Test Touchpad mit Tasten"
    device.enable(INPUT_PROP_POINTER)
    device.enable(INPUT_PROP_BUTTONPAD)
    for key in (EV_KEY.BTN_LEFT, EV_KEY.BTN_TOUCH, *TOOLS.values()):
        device.enable(key)
    if kind == "touchpad-tasten":
        for key in (EV_KEY.KEY_VOLUMEDOWN, EV_KEY.KEY_VOLUMEUP, EV_KEY.KEY_A):
            device.enable(key)
    device.enable(EV_ABS.ABS_X, InputAbsInfo(minimum=0, maximum=XMAX, resolution=RES))
    device.enable(EV_ABS.ABS_Y, InputAbsInfo(minimum=0, maximum=YMAX, resolution=RES))
    device.enable(EV_ABS.ABS_MT_SLOT, InputAbsInfo(minimum=0, maximum=slots - 1))
    device.enable(EV_ABS.ABS_MT_TRACKING_ID, InputAbsInfo(minimum=0, maximum=65535))
    device.enable(EV_ABS.ABS_MT_POSITION_X, InputAbsInfo(minimum=0, maximum=XMAX, resolution=RES))
    device.enable(EV_ABS.ABS_MT_POSITION_Y, InputAbsInfo(minimum=0, maximum=YMAX, resolution=RES))
    device.enable(EV_ABS.ABS_MT_TOOL_TYPE, InputAbsInfo(minimum=0, maximum=2))
    return device.create_uinput_device()


def frame(uinput, slots, points, before):
    """points: (x, y) je Finger oder [] zum Abheben. Gibt die Zahl belegter Slots zurück."""
    events = []
    count = len(points)
    for slot in range(slots):
        if slot < count:
            x, y = points[slot]
            events.append(InputEvent(EV_ABS.ABS_MT_SLOT, slot))
            if slot >= before:
                tracking[0] += 1
                events.append(InputEvent(EV_ABS.ABS_MT_TRACKING_ID, tracking[0]))
            events.append(InputEvent(EV_ABS.ABS_MT_POSITION_X, int(x)))
            events.append(InputEvent(EV_ABS.ABS_MT_POSITION_Y, int(y)))
        elif slot < before:
            events.append(InputEvent(EV_ABS.ABS_MT_SLOT, slot))
            events.append(InputEvent(EV_ABS.ABS_MT_TRACKING_ID, -1))
    if count:
        events.append(InputEvent(EV_ABS.ABS_X, int(points[0][0])))
        events.append(InputEvent(EV_ABS.ABS_Y, int(points[0][1])))
    for fingers, tool in TOOLS.items():
        events.append(InputEvent(tool, 1 if count == fingers else 0))
    events.append(InputEvent(EV_KEY.BTN_TOUCH, 1 if count else 0))
    events.append(InputEvent(EV_SYN.SYN_REPORT, 0))
    uinput.send_events(events)
    return min(count, slots)


def move(uinput, slots, start, dx, dy, duration=0.30):
    steps = max(1, int(duration / TICK))
    used = frame(uinput, slots, start, 0)
    time.sleep(TICK * 3)
    for step in range(1, steps + 1):
        share = step / steps
        used = frame(uinput, slots, [(x + dx * share, y + dy * share) for x, y in start], used)
        time.sleep(TICK)
    time.sleep(TICK * 2)
    frame(uinput, slots, [], used)
    time.sleep(0.4)


def fingers_at(count, downwards=False):
    """Finger nebeneinander in der Mitte, 18 mm Abstand; nach unten oben beginnen, sonst unten."""
    y = YMAX * (0.25 if downwards else 0.6)
    gap = 18 * RES
    return [(XMAX / 2 + (i - (count - 1) / 2) * gap, y) for i in range(count)]


def run(uinput, slots, parts):
    command = parts[0]
    if command in ("swipe3", "swipe4", "scroll2"):
        count = {"swipe3": 3, "swipe4": 4, "scroll2": 2}[command]
        rx, ry = DIRECTIONS[parts[1]]
        mm = float(parts[2]) if len(parts) > 2 else 20
        move(uinput, slots, fingers_at(count, ry > 0), rx * mm * RES, ry * mm * RES)
    elif command == "pfad":
        count, dx_mm, dy_mm, duration = int(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
        move(uinput, slots, fingers_at(count, dy_mm > 0), dx_mm * RES, dy_mm * RES, duration)
    elif command == "zeiger1":
        mm = float(parts[1]) if len(parts) > 1 else 20
        move(uinput, slots, [(XMAX * 0.3, YMAX * 0.5)], mm * RES, 0)
    elif command == "tippen3":
        used = frame(uinput, slots, fingers_at(3), 0)
        time.sleep(0.05)
        frame(uinput, slots, [], used)
        time.sleep(0.4)
    else:
        print("unbekannt:", " ".join(parts), flush=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    fifo = sys.argv[1]
    kind = sys.argv[sys.argv.index("--art") + 1] if "--art" in sys.argv else "touchpad"
    slots = int(sys.argv[sys.argv.index("--slots") + 1]) if "--slots" in sys.argv else 5
    if kind not in ("touchpad", "tastatur", "touchpad-tasten"):
        print(f"unbekannte Art {kind}", file=sys.stderr)
        return 2
    uinput = create(kind, slots)
    print(f"geraet {uinput.devnode} {uinput.syspath}", flush=True)
    if not os.path.exists(fifo):
        os.mkfifo(fifo, 0o600)
    while True:
        with open(fifo, encoding="utf-8") as handle:
            for line in handle:
                parts = line.split()
                if not parts:
                    continue
                if parts[0] == "ende":
                    print("ende", flush=True)
                    return 0
                if kind != "tastatur":
                    run(uinput, slots, parts)
                print("fertig", " ".join(parts), flush=True)


if __name__ == "__main__":
    sys.exit(main())
