function _zenos_ls --description 'ls über eza; GNU-Optionen, die eza anders versteht, gehen an ls'
    # eza und GNU ls teilen nur wenige Kurzoptionen (-1 -l -a -A -d -R -r -i -F -h). Alles andere
    # (z. B. -t, -S, -ltr) bedeutet in eza etwas anderes oder fehlt, dann antwortet das echte ls.
    for arg in $argv
        test "$arg" = --; and break
        if string match -qr '^-' -- $arg
            if not string match -qr '^-[1laAdRriFh]+$|^--(all|almost-all|recurse|reverse|long|oneline)$' -- $arg
                command ls --color=auto $argv
                return
            end
        end
    end
    eza --group-directories-first $argv
end
