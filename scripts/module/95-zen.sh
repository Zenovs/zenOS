#!/usr/bin/env bash
# 95-zen: Befehl zen unter /usr/local/bin und Log-Ordner
# shellcheck shell=bash

modul_system() {
  system_verknuepfen "$ZENOS_CODE/scripts/zen" /usr/local/bin/zen
  ordner_sicherstellen /var/log/zenos 0755 root:root
}
