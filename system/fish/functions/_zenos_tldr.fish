function _zenos_tldr --description 'tldr-Seite als Markdown (Deutsch, sonst Englisch), nur aus dem lokalen Speicher'
    # _zenos_tldr BEFEHL… → Rohtext der Seite; Status 1, wenn es keine gibt.
    # tealdeer lädt nie selbst nach (auto_update ist aus); geladen wird nur mit «tldr --update».
    command -q tldr; or return 1
    env LANG=de_DE.UTF-8 LANGUAGE=de:en tldr --raw --quiet -- $argv 2>/dev/null
end
