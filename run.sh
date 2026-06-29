#!/bin/bash

# --- BLUEFIN AUTO-CONFIGURATION SCRIPT ---
# Written for C4PIN.org
# Author: Devon Buecher | KitsuneRhin@github
# License: Apache 2.0
# Version: 2.062926

## -- Variables & Helpers -- ##
ostree_complete=false
rebase_complete=false
needs_reboot=false

warn()  { gum style --foreground "#ffd700" --bold "⚠ $*"; }
err()   { gum style --foreground "#ff5555" --bold "✗ $*"; }
ok()    { gum style --foreground "#00ff00" "✓ $*"; }
info()  { gum style --foreground "#00aaff" "  $*"; }
die()   { err "$*"; exit 1; }

## -- Define Functions -- ##

display_info() {
    echo ""
    gum spin --spinner dot --title "Gathering system info..." -- sleep 2
    # - PC Info -
    info "-- System --"
    sudo dmidecode -t system | grep --color=always -E "Manufacturer|Product Name|Serial Number" | sed 's/^[[:space:]]*//'
	echo ""
	
    # - CPU Model -
    info "-- CPU --"
    lscpu | grep --color=always -E "Model name:" | sed -E 's/\s+/ /g'
	echo ""
	
    # - Memory -
    info "-- RAM --"
    cat /proc/meminfo | numfmt --field 2 --from-unit=Ki --to=iec | sed 's/ kB//g' | grep --color=always -E "MemTotal:" | sed -E 's/\s+/ /g'
	echo ""
	
    # - Storage -
    info "-- Storage --"
    if lsblk | grep -q "mmcblk"; then 
        lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|mmcblk"
    fi
    if lsblk | grep -q "nvme0n1"; then 
        lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|nvme0n1"
    else
        warn "No NVMe drive found. Listing all disks..."
        for disk in sda sdb sdc; do
            if lsblk | grep -q "$disk"; then
                lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|$disk"
            fi
        done
    fi
	echo ""

    # - GPU Info -
    info "-- GPU --"
    lspci | grep --color=always -E "VGA|3D|Display" | sed 's/^[[:space:]]*//'
	echo ""

    # - Battery info -
    info "-- Battery --"
    bat_found=false
    for i in {0..3}; do
        if upower -e | grep -q "BAT$i"; then
            upower -i /org/freedesktop/UPower/devices/battery_BAT"$i" | grep --color=always -E "capacity:|energy-full:|energy-full-design:|time to empty:" | sed 's/^[[:space:]]*//'
            bat_found=true
        fi
    done
    if ! $bat_found; then
        err "Battery not found!"
    fi
    echo ""
}
# -------------------------------------------------------------------------------

install_extension() {
    [ -n "$1" ] || { err "install_extension called with no extension ID"; return 1; }

    local GNOME_VER
    GNOME_VER=$(gnome-shell --version | grep -oP '\d+' | head -1)
    local EXT_ID=$1
    local INFO DOWNLOAD_URL UUID

    INFO=$(curl -sf "https://extensions.gnome.org/extension-info/?pk=${EXT_ID}&shell_version=${GNOME_VER}")
    if [ -z "$INFO" ]; then
        err "Could not reach extensions.gnome.org for extension ID ${EXT_ID}"
        return 1
    fi

    DOWNLOAD_URL=$(echo "$INFO" | jq -r '.download_url')
    UUID=$(echo "$INFO" | jq -r '.uuid')

    if [ "$DOWNLOAD_URL" == "null" ] || [ "$UUID" == "null" ]; then
        err "Could not find extension info for ID ${EXT_ID} (GNOME ${GNOME_VER})"
        return 1
    fi

    gum spin --title "Downloading extension ${UUID}..." -- \
        curl -sfL "https://extensions.gnome.org${DOWNLOAD_URL}" -o "/tmp/${UUID}.zip"

    if ! gum spin --title "Installing extension ${UUID}..." -- \
            gnome-extensions install "/tmp/${UUID}.zip" --force; then
        err "Failed to install extension ${UUID}"
        rm -f "/tmp/${UUID}.zip"
        return 1
    fi

    sleep 1
    gnome-extensions enable "$UUID"

    rm -f "/tmp/${UUID}.zip"
}
# -------------------------------------------------------------------------------

