function _zenos_colors --description 'Syntaxfarben von zenOS setzen (global)'
    # Nur die 16 Terminalfarben: Befehle im Akzent, Tippfehler rot, Kommentare und Vorschläge
    # gedämpft, gültige Pfade nicht unterstrichen. Eigene Farben mit «set -g» in config.fish gehen vor.
    set -g fish_color_normal normal
    set -g fish_color_command green
    set -g fish_color_keyword green
    set -g fish_color_param normal
    set -g fish_color_option normal
    set -g fish_color_quote normal
    set -g fish_color_operator normal
    set -g fish_color_escape yellow
    set -g fish_color_redirection brblack
    set -g fish_color_end brblack
    set -g fish_color_error red
    set -g fish_color_comment brblack
    set -g fish_color_autosuggestion brblack
    set -g fish_color_cancel brblack
    set -g fish_color_valid_path normal
    set -g fish_color_search_match --reverse
    set -g fish_color_selection --reverse
    set -g fish_color_history_current --bold
    set -g fish_pager_color_progress brblack
    set -g fish_pager_color_description brblack
    set -g fish_pager_color_prefix normal --bold --underline
    set -g fish_pager_color_completion normal
    set -g fish_pager_color_selected_background --reverse
end
