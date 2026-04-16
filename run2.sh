#!/bin/bash

# --- BLUEFIN AUTO-CONFIGURATION SCRIPT ---
# Written for C4PIN.org
# Author: KitsuneRhin @github
# License: Apache 2.0
# Version: 2.041626

## -- Define Variables -- ##
ostree_complete=false

## -- Define Functions -- ##

display_info() {
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
    if lsblk | grep -q "msblk"; then 
        lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|msblk"
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
    for i in {0...3}; do
        if upower -e | grep -q "BAT$i"; then
            upower -i /org/freedesktop/UPower/devices/battery_BAT$i | grep --color=always -E "capacity:|energy-full:|energy-full-design:|time to empty:" | sed 's/^[[:space:]]*//'
            bat_found=true
        fi
    done
    if ! $bat_found; then
        echo "Battery not found!"
    fi
}

auto_configure() {
    echo "Starting auto-configuration process..."
    # --- Install Override for Shutdown-on-Close ---
    gum spin --spinnder dot --title "Applying power configuration" -- sleep 3
    cat >> /etc/systemd/logind.conf<< EOF
[Login]
lidswitch-ignore-inhibited=yes
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=suspend
EOF

    gum spin --spinner dot --title "Applying input configuration..." -- sleep 3
    gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt','lv3:rwin']"
    gsettings set org.gnome.desktop.periherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'

    gum spin --spinner dot --title "Reloading systemd services" -- sleep 2
    systemctl daemon-reload && systemctl daemon-reexec
    echo "Done."
}

new_image() {
    gum confirm "Cancel pending ostree operation?" && rpm-ostree cleanup -p || return 0
}

run_ostree_keepalive() {
    if $ostree_complete; then
        echo "Ostree already has an update queued."
    fi
  local logfile
  local choice
  if [ "$1" == "update" ]; then
        choice="rpm-ostree upgrade"
  elif [ "$1" == "nvidia" ]; then
        choice="sudo bootc switch ghcr.io/ublue-os/bluefin-nvidia:stable --enforce-container-sigpolicy"
  elif [ "$1" == "rebase" ]; then
        choice="ujust --rebase-helper"
  else
    echo "Invalid choice for run_ostree_keepalive: $1"
    return 1
  fi
  
  logfile="$(mktemp /tmp/rpm-ostree-install.XXXXXX.log)"

  # Start rpm-ostree in background
  sudo "$choice" >"$logfile" 2>&1 &
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
    echo "System image built successfully."
    rm -f "$logfile"
    ostree_complete=true
    return 0
  else
    echo "Ostree update failed (exit code $rc). Last 200 lines:"
    sudo tail -n 200 "$logfile"
    new_image
    return $rc
  fi
}

nvidia_rebase() {
    if [ gum confirm "Does this device have an NVIDIA discrete graphics unit?" ]; then
            gum confirm "Rebase to Bluefin-NVIDIA image?" \
                && run_ostree_keepalive "nvidia" || echo "Cancelling NVIDIA rebase..." && return 0
    gum spin --spinner dot --title "Updating system flatpaks..." \
        -- if flatpack remotes | grep -q system; then
                flatpak update -y
           fi
    gum spin --spinner dot --title "Updating user flatpacks..." \
        -- if flatpack remotes | grep -q user; then
                flatpak update --user -y
           fi
    fi
}

# --- Main Script -- #
gum confirm "Display hardware information?" \
    && display_info || tee >> /dev/null
gum confirm "Run auto-configuration?" \
    && auto_configure || tee >> /dev/null
gum confirm "Has the MOK (secure boot key) been enrolled?" \
    && echo "Skipping MOK enrollment..." || ujust enroll-secure-boot-key && echo "Key ready. Please reboot with Secure Boot ENABLED to finish install."
nvidia_rebase
if ! $ostree_complete; then
    gum confirm "Run system updates?" \
        && ujust --update || echo "Skipping system updates..."
