#!/usr/bin/env bash
# AgentsWorld installer for Linux, macOS and WSL. Read it before piping it into bash.
#
#   curl -fsSL https://moukrea.github.io/agentsworld/install.sh | bash                      the app (asks when it can)
#   curl -fsSL https://moukrea.github.io/agentsworld/install.sh | bash -s -- --client-only   the app, join mode only
#   curl -fsSL https://moukrea.github.io/agentsworld/install.sh | bash -s -- --host          headless host (service)
#   curl -fsSL https://moukrea.github.io/agentsworld/install.sh | bash -s -- --agent --hub URL --token TOKEN
#
# Everything goes into the user's home: no root, except for --format deb|rpm (the system package manager). Every
# download comes from a release of github.com/moukrea/agentsworld and is checked against that release's SHA256SUMS
# before anything is replaced. Running it again upgrades in place what is installed (the roles in install.env);
# `agentsworld update` does exactly that. `agentsworld uninstall` removes it. Options: --help.
# French text uses typographic apostrophes; the Node snippets are single-quoted on purpose.
# shellcheck disable=SC1112,SC2016
set -Eeuo pipefail
umask 077

STAGE='initialisation'
# shellcheck disable=SC2154
trap 'rc=$?; printf "\nagentsworld: échec pendant « %s » (ligne %s, code %s). Voir l’erreur ci-dessus ; rien de ce qui marchait n’a été remplacé.\n" "$STAGE" "$LINENO" "$rc" >&2; ustatus error "échec pendant : $STAGE"; exit "$rc"' ERR
# The update status the host reports (server/self-update.mjs): only written once the roles are known (TRACK=1).
TRACK=0
ustatus() {
  [[ "$TRACK" == 1 ]] || return 0
  local msg="${2//\\/\\\\}" failed='' file="$PREFIX/update-status.json" version="${3:-$CURRENT_VERSION}"
  msg="${msg//\"/\\\"}"
  if [[ "$1" == error ]]; then failed=",\"failed\":{\"tag\":\"${TAG:-}\",\"at\":$(date +%s),\"reason\":\"$msg\"}"; fi
  if printf '{"state":"%s","target":"%s","version":"%s","at":%s,"message":"%s"%s}\n' \
    "$1" "${TAG:-}" "$version" "$(date +%s)" "$msg" "$failed" > "$file.new" 2>/dev/null; then
    mv -f "$file.new" "$file" 2>/dev/null || true
  fi
}
say() { printf '\n  AgentsWorld · %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
fail() { trap - ERR; printf '\nagentsworld: %s\n' "$*" >&2; ustatus error "$*"; exit 1; }

usage() {
  cat <<'USAGE'
Installe AgentsWorld (https://github.com/moukrea/agentsworld).

Rôles (un seul par appel ; sans rôle : ceux déjà installés, sinon la question, sinon --app) :
  --app                 l'application de bureau ; au premier lancement, héberger le monde ici ou rejoindre un hôte
  --client-only         l'application en mode « Rejoindre un hôte » seulement, sans hôte sur cette machine
  --host                l'hôte sans écran : le monde tourne en service utilisateur (systemd, launchd)
  --agent               l'agent : envoie les sessions de cette machine à un hôte qui n'a pas Jaunt
     --hub URL          adresse de l'hôte (http://machine:4317), --token JETON (« agentsworld agent-token create » sur l'hôte)
     --name NOM         nom de cette machine dans le monde

Options :
  --port N              port HTTP de l'hôte (4317 par défaut)
  --link-port N         port AgentsWorld Link de l'hôte, pour les appareils (4318 par défaut)
  --relay wss://…       relais Link de l'hôte (aucun par défaut : réseau local seulement)
  --bind ADRESSE        adresse d'écoute HTTP de l'hôte : 127.0.0.1 (défaut avec Jaunt : le monde reste sur cette
                        machine, les appareils passent par Link) ou 0.0.0.0 (défaut sans Jaunt : les agents s'y connectent)
  --format F            Linux, application : appimage (défaut, sans root), deb ou rpm (sudo)
  --version vX.Y.Z      une version précise au lieu de la dernière
  --no-service          démarre l'hôte ou l'agent en arrière-plan au lieu d'un service
  --no-pair             n'affiche pas de code d'appairage à la fin
  -y, --yes             ne pose aucune question
  --only-services       met à jour seulement l'hôte et l'agent installés (mise à jour automatique)
USAGE
}

# --- Arguments ------------------------------------------------------------------------------------------------
ROLE='' HUB='' TOKEN='' AGENT_NAME='' PORT='' LINK_PORT='' RELAY='' BIND='' FORMAT='' WANT_VERSION='' YES=0 ONLY_SERVICES=0
NO_SERVICE="${AGENTSWORLD_NO_SERVICE:-0}" NO_PAIR="${AGENTSWORLD_SKIP_PAIR:-0}"
set_role() { [[ -z "$ROLE" || "$ROLE" == "$1" ]] || fail "Un seul rôle à la fois (--$ROLE et --$1)."; ROLE="$1"; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || fail "$1 attend une valeur."; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) set_role app ;;
    --client-only) set_role client-only ;;
    --host) set_role host ;;
    --agent) set_role agent ;;
    --hub) need_value "$@"; HUB="$2"; shift ;;
    --token) need_value "$@"; TOKEN="$2"; shift ;;
    --name) need_value "$@"; AGENT_NAME="$2"; shift ;;
    --port) need_value "$@"; PORT="$2"; shift ;;
    --link-port) need_value "$@"; LINK_PORT="$2"; shift ;;
    --relay) need_value "$@"; RELAY="$2"; shift ;;
    --bind) need_value "$@"; BIND="$2"; shift ;;
    --format) need_value "$@"; FORMAT="$2"; shift ;;
    --version) need_value "$@"; WANT_VERSION="$2"; shift ;;
    --no-service) NO_SERVICE=1 ;;
    --no-pair) NO_PAIR=1 ;;
    -y|--yes) YES=1 ;;
    --only-services) ONLY_SERVICES=1; YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "Option inconnue : $1" ;;
  esac
  shift
done

say 'Installation'
OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) fail 'Sous Windows, dans PowerShell : irm https://moukrea.github.io/agentsworld/install.ps1 | iex' ;;
esac
command -v curl >/dev/null || fail 'curl est nécessaire.'
command -v tar >/dev/null || fail 'tar est nécessaire.'
if command -v sha256sum >/dev/null; then SHA256=(sha256sum); elif command -v shasum >/dev/null; then SHA256=(shasum -a 256);
else fail 'sha256sum ou shasum est nécessaire pour vérifier les téléchargements.'; fi

PAGE="${AGENTSWORLD_PAGE_URL:-https://moukrea.github.io/agentsworld}"; PAGE="${PAGE%/}"
REPO="${AGENTSWORLD_REPO:-moukrea/agentsworld}"
DEV="${AGENTSWORLD_DEV_INSTALL:-0}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PREFIX="${AGENTSWORLD_PREFIX:-$DATA_HOME/agentsworld}"
BIN="${AGENTSWORLD_BIN_DIR:-$HOME/.local/bin}"
HOST_DATA="${AGENTSWORLD_HOST_DATA:-$PREFIX/host}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
AGENT_ENV="$CONFIG_HOME/agentsworld/agent.env"
RECORD="$PREFIX/install.env"
HOST_UNIT='agentsworld-host.service'
AGENT_UNIT='agentsworld-agent.service'
HOST_LABEL='io.github.moukrea.agentsworld.host'
AGENT_LABEL='io.github.moukrea.agentsworld.agent'
if [[ "$OS" == Darwin ]]; then
  DESKTOP_HOME="${AGENTSWORLD_DESKTOP_HOME:-$HOME/Library/Application Support/io.github.moukrea.agentsworld}"
  APPS_DIR="${AGENTSWORLD_APPS_DIR:-$HOME/Applications}"
