function _zenos_git_info --description 'Branch und Anzahl geänderter Dateien für die Eingabezeile'
    # Ausgabe: Zeile 1 Branch (oder kurzer Commit), Zeile 2 Anzahl geänderter Dateien (leer, wenn
    # unbekannt). Ausserhalb eines Repos nichts. Git läuft nur im Repo und höchstens 0,5 s; das
    # Ergebnis gilt bis zur nächsten Eingabezeile oder einem Ordnerwechsel (Neuzeichnen kostet nichts).
    set -l key "$PWD|$_zenos_prompt_count"
    if test "$key" = "$_zenos_git_key"
        printf '%s\n' $_zenos_git_value
        return 0
    end
    set -g _zenos_git_key $key
    set -g _zenos_git_value

    # .git suchen, ohne einen Prozess zu starten
    set -l root $PWD
    while not test -e $root/.git
        if test "$root" = /
            return 0
        end
        set root (path dirname -- $root)
    end

    # Branch direkt aus HEAD lesen (auch bei Worktrees, wo .git eine Datei ist)
    set -l git_dir $root/.git
    if test -f $git_dir
        read -l pointer <$git_dir
        set git_dir (string replace -r '^gitdir: ' '' -- $pointer)
        string match -q -- '/*' $git_dir; or set git_dir $root/$git_dir
    end
    test -r $git_dir/HEAD; or return 0
    read -l head <$git_dir/HEAD
    set -l branch
    if string match -qr '^ref: refs/heads/' -- $head
        set branch (string replace -r '^ref: refs/heads/' '' -- $head)
    else if string match -qr '^ref: ' -- $head
        set branch (string replace -r '^ref: ' '' -- $head)
    else
        set branch (string sub --length 7 -- $head)
    end

    # Anzahl geänderter Dateien (inkl. neuer). core.fsmonitor aus: ein fremdes Repo darf beim
    # Anzeigen der Eingabezeile keine Programme starten.
    set -l changed
    if command -q git; and command -q timeout
        set -l out (command timeout 0.5 git --no-optional-locks -c core.fsmonitor=false -C $root \
            status --porcelain --ignore-submodules=dirty 2>/dev/null)
        and set changed (count $out)
    end

    set -g _zenos_git_value $branch $changed
    printf '%s\n' $_zenos_git_value
end
