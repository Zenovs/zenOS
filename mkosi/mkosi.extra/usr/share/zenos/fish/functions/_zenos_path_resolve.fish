function _zenos_path_resolve --description 'Pfad aus einer Befehlszeile auflösen, ohne etwas auszuführen'
    # _zenos_path_resolve PFAD [ORDNER] → absoluter, normalisierter Pfad (ORDNER statt $PWD für
    # relative Pfade). ~, ~benutzer und einfache $VARIABLEN werden aufgelöst; enthält der Pfad eine
    # Befehlsersetzung, ist er unbekannt (Status 1). Symlinks werden nicht verfolgt.
    set -l __zpr_path $argv[1]
    set -l __zpr_base $argv[2]
    test -n "$__zpr_base"; or set __zpr_base $PWD
    if string match -q -- '*(*' $__zpr_path
        return 1
    end

    # ~ und ~benutzer
    if string match -qr '^~(/|$)' -- $__zpr_path
        set __zpr_path $HOME(string sub --start 2 -- $__zpr_path)
    else if set -l __zpr_user (string match -r '^~([A-Za-z_][A-Za-z0-9_.-]*)(/.*)?$' -- $__zpr_path)
        if test "$__zpr_user[2]" = root
            set __zpr_path /root$__zpr_user[3]
        else
            set __zpr_path /home/$__zpr_user[2]$__zpr_user[3]
        end
    end

    # $NAME und ${NAME}: Wert der Variable, leer, wenn sie fehlt (wie in der Shell)
    set -l __zpr_rounds 0
    while set -l __zpr_var (string match -r '\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?' -- $__zpr_path)
        set __zpr_rounds (math $__zpr_rounds + 1)
        test $__zpr_rounds -le 10; or return 1
        set -l __zpr_value
        if set -q $__zpr_var[2]
            set __zpr_value (string join ' ' -- $$__zpr_var[2])
        end
        set __zpr_path (string replace -- $__zpr_var[1] "$__zpr_value" $__zpr_path)
    end

    string match -q -- '/*' $__zpr_path; or set __zpr_path $__zpr_base/$__zpr_path

    set -l __zpr_parts
    for __zpr_part in (string split --no-empty / -- $__zpr_path)
        switch $__zpr_part
            case .
            case ..
                set -q __zpr_parts[1]; and set -e __zpr_parts[-1]
            case '*'
                set -a __zpr_parts $__zpr_part
        end
    end
    echo /(string join / -- $__zpr_parts)
end
