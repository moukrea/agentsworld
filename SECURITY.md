# Sécurité — aperçu non audité

AgentsWorld montre tes sessions Claude Code et Codex et permet d'y **répondre** : un appareil qui a le droit
« répondre » écrit dans ces sessions, donc agit avec les droits de l'agent sur sa machine. N'accorde ce droit qu'à tes
propres appareils, et retire un appareil perdu (Réglages › Appareil › Appareils reliés › Retirer).

## Ce qui est protégé

- **Canal AgentsWorld Link** entre un appareil et son hôte : chaque installation a une identité P-256 à long terme ;
  la poignée de main (modèle Noise IK, ECDH P-256 statiques et éphémères, HKDF-SHA256) authentifie les deux côtés,
  le secret du code d'appairage en plus au premier contact ; chaque trame est chiffrée en AES-256-GCM. Les primitives
  viennent de WebCrypto ; leur composition en protocole est récente et **n'a pas été auditée**.
- **Appairage** : un code `aw1.` (affiché en QR code) porte l'identité publique de l'hôte, ses adresses (réseau local,
  relais) et un secret à usage unique, valable 10 minutes ; l'hôte brûle la session après 5 échecs. Les droits
  accordés (`observe`, `answer`, `admin`) sont décidés par l'hôte, jamais par le code. Une révocation ferme aussitôt
  les canaux de l'appareil.
- **Relais** : il ne voit que des trames chiffrées, les identifiants d'hôte, les adresses réseau, la taille et le
  rythme du trafic. Un hôte ne peut s'y inscrire que pour l'identifiant de sa propre clé (défi signé). Le relais ne
  détient aucun secret d'appairage ni clé d'appareil.
- **Réseau local** : l'application Android n'ouvre de `ws://` en clair que vers des adresses privées ; les relais sont
  en `wss://`. Le contenu reste chiffré de bout en bout dans les deux cas.
- **Mises à jour** : l'application de bureau n'installe qu'une mise à jour signée par la clé AgentsWorld (clé publique
  intégrée à l'application, manifeste `latest.json` de la dernière release publiée). L'APK est signé par la clé
  AgentsWorld, certificat SHA-256 `fb19a3dc67e560428c412b1450c19b701d952ce0084d873fb1c0d8724d44e72b` ; Android refuse
  une mise à jour signée par une autre clé. Chaque release publie `SHA256SUMS`.
- **Installateurs** (`install.sh`, `install.ps1`, servis par GitHub Pages depuis ce dépôt) : ils ne téléchargent qu'en
  HTTPS depuis les releases de ce dépôt et vérifient chaque fichier avec le `SHA256SUMS` de la release avant de
  remplacer quoi que ce soit ; tout s'installe dans ton dossier personnel, sans droits administrateur (sauf
  `--format deb|rpm`, qui passe par le gestionnaire de paquets). Le Node de l'hôte sans écran est le binaire officiel
  de nodejs.org, vérifié avec son `SHASUMS256.txt` au moment de la construction. La page publie aussi le `SHA256SUMS`
  des deux scripts. `curl … | bash` fait confiance à cette page et à GitHub : lis le script avant si tu préfères.
- **Mises à jour automatiques** de l'hôte sans écran et de l'agent : la page désigne la version, l'archive est vérifiée
  avec le `SHA256SUMS` de sa release, et si la nouvelle version ne répond pas l'ancienne reprend. L'application Android
  vérifie aussi le certificat de signature de l'APK avant de le passer à l'installateur d'Android ; l'application de
  bureau, la signature de sa mise à jour. Quiconque peut publier une release ou la page de ce dépôt peut donc mettre à
  jour les hôtes et les agents installés : c'est le même pouvoir que sur ce qu'installent les commandes en une ligne.

## Ce qui n'est pas protégé

- Un appareil, un navigateur ou un compte système compromis reste compromis ; un appareil appairé avec le droit
  « répondre » peut écrire dans les sessions.
- Quiconque contrôle ce dépôt, le dépôt source privé ou les clés de signature peut publier une version malveillante :
  le chiffrement de bout en bout ne protège pas contre un client modifié.
- Les applications macOS et Windows ne sont pas signées par un éditeur reconnu : vérifie le fichier téléchargé avec
  `SHA256SUMS` avant la première installation.
- Un QR code d'appairage complet donne accès à l'hôte pendant 10 minutes : ne le mets jamais dans une issue, une
  capture d'écran publique ou un journal.
- Sur l'hôte, les clés et la liste des appareils sont des fichiers 0600 de son dossier de données ; sur Android, les
  clés de l'appareil sont des `CryptoKey` non exportables du WebView. Désinstaller l'application oublie ses appairages.
- Le relais est un service partagé : il n'est pas un système anti-abus complet et peut être indisponible.
- L'hôte sans écran (`--host`) sert le jeu en HTTP sur le port 4317 : sur la machine même, tout processus local en
  est propriétaire (c'est ainsi que `agentsworld pair` crée un code). Installé avec Jaunt, il n'écoute que sur
  127.0.0.1. Sans Jaunt, il écoute sur toutes les interfaces pour que les agents s'y connectent (avec leur jeton) :
  quelqu'un sur ton réseau peut alors **regarder** le monde (sessions, projets, questions) sans pouvoir y répondre.
  Sur un réseau qui n'est pas le tien, filtre ce port ou choisis `--bind 127.0.0.1`. Les appareils, eux, passent
  toujours par AgentsWorld Link (port 4318, appairés et chiffrés).

## Signaler une vulnérabilité

Utilise le signalement privé de vulnérabilité de ce dépôt (onglet Security › Report a vulnerability). Ne publie jamais
de code d'appairage, de clé, de fichier `link-identity.json` ou `link-peers.json`, ni de journal contenant des
sessions.
