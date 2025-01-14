#!/bin/bash

sudo apt update
sudo apt install clang cmake build-essential cargo

# Clone and build
cd $HOME
git clone https://github.com/romanz/electrs
cd electrs
cargo build --locked --release

# Install system files
sudo cp -v target/release/electrs /usr/local/bin/
sudo mkdir -p /var/lib/electrs/db
sudo mkdir /etc/electrs
sudo chmod 0750 /var/lib/electrs
sudo chmod 0750 /etc/electrs

cd $HOME/bitcoin-scripts
sudo cp -v electrs.conf /etc/electrs/config.toml
sudo chown -R electrs:electrs /etc/electrs
sudo chown -R electrs:electrs /var/lib/electrs

# Create electrs user:group and add to bitcoin group (if needed)
group_check=$(getent group electrs)
if [ "$?" -ne 0 ]; then
    sudo adduser --gecos "" --disabled-password electrs
    sudo usermod -aG bitcoin electrs
fi

# Install systemd service
sudo cp -v electrs.service /etc/systemd/system/
sudo systemctl enable --now electrs.service
