function _zenos_status_text --description 'Text der Statuszeile: «✓ 0,1 s» oder «✗ Fehler 1 · Klartext · 3,2 s»'
    # _zenos_status_text STATUS DAUER_MS
    set -l code $argv[1]
    set -l duration (_zenos_duration $argv[2])
    if test "$code" = 0
        echo "✓ $duration"
        return 0
    end
    set -l reason (_zenos_exit_reason $code)
    if test -n "$reason"
        echo "✗ Fehler $code · $reason · $duration"
    else
        echo "✗ Fehler $code · $duration"
    end
end