else
  DESKTOP_HOME="${AGENTSWORLD_DESKTOP_HOME:-$DATA_HOME/io.github.moukrea.agentsworld}"
fi
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
[[ "$REPO" =~ $REPO_RE ]] || fail 'Nom de dépôt invalide.'

record_get() { if [[ -f "$RECORD" ]]; then sed -n "s/^$1=//p" "$RECORD" | tail -n 1; fi; }
INSTALLED_ROLES="$(record_get roles)"
if [[ "$OS" == Linux && -z "$FORMAT" ]]; then FORMAT="$(record_get app_format)"; fi
# An update keeps how the host and the agent run: a host installed with --no-service stays without one.
if [[ "$(record_get service)" == none && -n "$(record_get roles)" ]]; then NO_SERVICE=1; fi
# Regular expressions in variables: the same meaning under bash 3.2 (macOS) and 5.
TOKEN_RE='^[A-Za-z0-9_-]{16,200}$'
HUB_RE='^(https?|wss?)://[]A-Za-z0-9._~:@%/?=&+[-]+$'
NAME_RE='^[^"\$`]{1,64}$'
RELAY_RE='^wss://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$'
DEV_RELAY_RE='^ws://(127\.0\.0\.1|localhost)(:[0-9]+)?/?$'
PORT_RE='^[0-9]{1,5}$'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

TTY=0
if [[ "$YES" != 1 ]] && { : </dev/tty; } 2>/dev/null; then TTY=1; fi
ask() { local reply; read -r -p "  $1 " reply </dev/tty || reply=''; printf '%s' "${reply%$'\r'}"; }

# --- Jaunt and the role ---------------------------------------------------------------------------------------
JAUNT=0
if command -v jaunt >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/jaunt" || -d "${JAUNT_STATE:-$HOME/.local/share/jaunt}" ]]; then JAUNT=1; fi
DISPLAY_OK=0
if [[ "$OS" == Darwin || -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then DISPLAY_OK=1; fi

if [[ "$ONLY_SERVICES" == 1 ]]; then
  # The automatic update: the host and the agent only (the desktop app updates itself).
  ROLES=''
  for role in $INSTALLED_ROLES; do case "$role" in host|agent) ROLES="${ROLES:+$ROLES }$role" ;; esac; done
  [[ -n "$ROLES" ]] || { info 'Ni hôte ni agent installé : rien à mettre à jour.'; exit 0; }
elif [[ -z "$ROLE" && -n "$INSTALLED_ROLES" && "$TTY" != 1 ]]; then
  ROLES="$INSTALLED_ROLES"   # an update: every installed role, without asking
elif [[ -z "$ROLE" && "$TTY" == 1 ]]; then
  if [[ "$DISPLAY_OK" == 1 ]]; then RECOMMENDED=1; else RECOMMENDED=3; fi
  if [[ -n "$INSTALLED_ROLES" ]]; then RECOMMENDED=0; fi
  {
    printf '\n  Que faut-il installer sur cette machine ?\n\n'
    [[ -n "$INSTALLED_ROLES" ]] && printf '  0) Mettre à jour ce qui est installé (%s)\n' "$INSTALLED_ROLES"
    printf '  1) L’application : au premier lancement, tu choisis d’héberger le monde ici ou de rejoindre un hôte.\n'
    printf '  2) Client seulement : l’application pour rejoindre un hôte, sans hôte sur cette machine.\n'
    printf '  3) Hôte sans écran : le monde tourne en service (serveur, machine toujours allumée), sans application.\n'
    printf '  4) Agent : cette machine envoie ses sessions à un hôte qui n’a pas Jaunt.\n\n'
    if [[ "$JAUNT" == 1 ]]; then
      printf '  Jaunt est installé ici. Avec Jaunt, UN SEUL hôte, sur une de tes machines reliées à Jaunt, voit les\n'
      printf '  sessions de toutes tes machines liées : les autres n’ont besoin que du client (2), ou de rien.\n'
      printf '  L’agent (4) est inutile avec Jaunt.\n'
    else
      printf '  Jaunt n’est pas installé ici. Sans Jaunt, chaque machine dont tu veux voir les sessions a besoin de\n'
      printf '  l’agent (4), sauf l’hôte lui-même. Avec Jaunt (https://github.com/moukrea/jaunt), un seul hôte suffit.\n'
    fi
  } >/dev/tty
  CHOICE="$(ask "Ton choix [$RECOMMENDED] :")"
  case "${CHOICE:-$RECOMMENDED}" in
    0) [[ -n "$INSTALLED_ROLES" ]] || fail 'Rien n’est installé.'; ROLES="$INSTALLED_ROLES" ;;
    1) ROLES=app ;;
    2) ROLES=client-only ;;
    3) ROLES=host ;;
    4) ROLES=agent ;;
    *) fail "Choix inconnu : $CHOICE" ;;
  esac
else
  ROLES="${ROLE:-app}"
fi

if [[ " $ROLES " == *" agent "* ]]; then
  if [[ -z "$HUB" ]]; then HUB="$(sed -n 's/^AGENTSWORLD_HUB="\(.*\)"$/\1/p' "$AGENT_ENV" 2>/dev/null || true)"; fi
  if [[ -z "$TOKEN" ]]; then TOKEN="$(sed -n 's/^AGENTSWORLD_TOKEN="\(.*\)"$/\1/p' "$AGENT_ENV" 2>/dev/null || true)"; fi
  if [[ -z "$AGENT_NAME" ]]; then AGENT_NAME="$(sed -n 's/^AGENTSWORLD_MACHINE_NAME="\(.*\)"$/\1/p' "$AGENT_ENV" 2>/dev/null || true)"; fi
  if [[ -z "$HUB" && "$TTY" == 1 ]]; then HUB="$(ask 'Adresse de l’hôte (http://machine:4317) :')"; fi
  if [[ -z "$TOKEN" && "$TTY" == 1 ]]; then read -r -s -p '  Jeton de l’agent (agentsworld agent-token create sur l’hôte) : ' TOKEN </dev/tty; printf '\n' >/dev/tty; fi
  [[ -n "$HUB" && -n "$TOKEN" ]] || fail 'L’agent a besoin de --hub URL et --token JETON (« agentsworld agent-token create <nom> » sur l’hôte les donne).'
  [[ "$TOKEN" =~ $TOKEN_RE ]] || fail 'Jeton invalide.'
  [[ "$HUB" =~ $HUB_RE ]] || fail 'Adresse de l’hôte invalide (http://machine:4317).'
  [[ -z "$AGENT_NAME" || ( "$AGENT_NAME" =~ $NAME_RE && "$AGENT_NAME" != *$'\n'* ) ]] || fail 'Nom de machine invalide.'
  if [[ "$JAUNT" == 1 ]]; then warn 'Jaunt est installé ici : un hôte relié à Jaunt voit déjà cette machine si elle est liée. L’agent sert aux machines sans Jaunt.'; fi