auto_configure() {
    # --- Install Drop-in Override for Shutdown-on-Close ---
    gum spin --spinner dot --title "Applying power configuration" -- sleep 3
    gsettings set org.gnome.desktop.session idle-delay 600 # 10 min
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim true
    gsettings set org.gnome.settings-daemon.plugins.power idle-brightness 20
    gsettings set org.gnome.desktop.screensaver lock-enabled true
    gsettings set org.gnome.desktop.screensaver lock-delay 30
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 1800 # 30 min
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 900 # 15 min
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'suspend'
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee /etc/systemd/logind.conf.d/lid-switch.conf > /dev/null << EOF
[Login]
LidSwitchIgnoreInhibited=yes
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=suspend
EOF
ok "Power Config"

    # --- Update Touchpad and Keyboard Settings ---
    gum spin --spinner dot --title "Applying input configuration..." -- sleep 3
    gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt','lv3:rwin']"
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
    gum spin --spinner dot --title "Reloading systemd services" -- sleep 2
    systemctl daemon-reload && systemctl daemon-reexec
    ok "Input Config"

    # --- Install Extensions ---
    install_extension 4269 || die "Failed to install App Grid extension."
        ok "App Grid"
    install_extension 2087 || die "Failed to install Desktop Icons extension."
        ok "Desktop Icons"
}
# -------------------------------------------------------------------------------

ostree_cleanup() {
    if [ "$1" -eq 0 ]; then
        warn "Ostree already has an update queued."
        gum confirm "Cancel pending ostree operation?" && true || { needs_reboot=true; return 0; }
    fi
    gum spin --spinner dot --title "Cleaning up..." -- rpm-ostree cancel  
    gum spin --spinner dot --title "Cleaning up..." -- rpm-ostree cleanup -p
    ostree_complete=false
    ok "Ostree cleared"
}
# -------------------------------------------------------------------------------

nvidia_rebase() {
    local logfile
    local -a choice_cmd
    logfile="$(mktemp /tmp/rpm-ostree-install.XXXXXX.log)"
    choice_cmd=(bootc switch ghcr.io/ublue-os/bluefin-nvidia-open:stable --enforce-container-sigpolicy)

    # Start rpm-ostree in background
    ( "${choice_cmd[@]}" >"$logfile" 2>&1; echo $? >"$logfile.rc" ) &
    local pid=$!

    # Phase 1: just wait for rpm-ostree to begin working
    gum spin --spinner dot --title "Connecting to image server..." -- \
        bash -c "while ! grep -qiE 'layers already present|already at latest' '$logfile' 2>/dev/null; do sleep 1; done"

    # Phase 2: run unless there's nothing to do
    if ! grep -qiE "already at latest" "$logfile"; then
        gum spin --spinner dot --title "Fetching NVIDIA image..." -- \
            bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    fi

    wait "$pid" 2>/dev/null
    local rc
    rc=$(cat "$logfile.rc" 2>/dev/null)
    rc=${rc:-1}

    if [ "$rc" -eq 0 ]; then
        if grep -qiE "already at latest" "$logfile"; then
            ok "System image is already up to date."
            rm -f "$logfile" "$logfile.rc"
            ostree_complete=false
            return 0
        fi
        ok "System image ready."
        rm -f "$logfile" "$logfile.rc"
        ostree_complete=true
        needs_reboot=true
        return 0
    else
        err "Ostree update failed!" && info "(exit code $rc)."
        if gum confirm "Display logs?"; then
            tail -n 200 "$logfile"
        fi
        rm -f "$logfile" "$logfile.rc"
        ostree_cleanup 1
        return $rc
    fi
}
# -------------------------------------------------------------------------------

