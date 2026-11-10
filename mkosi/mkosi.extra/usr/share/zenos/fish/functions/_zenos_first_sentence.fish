function _zenos_first_sentence --description 'Erster Satz eines Textes (für Optionsbeschreibungen)'
    # Schneidet nach dem ersten Satzende ab; Abkürzungen wie «z. B.» oder «e.g.» zählen nicht.
    set -l text (string trim -- (string join ' ' -- $argv) | string replace -ra '\s+' ' ')
    string replace -r -- '^(.*?[^\s.][^\s.][.!?])\s+(?=[A-ZÄÖÜ(]).*$' '$1' $text
end