fi
for value in "$PORT" "$LINK_PORT"; do
  [[ -z "$value" || ( "$value" =~ $PORT_RE && "$value" -ge 1 && "$value" -le 65535 ) ]] || fail "Port invalide : $value"
done
if [[ -n "$RELAY" ]]; then
  [[ "$RELAY" =~ $RELAY_RE ]] || { [[ "$DEV" == 1 && "$RELAY" =~ $DEV_RELAY_RE ]]; } \
    || fail 'Relais invalide : wss://machine[/chemin], sans identifiants, requête ni fragment.'
fi
case "${FORMAT:-appimage}" in appimage|deb|rpm) ;; *) fail "Format inconnu : $FORMAT (appimage, deb ou rpm)" ;; esac
case "$BIND" in ''|127.0.0.1|0.0.0.0|::|::1) ;; *) [[ "$BIND" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail "Adresse d’écoute invalide : $BIND" ;; esac
[[ -z "$FORMAT" || "$OS" == Linux ]] || fail '--format ne concerne que Linux.'

# --- Downloads ------------------------------------------------------------------------------------------------
CURRENT_VERSION="$(cat "$PREFIX/runtime/current/VERSION" 2>/dev/null || true)"
case " $ROLES " in *" host "*|*" agent "*) TRACK=1 ;; esac
mkdir -p "$PREFIX" "$BIN"
chmod 700 "$PREFIX"
TMP="$(mktemp -d "$PREFIX/.install.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PROGRESS=(--silent)
if [[ -t 2 ]]; then PROGRESS=(--progress-bar); fi
fetch() {
  local url="$1" out="$2"
  case "$url" in
    https://*)
      printf '  · %s\n' "${url##*/}"
      curl --disable --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --show-error --location --retry 3 \
        --connect-timeout 15 --max-time 900 "${PROGRESS[@]}" -o "$out" "$url" ;;
    http://127.0.0.1:*|http://localhost:*)
      [[ "$DEV" == 1 ]] || fail 'HTTP seulement pour les tests locaux (AGENTSWORLD_DEV_INSTALL=1).'
      curl --fail --silent --show-error --location -o "$out" "$url" ;;
    *) fail "Téléchargement refusé (HTTPS seulement) : $url" ;;
  esac
}

STAGE='version à installer'
if [[ -n "${AGENTSWORLD_VERSION:-}" ]]; then WANT_VERSION="$AGENTSWORLD_VERSION"; fi
if [[ -z "$WANT_VERSION" ]]; then
  fetch "$PAGE/config.json" "$TMP/config.json"
  grep -q '"version"[[:space:]]*:[[:space:]]*1[,}[:space:]]' "$TMP/config.json" || fail 'config.json de la page : format inconnu.'
  WANT_VERSION="$(sed -n 's/.*"release"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP/config.json" | head -n 1)"
fi
TAG="$WANT_VERSION"; [[ "$TAG" == v* ]] || TAG="v$TAG"
[[ "$TAG" =~ $TAG_RE ]] || fail "Version invalide : $TAG"
VERSION="${TAG#v}"
BASE="${AGENTSWORLD_RELEASE_BASE:-https://github.com/$REPO/releases/download/$TAG}"; BASE="${BASE%/}"
say "Version $TAG ($ROLES)"
ustatus downloading "Téléchargement de $TAG"
fetch "$BASE/SHA256SUMS" "$TMP/SHA256SUMS"

# Download one release asset and check it against SHA256SUMS; nothing unverified is ever kept.
asset() {
  local name="$1" expected actual
  expected="$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$TMP/SHA256SUMS" | head -n 1)"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "$name n’est pas dans SHA256SUMS de $TAG (cette version ne le publie pas pour ce système)."
  fetch "$BASE/$name" "$TMP/$name"
  actual="$("${SHA256[@]}" "$TMP/$name" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then rm -f "$TMP/$name"; fail "Somme SHA-256 incorrecte pour $name : rien n’a été installé."; fi
  printf '    SHA-256 vérifié\n'
}

ARCH="$(uname -m)"
if [[ "$OS" == Darwin && "$ARCH" == x86_64 && "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then ARCH=arm64; fi
case "$OS-$ARCH" in
  Linux-x86_64|Linux-amd64) PLATFORM=linux-x64 ;;
  Linux-aarch64|Linux-arm64) PLATFORM=linux-arm64 ;;
  Darwin-arm64) PLATFORM=darwin-arm64 ;;
  Darwin-x86_64) PLATFORM=darwin-x64 ;;
  *) PLATFORM="" ;;
esac

# --- Services -------------------------------------------------------------------------------------------------
SERVICE=none
if [[ "$NO_SERVICE" != 1 ]]; then
  if [[ "$OS" == Darwin ]]; then SERVICE=launchd
  elif command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then SERVICE=systemd
  fi
fi
RUNTIME="$PREFIX/runtime"
RT="$RUNTIME/current"
sd_quote() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//%/%%}"; printf '"%s"' "$s"; }
xml() { local s="${1//&/&amp;}"; s="${s//</&lt;}"; printf '%s' "${s//>/&gt;}"; }
pid_alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }

# Start or restart one role's service: name (host|agent), then the command.
service_up() {
  local role="$1"; shift
  local unit label log="$PREFIX/$role.log" pidfile="$PREFIX/$role.pid"
  if [[ "$role" == host ]]; then unit="$HOST_UNIT"; label="$HOST_LABEL"; else unit="$AGENT_UNIT"; label="$AGENT_LABEL"; fi
  case "$SERVICE" in
    systemd)
      local dir="$CONFIG_HOME/systemd/user" exec='' word envs=()
      for word in "$@"; do exec+="$(sd_quote "$word") "; done
      mkdir -p "$dir"
      if [[ "$role" == host ]]; then
        envs=("Environment=$(sd_quote "AGENTSWORLD_DATA=$HOST_DATA")" "Environment=NODE_NO_WARNINGS=1")
      else
        envs=("EnvironmentFile=$(sd_quote "$AGENT_ENV")" "Environment=NODE_NO_WARNINGS=1")
      fi
      {
        printf '[Unit]\nDescription=AgentsWorld %s (installed by install.sh)\nAfter=network-online.target\nWants=network-online.target\n\n' \
          "$([[ "$role" == host ]] && printf 'host' || printf 'agent')"
        printf '[Service]\nType=simple\n'
        printf '%s\n' "${envs[@]}"
        printf 'ExecStart=%s\nRestart=on-failure\nRestartSec=5\nTimeoutStopSec=20\nUMask=0077\nNoNewPrivileges=yes\n\n[Install]\nWantedBy=default.target\n' "${exec% }"
      } > "$dir/$unit.new"
      chmod 644 "$dir/$unit.new"
      mv -f "$dir/$unit.new" "$dir/$unit"
      systemctl --user daemon-reload
      systemctl --user enable "$unit" >/dev/null 2>&1 || systemctl --user enable "$unit"
      systemctl --user restart "$unit"
      if [[ "${AGENTSWORLD_NO_LINGER:-0}" != 1 ]] && command -v loginctl >/dev/null \
        && [[ "$(loginctl show-user "$(id -u)" --property=Linger --value 2>/dev/null || true)" != yes ]]; then
        loginctl --no-ask-password enable-linger >/dev/null 2>&1 \
          || info "Pour démarrer avant toute connexion (au démarrage de la machine) : loginctl enable-linger \"\$USER\""
      fi ;;
    launchd)
      local plist="$HOME/Library/LaunchAgents/$label.plist" word args='' penvs=''
      for word in "$@"; do args+="<string>$(xml "$word")</string>"; done
      if [[ "$role" == host ]]; then
        penvs="<key>AGENTSWORLD_DATA</key><string>$(xml "$HOST_DATA")</string>"
      else
        local key
        for key in AGENTSWORLD_HUB AGENTSWORLD_TOKEN AGENTSWORLD_MACHINE_NAME; do
          local value; value="$(sed -n "s/^$key=\"\(.*\)\"$/\1/p" "$AGENT_ENV")"
          [[ -n "$value" ]] && penvs+="<key>$key</key><string>$(xml "$value")</string>"
        done
      fi
      mkdir -p "$HOME/Library/LaunchAgents"
      cat > "$plist.new" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>EnvironmentVariables</key><dict>$penvs<key>NODE_NO_WARNINGS</key><string>1</string></dict>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>5</integer>
