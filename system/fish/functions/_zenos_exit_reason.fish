function _zenos_exit_reason --description 'Klartext zu einem Exit-Status (leer, wenn es keinen gibt)'
    set -l code $argv[1]
    switch $code
        case 1
            echo 'allgemeiner Fehler'
        case 2
            echo 'falscher Aufruf'
        case 126
            echo 'nicht ausführbar'
        case 127
            echo 'Befehl nicht gefunden'
        case 130
            echo 'abgebrochen (Ctrl+C)'
        case 137
            echo 'hart beendet (SIGKILL)'
        case 139
            echo 'Speicherzugriffsfehler (SIGSEGV)'
        case 141
            echo 'Pipe geschlossen (SIGPIPE)'
        case 143
            echo 'beendet (SIGTERM)'
        case '*'
            # Andere Signale: 128 + Nummer
            if string match -qr '^[0-9]+$' -- $code; and test $code -gt 128 -a $code -lt 160
                set -l signal (fish_status_to_signal $code)
                and string match -q 'SIG*' -- $signal
                and echo "Signal $signal"
            end
    end
    return 0
end
