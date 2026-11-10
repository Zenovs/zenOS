function _zenos_after_command --description 'Statuszeile und Trennlinie nach einem Befehl'
    # Aufruf aus dem Ereignis fish_postexec: _zenos_after_command STATUS DAUER_MS BEFEHLSZEILE
    # Jeder Befehl wird so zu einem Block: Eingabezeile, Ausgabe, Statuszeile, leise Trennlinie.
    set -l code $argv[1]
    set -l ms $argv[2]
    set -l cmdline (string join \n -- $argv[3..])

    # Nur, wenn wirklich etwas lief: keine leeren Eingaben, keine reinen Kommentare
    string split \n -- $cmdline | string trim | string match -qrv '^(#.*)?$'
    or return 0
    # Nach clear und reset bleibt der Bildschirm leer
    if string match -qr '^\s*(command\s+)?(clear|reset|tput\s+(clear|reset))\s*$' -- $cmdline
        return 0
    end

    set -l width $COLUMNS
    test -n "$width"; or set width 80
    set -l reset (set_color normal)

    # Endet die Ausgabe ohne Zeilenumbruch, bleibt ein leises ⏎ stehen und es geht in der nächsten
    # Zeile weiter (derselbe Kniff wie in fish: die Leerzeichen brechen nur um, wenn die Zeile nicht leer war).
    # Nach Ctrl+C steht dort schon «^C», dann ohne Zeichen.
    set -l mark ⏎
    test "$code" = 130; and set mark ' '
    printf '%s%s%s%s\r\e[K' (set_color brblack) $mark $reset "$(string repeat -n (math $width - 1) ' ')"

    if test "$code" = 0
        printf '%s%s%s\n' (set_color brblack) (_zenos_status_text $code $ms) $reset
    else
        printf '%s%s%s\n' (set_color red) (_zenos_status_text $code $ms) $reset
    end
    # Trennlinie ohne Zeichen: eine gelöschte Zeile mit Durchstreichung. kitty zieht sie über die ganze
    # Breite; beim Verkleinern des Fensters bricht sie nicht in mehrere Zeilen um (sie entfällt), und
    # beim Kopieren bleibt nur eine Leerzeile. Andere Terminals zeigen eine Leerzeile.
    printf '%s\e[9m\e[K%s\n' (set_color --dim brblack) $reset
end