<key>StandardOutPath</key><string>$(xml "$log")</string>
<key>StandardErrorPath</key><string>$(xml "$log")</string>
</dict></plist>
PLIST
      chmod 600 "$plist.new"
      mv -f "$plist.new" "$plist"
      launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
      if ! launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
        launchctl bootout "user/$(id -u)/$label" >/dev/null 2>&1 || true
        launchctl bootstrap "user/$(id -u)" "$plist" || { warn 'launchd a refusé le service : démarrage en arrière-plan.'; SERVICE=none; service_up "$role" "$@"; return; }
      fi ;;
    none)
      if pid_alive "$pidfile"; then kill "$(cat "$pidfile")" 2>/dev/null || true; sleep 2; fi
      if [[ "$role" == agent ]]; then
        # shellcheck disable=SC1090
        ( set -a; . "$AGENT_ENV"; set +a; NODE_NO_WARNINGS=1 nohup "$@" >>"$log" 2>&1 </dev/null & printf '%s\n' "$!" >"$pidfile" )
      else
        ( AGENTSWORLD_DATA="$HOST_DATA" NODE_NO_WARNINGS=1 nohup "$@" >>"$log" 2>&1 </dev/null & printf '%s\n' "$!" >"$pidfile" )
      fi
      info "Démarré en arrière-plan (pas de service : à relancer après un redémarrage avec « agentsworld start »)." ;;
  esac
}

service_stop() {
  local role="$1" unit label
  if [[ "$role" == host ]]; then unit="$HOST_UNIT"; label="$HOST_LABEL"; else unit="$AGENT_UNIT"; label="$AGENT_LABEL"; fi
  if [[ "$OS" == Linux ]] && command -v systemctl >/dev/null && [[ -f "$CONFIG_HOME/systemd/user/$unit" ]]; then
    systemctl --user stop "$unit" >/dev/null 2>&1 || true
  fi
  if [[ "$OS" == Darwin && -f "$HOME/Library/LaunchAgents/$label.plist" ]]; then
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || launchctl bootout "user/$(id -u)/$label" >/dev/null 2>&1 || true
  fi
  if pid_alive "$PREFIX/$role.pid"; then kill "$(cat "$PREFIX/$role.pid")" 2>/dev/null || true; fi
}

# --- Runtime (host and agent): Node + the server, CLI and agent bundles ---------------------------------------
install_runtime() {
  [[ -n "$PLATFORM" ]] || fail "Pas d’hôte ni d’agent publié pour $OS $ARCH (Linux et macOS x64/arm64)."
  local name="agentsworld-host_${VERSION}_${PLATFORM}.tar.gz" target node_version
  if [[ -x "$RT/bin/node" && "$(cat "$RT/VERSION" 2>/dev/null || true)" == "$VERSION" && "${AGENTSWORLD_REINSTALL:-0}" != 1 ]]; then
    info "Moteur $VERSION déjà en place."
    return
  fi
  STAGE="téléchargement du moteur $TAG"
  asset "$name"
  STAGE='installation du moteur'
  ustatus installing "Installation de $TAG"
  mkdir -p "$RUNTIME/versions"
  target="$RUNTIME/versions/$TAG-$(date +%s)-$$"
  mkdir -p "$target"
  tar -xzf "$TMP/$name" -C "$target" || { rm -rf "$target"; fail 'Archive du moteur illisible.'; }
  # The new runtime must run here before anything points at it.
  node_version="$("$target/bin/node" --version 2>/dev/null || true)"
  [[ -n "$node_version" ]] || { rm -rf "$target"; fail 'Le Node fourni ne démarre pas sur ce système.'; }
  [[ -f "$target/server/agentsworld-server.mjs" && -f "$target/cli/agentsworld.mjs" ]] || { rm -rf "$target"; fail 'Archive du moteur incomplète.'; }
  # Keep the runtime that runs now for a rollback (install_host / install_agent switch back if the new one fails).
  if [[ -L "$RT" ]] && [[ -d "$RT" ]]; then PREV_RT="$(cd -P "$RT" && pwd)"; fi
  switch_runtime "$target/bin/node" "$target" "$PREV_RT"
  info "Moteur $VERSION installé (Node $node_version)."
}

PREV_RT=''
# Point `current` at a runtime atomically (rename over the old link). With a third argument (the runtime that ran
# until now, possibly empty), every other version is removed: the new one and that one are kept for a rollback.
switch_runtime() {
  "$1" -e '
    const fs = require("fs"), path = require("path");
    const [runtime, target, keep] = process.argv.slice(1), tmp = path.join(runtime, "current.new");
    fs.rmSync(tmp, {force: true});
    fs.symlinkSync(target, tmp);
    fs.renameSync(tmp, path.join(runtime, "current"));
    if (process.argv.length < 4) process.exit(0);
    const versions = path.join(runtime, "versions");
    const kept = new Set([target, keep].filter(Boolean).map((d) => fs.realpathSync(d)));
    for (const name of fs.readdirSync(versions)) {
      const dir = path.join(versions, name);
      if (!kept.has(fs.realpathSync(dir))) fs.rmSync(dir, {recursive: true, force: true});
    }
  ' "$RUNTIME" "$2" ${3+"$3"}
}

# The host answers /api/health with this protocol and, when given, this version.
PROTOCOL=3
# (Inside $(…) a failing command would run the ERR trap: set -E. Hence the `|| true` in command substitutions.)
host_healthy() {
  local out
  out="$(curl -fsS --max-time 2 "http://127.0.0.1:$1/api/health" 2>/dev/null || true)"
  [[ -n "$out" ]] || return 1
  [[ "$out" == *"\"protocol\":$PROTOCOL"* ]] || return 1
  [[ -z "${2:-}" || "$out" == *"\"version\":\"$2\""* ]]
}
wait_host() {
  for _ in $(seq 1 "${3:-60}"); do
    if host_healthy "$1" "${2:-}"; then return 0; fi
    sleep 1
  done
  return 1
}

