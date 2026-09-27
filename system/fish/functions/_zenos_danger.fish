function _zenos_danger --description 'Prüft eine Befehlszeile auf gefährliche Befehle'
    # _zenos_danger BEFEHLSZEILE
    # Ist etwas gefährlich, gibt die Funktion den Warntext aus (eine Zeile) und endet mit 0, sonst mit 1.
    # Geprüft wird jeder Befehl der Zeile (auch nach ;, &&, |, in mehrzeilig eingefügtem Text und in
    # Befehlsersetzungen), nicht aber Kommentare und «?»-Erklärungen. Nichts wird ausgeführt.
    #
    # Gefährlich ist (Muster → Warntext unten):
    #   Fork-Bomb                   :(){ :|:& };:                                   fork-bomb
    #   rm -r / -f auf /            rm -rf /   rm -rf /*                            delete-root
    #   rm -r / -f auf ~            rm -rf ~   rm -rf $HOME   rm -rf ~/*            delete-home
    #   rm -r / -f im System        sudo rm -rf /var/log/test   rm -f /etc/x        delete-system
    #   Skript aus dem Internet     curl … | sh   wget -qO- … | sudo bash           remote-script
    #                               bash -c "$(curl …)"   sh <(curl …)
    #   chmod -R 777 (überall)      chmod -R 777 x   chmod -R a+rwx x               world-writable
    #   chown/chmod/chgrp -R        sudo chown -R benutzer /usr                     permissions-system
    #     auf / oder im System
    #   dd auf ein Laufwerk         dd if=bild of=/dev/sda                          disk-write
    #   Umleitung auf ein Laufwerk  echo x > /dev/sda   … | sudo tee /dev/nvme0n1   disk-write
    #   Formatieren                 mkfs, mkfs.ext4, mke2fs, wipefs -a              format
    # Harmlos bleibt zum Beispiel rm -rf ./build oder rm -rf ~/tmp/x (siehe _zenos_path_kind).
    set -l text (string join \n -- $argv)
    string match -qr '\S' -- $text; or return 1

    set -l key
    # Fork-Bomb auf dem Rohtext (der Tokenizer zerlegt sie)
    if string match -qr -- '([^\s(){};|&]+)\s*\(\)\s*\{\s*\1\s*\|\s*\1\s*&\s*;?\s*\}\s*;?\s*\1' $text
        set key fork-bomb
    else
        set key (_zenos_danger_scan $text)
    end
    test -n "$key"; or return 1

    switch $key
        case fork-bomb
            echo 'Startet sich endlos selbst und legt das System lahm. Hilft dann nur noch ein Neustart.'
        case delete-root
            echo 'Löscht das ganze System. Das lässt sich nicht rückgängig machen.'
        case delete-home
            echo 'Löscht deinen ganzen persönlichen Ordner. Das lässt sich nicht rückgängig machen.'
        case delete-system
            echo 'Löscht Dateien in einem Systemordner. Das lässt sich nicht rückgängig machen.'
        case remote-script
            echo 'Führt ein Skript aus dem Internet ungeprüft aus. Lade es besser zuerst herunter und lies es.'
        case world-writable
            echo 'Gibt allen Benutzern Schreibrechte auf alles darunter. Das lässt sich kaum sauber rückgängig machen.'
        case permissions-system
            echo 'Ändert Besitz oder Rechte in einem Systemordner. Danach startet das System womöglich nicht mehr.'
        case disk-write
            echo 'Überschreibt ein Laufwerk direkt. Alle Daten darauf gehen verloren.'
        case format
            echo 'Formatiert ein Laufwerk. Alle Daten darauf gehen verloren.'
        case '*'
            echo 'Dieser Befehl kann Daten zerstören.'
    end
    return 0
end
