function fish_title --description 'Titel für Fenster und Tab: laufender Befehl, sonst der Ordner'
    if set -q argv[1]; and test -n "$argv[1]"
        string split --fields 1 -- ' ' (string trim -- $argv[1])
    else if test "$PWD" = "$HOME"
        echo '~'
    else
        path basename -- $PWD
    end
end
