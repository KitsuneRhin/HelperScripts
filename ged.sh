#!/bin/bash

# --- BURLINGTON GED PROGRAM SETUP SCRIPT ---
# Written for C4PIN.org
# Author: Devon Buecher | KitsuneRhin@github
# License: Apache 2.0
# Version: 2.051826

## -- Variables & Helpers -- ##
USER_NAME="GEDstudent"
USER_PASS="GEDandBeyond!"
USER_UID=""
USER_HOME=""
USER_DBUS=""

ADMIN_NAME="GEDadmin"
ADMIN_PASS="2DsBLGtpp3"
ADMIN_UID=""
ADMIN_HOME=""
ADMIN_DBUS=""

warn()  { gum style --foreground "#ffd700" --bold "⚠ $*"; }
err()   { gum style --foreground "#ff5555" --bold "✗ $*"; }
ok()    { gum style --foreground "#00ff00" "✓ $*"; }
info()  { gum style --foreground "#00aaff" "  $*"; }

## -- Define Functions -- ##

modify_users() {
    gum spin --title "Creating student user..." -- sudo useradd -m "$USER_NAME"
    echo "$USER_NAME:$USER_PASS" | sudo chpasswd
    gum spin --title "Renaming admin user..." -- sudo usermod -l "$ADMIN_NAME" "$USER"
    echo "$ADMIN_NAME:$ADMIN_PASS" | sudo chpasswd
    ok "Users modified successfully."

    gum spin --title "Populating user properties..." -- sleep 2
    USER_UID=$(id -u "$USER_NAME")
    USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
    USER_DBUS="unix:path=/run/user/${USER_UID}/bus"
    ADMIN_UID=$(id -u "$ADMIN_NAME")
    ADMIN_HOME=$(getent passwd "$ADMIN_NAME" | cut -d: -f6)
    ADMIN_DBUS="unix:path=/run/user/${ADMIN_UID}/bus"
    ok "User properties populated."
}

install_flatpaks() {
    gum spin --title "Installing Zoom..." -- flatpak install -y --system flathub us.zoom.Zoom
    gum spin --title "Installing Chrome..." -- flatpak install -y --system flathub com.google.Chrome
    ok "Flatpaks installed successfully."
}

install_extension() {
    local GNOME_VER
    GNOME_VER=$(gnome-shell --version | grep -oP '\d+' | head -1)
    local EXT_ID=$1
    local INFO DOWNLOAD_URL UUID

    INFO=$(curl -sf "https://extensions.gnome.org/extension-info/?pk=${EXT_ID}&shell_version=${GNOME_VER}")
    DOWNLOAD_URL=$(echo "$INFO" | jq -r '.download_url')
    UUID=$(echo "$INFO" | jq -r '.uuid')

    gum spin --title "Downloading extension ${UUID}..." -- \
        curl -sfL "https://extensions.gnome.org${DOWNLOAD_URL}" -o "/tmp/${UUID}.zip"

    gum spin --title "Installing extension ${UUID}..." -- \
        sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$USER_DBUS" \
            gnome-extensions install "/tmp/${UUID}.zip" --force

    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$USER_DBUS" \
        gnome-extensions enable "$UUID"

    rm -f "/tmp/${UUID}.zip"
    ok "Extension ${UUID} installed successfully."
}

configure_environment() {
    local MIME_FILE

    MIME_FILE="$USER_HOME/.config/mimeapps.list"
    mkdir -p "$USER_HOME/.config"
    sed -i '/x-scheme-handler\/http\|x-scheme-handler\/https\|text\/html\|application\/xhtml/d' "$MIME_FILE" 2>/dev/null || true
    cat >> "$MIME_FILE" <<'EOF'
[Default Applications]
x-scheme-handler/http=com.google.Chrome.desktop
x-scheme-handler/https=com.google.Chrome.desktop
text/html=com.google.Chrome.desktop
application/xhtml+xml=com.google.Chrome.desktop
EOF
    chown "$USER_NAME:$USER_NAME" "$MIME_FILE"
    ok "Student default browser set."

    MIME_FILE="$ADMIN_HOME/.config/mimeapps.list"
    mkdir -p "$ADMIN_HOME/.config"
    sed -i '/x-scheme-handler\/http\|x-scheme-handler\/https\|text\/html\|application\/xhtml/d' "$MIME_FILE" 2>/dev/null || true
    cat >> "$MIME_FILE" <<'EOF'
[Default Applications]
x-scheme-handler/http=com.google.Chrome.desktop
x-scheme-handler/https=com.google.Chrome.desktop
text/html=com.google.Chrome.desktop
application/xhtml+xml=com.google.Chrome.desktop
EOF
    chown "$ADMIN_NAME:$ADMIN_NAME" "$MIME_FILE"
    ok "Admin default browser set."
}

## -- Main -- ##
modify_users
install_flatpaks
install_extension 4269 # Alphabetical App Grid
install_extension 2087 # Desktop Icons (DING)
configure_environment
