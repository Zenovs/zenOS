function fish_prompt --description 'Eingabezeile von zenOS'
    # Zeile 1: Ordner (Akzent) · «auf» · Branch · «N geändert», Zeile 2: ›
    # Beispiel: ~/code/projekt auf dev · 2 geändert
    set -l dim (set_color brblack)
    set -l reset (set_color normal)
    set -l line
    if set -q SSH_CONNECTION
        set -a line $dim(prompt_hostname)$reset' '
    end
    set -a line (set_color green)(_zenos_pwd)$reset

    set -l git (_zenos_git_info)
    if test -n "$git[1]"
        set -a line ' '$dim'auf'$reset' '(set_color yellow)$git[1]$reset
        if test -n "$git[2]"; and test "$git[2]" -gt 0
            set -a line ' '$dim'· '$git[2]' geändert'$reset
        end
    end

    printf '%s\n' (string join '' -- $line)
    if fish_is_root_user
        printf '%s›%s ' (set_color red) $reset
    else
        printf '%s›%s ' (set_color green) $reset
    end
end
