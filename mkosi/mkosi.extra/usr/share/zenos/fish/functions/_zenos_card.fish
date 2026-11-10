function _zenos_card --description 'Zeichnet eine Karte mit Rahmen (für «?» und Warnungen)'
    # _zenos_card FARBE BREITE ZEILE…
    #   FARBE   Argumente für set_color, mit Kommas getrennt, z. B. yellow oder --dim,brblack
    #   BREITE  Gesamtbreite in Zellen (inkl. Rahmen); jede ZEILE darf BREITE-4 Zellen breit sein
    set -l border (set_color (string split , -- $argv[1]))
    set -l width $argv[2]
    set -l inner (math $width - 4)
    set -l reset (set_color normal)
    set -l rule "$(string repeat -n (math $width - 2) ─)"

    printf '%s╭%s╮%s\n' $border $rule $reset
    for line in $argv[3..]
        set -l length (string length --visible -- $line)
        if test $length -gt $inner
            set line (string shorten --max $inner -- $line)$reset
            set length (string length --visible -- $line)
        end
        printf '%s│%s %s%s%s %s│%s\n' $border $reset $line $reset "$(string repeat -n (math $inner - $length) ' ')" $border $reset
    end
    printf '%s╰%s╯%s\n' $border $rule $reset
end
