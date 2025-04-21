#!/usr/bin/env bash
# install-dependencies.sh
# Liest alle *executables.json in config/, installiert Pakete & JARs
# und startet rekursiv weitere install‑dependencies‑Skripte in vendor/.

set -euo pipefail

###############################################################################
# 0 – Rekursions‑Schutz
###############################################################################
if [[ -n "${INSTALL_DEPS_RUNNING:-}" ]]; then
  exit 0
fi
export INSTALL_DEPS_RUNNING=1

###############################################################################
# 1 – Verzeichnisse & Werkzeuge
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/../config}"      # override möglich
JQ=$(command -v jq) || { echo "jq nötig – sudo apt install jq"; exit 1; }

###############################################################################
# 2 – Alle *executables.json einsammeln
###############################################################################
mapfile -t CONFIG_FILES < <(find "$CONFIG_DIR" -maxdepth 1 -name '*executables.json' -type f | sort)
if ((${#CONFIG_FILES[@]}==0)); then
  echo "Keine executables.json‑Dateien in $CONFIG_DIR gefunden."
  exit 1
fi

echo "Gefundene Konfig‑Dateien:"
printf '  • %s\n' "${CONFIG_FILES[@]}"

###############################################################################
# 3 – Pakete (apt) installieren
###############################################################################
declare -A SEEN_PKG
sudo apt-get update            # einmal zu Beginn

for cfg in "${CONFIG_FILES[@]}"; do
  jq -r '(.shellExecutables? // {}) | to_entries[] | [.value.packageDeb // .value.package, .value.packagePip // empty] | @tsv
  ' "$cfg" | while IFS=$'\t' read -r apt_pkg pip_pkg; do
    for package in $apt_pkg; do
      [[ -z "$package" || -n "${SEEN_PKG[$package]:-}" ]] && continue
      SEEN_PKG["$package"]=1
      if ! dpkg -s "$package" &>/dev/null; then
        echo "Installiere: $package"
        if ! sudo apt-get install -y "$package"; then
          if [[ -n "$pip_pkg" ]] && command -v pip3 &>/dev/null; then
            echo "  apt fehlgeschlagen – versuche pip3 install $pip_pkg"
            sudo pip3 install "$pip_pkg"
          else
            echo "!!! $package nicht verfügbar !!!"
          fi
        fi
      fi
    done
  done
done

###############################################################################
# 4 – Java‑Executables herunterladen
###############################################################################
declare -A SEEN_JAR
for cfg in "${CONFIG_FILES[@]}"; do
  jq -r '.javaExecutables? // {} | to_entries[] | select(.value.url? and .value.path?) | [.value.url, .value.path] | @tsv
  ' "$cfg" | while IFS=$'\t' read -r url target; do
    [[ -n "${SEEN_JAR[$target]:-}" ]] && continue
    SEEN_JAR["$target"]=1
    if [[ ! -f "$target" ]]; then
      echo "Lade $url → $target ..."
      sudo curl -L -o "$target" "$url"
      sudo chmod +x "$target"
    else
      echo "$target bereits vorhanden"
    fi
  done
done

###############################################################################
# 5 – weitere install‑dependencies.sh in vendor/ ausführen
###############################################################################
# 5.1  Projekt‑Root ermitteln → steige solange nach oben, bis ein vendor/-Ordner
#      gefunden wird oder / erreicht ist.
ROOT="$SCRIPT_DIR"
while [[ "$ROOT" != "/" && ! -d "$ROOT/vendor" ]]; do
  ROOT="$(dirname "$ROOT")"
done

VENDOR_DIR="$ROOT/vendor"
if [[ -d "$VENDOR_DIR" ]]; then
  echo "Suche in $VENDOR_DIR nach weiteren install‑dependencies‑Skripten ..."
  while IFS= read -r other_script; do
    # Eigene Datei überspringen
    if [[ "$(realpath "$other_script")" != "$(realpath "$SCRIPT_DIR/install-dependencies.sh")" ]]; then
      echo "──────────────────────────────────────────────────────────────"
      echo "Starte abhängiges Skript: $other_script"
      bash "$other_script"
      echo "Fertig: $other_script"
      echo "──────────────────────────────────────────────────────────────"
    fi
  done < <(find "$VENDOR_DIR"  -maxdepth 5 -type f -name 'install-dependencies.sh')
fi

echo "Alle definierten Abhängigkeiten wurden geprüft und installiert."
