#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/executables.json"
JQ=$(which jq)

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  exit 1
fi

if [ -z "$JQ" ]; then
  echo "jq ist erforderlich. Installiere es mit: sudo apt install jq"
  exit 1
fi

echo "Lese Konfiguration: $CONFIG_FILE"

# ShellExecutables – Pakete installieren
jq -r '.shellExecutables | to_entries[] | select(.value.package) | .value.package' "$CONFIG_FILE" | while read -r package; do
  if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "Installiere fehlendes Paket: $package"
    sudo apt-get update
    sudo apt-get install -y "$package"
  else
    echo "$package ist bereits installiert"
  fi
done

# JavaExecutables – Dateien herunterladen
jq -r '.javaExecutables | to_entries[] | select(.value.url and .value.path) | [.value.url, .value.path] | @tsv' "$CONFIG_FILE" | while IFS=$'\t' read -r url target; do
  if [ ! -f "$target" ]; then
    echo "Lade $url nach $target ..."
    sudo curl -L -o "$target" "$url"
    sudo chmod +x "$target"
    echo "Heruntergeladen: $target"
  else
    echo "JAR-Datei bereits vorhanden: $target"
  fi
done

echo "Alle definierten Abhängigkeiten wurden geprüft und installiert."