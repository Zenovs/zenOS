function _zenos_explain_help --description '«?» ohne Befehl: Bedienung des Terminals'
    # _zenos_explain_help BREITE
    set -l width $argv[1]
    set -l inner (math $width - 4)
    set -l dim (set_color brblack)
    set -l accent (set_color yellow)
    set -l bold (set_color --bold)
    set -l reset (set_color normal)

    set -l lines $bold'?'$reset'  erklärt Befehle, lokal und ohne Internet.'
    set -a lines ''
    set -a lines $accent(string pad --right --width 14 -- '? rsync -avz')$reset'was rsync tut und was -a, -v, -z bedeuten'
    set -a lines $accent(string pad --right --width 14 -- '? git log')$reset'Unterbefehle gehen auch'
    set -a lines ''

    # Tastenkürzel (kitty, fish, fzf, zoxide)
    set -l keys \
        'Ctrl+C' 'kopieren, wenn etwas markiert ist, sonst abbrechen' \
        'Ctrl+V' 'einfügen' \
        'Super+↑ ↓' 'zum vorherigen oder nächsten Befehl' \
        'Ctrl+R' 'Verlauf durchsuchen' \
        'Ctrl+T' 'Datei suchen und einfügen' \
        'z Ordner' 'in einen oft besuchten Ordner springen' \
        'Super+T' 'neuer Tab' \
        'Super+W' 'Tab schliessen' \
        'Super+D' 'teilen (Super+Shift+D untereinander)' \
        'Super+K' 'leeren' \
        'Super+Plus' 'Schrift grösser (Minus kleiner, 0 normal)'
    for i in (seq 1 2 (count $keys))
        set -l wrapped (_zenos_wrap (math $inner - 14) $keys[(math $i + 1)])
        set -a lines $accent(string pad --right --width 14 -- $keys[$i])$reset$wrapped[1]
        for rest in $wrapped[2..]
            set -a lines "$(string repeat -n 14 ' ')"$rest
        end
    end
    set -a lines ''
    for rest in (_zenos_wrap $inner 'Vor gefährlichen Befehlen fragt das Terminal einmal nach. Enter bricht ab, t führt trotzdem aus.')
        set -a lines $dim$rest$reset
    end
    set -a lines (_zenos_align_right $inner $dim'lokal · offline'$reset)

    _zenos_card --dim,brblack $width $lines
end
