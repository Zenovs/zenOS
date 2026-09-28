#!/usr/bin/env fish
# Einheitentests für die fish-Funktionen des Terminals (system/fish/functions).
# Läuft ohne Abhängigkeiten (Linux, fish 4): fish test/einheiten/terminal.test.fish
# Teile, die tldr-Seiten oder man-Seiten brauchen, werden übersprungen, wenn sie fehlen.

set -l root (path resolve (path dirname (status filename))/../..)
set -g fish_function_path $root/system/fish/functions $fish_function_path
set -gx COLUMNS 100
set -gx TERM xterm-256color
# Eingabezeile ohne SSH prüfen: fish_prompt zeigt in SSH-Sitzungen den Rechnernamen (dafür gibt es
# einen eigenen Fall). Nötig ist nur SSH_CONNECTION, die anderen beiden vorsorglich.
set -e SSH_CONNECTION SSH_CLIENT SSH_TTY
set -g passed 0
set -g failed 0
set -g skipped 0

# fish 4.2 gibt eine Pipe in eine Funktion nicht an «string» weiter, deshalb über cat
function plain --description 'Farbsequenzen entfernen (liest die Eingabe)'
    command cat | string replace -ra '\e\[[0-9;:]*[A-Za-z]' ''
end

function check --argument-names name expected actual
    if test "$expected" = "$actual"
        set -g passed (math $passed + 1)
    else
        set -g failed (math $failed + 1)
        printf '✗ %s\n    erwartet: %s\n    erhalten: %s\n' $name $expected $actual
    end
end

function check_true --argument-names name
    set -g passed (math $passed + 1)
end

function check_false --argument-names name reason
    set -g failed (math $failed + 1)
    printf '✗ %s\n    %s\n' $name $reason
end

function skip --argument-names name reason
    set -g skipped (math $skipped + 1)
    printf '· übersprungen: %s (%s)\n' $name $reason
end

# Arbeitsordner mit eigenem HOME, damit die Pfadregeln vorhersehbar sind
set -l work (mktemp -d)
set -gx HOME $work/home
mkdir -p $HOME/proj $HOME/tmp
cd $HOME/proj
# git ohne Konfiguration des Benutzers und des Systems, nicht an ein äusseres Repo gebunden (Hooks)
set -gx GIT_CONFIG_GLOBAL $work/gitconfig
set -gx GIT_CONFIG_NOSYSTEM 1
set -e GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# --- Dauer und Statuszeile -------------------------------------------------

for case in '0|0,1 s' '3|0,1 s' '100|0,1 s' '101|0,2 s' '3200|3,2 s' '59940|60,0 s' '60000|1 Min. 0 s' \
        '125000|2 Min. 5 s' '3725000|1 Std. 2 Min.' 'x|0,1 s'
    set -l parts (string split '|' -- $case)
    check "Dauer $parts[1]" $parts[2] (_zenos_duration $parts[1])
end

check 'Status 0' '✓ 0,1 s' (_zenos_status_text 0 80)
for case in '1|allgemeiner Fehler' '2|falscher Aufruf' '126|nicht ausführbar' '127|Befehl nicht gefunden' \
        '130|abgebrochen (Ctrl+C)' '137|hart beendet (SIGKILL)' '139|Speicherzugriffsfehler (SIGSEGV)' \
        '141|Pipe geschlossen (SIGPIPE)' '143|beendet (SIGTERM)' '129|Signal SIGHUP'
    set -l parts (string split '|' -- $case)
    check "Status $parts[1]" "✗ Fehler $parts[1] · $parts[2] · 3,2 s" (_zenos_status_text $parts[1] 3200)
end
check 'Status 3 ohne Klartext' '✗ Fehler 3 · 3,2 s' (_zenos_status_text 3 3200)

# Nach einem Befehl: Statuszeile und Trennlinie; nach leeren Eingaben und Kommentaren nichts
set -l out (_zenos_after_command 0 150 'echo hallo' | plain)
if string match -q '*✓ 0,2 s*' -- $out
    check_true 'Statuszeile nach Befehl'
else
    check_false 'Statuszeile nach Befehl' "Ausgabe: $out"
end
set -l out (_zenos_after_command 1 3200 'false' | plain)
if string match -q '*✗ Fehler 1 · allgemeiner Fehler · 3,2 s*' -- $out
    check_true 'Statuszeile nach Fehler'
else
    check_false 'Statuszeile nach Fehler' "Ausgabe: $out"