run_ostree_keepalive() {
    if $ostree_complete; then
        ostree_cleanup 0
    fi
   local logfile
   local -a choice_cmd
    if [ "$1" == "update" ]; then
        choice_cmd=(rpm-ostree upgrade)
    elif [ "$1" == "nvidia" ]; then
        nvidia_rebase
        rebase_complete=true
        return $?
    elif [ "$1" == "rebase" ]; then
        ujust --rebase-helper
        ostree_complete=true
        return 0
    else
        err "Invalid choice for run_ostree_keepalive: $1"
        return 1
    fi

    logfile="$(mktemp /tmp/rpm-ostree-install.XXXXXX.log)"

    # Start rpm-ostree in background
    ( "${choice_cmd[@]}" >"$logfile" 2>&1; echo $? >"$logfile.rc" ) &
    local pid=$!

    # Phase 1: just wait for rpm-ostree to begin working
    gum spin --spinner dot --title "Connecting to image server..." -- \
        bash -c "while ! grep -qiE 'Pulling manifest|No upgrade available|already up to date' '$logfile' 2>/dev/null; do sleep 2; done"

    # Phase 2: run unless there's nothing to do
    if ! grep -qiE "No upgrade available|already up to date" "$logfile"; then
        gum spin --spinner dot --title "Building system image..." -- \
            bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    fi

    wait "$pid" 2>/dev/null
    local rc
    rc=$(cat "$logfile.rc" 2>/dev/null)
    rc=${rc:-1}

    if [ "$rc" -eq 0 ]; then
        if grep -qiE "no upgrade available|already up to date|already at latest" "$logfile"; then
            ok "System image is already up to date."
            rm -f "$logfile" "$logfile.rc"
            ostree_complete=false
            return 0
        fi
        ok "System image ready."
        rm -f "$logfile" "$logfile.rc"
        ostree_complete=true
        needs_reboot=true
        return 0
    else
        err "Ostree update failed!" && info "(exit code $rc)."
        if gum confirm "Display logs?"; then
            tail -n 200 "$logfile"
        fi
        rm -f "$logfile" "$logfile.rc"
        ostree_cleanup 1
        return $rc
    fi
}
# -------------------------------------------------------------------------------

firmware_update() {
    local logfile
    logfile="$(mktemp /tmp/fwupd-install.XXXXXX.log)"

    gum spin --spinner dot --title "Refreshing firmware metadata..." -- \
        bash -c "fwupdmgr refresh --force -y >'$logfile' 2>&1"

    if ! fwupdmgr get-updates >>"$logfile" 2>&1 || grep -qiE "No updates available|Devices with no available firmware updates" "$logfile"; then
        ok "Firmware is already up to date"
        rm -f "$logfile"
        return 0
    fi

    gum spin --spinner dot --title "Installing firmware updates..." -- \
        bash -c "fwupdmgr update -y >>'$logfile' 2>&1"
    local rc=$?

    if [ "$rc" -eq 0 ]; then
        ok "Firmware updated."
        needs_reboot=true
    else
        warn "Firmware update finished with warnings (exit code $rc)."
        if gum confirm "Display logs?"; then tail -n 200 "$logfile"; fi
    fi
    rm -f "$logfile"
}
# -------------------------------------------------------------------------------

system_update() {
    if lspci | grep -iE "VGA|3D|Display" | grep -qi nvidia; then
        gum confirm "NVIDIA GPU detected. Rebase to Bluefin-NVIDIA image?" \
            && run_ostree_keepalive "nvidia" || true
    fi

    if gum confirm "Run system updates?"; then
        if ! $rebase_complete; then
            if ! $ostree_complete; then
                run_ostree_keepalive "update"
            else
                ostree_cleanup 0
            fi
        else
            info "Rebase already staged, skipping ostree update..."
        fi
        gum spin --spinner dot --title "Updating system flatpaks..." \
            -- bash -c "flatpak update --system -y"
        gum spin --spinner dot --title "Updating user flatpaks..." \
            -- bash -c "flatpak update --user -y"
        ok "Flatpaks updated."

        firmware_update

    else echo "Skipping system updates..."
    fi
}
# -------------------------------------------------------------------------------

mok_util() {
    echo ""
    gum spin --spinner dot --title "Working..." -- sleep 2
        mok_output=$(ujust enroll-secure-boot-key 2>&1)
        if echo "$mok_output" | grep -qE "SKIP|already enrolled"; then
            ok "Secure Boot Key is already registered."
        
        else 
            needs_reboot=true
            warn "At next reboot, ensure that secure boot is enabled in the BIOS."
            echo -e "\nThe mokutil UEFI menu will be displayed upon boot."
            info "Select 'Enroll MOK', then enter < universalblue > as the password."
        fi
}
# -------------------------------------------------------------------------------

