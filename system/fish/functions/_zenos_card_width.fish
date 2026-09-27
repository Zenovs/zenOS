function _zenos_card_width --description 'Breite der Karten: so breit wie das Terminal, höchstens 76 Zellen'
    # 76 Zellen passen auch in eine Rasterhälfte bei 1440 px (etwa 84 Zellen). Gedruckte Karten brechen
    # sonst beim Einrasten in eine Hälfte um (kitty bricht lange Zeilen beim Verkleinern um).
    set -l columns $COLUMNS
    string match -qr '^[0-9]+$' -- $columns; or set columns 80
    math "max(24, min($columns - 1, 76))"
end
