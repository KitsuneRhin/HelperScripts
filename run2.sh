#!/bin/bash

# --- BLUEFIN AUTO-CONFIGURATION SCRIPT ---
# Written for C4PIN.org
# Author: KitsuneRhin @github
# License: Apache 2.0
# Version: 2.041626

## -- Variables -- ##
ostree_complete=false

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

ostree_cleanup() {
    if $1 == 0; then
        echo "Ostree already has an update queued."
        gum confirm "Cancel pending ostree operation?" && tee >> /dev/null || return 0
    fi
    gum spin --spinner dot --title "Cancelling ostree operation..." -- rpm-ostree cancel && rpm-ostree cleanup -p
    ostree_complete=false
}

run_ostree_keepalive() {
    if $ostree_complete; then
        ostree_cleanup 0
    fi
  local logfile
  local choice
  if [ "$1" == "update" ]; then
        choice="rpm-ostree upgrade"
  elif [ "$1" == "nvidia" ]; then
        choice="sudo bootc switch ghcr.io/ublue-os/bluefin-nvidia:stable --enforce-container-sigpolicy"
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
    ostree_cleanup 1
    return $rc
  fi
}

system_update() {
    if gum confirm "Does this device have an NVIDIA discrete graphics unit?"; then
            gum confirm "Rebase to Bluefin-NVIDIA image?" \
                && run_ostree_keepalive "nvidia" || echo "Cancelling NVIDIA rebase..." && return 0
    fi
    
    if gum confirm "Run system updates?"; then
        if ! $ostree_complete; then
            run_ostree_keepalive "update"
        else
            echo "Ostree already has an update queued."
            ostree_cleanup
        fi
        gum spin --spinner dot --title "Updating system flatpaks..." \
        -- if flatpack remotes | grep -q system; then
                flatpak update -y
           fi
        gum spin --spinner dot --title "Updating user flatpacks..." \
        -- if flatpack remotes | grep -q user; then
                flatpak update --user -y
           fi
    else echo "Skipping system updates..."
    fi
}

# --- Main Script -- #
if ! rpm-ostree status | grep -qE "idle|Idle"; then
    ostree_complete=true
    ostree_cleanup 0
fi

gum confirm "Display hardware information?" \
    && display_info || tee >> /dev/null
gum confirm "Run auto-configuration?" \
    && auto_configure || echo "Skipping auto-configuration..."
gum confirm "Has the MOK (secure boot key) been enrolled?" \
    && echo "Skipping MOK enrollment..." || ujust enroll-secure-boot-key && echo "Key ready. Please reboot with Secure Boot ENABLED to finish install."
system_update

