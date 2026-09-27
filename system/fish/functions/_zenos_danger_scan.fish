function _zenos_danger_scan --description 'Zerlegt eine Befehlszeile und prüft jeden Befehl (für _zenos_danger)'
    # Gibt den Schlüssel der ersten Gefahr aus (siehe _zenos_danger), sonst nichts.
    # fishs eigener Tokenizer (read --tokenize) trennt Wörter, Anführungszeichen und Kommentare,
    # ohne etwas auszuführen oder aufzulösen.
    set -l tokens
    printf '%s\n' $argv | read -z -l -a --tokenize tokens
    set -a tokens ';'

    set -l words          # Wörter des aktuellen Befehls, mit Umleitungen
    set -l fetched 0      # im laufenden Rohr kam schon curl oder wget vor
    set -l dir $PWD       # Ordner nach «cd» in derselben Zeile
    for token in $tokens
        # Befehlsersetzungen: ( … ) und $( … ) selbst prüfen
        if string match -q -- '*(*' $token
            for inner in (string match -ra -- '\$?\((?:[^()]++|(?R))*\)' $token)
                set -l key (_zenos_danger_scan (string replace -r -- '^\$?\((.*)\)$' '$1' $inner))
                if test -n "$key"
                    echo $key
                    return 0
                end
            end
        end

        switch $token
            case ';' '&&' '||' '&' \n '|' '&|' '|&'
                if set -q words[1]
                    set -l command (_zenos_command_words $words)
                    if set -q command[1]
                        set -l name (string replace -r '^.*/' '' -- $command[1])
                        set -l key (_zenos_danger_command $fetched $dir $command)
                        if test -n "$key"
                            echo $key
                            return 0
                        end
                        contains -- $name curl wget fetch aria2c http https xh; and set fetched 1
                        if test "$name" = cd
                            if set -q command[2]
                                set -l next (_zenos_path_resolve $command[2] $dir); and set dir $next
                            else
                                set dir $HOME
                            end
                        end
                    end
                end
                set words
                # Ein neues Rohr beginnt nach allem ausser |
                contains -- $token '|' '&|' '|&'; or set fetched 0
            case '*'
                set -a words $token
        end
    end
    return 0
end
