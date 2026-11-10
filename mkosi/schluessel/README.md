# Schlüssel für Updates

Hier liegt nur der **öffentliche** Schlüssel, mit dem der Argon die Signatur jedes Updates prüft:
`zenos-updates.asc` (OpenPGP, ASCII). Der Bau schreibt ihn nach `/etc/systemd/import-pubring.gpg`; ohne ihn baut das
Image für den Argon nicht (`mkosi.finalize`).

Den geheimen Teil hat nur Zeno, auf seinem Schlüssel-Stick (später einem Hardware-Schlüssel). Er kommt nie in dieses
Repo, nie auf den Mac mit Claude Code und nie auf den Argon. Wie der Schlüssel entsteht und wie signiert wird:
`docs/signieren.md`.
