function _zenos_wrap --description 'Bricht Text an Wortgrenzen um'
    # _zenos_wrap BREITE TEXT… → eine Zeile pro Ausgabezeile. Breite in Zellen; überlange Wörter
    # werden hart getrennt. Für Text ohne Farbsequenzen.
    set -l width $argv[1]
    set -l line ''
    for word in (string split --no-empty ' ' -- (string join ' ' -- $argv[2..]))
        if test -z "$line"
            set line $word
        else if test (math (string length --visible -- $line) + 1 + (string length --visible -- $word)) -le $width
            set line "$line $word"
        else
            echo $line
            set line $word
        end
        while test (string length --visible -- $line) -gt $width
            string sub --length $width -- $line
            set line (string sub --start (math $width + 1) -- $line)
        end
    end
    test -n "$line"; and echo $line
    return 0
end
