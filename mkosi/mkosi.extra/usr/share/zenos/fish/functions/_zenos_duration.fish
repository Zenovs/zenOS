function _zenos_duration --description 'Dauer für die Statuszeile, deutsches Dezimalkomma'
    # _zenos_duration MILLISEKUNDEN → «0,1 s», «3,2 s», «2 Min. 5 s», «1 Std. 4 Min.»
    # Unter einer Minute in Zehntelsekunden, aufgerundet (nie «0,0 s»).
    set -l ms $argv[1]
    string match -qr '^[0-9]+$' -- $ms; or set ms 0
    if test $ms -lt 60000
        set -l tenths (math "max(1, ceil($ms / 100))")
        printf '%d,%d s\n' (math "floor($tenths / 10)") (math "$tenths % 10")
    else if test $ms -lt 3600000
        set -l seconds (math "floor($ms / 1000)")
        printf '%d Min. %d s\n' (math "floor($seconds / 60)") (math "$seconds % 60")
    else
        set -l minutes (math "floor($ms / 60000)")
        printf '%d Std. %d Min.\n' (math "floor($minutes / 60)") (math "$minutes % 60")
    end
end
