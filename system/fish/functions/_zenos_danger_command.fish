function _zenos_danger_command --description 'Prüft einen einzelnen Befehl (für _zenos_danger)'
    # _zenos_danger_command GEHOLT ORDNER BEFEHL [WORT…]
    #   GEHOLT  1, wenn im selben Rohr vorher curl oder wget lief
    #   ORDNER  Ordner für relative Pfade (nach «cd» in derselben Zeile)
    # Gibt den Schlüssel der Gefahr aus (siehe _zenos_danger), sonst nichts (Status 1).
    set -l fetched $argv[1]
    set -l dir $argv[2]
    set -l name (string replace -r '^.*/' '' -- $argv[3])
    set -l words $argv[4..]

    # Umleitungen von den Argumenten trennen
    set -l args
    set -l outputs      # Ziele von > und >>
    set -l skip
    for word in $words
        switch "$skip"
            case output
                set -a outputs $word
                set skip
                continue
            case input
                set -a args $word
                set skip
                continue
            case fd
                set skip
                continue
        end
        if string match -qr '^[0-9]*>&$' -- $word
            set skip fd
        else if string match -qr '^([0-9]*|&)>>?[|?]?$' -- $word
            set skip output
        else if string match -qr '^[0-9]*<<?$' -- $word
            set skip input
        else
            set -a args $word
        end
    end

    # Umleitung auf ein Laufwerk, bei jedem Befehl
    for target in $outputs
        if _zenos_is_disk $target
            echo disk-write
            return 0
        end
    end

    set -l interpreters sh bash zsh dash ksh mksh fish source . eval python python3 perl ruby node php
    set -l fetchers curl wget fetch aria2c http https xh

    switch $name
        case '?' _zenos_explain
            return 1

        case rm
            set -l forced 0
            set -l targets
            set -l options_done 0
            for arg in $args
                if test $options_done = 0
                    if test "$arg" = --
                        set options_done 1
                        continue
                    else if string match -qr '^--(recursive|force)$' -- $arg
                        set forced 1
                        continue
                    else if string match -qr '^-[A-Za-z]*[rRf]' -- $arg
                        set forced 1
                        continue
                    else if string match -qr '^-.' -- $arg
                        continue
                    end
                end
                set -a targets $arg
            end
            test $forced = 1; or return 1
            set -l kinds
            for target in $targets
                set -a kinds (_zenos_path_kind $target $dir)
            end
            if contains wurzel $kinds
                echo delete-root
            else if contains home $kinds
                echo delete-home
            else if contains system $kinds
                echo delete-system
            else
                return 1
            end
            return 0

        case chmod chown chgrp
            set -l recursive 0
            set -l reference 0
            set -l rest
            for arg in $args
                if string match -qr '^--recursive$|^-[A-Za-z]*R' -- $arg
                    set recursive 1
                else if string match -qr '^--reference' -- $arg
                    set reference 1
                else if not string match -qr '^-.' -- $arg
                    set -a rest $arg
                end
            end
            test $recursive = 1; or return 1
            # Erstes Argument ist Modus bzw. Besitzer (ausser mit --reference)
            set -l mode
            if test $reference = 0; and set -q rest[1]
                set mode $rest[1]
                set -e rest[1]
            end
            if test $name = chmod; and string match -qr '^0?777$|^(a|ugo)?[+=]rwx$' -- $mode
                echo world-writable
                return 0
            end
            for target in $rest
                if contains -- (_zenos_path_kind $target $dir) wurzel system
                    echo permissions-system
                    return 0
                end
            end
            return 1

        case dd
            for arg in $args
                if string match -q -- 'of=*' $arg; and _zenos_is_disk (string replace 'of=' '' -- $arg)
                    echo disk-write
                    return 0
                end
            end
            return 1

        case tee
            for arg in $args
                if _zenos_is_disk $arg
                    echo disk-write
                    return 0
                end
            end
            return 1

        case mkfs 'mkfs.*' mke2fs
            if not string match -qr '^(-h|--help|-V|--version)$' -- $args
                echo format
                return 0
            end
            return 1

        case wipefs
            if string match -qr '^(-a|--all|-[A-Za-z]*a[A-Za-z]*)$' -- $args
                echo format
                return 0
            end
            return 1
    end

    if contains -- $name $interpreters
        # curl … | sh
        if test "$fetched" = 1
            echo remote-script
            return 0
        end
        # sh -c "$(curl …)", sh <(curl …), source (curl … | psub)
        for arg in $args
            for inner in (string match -ra -- '\$?\((?:[^()]++|(?R))*\)' $arg)
                set -l inner_tokens
                string replace -r -- '^\$?\((.*)\)$' '$1' $inner | read -z -l -a --tokenize inner_tokens
                set -l first (_zenos_command_words $inner_tokens)
                if contains -- (string replace -r '^.*/' '' -- "$first[1]") $fetchers
                    echo remote-script
                    return 0
                end
            end
        end
        # sh -c 'Skript': das Skript selbst prüfen
        if contains -- $name sh bash zsh dash ksh mksh fish
            set -l script_next 0
            for arg in $args
                if test $script_next = 1
                    set -l key (_zenos_danger_scan $arg)
                    if test -n "$key"
                        echo $key
                        return 0
                    end
                    break
                end
                string match -qr '^-[A-Za-z]*c[A-Za-z]*$' -- $arg; and set script_next 1
            end
        end
    end
    return 1
end
