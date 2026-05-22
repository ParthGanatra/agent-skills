#!/usr/bin/env bash
# Resolve youtube-summary vault config and print it as KEY=VALUE lines.
# Run this first; parse the output to learn where to write the note.
#
# Resolution order (highest priority first):
#   1. environment variables: OBSIDIAN_VAULT_NAME / OBSIDIAN_VAULT_PATH / NOTES_SUBFOLDER
#   2. config file: $YT_SUMMARY_CONFIG, else ~/.config/youtube-summary/config.sh
# Exits non-zero with setup guidance if the vault isn't configured.

set -euo pipefail

CONFIG="${YT_SUMMARY_CONFIG:-$HOME/.config/youtube-summary/config.sh}"

# capture any env overrides before sourcing the file
_env_name="${OBSIDIAN_VAULT_NAME:-}"
_env_path="${OBSIDIAN_VAULT_PATH:-}"
_env_sub="${NOTES_SUBFOLDER:-}"

if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
fi

# env overrides win over file values
[[ -n "$_env_name" ]] && OBSIDIAN_VAULT_NAME="$_env_name"
[[ -n "$_env_path" ]] && OBSIDIAN_VAULT_PATH="$_env_path"
[[ -n "$_env_sub"  ]] && NOTES_SUBFOLDER="$_env_sub"

VAULT_NAME="${OBSIDIAN_VAULT_NAME:-}"
VAULT_PATH="${OBSIDIAN_VAULT_PATH:-}"
NOTES_SUBFOLDER="${NOTES_SUBFOLDER:-Learnings/youtube}"

if [[ -z "$VAULT_NAME" || -z "$VAULT_PATH" ]]; then
  # No Obsidian vault configured — fall back to PLAIN mode: the note is written
  # as Markdown into the current directory. Print a discoverable hint to stderr.
  cat >&2 <<EOF
info: no Obsidian vault configured — using plain mode (Markdown saved to the
current working directory). To save into your Obsidian vault instead, create
$CONFIG (template: config.example.sh next to SKILL.md) with OBSIDIAN_VAULT_NAME /
OBSIDIAN_VAULT_PATH / NOTES_SUBFOLDER, or set them as environment variables.
EOF
  echo "MODE=plain"
  echo "NOTES_DIR=$PWD"
  exit 0
fi

# expand a leading ~ in the path if present
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
NOTES_DIR="$VAULT_PATH/$NOTES_SUBFOLDER"

if [[ ! -d "$VAULT_PATH" ]]; then
  echo "warning: vault path does not exist: $VAULT_PATH" >&2
fi

echo "MODE=obsidian"
echo "VAULT_NAME=$VAULT_NAME"
echo "VAULT_PATH=$VAULT_PATH"
echo "NOTES_SUBFOLDER=$NOTES_SUBFOLDER"
echo "NOTES_DIR=$NOTES_DIR"
