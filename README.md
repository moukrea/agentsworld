# AgentsWorld

Un petit monde en voxels où tes sessions Claude Code et Codex vivent comme des habitants : elles travaillent, posent
leurs questions, attendent ta réponse, partent en pause. Tu te promènes en ville, tu leur parles (au clavier, à la
manette ou à la voix) et tu réponds à leurs questions sans ouvrir de terminal.

Ce dépôt sert les téléchargements et les workflows qui les construisent ; le code source est privé. AgentsWorld est
un aperçu sans garantie ni support : les issues et pull requests ne sont pas acceptées ici. Modèle de sécurité :
[SECURITY.md](SECURITY.md) ; conditions d'utilisation : [LICENSE](LICENSE) (PolyForm Noncommercial 1.0.0).

## Télécharger

Tout est sur la page [Releases](https://github.com/moukrea/agentsworld/releases/latest), avec `SHA256SUMS` pour
vérifier les fichiers (`sha256sum -c SHA256SUMS --ignore-missing`).

| Système | Fichier | Installation |
|---|---|---|
| Android 8 ou plus | `AgentsWorld_<version>_android.apk` | ouvrir l'APK sur le téléphone (autoriser l'installation d'applis inconnues pour le navigateur ou le gestionnaire de fichiers), ou `adb install -r` |
| Linux | `AgentsWorld_<version>_amd64.AppImage` | `chmod +x AgentsWorld_*.AppImage`, puis le lancer ; il se met à jour seul |
| Debian, Ubuntu | `AgentsWorld_<version>_amd64.deb` | `sudo apt install ./AgentsWorld_<version>_amd64.deb` |
| Fedora, openSUSE | `AgentsWorld-<version>-1.x86_64.rpm` | `sudo dnf install ./AgentsWorld-<version>-1.x86_64.rpm` |
| macOS | `AgentsWorld_<version>_aarch64.dmg` (Apple silicon), `_x64.dmg` (Intel) | glisser l'app dans Applications ; non signée : clic droit › Ouvrir la première fois |
| Windows | `AgentsWorld_<version>_x64-setup.exe` | installation pour l'utilisateur ; non signée : SmartScreen › Informations complémentaires › Exécuter quand même |

L'APK est signé par la clé AgentsWorld (certificat SHA-256
`fb19a3dc67e560428c412b1450c19b701d952ce0084d873fb1c0d8724d44e72b`) : une mise à jour s'installe par-dessus sans
perdre les appairages. Les mises à jour des applications de bureau sont signées et vérifiées avant installation.

## Héberger et rejoindre un monde

Le monde tourne sur un **hôte** : l'application de bureau en mode « Héberger ce monde sur cette machine », ou un
serveur AgentsWorld sans écran. Les autres appareils le **rejoignent** :

1. Sur l'hôte, Réglages › Appareil › « Appairer un appareil » affiche un QR code (valable 10 minutes, une seule fois).
2. Sur le téléphone, « Rejoindre un hôte » › « Scanner le QR code » ; sur un autre ordinateur, « Rejoindre un hôte »,
   puis coller le code ou importer l'image du QR code.

Ça marche sur le réseau local, en direct, et depuis n'importe où par le relais que l'hôte a configuré : son adresse
voyage dans le code. Le canal est chiffré de bout en bout ; le relais ne fait que passer des trames qu'il ne peut pas
lire.

Les sessions viennent de [Jaunt](https://github.com/moukrea/jaunt), qui donne accès à tes terminaux depuis tous tes
appareils : un hôte AgentsWorld relié à Jaunt voit les sessions Claude Code et Codex de toutes tes machines et peut y
répondre.
