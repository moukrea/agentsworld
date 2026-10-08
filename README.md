# AgentsWorld

Un petit monde en voxels où tes sessions Claude Code et Codex vivent comme des habitants : elles travaillent, posent
leurs questions, attendent ta réponse, partent en pause. Tu te promènes en ville, tu leur parles (au clavier, à la
manette ou à la voix) et tu réponds à leurs questions sans ouvrir de terminal.

Ce dépôt sert les téléchargements et les workflows qui les construisent ; le code source est privé. AgentsWorld est
un aperçu sans garantie ni support : les issues et pull requests ne sont pas acceptées ici. Modèle de sécurité :
[SECURITY.md](SECURITY.md) ; conditions d'utilisation : [LICENSE](LICENSE) (PolyForm Noncommercial 1.0.0).

## Installer

Une ligne, dans un terminal (Linux, macOS, WSL) :

```sh
curl -fsSL https://moukrea.github.io/agentsworld/install.sh | bash
```

Sous Windows 10 ou 11, dans PowerShell :

```powershell
irm https://moukrea.github.io/agentsworld/install.ps1 | iex
```

Dans un terminal, l'installateur demande quoi installer (et recommande selon la machine) ; sinon il installe
l'application. Tout va dans ton dossier personnel, **sans droits administrateur**. Chaque fichier vient d'une
[release](https://github.com/moukrea/agentsworld/releases/latest) de ce dépôt et est vérifié avec son `SHA256SUMS` avant
de remplacer quoi que ce soit. Relancer la même ligne met à jour ce qui est installé, sans rien perdre.

| Rôle | Linux, macOS, WSL | Windows (PowerShell) | Ce que ça installe |
|---|---|---|---|
| **Application** (défaut) | `… \| bash` | `irm … \| iex` | l'application de bureau ; au premier lancement, tu choisis d'**héberger** le monde sur cette machine ou de **rejoindre** un hôte |
| **Client seulement** | `… \| bash -s -- --client-only` | `… -ClientOnly` | l'application en mode « Rejoindre un hôte » uniquement, sans hôte sur cette machine |
| **Hôte sans écran** | `… \| bash -s -- --host` | `… -Host` | le monde en service utilisateur (systemd, launchd, tâche planifiée), pour une machine toujours allumée, sans application |
| **Agent** | `… \| bash -s -- --agent --hub http://hote:4317 --token …` | `… -Agent -Hub … -Token …` | un petit service qui envoie les sessions de cette machine à un hôte qui n'a pas Jaunt |

Sous Windows, les options passent par `& ([scriptblock]::Create((irm https://moukrea.github.io/agentsworld/install.ps1))) -ClientOnly`.

**Avec [Jaunt](https://github.com/moukrea/jaunt)**, **un seul hôte** suffit : installé sur une de tes machines
reliées à Jaunt, il voit les sessions Claude Code et Codex de **toutes** tes machines liées. Les autres machines n'ont
besoin que du client (`--client-only`), ou de rien ; l'application Android est un client pur. **Sans Jaunt**, chaque
machine dont tu veux voir les sessions a besoin du rôle agent (sauf l'hôte lui-même) : sur l'hôte,
`agentsworld agent-token create <nom>` donne la commande exacte à lancer sur l'autre machine.

Options : `--port N` et `--link-port N` (ports de l'hôte, 4317 et 4318 par défaut), `--relay wss://…` (relais pour
joindre l'hôte hors du réseau local ; aucun par défaut), `--bind 127.0.0.1|0.0.0.0` (avec Jaunt, l'hôte n'écoute que
sur cette machine ; sans Jaunt, sur le réseau, pour les agents), `--format deb|rpm` (Linux : paquet système au lieu de
l'AppImage, demande `sudo`), `--version vX.Y.Z`, `--no-service`, `--yes` (aucune question). `bash -s -- --help` les
liste toutes.

### Après l'installation

- **Application** : ouvre AgentsWorld depuis le menu des applications. Pour rejoindre un hôte, « Rejoindre un hôte »,
  puis colle son code d'appairage ou importe l'image de son QR code.
- **Hôte sans écran** : l'installateur affiche un **QR code d'appairage** (et le code `aw1.…`) ; scanne-le avec
  l'application Android, ou colle le code dans l'application de bureau. Avec Jaunt, relie l'hôte à Jaunt :
  `agentsworld jaunt-enroll` (une demande apparaît sur ton téléphone appairé à Jaunt : accepte-la).

La commande `agentsworld` (dans `~/.local/bin`, ou `%LOCALAPPDATA%\agentsworld-cli\bin` sous Windows) gère le reste :

```sh
agentsworld status                 # ce qui est installé et en marche
agentsworld pair                   # nouveau code d'appairage + QR code (hôte ; 10 minutes, un seul appareil)
agentsworld jaunt-enroll           # relier l'hôte à Jaunt
agentsworld agent-token create Laptop   # jeton et commande d'installation d'un agent
agentsworld logs [host|agent|app] [-f]
agentsworld start | stop | restart
agentsworld update                 # met à jour ce qui est installé
agentsworld role                   # rôles installés ; role add <rôle> ; role remove <rôle>
agentsworld uninstall [--purge]    # désinstalle (--purge : aussi le monde et les appairages)
```

`--client-only` ne désinstalle jamais un hôte déjà là ; `agentsworld role remove host` le fait.

### Mises à jour automatiques

Tout se met à jour seul, comme Jaunt. L'**hôte sans écran** et l'**agent** regardent toutes les 15 minutes la version
publiée ; une nouvelle version s'installe d'elle-même (jamais pendant un enregistrement vocal ni pendant l'envoi d'une
réponse), vérifiée avec `SHA256SUMS`, puis le service redémarre en sauvegardant le monde. Si la nouvelle version ne
répond pas, l'ancienne reprend aussitôt et l'échec s'affiche dans le panneau Sources et dans `agentsworld status`.
L'**application de bureau** propose « Mettre à jour maintenant » ou « Ignorer » au lancement puis régulièrement (une
installation `.deb`/`.rpm` indique la commande à lancer) ; l'**application Android** aussi, au plus toutes les 6 heures,
puis passe par l'installateur d'Android. Une page du jeu ouverte sur un hôte mis à jour propose de se recharger.
`agentsworld update --auto off` coupe les mises à jour automatiques de l'hôte et de l'agent.

## Télécharger à la main

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
| Hôte sans écran | `agentsworld-host_<version>_<système>.tar.gz` (`.zip` sous Windows) | Node et le serveur, prêts à lancer ; l'installateur s'en charge |

L'APK est signé par la clé AgentsWorld (certificat SHA-256
`fb19a3dc67e560428c412b1450c19b701d952ce0084d873fb1c0d8724d44e72b`) : une mise à jour s'installe par-dessus sans
perdre les appairages. Les mises à jour des applications de bureau sont signées et vérifiées avant installation. Les
installateurs eux-mêmes sont publiés avec leur `SHA256SUMS` sur https://moukrea.github.io/agentsworld/SHA256SUMS.

## Héberger et rejoindre un monde

Le monde tourne sur un **hôte** : l'application de bureau en mode « Héberger ce monde sur cette machine », ou un
serveur AgentsWorld sans écran. Les autres appareils le **rejoignent** :

1. Sur l'hôte, Réglages › Appareil › « Appairer un appareil » affiche un QR code (valable 10 minutes, une seule fois) ;
   sur un hôte sans écran, `agentsworld pair` l'affiche dans le terminal.
2. Sur le téléphone, « Rejoindre un hôte » › « Scanner le QR code » ; sur un autre ordinateur, « Rejoindre un hôte »,
   puis coller le code ou importer l'image du QR code.

Ça marche sur le réseau local, en direct, et depuis n'importe où par le relais que l'hôte a configuré : son adresse
voyage dans le code. Le canal est chiffré de bout en bout ; le relais ne fait que passer des trames qu'il ne peut pas
lire.

Les sessions viennent de [Jaunt](https://github.com/moukrea/jaunt), qui donne accès à tes terminaux depuis tous tes
appareils : un hôte AgentsWorld relié à Jaunt voit les sessions Claude Code et Codex de toutes tes machines et peut y
répondre.