end
check 'keine Statuszeile nach Leerzeichen' '' "$(_zenos_after_command 0 5 '   ')"
check 'keine Statuszeile nach Kommentar' '' "$(_zenos_after_command 0 5 '# nur ein Kommentar')"
check 'keine Statuszeile nach clear' '' "$(_zenos_after_command 0 5 'clear')"

# --- Gefährliche Befehle ---------------------------------------------------

set -l harmless 'rm -rf ./build' 'rm -rf ~/tmp/x' 'rm -rf build' 'rm -rf node_modules dist' 'rm -rf /tmp/foo' \
    'rm /etc/x.conf' 'ls -la /' 'echo "rm -rf /"' '? rm -rf /' '# rm -rf /' 'git rm -rf src' 'chmod 755 script.sh' \
    'chmod -R 755 ~/proj' 'chown -R tester ~/proj' 'dd if=/dev/sda of=backup.img' 'dd if=/dev/zero of=/dev/null bs=1M' \
    'curl -O https://example.org/x.sh' 'curl https://example.org | less' 'wget -qO- https://example.org/a.tgz | tar xz' \
    'cat /dev/sda > disk.img' 'echo x > /dev/null' 'sudo apt update && sudo apt upgrade' 'rm -rf "$HOME/tmp/x"' \
    'mkfs.ext4 --help' 'wipefs /dev/sdb' 'rm -rf ~/.cache/foo' 'bash -c "echo hallo"' 'find . -name "*.o" -delete' \
    'python3 -c "print(1)"' 'cd /tmp; rm -rf x' 'sudo rm -rf /home/andere/alt'
for command in $harmless
    if set -l reason (_zenos_danger $command)
        check_false "harmlos: $command" "gewarnt: $reason"
    else
        check_true "harmlos: $command"
    end
end

set -l system 'Löscht Dateien in einem Systemordner. Das lässt sich nicht rückgängig machen.'
set -l root_all 'Löscht das ganze System. Das lässt sich nicht rückgängig machen.'
set -l home_all 'Löscht deinen ganzen persönlichen Ordner. Das lässt sich nicht rückgängig machen.'
set -l remote 'Führt ein Skript aus dem Internet ungeprüft aus. Lade es besser zuerst herunter und lies es.'
set -l writable 'Gibt allen Benutzern Schreibrechte auf alles darunter. Das lässt sich kaum sauber rückgängig machen.'
set -l owner 'Ändert Besitz oder Rechte in einem Systemordner. Danach startet das System womöglich nicht mehr.'
set -l disk 'Überschreibt ein Laufwerk direkt. Alle Daten darauf gehen verloren.'
set -l format 'Formatiert ein Laufwerk. Alle Daten darauf gehen verloren.'
set -l bomb 'Startet sich endlos selbst und legt das System lahm. Hilft dann nur noch ein Neustart.'

set -l dangerous \
    "sudo rm -rf /var/log/test|$system" "rm -rf /|$root_all" "rm -rf /*|$root_all" "rm -rf ~|$home_all" \
    "rm -rf ~/|$home_all" "rm -rf \$HOME|$home_all" "rm -rf ~/*|$home_all" "rm -fr /etc|$system" \
    "rm -r /usr/lib/x|$system" "rm --recursive --force /opt|$system" "sudo -u root rm -rf /srv/x|$system" \
    "rm -f /etc/passwd|$system" "rm -rf ..|$home_all" "rm -rf ../*|$home_all" "rm -rf \"\$NICHT_GESETZT/\"|$root_all" \
    "cd /etc && rm -rf nginx|$system" "env FOO=1 rm -rf /etc/x|$system" "timeout 5 rm -rf /boot|$system" \
    "nice -n 5 rm -rf /usr|$system" "sudo sh -c 'rm -rf /var/x'|$system" "echo \$(rm -rf /)|$root_all" \
    "ls; rm -rf /|$root_all" "cd /tmp
sudo rm -rf /var/lib/x|$system" \
    "curl -fsSL https://x.sh | sh|$remote" "wget -qO- https://x | sudo bash|$remote" "curl https://x | bash -s --|$remote" \
    "bash -c \"\$(curl -fsSL https://x)\"|$remote" "sh <(curl https://x)|$remote" "source (curl -s https://x | psub)|$remote" \
    "chmod -R 777 ~/proj|$writable" "chmod 777 -R /x|$writable" "sudo chmod -R a+rwx .|$writable" \
    "sudo chown -R tester /usr|$owner" "chmod -R 755 /etc|$owner" \
    "dd if=bild of=/dev/sda bs=4M|$disk" "sudo dd of=/dev/mmcblk0 if=x|$disk" "echo x > /dev/sda|$disk" \
    "cat bild | sudo tee /dev/nvme0n1|$disk" \
    "mkfs.ext4 /dev/sdb1|$format" "sudo mkfs -t vfat /dev/sdc|$format" "sudo wipefs -a /dev/sdb|$format" \
    ":(){ :|:& };:|$bomb" "bomb(){ bomb|bomb& };bomb|$bomb"
