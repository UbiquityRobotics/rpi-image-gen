#!/bin/bash
set -e  # Exit on error

LOG_FILE="/var/log/wifi-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1  # Log all output

# Check if already configured
if [ -f /etc/wifi_configured ]; then
    echo "WiFi already configured. Exiting."
    exit 0
fi

# Verify whiptail installation
if ! command -v whiptail >/dev/null; then
    echo "Error: whiptail not found. Install with: sudo apt install whiptail"
    exit 1
fi

# Get user input
SSID=$(whiptail --inputbox "Enter WiFi SSID" 8 39 --title "WiFi Setup" 3>&1 1>&2 2>&3) || exit 1
PASS=$(whiptail --passwordbox "Enter WiFi Password" 8 39 --title "WiFi Setup" 3>&1 1>&2 2>&3) || exit 1

# Write configuration
CONF_FILE="/etc/wpa_supplicant/wpa_supplicant.conf"
echo "network={
    ssid=\"$SSID\"
    psk=\"$PASS\"
}" | sudo tee -a "$CONF_FILE" >/dev/null

# Set permissions
sudo chmod 600 "$CONF_FILE"

# Mark as configured
sudo touch /etc/wifi_configured

# Restart networking
sudo systemctl restart wpa_supplicant.service || true
sudo systemctl disable wifi-setup.service
sudo systemctl daemon-reload

echo "WiFi configuration complete. Rebooting..."
sudo reboot

