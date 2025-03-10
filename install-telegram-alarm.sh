#!/bin/bash

# Create venv
if [ ! -d venv ];
then
    sudo apt install python3-venv
    python3 -m venv venv
fi

# Make script executable
chmod +x telegram_alarm.py

# Install required Python package
source venv/bin/activate
pip3 install requests

# Get username
USERNAME=$(whoami)

# Update service file with correct username
sed -i "s/YOUR_USERNAME/$USERNAME/g" telegram-alarm.service
sed -i "s|ALARM_PATH|$HOME/diy-bitcoin-stack/telegram_alarm.py|" telegram-alarm.service

# Check if config has been updated
if grep -q "YOUR_BOT_TOKEN_HERE" config.json; then
    echo "⚠️  Please edit config.json with your Telegram bot token and chat ID before continuing."
    exit 1
fi

# Copy service file to systemd directory
echo "Installing systemd service..."
sudo cp telegram-alarm.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start the service
echo "Enabling and starting the service..."
sudo systemctl enable telegram-alarm.service
sudo systemctl start telegram-alarm.service

# Check service status
echo "Service status:"
sudo systemctl status telegram-alarm.service

echo ""
echo "✅ Installation complete!"
echo "   You can check the logs with: tail -f telegram_alarm.log"
