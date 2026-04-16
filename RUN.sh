#!/bin/bash

## --- BLUEFIN AUTO-CONFIGURATION SCRIPT ---
# Written for C4PIN.org
# Author: KitsuneRhin @github
# License: Apache 2.0
# Version: 01262026


# --- Install Override for Shutdown-on-Close ---
echo "Installing logind.conf shutdown override file..."
cat >> /etc/systemd/logind.conf<< EOF
[Login]
HandleLidSwitch=poweroff
HandleLidSwitchDocked=poweroff
EOF
systemctl daemon-reload && systemctl daemon-reexec
echo "Success."

# --- Query MOK Status ---
echo -e "\nHas the MOK (secure boot key) been enrolled? (Y/n)"
select strictreply in "Yes" "No"; do
       relaxedreply=${strictreply:-$REPLY}
       case $relaxedreply in
           Yes | yes | y ) echo -e "\nSkipping MOK Enrollment..."; break;;
           No  | no  | n ) ujust enroll-secure-boot-key; echo "Key ready. Please reboot with Secure Boot ENABLED to finish install."; break;; 
       esac
done

# --- Query NVIDIA Driver Needed ---
echo -e "\nDoes this device have an NVIDIA discrete graphics unit? (Y/n)"
dFlag=false
select strictreply in "Yes" "No"; do
	relaxedreply=${strictreply:-$REPLY}
	case $relaxedreply in
		Yes | yes | y ) dFlag=true; break;;
		No  | no  | n ) echo -e "\n Skipping NVIDIA Rebase..."; break;;
	esac
done
if $dFlag; then
	echo -e "\nRebase to Bluefin-NVIDIA version? (Y/n)"
	select strictreply in "Yes" "No"; do
		relaxedreply=${strictreply:-$REPLY}
		case $relaxedreply in
			Yes | yes | y ) echo -e "\nPlease wait. Building new system image...\n"; sudo bootc switch ghcr.io/ublue-os/bluefin-nvidia:stable --enforce-container-sigpolicy --quiet; echo "\nSuccess. Changes will take effect on next reboot."; break;;
			No  | no  | n ) echo -e "\nCancelling operation..."; break;;
		esac
	done
fi

# --- Exit Conditions ---
echo -e "\nScript complete. Would you like to reboot or shutdown?"
select strictreply in "Reboot" "Shutdown" "Quit"; do
       relaxedreply=${strictreply:-$REPLY}
       case $relaxedreply in
           R | r | 1 | reboot ) sudo systemctl reboot; break;;
           S | s | 2 | shutdown ) sudo shutdown now; break;;
           Q | q | 3 | quit ) echo "Goodbye."; exit;;
       esac
done
