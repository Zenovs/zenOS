function _zenos_tldr_code --description 'Beispielbefehl aus einer tldr-Zeile ohne Markdown und Platzhalter-Klammern'
    # `rsync {{[-a|--archive]}} {{pfad/zu/quelle}}` → rsync -a pfad/zu/quelle
    string replace -r -- '^`(.*)`$' '$1' $argv[1] \
        | string replace -ra -- '\{\{\[([^|\]]*)\|[^\]]*\]\}\}' '$1' \
        | string replace -ra -- '\{\{(.*?)\}\}' '$1'
end
