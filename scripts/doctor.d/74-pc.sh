#!/usr/bin/env bash
# 74-pc: x86-Rechner (amd64) – Systemplatte verschlüsselt, Start mit UEFI und Secure Boot
# shellcheck shell=bash
#
# docs/sicherheit.md: Auf dem Bürorechner ist die Festplattenverschlüsselung Pflicht und Secure Boot an. Beides
# richtet die Installation ein (der Ubuntu-Installer bzw. das UEFI), zenOS ändert daran nichts; doctor sagt nur, wie es
# steht. Auf dem Pi ist die Verschlüsselung in 0.1 nicht umgesetzt und Secure Boot bewusst aus: Dort schweigt der
# Abschnitt. Gelesen wird nur /sys, ausgegeben werden keine Gerätenamen.

# Wurzel von sysfs (Tests setzen eine eigene)
_PC_SYS=/sys
_PC_SECURE_BOOT=firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c

pruefe_pc() {
  [[ "$(dpkg --print-architecture 2>/dev/null)" == amd64 ]] || return 0
  abschnitt "PC: Systemplatte und Start"
  _pc_verschluesselung
  _pc_secure_boot
}

# Liegt das Blockgerät MAJ:MIN auf dm-crypt? Über /sys/dev/block/<n>/slaves bis zu den Partitionen hinunter (LVM auf
# LUKS wie beim Ubuntu-Installer, oder LUKS direkt). dm-crypt trägt eine uuid «CRYPT-…».
_pc_auf_crypt() { # MAJ:MIN [TIEFE]
  local geraet=$_PC_SYS/dev/block/$1 tiefe=${2:-0} uuid unter
  (( tiefe < 8 )) || return 1
  uuid=$(cat -- "$geraet/dm/uuid" 2>/dev/null) || uuid=""
  [[ "$uuid" != CRYPT-* ]] || return 0
  for unter in "$geraet"/slaves/*; do
    [[ -r "$unter/dev" ]] || continue
    _pc_auf_crypt "$(cat -- "$unter/dev")" $((tiefe + 1)) && return 0
  done
  return 1
}

_pc_verschluesselung() {
  local nummer
  nummer=$(findmnt -n -o MAJ:MIN --target / 2>/dev/null) || nummer=""
  nummer=${nummer//[[:space:]]/}
  if [[ ! "$nummer" =~ ^[0-9]+:[0-9]+$ || ! -e "$_PC_SYS/dev/block/$nummer" ]]; then
    hinweis "Verschlüsselung der Systemplatte nicht feststellbar"
  elif _pc_auf_crypt "$nummer"; then
    ok "Systemplatte verschlüsselt (LUKS)"
  else
    warnung "Systemplatte nicht verschlüsselt – auf dem Bürorechner Pflicht (docs/sicherheit.md); geht nur mit einer Neuinstallation (Installer-Stick: «LVM und Verschlüsselung verwenden», ANLEITUNG H9)"
  fi
}

# Secure Boot: EFI-Variable SecureBoot, 4 Bytes Attribute, dann 1 Byte (1 = an)
_pc_secure_boot() {
  local wert
  if [[ ! -d $_PC_SYS/firmware/efi ]]; then
    warnung "Start ohne UEFI (BIOS-Modus) – Secure Boot geht so nicht (UEFI-Einstellungen, danach Neuinstallation)"
    return 0
  fi
  wert=$(od -An -t u1 -j 4 -N 1 -- "$_PC_SYS/$_PC_SECURE_BOOT" 2>/dev/null | tr -d '[:space:]') || wert=""
  case "$wert" in
    1) ok "Secure Boot an" ;;
    0) warnung "Secure Boot ist aus – auf dem Bürorechner soll es an sein (in den UEFI-Einstellungen; Ubuntu startet signiert)" ;;
    *) hinweis "Secure Boot nicht feststellbar" ;;
  esac
}