# The agent is still running a few seconds after its start.
agent_alive() {
  sleep 8
  case "$SERVICE" in
    systemd) systemctl --user is-active --quiet "$AGENT_UNIT" ;;
    launchd) launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null | grep -q 'state = running' \
               || launchctl print "user/$(id -u)/$AGENT_LABEL" 2>/dev/null | grep -q 'state = running' ;;
    *) pid_alive "$PREFIX/agent.pid" ;;
  esac
}

# The new runtime does not serve: back to the previous one, restarted, and the update reported as failed.
rollback() {
  local role="$1" reason="$2"
  if [[ -z "$PREV_RT" || ! -x "$PREV_RT/bin/node" || "$PREV_RT" == "$(cd -P "$RT" && pwd)" ]]; then fail "$reason"; fi
  warn "$reason : retour à la version précédente."
  switch_runtime "$PREV_RT/bin/node" "$PREV_RT"
  CURRENT_VERSION="$(cat "$PREV_RT/VERSION" 2>/dev/null || true)"
  # Before the restart: the previous runtime reports this failure as soon as it is back.
  ustatus error "$reason"
  local again=() other
  for other in $ROLES; do case "$other" in host|agent) again+=("$other") ;; esac; done
  for other in "${again[@]}"; do
    if [[ "$other" == host ]]; then node_cmd server/agentsworld-server.mjs; service_up host "${NODE_RUN[@]}" --config "$HOST_DATA/config.json"
    else node_cmd agent/agentsworld-agent.mjs; service_up agent "${NODE_RUN[@]}"; fi
  done
  if [[ "$role" == host ]] && ! wait_host "$HOST_PORT" '' 60; then warn 'La version précédente ne répond pas non plus : « agentsworld logs host ».'; fi
  fail "$reason ; la version $CURRENT_VERSION a repris."
}

NODE_RUN=()
node_cmd() { NODE_RUN=("$RT/bin/node" --preserve-symlinks-main "$RT/$1"); }

# The host's config.json (kept across updates; options given now replace its values). When the host is not running
# yet, both ports must be free before anything is written.
host_config() {
  local file="$HOST_DATA/config.json"
  mkdir -p "$HOST_DATA"
  chmod 700 "$HOST_DATA"
  "$RT/bin/node" -e '
    const fs = require("fs"), net = require("net");
    const [file, port, linkPort, relay, running, bind, jaunt] = process.argv.slice(1);
    let config = {};
    try { config = JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) { if (error.code !== "ENOENT") throw error; }
    const fresh = Object.keys(config).length === 0;
    config.link = {...(config.link ?? {})};
    // With Jaunt, agents are useless: the world stays on this machine (devices use Link). Without, agents need HTTP.
    if (fresh) { config.port = 4317; config.bind = jaunt === "1" ? "127.0.0.1" : "0.0.0.0"; config.link = {enabled: true, port: 4318, relays: []}; }
    if (bind) config.bind = bind;
    if (port) config.port = Number(port);
    if (linkPort) config.link.port = Number(linkPort);
    if (relay) config.link.relays = [relay];
    const free = (p) => new Promise((resolve) => {
      const s = net.createServer();
      s.once("error", () => resolve(false));
      s.listen(p, "0.0.0.0", () => s.close(() => resolve(true)));
    });
    (async () => {
      const http = config.port ?? 4317, link = config.link?.port ?? 4318;
      if (running !== "1") {
        if (!(await free(http))) { console.error(`Le port ${http} est déjà pris sur cette machine (un autre AgentsWorld ?). Choisis-en un autre : --port N.`); process.exit(3); }
        if (!(await free(link))) { console.error(`Le port Link ${link} est déjà pris sur cette machine. Choisis-en un autre : --link-port N.`); process.exit(3); }
      }
      if (fresh || port || linkPort || relay || bind) {
        fs.writeFileSync(file + ".new", JSON.stringify(config, null, 2) + "\n", {mode: 0o600});
        fs.renameSync(file + ".new", file);
      }
      console.log(`${http} ${link}`);
    })();
  ' "$file" "$PORT" "$LINK_PORT" "$RELAY" "$1" "$BIND" "$JAUNT" || return 3
}

install_host() {
  install_runtime
  STAGE='configuration de l’hôte'
  local ports http link running=0
  if [[ "$SERVICE" == systemd ]] && systemctl --user is-active --quiet "$HOST_UNIT" 2>/dev/null; then running=1; fi
  if [[ "$SERVICE" == launchd ]] && launchctl print "gui/$(id -u)/$HOST_LABEL" >/dev/null 2>&1; then running=1; fi
  if pid_alive "$PREFIX/host.pid"; then running=1; fi
  ports="$(host_config "$running")" || fail 'Rien n’a été démarré.'
  http="${ports% *}"; link="${ports#* }"
  STAGE='démarrage du service de l’hôte'
  service_stop host
  node_cmd server/agentsworld-server.mjs
  service_up host "${NODE_RUN[@]}" --config "$HOST_DATA/config.json"
  HOST_PORT="$http"
  if ! wait_host "$http" "$VERSION" 90; then
    rollback host "La version $VERSION de l’hôte ne répond pas sur le port $http (/api/health, protocole $PROTOCOL)"
  fi
  info "Hôte en marche : http://127.0.0.1:$http (appareils : port Link $link)."
}

install_agent() {
  install_runtime
  STAGE='configuration de l’agent'
  mkdir -p "$(dirname "$AGENT_ENV")"
  chmod 700 "$(dirname "$AGENT_ENV")"
  {
    printf 'AGENTSWORLD_HUB="%s"\nAGENTSWORLD_TOKEN="%s"\n' "$HUB" "$TOKEN"
    [[ -n "$AGENT_NAME" ]] && printf 'AGENTSWORLD_MACHINE_NAME="%s"\n' "$AGENT_NAME"
    [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && printf 'CLAUDE_CONFIG_DIR="%s"\n' "$CLAUDE_CONFIG_DIR"
    true
  } > "$AGENT_ENV.new"
  chmod 600 "$AGENT_ENV.new"
  mv -f "$AGENT_ENV.new" "$AGENT_ENV"
  # One agent per machine: the unit from before the rename (agentshome-agent) goes.
  if [[ "$SERVICE" == systemd && -f "$CONFIG_HOME/systemd/user/agentshome-agent.service" ]]; then
    systemctl --user disable --now agentshome-agent.service >/dev/null 2>&1 || true
    rm -f "$CONFIG_HOME/systemd/user/agentshome-agent.service"
  fi
  STAGE='démarrage du service de l’agent'
  service_stop agent
  node_cmd agent/agentsworld-agent.mjs
  service_up agent "${NODE_RUN[@]}"
  if ! agent_alive; then rollback agent "La version $VERSION de l’agent s’arrête au démarrage"; fi
  info "Agent en marche : il envoie les sessions de cette machine à $HUB."
}

# --- Desktop app ----------------------------------------------------------------------------------------------
desktop_mode() {
  local client_only="$1" mode
  mkdir -p "$DESKTOP_HOME"
  if [[ "$client_only" == 1 ]]; then
    printf '{\n  "mode": "join",\n  "clientOnly": true\n}\n' > "$DESKTOP_HOME/desktop.json.new"
  else
    mode="$(sed -En 's/.*"mode"[[:space:]]*:[[:space:]]*"(host|join)".*/\1/p' "$DESKTOP_HOME/desktop.json" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$mode" ]]; then printf '{\n  "mode": "%s"\n}\n' "$mode"; else printf '{\n  "mode": null\n}\n'; fi > "$DESKTOP_HOME/desktop.json.new"
  fi
  chmod 600 "$DESKTOP_HOME/desktop.json.new"
  mv -f "$DESKTOP_HOME/desktop.json.new" "$DESKTOP_HOME/desktop.json"
}

