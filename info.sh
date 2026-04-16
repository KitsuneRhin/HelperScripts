#!/bin/bash

## --- TRIAGE HARDWARE INFO SCRIPT ---
# Written by Devon Buecher for C4PIN.org
# License CC BY-NC-SA 4.0
# Version: 03032026


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
if lsblk | grep -q "nvme0n1"; then 
	lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|nvme0n1"
else
	lsblk -d -o NAME,SIZE | grep --color=always -E "^NAME|sda"
fi

# - Battery info -
echo -e "\n*--- Battery ---*"
if upower -e | grep -q "BAT0"; then
	upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep --color=always -E "capacity:|energy-full:|energy-full-design:|time to empty:" | sed 's/^[[:space:]]*//'
elif upower -e | grep -q "BAT1"; then
	upower -i /org/freedesktop/UPower/devices/battery_BAT1 | grep --color=always -E "capacity:|energy-full:|energy-full-design:|time to empty:" | sed 's/^[[:space:]]*//'
else
	echo "Battery not found!"
fi
