#!/bin/bash

# --- BLUEFIN AUTO-CONFIGURATION SCRIPT ---
# Written for C4PIN.org
# Author: KitsuneRhin @github
# License: Apache 2.0
# Version: 2.041626

## -- Variables -- ##
ostree_complete=false
needs_reboot==false

## -- Define Functions -- ##

display_info() {
    gum spin --spinner dot --title "Gathering system info..." -- sleep 2
    # - PC Info -
    sudo dmidecode -t system | grep --color=always -E "Manufacturer|Product Name|Serial Number" | sed 's/^[[:space:]]*//'

    # - CPU Model -
    echo -e "\n*--- CPU ---*"
    lscpu | grep --color=always -E "Model name:" | sed -E 's/\s+/ /g'

    # - Memory -
    echo -e "\n*--- RAM ---*"
    cat /proc/meminfo | numfmt --field 2 --from-unit=Ki --to=iec | sed 's/ kB//g' | grep --color=always -E "MemTotal:" | sed -E 's/\s+/ /g'

    # - Storage -
    echo -e "\n*--- Storage ---*"
    if lsblk | grep -q "mmcblk"; then 
        lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|mmcblk"
    fi
    if lsblk | grep -q "nvme0n1"; then 
        lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|nvme0n1"
    else
        echo "No NVMe drive found. Listing all disks..."
        for disk in sda sdb sdc; do
            if lsblk | grep -q "$disk"; then
                lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|$disk"
            fi
        done
    fi

    # - Battery info -
    echo -e "\n*--- Battery ---*"
    bat_found=false
    for i in {0..3}; do
        if upower -e | grep -q "BAT$i"; then
            upower -i /org/freedesktop/UPower/devices/battery_BAT"$i" | grep --color=always -E "capacity:|energy-full:|energy-full-design:|time to empty:" | sed 's/^[[:space:]]*//'
            bat_found=true
        fi
    done
    if ! $bat_found; then
        echo "Battery not found!"
    fi
}
# -------------------------------------------------------------------------------

auto_configure() {
    # --- Install Drop-in Override for Shutdown-on-Close ---
    gum spin --spinner dot --title "Applying power configuration" -- sleep 3
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee /etc/systemd/logind.conf.d/lid-switch.conf > /dev/null << EOF
[Login]
LidSwitchIgnoreInhibited=yes
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=suspend
EOF

    # --- Update Touchpad and Keyboard Settings ---
    gum spin --spinner dot --title "Applying input configuration..." -- sleep 3
    gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt','lv3:rwin']"
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
    gum spin --spinner dot --title "Reloading systemd services" -- sleep 2
    systemctl daemon-reload && systemctl daemon-reexec
}
# -------------------------------------------------------------------------------

ostree_cleanup() {
    if [ "$1" -eq 0 ]; then
        echo "Ostree already has an update queued."
        gum confirm "Cancel pending ostree operation?" && true || return 0
    fi
    gum spin --spinner dot --title "Cancelling..." -- rpm-ostree cancel  
    gum spin --spinner dot --title "Cancelling..." -- rpm-ostree cleanup -p
    ostree_complete=false
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
        choice_cmd=(bootc switch ghcr.io/ublue-os/bluefin-nvidia:stable --enforce-container-sigpolicy)
    elif [ "$1" == "rebase" ]; then
        ujust --rebase-helper
        ostree_complete=true
        return 0
    else
        echo "Invalid choice for run_ostree_keepalive: $1"
        return 1
    fi
  
  logfile="$(mktemp /tmp/rpm-ostree-install.XXXXXX.log)"

  # Start rpm-ostree in background
  "${choice_cmd[@]}" >"$logfile" 2>&1 &
  local pid=$!

  # Spinner runs in parallel but does NOT wait inside gum
  (
    while kill -0 "$pid" 2>/dev/null; do
      last=$(tail -n 50 "$logfile" | sed -n '/./p' | tail -n1)
      last=${last:-"(no output yet)"}
      echo "… $last"
      sleep 2
    done
  ) | gum spin --spinner dot --title "Building system image..." >/dev/null 2>&1 &

  local spinner_pid=$!

  # Wait for the real rpm-ostree process
  wait "$pid"
  local rc=$?

  # Stop spinner cleanly
  kill "$spinner_pid" 2>/dev/null || true
  wait "$spinner_pid" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    echo "System image ready."
    rm -f "$logfile"
    ostree_complete=true
    return 0
  else
    echo "Ostree update failed (exit code $rc). Last 200 lines:"
    sudo tail -n 200 "$logfile"
    ostree_cleanup 1
    return $rc
  fi
}
# -------------------------------------------------------------------------------

system_update() {
    if gum confirm "Does this device have an NVIDIA discrete graphics unit?"; then
            gum confirm "Rebase to Bluefin-NVIDIA image?" \
                && run_ostree_keepalive "nvidia" || return 0
    fi
    
    if gum confirm "Run system updates?"; then
        if ! $ostree_complete; then
            run_ostree_keepalive "update"
        else
            ostree_cleanup 0
        fi
        gum spin --spinner dot --title "Updating system flatpaks..." \
            -- bash -c "flatpak update -y"
        gum spin --spinner dot --title "Updating user flatpaks..." \
            -- bash -c "flatpak update --user -y"
    else echo "Skipping system updates..."
    fi
}
# -------------------------------------------------------------------------------

## -- Reboot Menu -- ##
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
            gum spin --spinner dot --title "System rebooting..." -- bash -c "systemctl reboot "${bios_flag}""
            ;;
        "Shutdown")
            gum spin --spinner dot --title "Shutting down..." -- bash -c "systemctl poweroff"
            ;;
        "Quit")
            echo "goodbye."
            exit 0
            ;;
        *)
            echo "Invalid entry. Exiting..."
            exit 1
            ;;
    esac
}
# -------------------------------------------------------------------------------

# --- Main Script -- #
if ! rpm-ostree status | grep -qE "idle|Idle"; then
    ostree_complete=true
    ostree_cleanup 0
fi

gum confirm "Display hardware information?" \
    && display_info || true

gum confirm "Run auto-configuration?" \
    && auto_configure || echo "Skipping auto-configuration..."

if gum confirm "Has the MOK (secure boot key) been enrolled?"; then
    echo "Skipping MOK enrollment..."
else
    gum spin --spinner dot -- ujust enroll-secure-boot-key
fi

system_update
reboot_prompt
