# youtube-summary configuration
#
# Copy this file to ~/.config/youtube-summary/config.sh and edit the values,
# then the skill knows where to write notes. (Env vars of the same name
# override these, e.g. for one-off runs.)
#
#   mkdir -p ~/.config/youtube-summary
#   cp config.example.sh ~/.config/youtube-summary/config.sh
#   $EDITOR ~/.config/youtube-summary/config.sh

# The Obsidian vault NAME (as shown in Obsidian; used for the obsidian:// open URI).
OBSIDIAN_VAULT_NAME="MyVault"

# Absolute path to that vault's root folder on disk.
OBSIDIAN_VAULT_PATH="$HOME/obsidian/MyVault"

# Folder for the notes, RELATIVE to the vault root. Created if missing.
NOTES_SUBFOLDER="Learnings/youtube"