APP_PATH=''
install_app() {
  local client_only="$1" previous
  STAGE='installation de l’application'
  # The same version already installed (an update of other roles): only the mode changes. The app updates itself.
  previous="$(record_get app_path)"
  if [[ "$(record_get app_version)" == "$TAG" && -n "$previous" && -e "$previous" && "${FORMAT:-appimage}" == "$(r="$(record_get app_format)"; printf '%s' "${r:-appimage}")" && "${AGENTSWORLD_REINSTALL:-0}" != 1 ]]; then
    APP_PATH="$previous"
    desktop_mode "$client_only"
    info "Application $VERSION déjà en place : $APP_PATH"
    return
  fi
  if [[ "$OS" == Linux ]]; then
    [[ "$PLATFORM" == linux-x64 ]] || fail "L’application de bureau n’existe pas pour Linux $ARCH. L’hôte sans écran (--host) et l’app Android, oui."
    case "${FORMAT:-appimage}" in
      deb)
        asset "AgentsWorld_${VERSION}_amd64.deb"
        command -v apt-get >/dev/null || fail 'apt-get introuvable : utilise --format appimage.'
        sudo apt-get install -y "$TMP/AgentsWorld_${VERSION}_amd64.deb"
        APP_PATH='/usr/bin/agentsworld' ;;
      rpm)
        asset "AgentsWorld-${VERSION}-1.x86_64.rpm"
        if command -v dnf >/dev/null; then sudo dnf install -y "$TMP/AgentsWorld-${VERSION}-1.x86_64.rpm";
        elif command -v zypper >/dev/null; then sudo zypper --non-interactive install --allow-unsigned-rpm "$TMP/AgentsWorld-${VERSION}-1.x86_64.rpm";
        else fail 'dnf ou zypper introuvable : utilise --format appimage.'; fi
        APP_PATH='/usr/bin/agentsworld' ;;
      appimage)
        local name="AgentsWorld_${VERSION}_amd64.AppImage" dir="$PREFIX/app" exec_line apps="$DATA_HOME/applications"
        asset "$name"
        mkdir -p "$dir" "$apps"
        chmod 755 "$TMP/$name"
        ( cd "$TMP" && "./$name" --appimage-extract 'AgentsWorld.png' >/dev/null 2>&1 ) || true
        mv -f "$TMP/$name" "$dir/AgentsWorld.AppImage"
        APP_PATH="$dir/AgentsWorld.AppImage"
        if [[ -f "$TMP/squashfs-root/AgentsWorld.png" ]]; then cp -f "$TMP/squashfs-root/AgentsWorld.png" "$dir/icon.png"; chmod 644 "$dir/icon.png"; fi
        exec_line="\"$APP_PATH\""
        # Without libfuse2 an AppImage cannot mount itself: it extracts itself on each start instead.
        if ! { ldconfig -p 2>/dev/null || true; } | grep -q 'libfuse\.so\.2'; then exec_line="env APPIMAGE_EXTRACT_AND_RUN=1 $exec_line"; fi
        cat > "$apps/agentsworld.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=AgentsWorld
Comment=Le monde où vivent tes sessions Claude Code et Codex
Exec=$exec_line
Icon=$dir/icon.png
Terminal=false
Categories=Game;
StartupWMClass=agentsworld
DESKTOP
        chmod 644 "$apps/agentsworld.desktop"
        if command -v update-desktop-database >/dev/null; then update-desktop-database "$apps" >/dev/null 2>&1 || true; fi ;;
    esac
  else
    local arch name dest="$APPS_DIR/AgentsWorld.app"
    [[ "$PLATFORM" == darwin-arm64 ]] && arch=aarch64 || arch=x64
    name="AgentsWorld_${VERSION}_${arch}.app.tar.gz"
    asset "$name"
    mkdir -p "$TMP/app" "$APPS_DIR"
    tar -xzf "$TMP/$name" -C "$TMP/app"
    [[ -d "$TMP/app/AgentsWorld.app" ]] || fail 'Archive de l’application incomplète.'
    xattr -dr com.apple.quarantine "$TMP/app/AgentsWorld.app" 2>/dev/null || true
    rm -rf "$dest.old"
    if [[ -d "$dest" ]]; then mv "$dest" "$dest.old"; fi
    mv "$TMP/app/AgentsWorld.app" "$dest"
    rm -rf "$dest.old"
    APP_PATH="$dest"
    if [[ -d /Applications/AgentsWorld.app ]]; then warn "Une autre copie existe dans /Applications : celle-ci est dans $APPS_DIR."; fi
  fi
  desktop_mode "$client_only"
  if [[ "$client_only" == 1 ]]; then info "Application installée en client seul : $APP_PATH"; else info "Application installée : $APP_PATH"; fi
}

# --- The `agentsworld` command --------------------------------------------------------------------------------
write_record() {
  {
    printf 'roles=%s\nversion=%s\npage=%s\nrepo=%s\nos=%s\nservice=%s\n' "$1" "$TAG" "$PAGE" "$REPO" "$OS" "$SERVICE"
    printf 'host_data=%s\nhost_port=%s\napp_path=%s\napp_format=%s\ndesktop_home=%s\n' \
      "$HOST_DATA" "${HOST_PORT:-$(record_get host_port)}" "${APP_PATH:-$(record_get app_path)}" "${FORMAT:-$(record_get app_format)}" "$DESKTOP_HOME"
    printf 'auto_update=%s\n' "$(r="$(record_get auto_update)"; printf '%s' "${r:-1}")"
    if [[ -n "$APP_PATH" ]]; then printf 'app_version=%s\n' "$TAG"; else printf 'app_version=%s\n' "$(record_get app_version)"; fi
    # Installers' own tests against a loopback mirror: the automatic updater uses the same mirror.
    if [[ "$DEV" == 1 && -n "${AGENTSWORLD_RELEASE_BASE:-}" ]]; then
      printf 'dev_release_base=%s\ndev_update_interval=%s\n' "$AGENTSWORLD_RELEASE_BASE" "${AGENTSWORLD_UPDATE_INTERVAL:-}"
    fi
  } > "$RECORD.new"
  chmod 600 "$RECORD.new"
  mv -f "$RECORD.new" "$RECORD"
}

