function _zenos_is_disk --description 'Wahr, wenn der Pfad ein Laufwerk (Blockgerät) ist, z. B. /dev/sda oder /dev/mmcblk0'
    string match -qr '^/dev/(sd[a-z]|hd[a-z]|vd[a-z]|xvd[a-z]|nvme[0-9]|mmcblk[0-9]|md[0-9]|dm-[0-9]|loop[0-9]|disk/|mapper/)' -- $argv[1]
end
