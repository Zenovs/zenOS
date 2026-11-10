function _zenos_align_right --description 'Setzt Text rechtsbündig in eine Zeile der Breite BREITE'
    # _zenos_align_right BREITE TEXT (Farbsequenzen zählen nicht mit)
    set -l gap (math "max(0, $argv[1] - "(string length --visible -- $argv[2])")")
    printf '%s%s\n' "$(string repeat -n $gap ' ')" $argv[2]
end
