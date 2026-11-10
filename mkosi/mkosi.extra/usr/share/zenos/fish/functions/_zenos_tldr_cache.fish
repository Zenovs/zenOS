function _zenos_tldr_cache --description 'Ordner der lokalen tldr-Seiten (Status 1, wenn sie fehlen)'
    set -l dir
    if set -q TEALDEER_CACHE_DIR; and test -n "$TEALDEER_CACHE_DIR"
        set dir $TEALDEER_CACHE_DIR/tldr-pages
    else if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
        set dir $XDG_CACHE_HOME/tealdeer/tldr-pages
    else
        set dir $HOME/.cache/tealdeer/tldr-pages
    end
    test -d $dir/pages.en; or test -d $dir/pages.de; or return 1
    echo $dir
end