write_cli() {
  local file="$BIN/agentsworld"
  {
    printf '#!/usr/bin/env bash\n# The agentsworld command, written by install.sh (%s). Run « agentsworld help ».\n' "$TAG"
    printf 'PREFIX=%q\nCONFIG_HOME=%q\n' "$PREFIX" "$CONFIG_HOME"
    cat <<'CLI'
set -uo pipefail
RECORD="$PREFIX/install.env"
RT="$PREFIX/runtime/current"
rec() { sed -n "s/^$1=//p" "$RECORD" 2>/dev/null | tail -n 1; }
[[ -f "$RECORD" ]] || { echo "AgentsWorld n’est pas installé ici ($RECORD manquant)." >&2; exit 1; }
ROLES="$(rec roles)" OS="$(rec os)" SERVICE="$(rec service)" DATA="$(rec host_data)" PAGE="$(rec page)"
has() { case " $ROLES " in *" $1 "*) return 0 ;; esac; return 1; }
unit_of() { [[ "$1" == host ]] && echo agentsworld-host.service || echo agentsworld-agent.service; }
label_of() { echo "io.github.moukrea.agentsworld.$1"; }
node_cli() {
  [[ -x "$RT/bin/node" ]] || { echo "Cette commande demande l’hôte (agentsworld role add host)." >&2; exit 1; }
  AGENTSWORLD_DATA="$DATA" AGENTSWORLD_CONFIG="$DATA/config.json" NODE_NO_WARNINGS=1 \
    "$RT/bin/node" --preserve-symlinks-main "$RT/cli/agentsworld.mjs" "$@"
}
need_host() { has host || { echo "Pas d’hôte sans écran sur cette machine. Dans l’application : Réglages › Appareil. Ou : agentsworld role add host" >&2; exit 1; }; }
roles_with_service() { local r out=''; for r in host agent; do has "$r" && out+="$r "; done; echo "${1:-$out}"; }
svc() {
  local action="$1" role="$2"
  case "$SERVICE" in
    systemd) systemctl --user "$action" "$(unit_of "$role")" ;;
    launchd)
      local plist domain
      plist="$HOME/Library/LaunchAgents/$(label_of "$role").plist"; domain="gui/$(id -u)"
      launchctl print "$domain" >/dev/null 2>&1 || domain="user/$(id -u)"
      case "$action" in
        start) launchctl bootstrap "$domain" "$plist" 2>/dev/null || launchctl kickstart "$domain/$(label_of "$role")" ;;
        stop) launchctl bootout "$domain/$(label_of "$role")" ;;
        restart) launchctl bootout "$domain/$(label_of "$role")" 2>/dev/null; launchctl bootstrap "$domain" "$plist" ;;
        status) launchctl print "$domain/$(label_of "$role")" 2>/dev/null | grep -E '^\s*(state|pid|last exit code) =' || echo "  arrêté" ;;
      esac ;;
    *)
      local pidfile="$PREFIX/$role.pid"
      case "$action" in
        stop) [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile" ;;
        start|restart)
          [[ "$action" == restart && -f "$pidfile" ]] && { kill "$(cat "$pidfile")" 2>/dev/null; sleep 2; }
          if [[ "$role" == host ]]; then
            ( AGENTSWORLD_DATA="$DATA" NODE_NO_WARNINGS=1 nohup "$RT/bin/node" --preserve-symlinks-main "$RT/server/agentsworld-server.mjs" \
              --config "$DATA/config.json" >>"$PREFIX/host.log" 2>&1 </dev/null & echo "$!" >"$pidfile" )
          else
            # shellcheck disable=SC1091
            ( set -a; . "$CONFIG_HOME/agentsworld/agent.env"; set +a; NODE_NO_WARNINGS=1 nohup "$RT/bin/node" --preserve-symlinks-main \
              "$RT/agent/agentsworld-agent.mjs" >>"$PREFIX/agent.log" 2>&1 </dev/null & echo "$!" >"$pidfile" )
          fi ;;
        status) if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then echo "  en marche (pid $(cat "$pidfile"))"; else echo "  arrêté"; fi ;;
      esac ;;
  esac
}
installer() {
  local url="$PAGE/install.sh"
  if [[ -n "${AGENTSWORLD_INSTALLER:-}" ]]; then bash "$AGENTSWORLD_INSTALLER" "$@"; return; fi
  curl --proto '=https' --tlsv1.2 -fsSL "$url" | bash -s -- "$@"
}
remove_role() {
  local role="$1" purge="$2"
  case "$role" in
    host|agent)
      svc stop "$role" >/dev/null 2>&1
      if [[ "$SERVICE" == systemd ]]; then
        systemctl --user disable "$(unit_of "$role")" >/dev/null 2>&1
        rm -f "$CONFIG_HOME/systemd/user/$(unit_of "$role")"; systemctl --user daemon-reload 2>/dev/null
      fi
      rm -f "$HOME/Library/LaunchAgents/$(label_of "$role").plist" "$PREFIX/$role.pid"
      if [[ "$role" == agent && "$purge" == 1 ]]; then rm -f "$CONFIG_HOME/agentsworld/agent.env"; fi
      if [[ "$role" == host && "$purge" == 1 && -n "$DATA" ]]; then rm -rf "$DATA"; fi ;;
    app|client-only)
      local path; path="$(rec app_path)"
      case "$(rec app_format)" in
        deb) echo "Paquet système à retirer : sudo apt-get remove agents-world" ;;
        rpm) echo "Paquet système à retirer : sudo dnf remove agents-world" ;;
        *) [[ -n "$path" && "$path" == *AgentsWorld* ]] && rm -rf "$path"
           rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/agentsworld.desktop" "$PREFIX/app/icon.png" ;;
      esac
      [[ "$purge" == 1 ]] && rm -rf "$(rec desktop_home)" ;;
  esac
  ROLES="$(echo " $ROLES " | sed "s/ $role / /; s/^ *//; s/ *$//")"
  if [[ -n "$ROLES" ]]; then sed -i.bak "s/^roles=.*/roles=$ROLES/" "$RECORD" && rm -f "$RECORD.bak"; fi
}
usage() {
  cat <<'USAGE'
agentsworld status                      ce qui est installé et en marche
agentsworld pair [--rights observe|answer|admin]   code d'appairage + QR code pour un appareil (hôte)
agentsworld jaunt-enroll                relie l'hôte à Jaunt (à valider sur ton téléphone)
agentsworld agent-token create <nom>    jeton + commande d'installation d'un agent (machine sans Jaunt)
agentsworld logs [host|agent|app] [-f]  journaux
agentsworld start|stop|restart [host|agent]
agentsworld open                        ouvre l'application (ou la page de l'hôte)
agentsworld update [--auto on|off]      met à jour ce qui est installé (l'hôte et l'agent le font seuls)
agentsworld role                        rôles installés ; role add <app|client-only|host|agent> [options] ; role remove <rôle>
agentsworld uninstall [--purge]         désinstalle (--purge : aussi le monde, les appairages et les réglages)
USAGE
}
command="${1:-help}"; shift || true
case "$command" in
  status)
    if [[ " $* " == *" --json "* ]]; then if has host; then node_cli status "$@"; exit; else echo '{}'; exit 3; fi; fi
    echo "AgentsWorld $(rec version) · rôles : ${ROLES:-aucun}"
    if has app || has client-only; then echo "Application : $(rec app_path)$(has client-only && echo ' (client seul)')"; fi
    for role in $(roles_with_service); do echo "Service $role :"; svc status "$role" 2>&1 | sed 's/^/  /' | head -n 12; done
    if has host; then node_cli status "$@"; fi
    if has agent; then echo "Agent → $(sed -n 's/^AGENTSWORLD_HUB="\(.*\)"$/\1/p' "$CONFIG_HOME/agentsworld/agent.env" 2>/dev/null)"; fi ;;
  pair|agent-token) need_host; node_cli "$command" "$@" ;;
  jaunt-enroll)
    need_host
    if node_cli jaunt-enroll "$@"; then echo "Redémarrage de l’hôte…"; svc restart host >/dev/null 2>&1; fi ;;
  logs)
    role="${1:-}"; follow=''; for a in "$@"; do [[ "$a" == -f ]] && follow=1; done
    [[ "$role" == -f || -z "$role" ]] && { if has host; then role=host; elif has agent; then role=agent; else role=app; fi; }
    if [[ "$role" == app ]]; then
      log="$(rec desktop_home)/logs/desktop.log"; [[ -n "$follow" ]] && exec tail -f "$log"; tail -n 200 "$log"
    elif [[ "$SERVICE" == systemd ]]; then
      exec journalctl --user -u "$(unit_of "$role")" -n 200 ${follow:+-f}
    else
      [[ -n "$follow" ]] && exec tail -f "$PREFIX/$role.log"; tail -n 200 "$PREFIX/$role.log"
    fi ;;
  start|stop|restart) for role in $(roles_with_service "${1:-}"); do svc "$command" "$role"; done ;;
  open)
    path="$(rec app_path)"
    if [[ -n "$path" && -e "$path" ]]; then
      if [[ "$OS" == Darwin ]]; then open "$path"; else
        if ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then nohup "$path" >/dev/null 2>&1 &
        else APPIMAGE_EXTRACT_AND_RUN=1 nohup "$path" >/dev/null 2>&1 & fi
      fi
    elif has host; then
      url="http://127.0.0.1:$(rec host_port)/"; command -v xdg-open >/dev/null && xdg-open "$url" || { command -v open >/dev/null && open "$url"; } || echo "$url"
    else echo "Rien à ouvrir." >&2; exit 1; fi ;;
  update)
    if [[ "${1:-}" == --auto ]]; then
      case "${2:-}" in on) v=1 ;; off) v=0 ;; *) echo "agentsworld update --auto on|off" >&2; exit 2 ;; esac
      if grep -q '^auto_update=' "$RECORD"; then sed -i.bak "s/^auto_update=.*/auto_update=$v/" "$RECORD" && rm -f "$RECORD.bak"
      else echo "auto_update=$v" >> "$RECORD"; fi
      echo "Mises à jour automatiques : $2 (vérifiées toutes les 15 minutes par l’hôte ou l’agent)."
      exit 0
    fi
    installer --yes "$@" ;;
  role)
    sub="${1:-}"; shift || true
    case "$sub" in
      '') echo "${ROLES:-aucun}" ;;
      add) [[ -n "${1:-}" ]] || { usage; exit 2; }; r="$1"; shift; installer "--$r" "$@" ;;
      remove)
        if [[ -z "${1:-}" ]] || ! has "$1"; then echo "Rôle non installé : ${1:-}" >&2; exit 2; fi
        remove_role "$1" 0; echo "Rôle $1 retiré (données gardées)." ;;
      *) usage; exit 2 ;;
    esac ;;
  uninstall)
    purge=0; [[ "${1:-}" == --purge ]] && purge=1
    for role in $ROLES; do remove_role "$role" "$purge"; done
    rm -rf "$PREFIX/runtime" "$PREFIX/app" "$PREFIX"/.install.* "$PREFIX"/*.pid
    [[ "$purge" == 1 ]] && rm -f "$PREFIX"/*.log
    rm -f "$RECORD" "$0"
    rmdir "$PREFIX" 2>/dev/null
    echo "AgentsWorld désinstallé.$([[ "$purge" == 1 ]] || echo " Le monde et les appairages sont gardés dans ${DATA:-$PREFIX} (--purge les supprime).")" ;;
  version|--version) rec version ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
CLI
  } > "$file.new"
  chmod 755 "$file.new"
  mv -f "$file.new" "$file"
}

# --- Install --------------------------------------------------------------------------------------------------
HOST_PORT=''
ALL_ROLES="$INSTALLED_ROLES"
add_role() { case " $ALL_ROLES " in *" $1 "*) ;; *) ALL_ROLES="${ALL_ROLES:+$ALL_ROLES }$1" ;; esac; }
drop_role() { ALL_ROLES="$(printf ' %s ' "$ALL_ROLES" | sed "s/ $1 / /; s/^ *//; s/ *$//")"; }
for role in $ROLES; do
  case "$role" in
    app) install_app 0; drop_role client-only; add_role app ;;
    client-only) install_app 1; drop_role app; add_role client-only ;;
    host) install_host; add_role host ;;
    agent) install_agent; add_role agent ;;
    *) fail "Rôle inconnu dans install.env : $role" ;;
  esac
