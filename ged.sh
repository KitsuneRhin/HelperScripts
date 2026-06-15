#!/bin/bash

# --- BURLINGTON GED PROGRAM SETUP SCRIPT ---
# Written for C4PIN.org
# Author: Devon Buecher | KitsuneRhin@github
# License: Apache 2.0
# Version: 1.061526

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
die()   { err "$*"; exit 1; }

## -- Define Functions -- ##

modify_users() {
    gum spin --title "Creating student user..." -- sleep 2
        sudo useradd -m "$USER_NAME"
        echo "$USER_NAME:$USER_PASS" | sudo chpasswd || die "Failed to set student user password."
    
    gum spin --title "Configuring admin user..." -- sleep 2
        echo "$USER:$ADMIN_PASS" | sudo chpasswd || die "Failed to set admin user password."
        sudo usermod -l "$ADMIN_NAME" "$USER" || die "Failed to modify admin user."
    ok "Users modified"

    gum spin --title "Populating user properties..." -- sleep 2
        USER_UID=$(id -u "$USER_NAME")
        USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
        USER_DBUS="unix:path=/run/user/${USER_UID}/bus"
        
        ADMIN_UID=$(id -u "$ADMIN_NAME")
        ADMIN_HOME=$(getent passwd "$ADMIN_NAME" | cut -d: -f6)
        ADMIN_DBUS="unix:path=/run/user/${ADMIN_UID}/bus"
}

install_flatpaks() {
    gum spin --title "Installing Zoom..." -- flatpak install -y --system flathub us.zoom.Zoom || die "Failed to install Zoom."
    gum spin --title "Installing Chrome..." -- flatpak install -y --system flathub com.google.Chrome || die "Failed to install Chrome."
    ok "Flatpaks"
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
echo ""
info "--- BURLINGTON GED PROGRAM SETUP SCRIPT ---"

modify_users
install_flatpaks
configure_environment
ok "Script Complete."
echo ""
warn "The run.sh script must be run on the new user to complete the setup."
