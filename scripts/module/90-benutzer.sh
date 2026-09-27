#!/usr/bin/env bash
# 90-benutzer: Oberfläche verknüpfen und die Ordner für persönliche Daten anlegen
# shellcheck shell=bash

modul_benutzer() {
  verknuepfen "$ZENOS_CODE/shell" "$ZENOS_HOME/.config/quickshell"

  # Persönliches bleibt lokal und nur für den Benutzer lesbar
  benutzer_ordner_sicherstellen "$ZENOS_HOME/.config/zenos" 0700
  benutzer_ordner_sicherstellen "$ZENOS_HOME/.config/zenos/modi"
  benutzer_ordner_sicherstellen "$ZENOS_HOME/.config/zenos/zustaende"
  benutzer_ordner_sicherstellen "$ZENOS_HOME/.config/zenos/raster"
  benutzer_ordner_sicherstellen "$ZENOS_HOME/.local/state/zenos" 0700
  benutzer_ordner_sicherstellen "$ZENOS_HOME/Bilder/Screenshots"
}
