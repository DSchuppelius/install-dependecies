#!/usr/bin/env bash
# install-dependencies.sh
# Installiert Pakete & Java‑JARs aus allen *executables.json in config/
# und ruft rekursiv weitere install‑dependencies‑Skripte aus vendor/ auf.

set -euo pipefail

###############################################################################
# 0 – Rekursions‑Schutz
###############################################################################
if [[ -n "${INSTALL_DEPS_RUNNING:-}" ]]; then
  exit 0            # schon in übergeordnetem Aufruf aktiv
fi
export INSTALL_DEPS_RUNNING=1

###############################################################################
# 1 – Verzeichnisse & Werkzeuge
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/../config}"   # override möglich
JQ=$(command -v jq)
[[ -z "$JQ" ]] && { echo "jq erforderlich → sudo apt install jq"; exit 1; }

###############################################################################
# 2 – Alle *executables.json einsammeln
###############################################################################
mapfile -t CONFIG_FILES < <(find "$CONFIG_DIR" -maxdepth 1 -name '*executables.json' -type f | sort)
if ((${#CONFIG_FILES[@]} == 0)); then
  echo "Keine executables.json‑Dateien in $CONFIG_DIR gefunden."
  exit 1
fi

echo "Gefundene Konfig‑Dateien:"
printf '  • %s\n' "${CONFIG_FILES[@]}"

###############################################################################
# 3 – Pakete installieren (duplikate vermeiden)
###############################################################################
declare -A SEEN_PKG
for cfg in "${CONFIG_FILES[@]}"; do
  echo "→ bearbeite $cfg (shellExecutables)"
  jq -r '.shellExecutables | to_entries[] | select(.value.package) | .value.package' "$cfg" |
  while read -r package; do
    [[ -n "${SEEN_PKG[$package]:-}" ]] && continue
    SEEN_PKG["$package"]=1
    if ! dpkg -s "$package" &>/dev/null; then
      echo "  Installiere: $package"
      sudo apt-get update
      sudo apt-get install -y "$package"
    else
      echo "  $package bereits installiert"
    fi
  done
done

###############################################################################
# 4 – Java‑Executables herunterladen (duplikate vermeiden)
###############################################################################
declare -A SEEN_JAR
for cfg in "${CONFIG_FILES[@]}"; do
  echo "→ bearbeite $cfg (javaExecutables)"
  jq -r '.javaExecutables | to_entries[] | select(.value.url and .value.path) | \
         [.value.url, .value.path] | @tsv' "$cfg" |
  while IFS=$'\t' read -r url target; do
    [[ -n "${SEEN_JAR[$target]:-}" ]] && continue
    SEEN_JAR["$target"]=1
    if [[ ! -f "$target" ]]; then
      echo "  Lade $url → $target ..."
      sudo curl -L -o "$target" "$url"
      sudo chmod +x "$target"
    else
      echo "  $target bereits vorhanden"
    fi
  done
done

###############################################################################
# 5 – Weitere install‑dependencies‑Skripte in vendor/
###############################################################################
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor"

if [[ -d "$VENDOR_DIR" ]]; then
  echo "Suche rekursiv nach weiteren install‑dependencies.sh in $VENDOR_DIR ..."
  while IFS= read -r other_script; do
    if [[ "$(realpath "$other_script")" != "$(realpath "$SCRIPT_DIR/install-dependencies.sh")" ]]; then
      echo "──────────────────────────────────────────────────────────────"
      echo "Starte abhängiges Skript: $other_script"
      bash "$other_script"
      echo "Fertig: $other_script"
      echo "──────────────────────────────────────────────────────────────"
    fi
  done < <(find "$VENDOR_DIR" -path '*/install-dependencies/scripts/install-dependencies.sh' -type f)
fi

echo "Alle definierten Abhängigkeiten wurden geprüft und installiert."
