function _zenos_man_options --description 'Kurzbeschreibung von Optionen aus einer man-Seite'
    # _zenos_man_options SEITE OPTION… → pro gefundener Option eine Zeile «OPTION<Tab>Beschreibung».
    # Deutsch, wenn es die Seite auf Deutsch gibt (manpages-de), sonst Englisch. Erkennt die üblichen
    # Formen: «-a, --all» mit Text darunter, «--archive, -a   Text» (Übersicht) und «-v   Text».
    set -l page $argv[1]
    set -l options $argv[2..]
    set -q options[1]; or return 1
    command -q man; or return 1

    set -l text (env MANWIDTH=400 man -L de --nh --nj -- $page 2>/dev/null)
    or return 1

    printf '%s\n' $text | command awk -v wanted_list="$options" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function finish() {
            if (current != "" && !(current in found) && text != "") found[current] = text
            current = ""; text = ""; collecting = 0
        }
        BEGIN { n = split(wanted_list, list, " "); for (i = 1; i <= n; i++) wanted[list[i]] = 1 }
        {
            line = $0
            # Bindestriche aus groff (U+2010, U+2212) als «-»
            gsub(/\342\200\220|\342\210\222/, "-", line)
            if (collecting) {
                if (line ~ /^[ \t]*$/) { finish(); next }
                match(line, /^[ \t]*/)
                if (RLENGTH > indent) { text = (text == "" ? trim(line) : text " " trim(line)); next }
                finish()
            }
            if (line !~ /^[ \t]+-/) next
            match(line, /^[ \t]+/); indent_here = RLENGTH
            body = substr(line, indent_here + 1)
            head = body; rest = ""
            if (match(body, /[ \t][ \t]+/)) {
                head = substr(body, 1, RSTART - 1)
                rest = trim(substr(body, RSTART + RLENGTH))
            }
            gsub(/,/, " ", head)
            m = split(head, names, " ")
            hit = ""
            for (j = 1; j <= m; j++) {
                name = names[j]
                sub(/[=\[].*$/, "", name)
                if ((name in wanted) && !(name in found)) { hit = name; break }
            }
            if (hit == "") next
            if (rest != "") { found[hit] = rest; next }
            current = hit; indent = indent_here; text = ""; collecting = 1
        }
        END { finish(); for (o in found) print o "\t" found[o] }
    '
end
