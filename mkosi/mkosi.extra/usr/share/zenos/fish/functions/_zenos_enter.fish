function _zenos_enter --description 'Enter: gefährliche Befehle erst nach Rückfrage ausführen'
    # Gebunden an Enter (zenos.fish). Unvollständige Eingaben (offene Anführungszeichen, begin ohne
    # end) und Syntaxfehler behandelt fish wie gewohnt; alles andere prüft _zenos_danger.
    commandline --is-valid
    if test $status -ne 0
        commandline -f execute
        return
    end
    set -l reason (_zenos_danger (commandline | string collect))
    if test $status -ne 0
        commandline -f execute
        return
    end
    if _zenos_warn $reason
        commandline -f execute
    else
        # Befehl bleibt zum Ändern in der Eingabezeile
        commandline -f repaint
    end
end
