#!/bin/bash

## --- AUTO-CREATION: SECOND-LANGUAGE USER ---
# Written for C4PIN.org
# Author: KitsuneRhin @github
# License: Apache 2.0

set -euo pipefail

## -- Language Codes -- ##
british="en_GB.UTF-8"
mexican="es_MX.UTF-8"
quebec="fr_CA.UTF-8"
syrian="ar_SY.UTF-8"
ukrainian="uk_UA.UTF-8"
russian="ru_RU.UTF-8"
colombian="es_CO.UTF-8"

## -- Internal Variables -- ##
VERSION="07/13/26"
USERNAME=""
PASSWD=""
NEW_LANG=""
reboot_needed=false

warn()  { gum style --foreground "#ffaf00" --bold "⚠ $*"; }
err()   { gum style --foreground "#ff5555" --bold "✗ $*"; }
ok()    { gum style --foreground "#50fa7b" "✓ $*"; }
info()  { gum style --foreground "#8be9fd" "  $*"; }

ostree_cleanup() {
    if [ "$1" -eq 0 ]; then
        warn "Ostree already has an update queued."
        gum confirm "Cancel pending ostree operation?" && true || { info "Reboot PC to finish pending operation before running Language Script."; return 0; }
    fi
    gum spin --spinner dot --title "Cleaning up..." -- rpm-ostree cancel
    gum spin --spinner dot --title "Cleaning up..." -- rpm-ostree cleanup -p
    reboot_needed=false
    ok "Ostree cleared"
}

run_layer_keepalive() {
  local langpack="$1"
  local logfile
  logfile="$(mktemp /tmp/rpm-ostree-install.XXXXXX.log)"

  # Start rpm-ostree in background
  ( sudo rpm-ostree install -y "glibc-langpack-${langpack}" >"$logfile" 2>&1; echo $? >"$logfile.rc" ) &
local pid=$!

    gum spin --spinner dot --title "Checking for updates..." -- \
        bash -c "while ! grep -qiE 'Resolving dependencies|No upgrade|already installed' '$logfile' 2>/dev/null; do sleep 1; done"

    if ! grep -qiE "already installed|already present" "$logfile"; then
        gum spin --spinner dot --title "Layering language pack ${langpack}..." -- \
          bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    fi

wait "$pid" 2>/dev/null
local rc
rc=$(cat "$logfile.rc" 2>/dev/null)
rc=${rc:-1}

  if [ "$rc" -eq 0 ]; then
    echo "Layering completed successfully."
    reboot_needed=true
    rm -f "$logfile"
    return 0
  else
    err "Ostree update failed!" && info "(exit code $rc)."
    if gum confirm "Display logs?"; then tail -n 200 "$logfile"; fi
    rm -f "$logfile.rc"
    ostree_cleanup 1
    return $rc
  fi
}


run_lang() {
## -- Part 1 -- ##
# Create Profile and Layer in Language Pack (user-specific)

  echo "Creating user profile '$USERNAME'..."
  sudo useradd -m "$USERNAME"

  echo "Setting user password..."
  echo "$USERNAME:$PASSWD" | sudo chpasswd

  echo "Adding user to admin group..."
  sudo usermod -aG wheel "$USERNAME"

  echo "Creating language configuration files..."
  sudo mkdir -p /var/lib/AccountsService/users
  sudo tee /var/lib/AccountsService/users/"$USERNAME" > /dev/null <<EOF
[User]
Language=$NEW_LANG
EOF
  sudo chown root:root /var/lib/AccountsService/users/"$USERNAME"
  sudo chmod 644 /var/lib/AccountsService/users/"$USERNAME"

  langpack=$(echo "$NEW_LANG" | cut -d_ -f1 | cut -d. -f1)
  if ! run_layer_keepalive "$langpack"; then
    gum confirm "Layering failed. Continue anyway?" || { echo "Aborting."; exit 1; }
    reboot_needed=false
  fi

## -- Part 2 -- ##
# Configure Local Language Options

  gum spin --spinner dot --title "Updating program locales..." -- sleep 3
  sudo -u "$USERNAME" -H flatpak config --user --set languages "en;${langpack}"
  sudo -u "$USERNAME" -H flatpak override --user --env=LANG="$NEW_LANG" --env=LC_ALL="$NEW_LANG"
  sudo flatpak config --system --set languages "en;${langpack}"
  gum spin --spinner dot --title "Updating user flatpaks for language support..." -- sudo -u "$USERNAME" -H flatpak update --user -y
  gum spin --spinner dot --title "Updating system flatpaks for language support (this may take a while)..." -- sudo flatpak update --system -y
  echo "Locales updated."
}

## -- Language Selection Menu -- ##
select_lang() {
  LANG_OPTIONS=(
    "English (UK):british"
    "Spanish (Mexico):mexican"
    "Spanish (Colombia):colombian"
    "French (Canada):quebec"
    "Arabic (Syria):syrian"
    "Ukrainian:ukrainian"
    "Russian:russian"
  )

  echo "Select a language:"
  selection=$(printf "%s\n" "${LANG_OPTIONS[@]}" | cut -d: -f1 | gum choose)
  [ -z "$selection" ] && { err "No language selected. Exiting."; exit 1; }
  varname=$(printf "%s\n" "${LANG_OPTIONS[@]}" | grep "^$selection:" | cut -d: -f2)
  NEW_LANG=${!varname}
}

## -- Reboot Menu -- ##
reboot_prompt() {
  choice=$(printf "%s\n" \
    "Reboot now" \
    "Reboot later (exit)" \
    | gum choose --height=8 --cursor=">")

  case "$choice" in
    "Reboot now")
      if gum confirm "Reboot now?"; then
        gum spin --spinner dot --title "Rebooting..." -- bash -c "sudo systemctl reboot"
        exit 0
      else
        echo "Reboot canceled, exiting."
        exit 0
      fi
      ;;
    "Reboot later (exit)")
      echo "Restart sequence canceled."
      exit 0
      ;;
    *)
      echo "No selection! Exiting..."
      exit 1
      ;;
  esac
}

## -- Main -- ##
echo -e "\n-- Second-Language Profile Creator --\n"
echo "Version $VERSION"

if ! rpm-ostree status | grep -qE "idle|upgraded|removed|added"; then
    reboot_needed=true
    ostree_cleanup 0
    if $reboot_needed; then
      reboot_prompt
    fi
fi

select_lang
# User Inputs
USERNAME=$(gum input --placeholder "enter new username...")
[ -z "$USERNAME" ] && { err "No username entered. Exiting."; exit 1; }
match=0
while [ "$match" -eq 0 ]; do
  var1=$(gum input --placeholder "enter password for $USERNAME...")
  var2=$(gum input --placeholder "re-type password...")
  if [ "$var1" == "$var2" ]; then
    match=1
    PASSWD=${var1}
  else
    echo -e "\n Entries do not match. Please try again."
  fi
done
# --
run_lang

echo ""
if $reboot_needed; then
  warn "System requires a reboot to finish configuration."
fi
reboot_prompt
exit 0
