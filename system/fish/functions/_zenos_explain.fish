function _zenos_explain --description 'Erklärt einen Befehl als Karte, lokal und ohne Internet («?»)'
    # ? BEFEHL [OPTIONEN …]   Beschreibung aus tldr (Deutsch, sonst Englisch), die genutzten Optionen
    #                         kurz aus der man-Seite und ein passendes Beispiel.
    # ?                       erklärt die Bedienung des Terminals.
    set -l width (_zenos_card_width)
    set -l inner (math $width - 4)
    set -l dim (set_color brblack)
    set -l accent (set_color yellow)
    set -l bold (set_color --bold)
    set -l reset (set_color normal)

    # «? sudo rm -rf x» erklärt rm, «? sudo» allein sudo
    set -l words (_zenos_command_words $argv)
    set -q words[1]; or set words $argv[1]
    if not set -q words[1]; or contains -- "$words[1]" '?' --hilfe --help -h
        _zenos_explain_help $width
        return 0
    end
    set -l command (string replace -r '^.*/' '' -- $words[1])
    set -l args $words[2..]

    # tldr-Seite, bei «git log» zuerst die Seite des Unterbefehls
    set -l name $command
    set -l page
    set -l cache (_zenos_tldr_cache)
    if test -n "$cache"
        if set -q args[1]; and string match -qr '^[a-z0-9][a-z0-9-]*$' -- $args[1]
            set page (_zenos_tldr $command $args[1])
            and begin
                set name "$command $args[1]"
                set -e args[1]
            end
        end
        set -q page[1]; or set page (_zenos_tldr $command)
    end

    set -l description
    set -l example_texts
    set -l example_codes
    for line in $page
        if string match -qr '^> ' -- $line
            string match -q -- '*<http*' $line; and continue
            set -a description (string replace -r '^> ' '' -- $line | string replace -a '`' '')
        else if string match -qr '^- ' -- $line
            set -a example_texts (string replace -r '^- (.*?):?\s*$' '$1' -- $line | string replace -a '`' '')
        else if string match -qr '^`.*`$' -- $line
            set -a example_codes (_zenos_tldr_code $line)
        end
    end
    # Nur die erste Zeile: sie sagt, wozu der Befehl da ist
    set description $description[1]

    # Genutzte Optionen: -avz → -a -v -z, ausser die man-Seite kennt -avz selbst (find -name)
    set -l clusters
    set -l candidates
    for arg in $args
        test "$arg" = --; and break
        set -l cluster
        if string match -qr '^--[A-Za-z0-9]' -- $arg
            set cluster (string replace -r '=.*$' '' -- $arg)
        else if string match -qr '^-[A-Za-z]' -- $arg
            set cluster (string replace -r '^(-[A-Za-z]+).*$' '$1' -- $arg)
            for letter in (string split '' -- (string sub --start 2 -- $cluster))
                set -a candidates -$letter
            end
        else
            continue
        end
        contains -- $cluster $clusters; or set -a clusters $cluster
        set -a candidates $cluster
    end

    # Beschreibungen aus der man-Seite (des Unterbefehls, sonst des Befehls)
    set -l found_names
    set -l found_texts
    set -l have_man 0
    if set -q clusters[1]
        set -l man_page (string replace -a ' ' - -- $name)
        set -l found (_zenos_man_options $man_page $candidates)
        and set have_man 1
        if test $have_man = 0; and test "$man_page" != "$command"
            set found (_zenos_man_options $command $candidates)
            and set have_man 1
        end
        for entry in $found
            set -l fields (string split --max 1 \t -- $entry)
            set -a found_names $fields[1]
            set -a found_texts "$fields[2]"
        end
    end
    set -l option_names
    set -l option_texts
    test $have_man = 1; or set clusters
    for cluster in $clusters
        set -l parts $cluster
        if string match -qr '^-[A-Za-z]{2,}$' -- $cluster; and not contains -- $cluster $found_names
            set parts
            for letter in (string split '' -- (string sub --start 2 -- $cluster))
                set -a parts -$letter
            end
        end
        for option in $parts
            contains -- $option $option_names; and continue
            set -a option_names $option
            set -l index (contains --index -- $option $found_names)
            if test -n "$index"
                set -a option_texts (_zenos_first_sentence $found_texts[$index])
            else
                set -a option_texts ''
            end
        end
    end

    # Ohne tldr-Seite: Kurzbeschreibung aus dem man-Index, sonst aus fish selbst
    if test -z "$description"; and command -q whatis
        set -l summary (whatis -L de -- (string replace -a ' ' - -- $name) 2>/dev/null)
        or set summary (whatis -L de -- $command 2>/dev/null)
        and set description (string replace -r '^.*? - ' '' -- $summary[1])
    end
    if test -z "$description"
        if builtin -q -- $command
            set description 'Befehl von fish selbst (Hilfe: help '$command').'
        else if functions -q -- $command
            set -l details (functions --details --verbose -- $command)
            test -n "$details[5]"; and test "$details[5]" != n/a; and set description $details[5]
            test -n "$description"; or set description 'Funktion der Shell.'
        end
    end

    # Karte zusammensetzen
    set -l lines
    if test -n "$description"
        set -l indent (math (string length --visible -- $name) + 2)
        set -l wrapped (_zenos_wrap (math $inner - $indent) $description)
        set -a lines $bold$name$reset'  '$wrapped[1]
        for rest in $wrapped[2..]
            set -a lines "$(string repeat -n $indent ' ')"$rest
        end
    else
        set -a lines $bold$name$reset
        set -a lines $dim'Dazu gibt es hier keine Erklärung.'$reset
    end
    if test -z "$cache"
        set -a lines ''
        for rest in (_zenos_wrap $inner 'Die tldr-Seiten sind noch nicht geladen. Mit Internet einmal: tldr --update')
            set -a lines $dim$rest$reset
        end
    end

    if set -q option_names[1]
        set -a lines ''
        set -l column 4
        for option in $option_names
            set column (math "max($column, "(string length -- $option)" + 2)")
        end
        set column (math "min($column, 16)")
        for i in (seq (count $option_names))
            set -l text $option_texts[$i]
            test -n "$text"; or set text $dim'keine Beschreibung gefunden'$reset
            set -l wrapped (_zenos_wrap (math $inner - $column) $text)
            set -l label (string pad --right --width $column -- $option_names[$i])
            set -a lines $accent$label$reset$wrapped[1]
            for rest in $wrapped[2..3]
                set -a lines "$(string repeat -n $column ' ')"$rest
            end
        end
    end

    # Beispiele: mit Optionen das passendste, sonst bis zu drei
    set -l footer 'lokal · offline'
    if set -q example_codes[1]
        set -a lines ''
        if set -q option_names[1]
            set -l best 1
            set -l best_score -1
            for i in (seq (count $example_codes))
                set -l score 0
                set -l code_words (string split ' ' -- $example_codes[$i])
                for option in $option_names $clusters
                    contains -- $option $code_words; and set score (math $score + 1)
                end
                if test $score -gt $best_score
                    set best $i
                    set best_score $score
                end
            end
            set -l wrapped (_zenos_wrap $inner "Beispiel: $example_codes[$best]")
            for rest in $wrapped
                set -a lines $dim$rest$reset
            end
        else
            for i in (seq (math "min(3, "(count $example_codes)")"))
                for rest in (_zenos_wrap $inner $example_texts[$i])
                    set -a lines $dim$rest$reset
                end
                for rest in (_zenos_wrap (math $inner - 2) $example_codes[$i])
                    set -a lines '  '$rest
                end
            end
        end
    end
    # Fusszeile rechts, in die letzte Zeile, wenn Platz ist
    set -l last $lines[-1]
    if test (math (string length --visible -- $last) + (string length -- $footer) + 3) -le $inner; and test -n "$last"
        set -l gap (math $inner - (string length --visible -- $last) - (string length -- $footer))
        set lines[-1] $last"$(string repeat -n $gap ' ')"$dim$footer$reset
    else
        set -a lines (_zenos_align_right $inner $dim$footer$reset)
    end

    _zenos_card --dim,brblack $width $lines
end
