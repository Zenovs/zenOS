function _zenos_path_kind --description 'Ordnet einen Pfad ein: wurzel, home, system, frei oder unbekannt'
    # _zenos_path_kind PFAD [ORDNER]
    #   wurzel     /
    #   home       der persönliche Ordner selbst (~, $HOME, /home/<name>)
    #   system     alles andere ausserhalb der freien Bereiche, z. B. /etc, /var/log/test, /usr/lib/x
    #   frei       darunter: ~/…, /home/<name>/…, /tmp/…, /var/tmp/…, /dev/shm/…, /mnt/…, /media/…, /run/media/…
    #   unbekannt  Pfad mit Befehlsersetzung
    # Ein Platzhalter (*, ?, [, {) zählt wie der Ordner davor: ~/* ist so gefährlich wie ~.
    set -l path (_zenos_path_resolve $argv[1] $argv[2])
    or begin
        echo unbekannt
        return 0
    end

    set -l parts (string split --no-empty / -- $path)
    set -l index 1
    for part in $parts
        if string match -qr '[*?\[{]' -- $part
            if test $index -eq 1
                set parts
            else
                set parts $parts[1..(math $index - 1)]
            end
            break
        end
        set index (math $index + 1)
    end

    set -l n (count $parts)
    if test $n -eq 0
        echo wurzel
        return 0
    end

    set -l home (string split --no-empty / -- $HOME)
    set -l h (count $home)
    if test $h -gt 0; and test $n -ge $h; and test "$parts[1..$h]" = "$home"
        if test $n -eq $h
            echo home
        else
            echo frei
        end
        return 0
    end
    if test "$parts[1]" = home; and test $n -ge 2
        if test $n -eq 2
            echo home
        else
            echo frei
        end
        return 0
    end

    for root in tmp var/tmp dev/shm mnt media run/media
        set -l r (string split / -- $root)
        set -l k (count $r)
        if test $n -gt $k; and test "$parts[1..$k]" = "$r"
            echo frei
            return 0
        end
    end
    echo system
end