install_flatpaks() {
	gum spin --spinner dot --title "Installing LibreOffice..." -- flatpak install app/org.libreoffice.LibreOffice/x86_64/stable --noninteractive --assumeyes
	gum spin --spinner dot --title "Configuring..." -- sleep 5
	rm -f "$HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"
	mkdir -p "$HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/"
	cp -f ./registrymodifications.xcu "$HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"

	if [ ! -f "$HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu" ]; then
		warn "config file did not transfer"
	else
		ok "LibreOffice ready"
	fi
}
# -------------------------------------------------------------------------------

reboot_prompt() {
    choice=$(printf "%s\n" \
        "Reboot" \
        "Shutdown" \
        "Quit" \
        | gum choose --height=8 --cursor=">")
    
    local _flag
    case "$choice" in
        "Reboot")
            gum confirm "Reboot to BIOS?" && _flag="--firmware-setup" || true
            gum spin --spinner dot --title "System rebooting..." -- bash -c "systemctl reboot "${_flag}""
            ;;
        "Shutdown")
            gum spin --spinner dot --title "Shutting down..." -- bash -c "systemctl poweroff"
            ;;
        "Quit")
            echo "Goodbye."
            exit 0
            ;;
        *)
            err "Invalid entry. Exiting..."
            exit 1
            ;;
    esac
}
# -------------------------------------------------------------------------------

# --- Main Script -- #
gum spin --spinner dot --title "Initializing tool environment..." -- sleep 1
if [[ "$1" != "--inhibited" ]]; then
    export DBUS_SESSION_BUS_ADDRESS
    exec systemd-inhibit --what=sleep:idle \
                         --who="C4PIN Config Tool" \
                         --why="Running auto-configuration" \
                         --mode=block \
                         bash "$0" --inhibited
fi

clean_gsettings_val() {
    local v="$1"
    v="${v#uint32 }"
    v="${v#\'}"
    v="${v%\'}"
    echo "$v"
}

orig_idle_delay=$(clean_gsettings_val "$(gsettings get org.gnome.desktop.session idle-delay)")
orig_ac_type=$(clean_gsettings_val "$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type)")
orig_battery_type=$(clean_gsettings_val "$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type)")

restore_idle_settings() {
    gsettings set org.gnome.desktop.session idle-delay "$orig_idle_delay"
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "$orig_ac_type"
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "$orig_battery_type"
}
trap restore_idle_settings EXIT

gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'

command -v jq >/dev/null || die "jq is required but not installed"

echo ""
info "Bluefin Triage and Configuration Tool"

mode=$(printf "%s\n" \
    "Full Configuration" \
    "Hardware Info Only" \
    "Quit" \
    | gum choose --height=8 --cursor=">")

case "$mode" in
    "Hardware Info Only")
        display_info
        echo ""
        ok "-- Done. --"
        exit 0
        ;;
    "Quit")
        echo "Goodbye."
        exit 0
        ;;
    "Full Configuration")
        : # fall through to the rest of the script below
        ;;
    *)
        err "Invalid entry. Exiting..."
        exit 1
        ;;
esac

if ! rpm-ostree status | grep -qE "idle|upgraded|removed|added"; then
    ostree_complete=true
    ostree_cleanup 0
fi

gum confirm "Run auto-configuration?" \
    && auto_configure || echo "Skipping auto-configuration..."

mok_util
system_update

gum confirm "Install new Flatpaks? (LibreOffice)" \
    && install_flatpaks || echo "Skipping new Flatpak installation..."

user_home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
gum confirm "Push user guide to desktop?" \
    && cp ./Bluefin\ User\ Guide*.pdf "$user_home/Desktop/" || echo "Skipping user guide..."

echo ""
ok "-- Script complete. --"
echo ""
if $needs_reboot; then 
    warn "Logs indicate the system requires a reboot."
fi
reboot_prompt