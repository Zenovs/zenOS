function _zenos_warn --description 'Warnkarte unter der Eingabezeile; Status 0 heisst «trotzdem ausführen»'
    # _zenos_warn WARNTEXT
    # «Abbrechen» ist vorausgewählt: Enter, Esc, Ctrl+C und jede andere Taste brechen ab.
    # Nur «t» führt den Befehl trotzdem aus.
    set -l width (_zenos_card_width)
    set -l inner (math $width - 4)
    set -l reset (set_color normal)

    set -l text (_zenos_wrap (math $inner - 3) $argv)
    set -l lines (set_color yellow)'⚠'$reset'  '$text[1]
    for rest in $text[2..]
        set -a lines '   '$rest
    end
    set -a lines ''
    set -l buttons (set_color --reverse --bold)' Abbrechen ↵ '$reset'   Trotzdem ausführen '(set_color brblack)'t'$reset
    set -a lines (_zenos_align_right $inner $buttons)

    printf '\n'
    _zenos_card yellow $width $lines

    # Eigener Tastenmodus für die Rückfrage: Enter, Esc und Ctrl+C beenden sie, jede Zeichentaste
    # ebenso, Pfeile und Ähnliches bleiben ohne Wirkung. Eigene Tastenbelegungen stören so nicht.
    bind -M zenos_rueckfrage enter execute
    bind -M zenos_rueckfrage escape cancel-commandline
    bind -M zenos_rueckfrage ctrl-c cancel-commandline
    bind -M zenos_rueckfrage '' self-insert
    set -l mode $fish_bind_mode
    set -g fish_bind_mode zenos_rueckfrage
    read --nchars 1 --silent --prompt-str '' --local answer
    set -l read_status $status
    set -g fish_bind_mode $mode

    set -l run 1
    set -l outcome (set_color brblack)'Abgebrochen. Der Befehl steht noch in der Eingabezeile.'$reset
    if test $read_status -eq 0; and contains -- "$answer" t T
        set run 0
        set outcome (set_color brblack)'Wird trotzdem ausgeführt.'$reset
    end

    # Zeile der Tasteneingabe entfernen und die Knopfzeile durch das Ergebnis ersetzen
    # (Knopfzeile: zwei Zeilen über der Eingabezeile, darunter nur der untere Rahmen)
    set -l border (set_color yellow)
    set -l row (_zenos_align_right $inner $outcome)
    printf '\e[1A\r\e[2K\e[2A\r\e[2K%s│%s %s%s %s│%s\e[2B\r' \
        $border $reset $row "$(string repeat -n (math $inner - (string length --visible -- $row)) ' ')" $border $reset
    return $run
end
