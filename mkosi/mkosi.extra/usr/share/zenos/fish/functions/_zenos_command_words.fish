function _zenos_command_words --description 'Wörter ab dem eigentlichen Befehl (ohne sudo, env, VAR=wert …)'
    # _zenos_command_words WORT… → gibt die Wörter ab dem Befehl aus, eines pro Zeile.
    # «sudo -u root rm -rf x» → rm -rf x
    set -l words $argv
    set -l i 1
    set -l n (count $words)
    while test $i -le $n
        set -l word $words[$i]
        # Zuweisungen vor dem Befehl
        if string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' -- $word
            set i (math $i + 1)
            continue
        end
        # Präfixe mit ihren Optionen; die zweite Liste nennt Optionen, die einen Wert nehmen
        set -l takes_value
        switch (string replace -r '^.*/' '' -- $word)
            case sudo doas run0
                set takes_value -u -g -h -p -C -D -R -T -U -r -t --user --group --host --prompt \
                    --close-from --chdir --chroot --command-timeout --other-user --role --type
            case pkexec
                set takes_value --user
            case env
                set takes_value -u -C -S --unset --chdir --split-string
            case nice
                set takes_value -n --adjustment
            case ionice
                set takes_value -c -n -p -P -u --class --classdata --pid --pgid --uid
            case timeout
                set takes_value -s -k --signal --kill-after
            case stdbuf
                set takes_value -i -o -e
            case command builtin exec nohup time unbuffer
            case '*'
                break
        end
        set -l prefix (string replace -r '^.*/' '' -- $word)
        set i (math $i + 1)
        while test $i -le $n; and string match -q -- '-*' $words[$i]
            if test "$words[$i]" = --
                set i (math $i + 1)
                break
            end
            if contains -- $words[$i] $takes_value
                set i (math $i + 2)
            else
                set i (math $i + 1)
            end
        end
        # timeout DAUER BEFEHL: die Dauer überspringen
        if test "$prefix" = timeout; and test $i -le $n
            set i (math $i + 1)
        end
    end
    if test $i -le $n
        printf '%s\n' $words[$i..]
    end
end
