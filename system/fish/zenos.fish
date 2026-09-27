# zenOS · fish
# ~/.config/fish/conf.d/zenos.fish verweist hierher (scripts/module/60-terminal.sh).
#
# Eingabezeile, Statuszeile nach jedem Befehl, «?» zum Erklären, Warnung vor gefährlichen Befehlen,
# dazu eza, bat, zoxide und fzf. Farben nur über die 16 Terminalfarben: kitty setzt sie aus den
# Design-Tokens (Grün = Akzent, Rot = fehler, Gelb = warnung, Hellschwarz = gedaempft). So folgen
# auch ältere Ausgaben dem Wechsel zwischen hell und dunkel.

# 1Password-SSH-Agent, sobald 1Password ihn anbietet. Ein weitergeleiteter Agent (SSH-Sitzung) bleibt.
if test -S $HOME/.1password/agent.sock
    if not set -q SSH_CONNECTION; or not set -q SSH_AUTH_SOCK
        set -gx SSH_AUTH_SOCK $HOME/.1password/agent.sock
    end
end

status is-interactive; or return 0

# Funktionen aus system/fish/functions: nach den eigenen (~/.config/fish/functions), vor denen von fish
set -l functions_dir (path dirname -- (path resolve -- (status filename)))/functions
if not contains -- $functions_dir $fish_function_path
    set -l index (contains --index -- $__fish_config_dir/functions $fish_function_path)
    if test -n "$index"
        set -g fish_function_path $fish_function_path[1..$index] $functions_dir $fish_function_path[(math $index + 1)..]
    else
        set -g fish_function_path $functions_dir $fish_function_path
    end
end

set -g fish_greeting

# Syntaxfarben: Befehle im Akzent, Tippfehler rot, Kommentare und Vorschläge gedämpft
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

# Statuszeile und Trennlinie nach jedem ausgeführten Befehl
set -q _zenos_prompt_count; or set -g _zenos_prompt_count 0
function _zenos_on_postexec --on-event fish_postexec
    _zenos_after_command $status $CMD_DURATION $argv
end
# Neue Eingabezeile (nicht bei blossem Neuzeichnen): Git-Angaben neu bestimmen
function _zenos_on_prompt --on-event fish_prompt
    set -g _zenos_prompt_count (math $_zenos_prompt_count + 1)
end

# Enter: gefährliche Befehle erst nach Rückfrage. «repaint» zeigt vorher die ganze Befehlszeile.
bind enter repaint _zenos_enter
bind ctrl-j repaint _zenos_enter
bind -M insert enter repaint _zenos_enter
bind -M insert ctrl-j repaint _zenos_enter

# «?» erklärt Befehle, lokal und ohne Internet
function '?' --description 'Befehl erklären, lokal und ohne Internet'
    _zenos_explain $argv
end
complete -c '?' -x -a '(__fish_complete_subcommand)'

# eza statt ls (GNU-Optionen, die eza anders versteht, gehen weiter an ls)
if command -q eza
    function ls --wraps eza --description 'Dateien auflisten (eza)'
        _zenos_ls $argv
    end
    function ll --wraps eza --description 'Dateien mit Details auflisten (eza)'
        eza -l --group-directories-first --time-style=long-iso --git $argv
    end
    function la --wraps eza --description 'Alle Dateien auflisten, auch versteckte (eza)'
        eza -la --group-directories-first --time-style=long-iso $argv
    end
end

# bat heisst unter Ubuntu batcat; Farben aus der Terminalpalette
if not command -q bat; and command -q batcat
    function bat --wraps batcat --description 'Datei mit Syntaxfarben anzeigen (batcat)'
        batcat $argv
    end
end
set -q BAT_THEME; or set -gx BAT_THEME ansi

# zoxide: «z ordner» springt in einen oft besuchten Ordner
if command -q zoxide
    zoxide init fish | source
end

# fzf: Ctrl+R Verlauf, Ctrl+T Datei, Alt+C Ordner
if command -q fzf
    if not set -q FZF_DEFAULT_OPTS
        set -gx FZF_DEFAULT_OPTS "--height=40% --layout=reverse --info=inline-right --no-scrollbar --prompt='› ' --pointer='›' --marker='·' --color=fg:-1,bg:-1,hl:2,fg+:-1:bold,bg+:-1,hl+:2,gutter:-1,pointer:2,marker:2,prompt:2,info:8,spinner:8,header:8,border:8,query:-1"
    end
    fzf --fish | source
end
