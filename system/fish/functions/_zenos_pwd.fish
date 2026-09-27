function _zenos_pwd --description 'Aktueller Ordner für die Eingabezeile, ~ für den persönlichen Ordner'
    set -l dir $PWD
    if test -n "$HOME"; and test "$HOME" != /
        set dir (string replace -r -- '^'(string escape --style=regex -- $HOME)'(?=/|$)' '~' $dir)
    end
    # Sehr lange Pfade kürzen, damit die Zeile nicht umbricht
    set -l columns $COLUMNS
    test -n "$columns"; or set columns 80
    if test (string length --visible -- $dir) -gt (math "max(20, $columns - 30)")
        set dir (prompt_pwd --dir-length 1 --full-length-dirs 2)
    end
    echo $dir
end