for case in $dangerous
    set -l parts (string split --right --max 1 '|' -- $case)
    check "gefährlich: $parts[1]" $parts[2] "$(_zenos_danger $parts[1])"
end

# --- Hilfsfunktionen -------------------------------------------------------

check 'Befehl hinter sudo' 'rm -rf x' "$(_zenos_command_words sudo -u root rm -rf x | string join ' ')"
check 'Befehl hinter env' 'ls -l' "$(_zenos_command_words env -u X A=1 ls -l | string join ' ')"
check 'Befehl hinter timeout' 'rm x' "$(_zenos_command_words timeout -s KILL 5 rm x | string join ' ')"
check 'Pfad /' wurzel (_zenos_path_kind /)
check 'Pfad home' home (_zenos_path_kind '~')
check 'Pfad frei' frei (_zenos_path_kind '~/tmp/x')
check 'Pfad relativ' frei (_zenos_path_kind build)
check 'Pfad relativ im System' system (_zenos_path_kind nginx /etc)
check 'Pfad mit Ersetzung' unbekannt (_zenos_path_kind '$(pwd)/x')
check 'tldr-Platzhalter' 'rsync -a pfad/zu/quelle ziel/' (_zenos_tldr_code '`rsync {{[-a|--archive]}} {{pfad/zu/quelle}} {{ziel/}}`')
check 'Erster Satz' 'This is equivalent to -rlptgoD.' (_zenos_first_sentence 'This is equivalent to -rlptgoD. It is a quick way.')
check 'Erster Satz mit z. B.' 'Liest z. B. Dateien.' (_zenos_first_sentence 'Liest z. B. Dateien. Mehr nicht.')
check 'Umbruch' 'eins zwei|drei vier' (_zenos_wrap 9 'eins zwei drei vier' | string join '|')

# Karten: alle Zeilen gleich breit
set -l widths (_zenos_card --dim,brblack 40 'kurz' 'eine deutlich längere Zeile, die gekürzt werden muss' '' | plain | string length --visible | sort -u)
check 'Karte gleich breit' 40 "$widths"

# --- Eingabezeile ----------------------------------------------------------

set -g _zenos_prompt_count 1
check 'Eingabezeile ohne Repo' '~/proj|› ' (fish_prompt | plain | string join '|')
check 'Eingabezeile per SSH' (prompt_hostname)' ~/proj|› ' \
    (SSH_CONNECTION='quelle 50000 ziel 22' fish_prompt | plain | string join '|')