done
STAGE='commande agentsworld'
write_record "$ALL_ROLES"
write_cli
ustatus installed "Version $TAG en marche" "$VERSION"

say "Prêt ($TAG)"
case ":$PATH:" in *":$BIN:"*) ;; *) info "Ajoute $BIN à ton PATH pour avoir la commande « agentsworld » (ex. dans ~/.profile : export PATH=\"$BIN:\$PATH\")." ;; esac
for role in $ROLES; do
  case "$role" in
    app)
      info "Ouvre AgentsWorld depuis le menu des applications (ou « agentsworld open »)."
      info "Au premier lancement : « Héberger ce monde sur cette machine », ou « Rejoindre un hôte » avec le code d’appairage d’un hôte."
      if [[ "$JAUNT" == 1 ]]; then info "Jaunt est ici : en hébergeant, Réglages › Appareil › Application › « Relier à Jaunt » montre toutes tes machines liées."; fi ;;
    client-only)
      info "Ouvre AgentsWorld (« agentsworld open »), puis « Rejoindre un hôte » : colle le code d’appairage de l’hôte ou importe son QR code."
      info "Sur l’hôte : « agentsworld pair », ou Réglages › Appareil › « Appairer un appareil » dans son application." ;;
    host)
      if [[ "$NO_PAIR" != 1 ]]; then
        say 'Appairer un appareil (téléphone, autre ordinateur)'
        "$BIN/agentsworld" pair || warn 'Pas de code pour l’instant : « agentsworld pair » quand l’hôte répond.'
      else
        info 'Appairer un appareil : agentsworld pair'
      fi
      if [[ "$JAUNT" == 1 && ! -f "$HOST_DATA/jaunt-service.json" ]]; then
        say 'Jaunt'
        info 'Pour que cet hôte voie les sessions de toutes tes machines reliées à Jaunt :'
        info '  agentsworld jaunt-enroll      (une demande apparaît sur ton téléphone appairé à Jaunt : accepte-la)'
        if [[ "$TTY" == 1 ]]; then
          case "$(ask 'Le faire maintenant ? [O/n]')" in [nN]*) ;; *) "$BIN/agentsworld" jaunt-enroll || warn 'Enrôlement non fait : « agentsworld jaunt-enroll » pour réessayer.' ;; esac
        fi
      elif [[ "$JAUNT" != 1 ]]; then
        info 'Sans Jaunt, pour voir les sessions d’une autre machine : « agentsworld agent-token create <nom> » ici donne sa commande d’installation.'
      fi ;;
    agent) info "« agentsworld status » montre l’agent ; « agentsworld logs agent » ses journaux." ;;
  esac
done
info "Commande : $BIN/agentsworld (status, pair, logs, update, uninstall…)"