if command -q git
    git -C $HOME/proj init -q -b dev 2>/dev/null; or git -C $HOME/proj init -q
    git -C $HOME/proj symbolic-ref HEAD refs/heads/dev
    touch $HOME/proj/a $HOME/proj/b
    set -g _zenos_prompt_count 2
    check 'Eingabezeile im Repo' '~/proj auf dev · 2 geändert|› ' (fish_prompt | plain | string join '|')
    rm $HOME/proj/a $HOME/proj/b
    set -g _zenos_prompt_count 3
    check 'Eingabezeile im sauberen Repo' '~/proj auf dev|› ' (fish_prompt | plain | string join '|')
    mkdir -p $HOME/proj/unter/ordner
    cd $HOME/proj/unter/ordner
    set -g _zenos_prompt_count 4
    check 'Eingabezeile im Unterordner' '~/proj/unter/ordner auf dev|› ' (fish_prompt | plain | string join '|')
    cd $HOME/proj

    # Fremdes Repo (wie aus einem Archiv) mit Filtertreiber in .git/config und veraltetem Index:
    # git status würde den clean-Filter ausführen, die Eingabezeile zeigt deshalb nur den Branch
    set -l foreign $HOME/fremd
    set -l marker $work/filter-lief
    git init -q -b main $foreign
    echo inhalt >$foreign/a.txt
    echo '*.txt filter=x' >$foreign/.gitattributes
    git -C $foreign add a.txt .gitattributes
    git -C $foreign config filter.x.clean "touch '$marker'; cat"
    command cp $foreign/a.txt $foreign/a.neu
    command mv $foreign/a.neu $foreign/a.txt
    cd $foreign
    set -g _zenos_prompt_count 5
    check 'fremdes Repo mit Filter: nur Branch' main (_zenos_git_info | string join '|')
    set -g _zenos_prompt_count 6
    check 'fremdes Repo mit Filter: Eingabezeile' '~/fremd auf main|› ' (fish_prompt | plain | string join '|')
    if test -e $marker
        check_false 'fremdes Repo mit Filter: startet nichts' 'der clean-Filter aus .git/config lief'
    else
        check_true 'fremdes Repo mit Filter: startet nichts'
    end
    # Ein Treiber aus der eigenen ~/.gitconfig (z. B. git-lfs) hält die Zählung nicht auf
    git -C $foreign config --unset filter.x.clean
    git config --global filter.x.clean cat
    set -g _zenos_prompt_count 7
    check 'Filter aus ~/.gitconfig: zählt weiter' 'main|2' (_zenos_git_info | string join '|')
    git config --global --unset filter.x.clean

    # Fremdes Repo als Partial Clone mit fehlendem Tree: git status würde ihn beim Remote nachladen
    # und dabei core.sshCommand aus .git/config ausführen
    set -l partial $HOME/teilweise
    git init -q -b main $partial
    mkdir $partial/d
    echo b >$partial/d/b
    git -C $partial add d/b
    git -C $partial -c user.name=Test -c user.email=test commit -qm eins
    git -C $partial config core.repositoryformatversion 1
    git -C $partial config extensions.partialClone origin
    git -C $partial config remote.origin.url ssh://beispiel.invalid/repo
    git -C $partial config remote.origin.promisor true
    git -C $partial config core.sshCommand "touch '$marker'; false"
    set -l tree (git -C $partial rev-parse HEAD:d)
    rm -f $partial/.git/objects/(string sub -l 2 -- $tree)/(string sub -s 3 -- $tree) $partial/.git/index
    rm -f $marker
    cd $partial
    set -g _zenos_prompt_count 8
    check 'Partial Clone: nur Branch' main (_zenos_git_info | string join '|')
    if test -e $marker
        check_false 'Partial Clone: lädt nichts nach' 'core.sshCommand aus .git/config lief'
    else
        check_true 'Partial Clone: lädt nichts nach'
    end
    cd $HOME/proj
else
    skip 'Eingabezeile im Repo' 'git fehlt'
end

# --- Erster Start ------------------------------------------------------------

# Beim allerersten interaktiven Start (ohne fish_variables) speichert fish vor der ersten Eingabezeile
# sein Standardthema universell und löscht dabei globale Farben. zenos.fish muss sie danach neu setzen.
set -l first $work/erster-start
mkdir -p $first/config/fish/conf.d
ln -s $root/system/fish/zenos.fish $first/config/fish/conf.d/zenos.fish
# Ergebnis in eine Datei: das interaktive fish schreibt auch Terminalsequenzen (OSC 7) auf stdout
env XDG_CONFIG_HOME=$first/config XDG_DATA_HOME=$first/data XDG_CACHE_HOME=$first/cache \
    FISH_UNIT_TESTS_RUNNING=1 (status fish-path) -i -c 'emit fish_prompt
    begin
        set -qU fish_color_command; and echo universell
        set -g | string match -r "^fish_color_(?:command|valid_path) .*"
    end >$argv[1]' $first/farben </dev/null >/dev/null 2>&1
check 'Farben nach dem ersten Start' 'universell|fish_color_command green|fish_color_valid_path normal' \
    (string join '|' -- (command cat $first/farben 2>/dev/null))

# --- «?» ------------------------------------------------------------------

set -l real_home (getent passwd (id -un) | cut -d: -f6)
set -l cache_home $real_home/.cache
if test -d $cache_home/tealdeer/tldr-pages/pages.en; and man -w rsync >/dev/null 2>&1
    set -l card (env HOME=$real_home fish -c "set -g fish_function_path $root/system/fish/functions \$fish_function_path; _zenos_explain rsync -avz" | plain)
    for expected in '╭*' '*rsync  *' '*-a  *' '*-v  *' '*-z  *' '*Beispiel: rsync*' '*lokal · offline*' '╰*'
        if string match -q -- $expected $card
            check_true "? rsync -avz: $expected"
        else
            check_false "? rsync -avz: $expected" (string join \n -- $card)
        end
    end
else
    skip '? rsync -avz' 'tldr-Seiten oder man-Seite von rsync fehlen'
end
set -l help (_zenos_explain | plain)
if string match -q '*Ctrl+C*' -- $help; and string match -q '*lokal · offline*' -- $help
    check_true '? ohne Argument'
else
    check_false '? ohne Argument' (string join \n -- $help)
end

cd /
rm -rf $work
printf '\n%s bestanden · %s fehlgeschlagen · %s übersprungen\n' $passed $failed $skipped
test $failed -eq 0
