#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: setup-rtl.sh -d <domain>"
    echo "Example: setup-rtl.sh -d example.com"
    echo "Parameters:"
    echo "    -d,--domain                  BTCPay domain (with 'https://' prefix)"
    exit 22
fi

# Initialize variables for storing option values
while getopts ":d:" opt; do
  case $opt in
    d)
      btcpay_domain="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Parse long-form options using case statement
for arg in "$@"; do
  if [[ $arg == --* ]]; then
    key=$(echo $arg | cut -d= -f1 | tr -d --)
    value=$(echo $arg | cut -d= -f2-)

    case $key in
      domain)
        btcpay_domain=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

cd $HOME

# Create rtl user:group
group_check=$(getent group rtl)
if [ "$?" -ne 0 ]; then
    sudo adduser --gecos "" --disabled-password rtl
    sudo usermod -aG rtl $USER
    sudo usermod -aG lnd rtl
fi

sudo chown $USER:$USER -R /home/rtl

# Install RTL
cd /home/rtl
sudo apt install -y nodejs build-essential npm
git clone https://github.com/Ride-The-Lightning/rtl.git
cd rtl
sudo chown rtl:rtl -R .
sudo -u rtl npm install --omit=dev --legacy-peer-deps

sudo mkdir -p /var/lib/rtl
sudo cp $HOME/bitcoin-scripts/RTL-Config.json /var/lib/rtl
sudo chown rtl:rtl -R /var/lib/rtl
sudo chmod 640 /var/lib/rtl/RTL-Config.json

lnd_macaroon_path=/home/lnd/.lnd/data/chain/bitcoin/mainnet
lnd_config_path=/home/lnd/.lnd/lnd.conf
rtl_src_path=/home/rtl/rtl

sed -i "s|@BTCPAY_DOMAIN@|$btcpay_domain|g" /var/lib/rtl/RTL-Config.json
sed -i "s|@LND_MACAROON_PATH@|$lnd_macaroon_path|g" /var/lib/rtl/RTL-Config.json
sed -i "s|@LND_CONFIG_PATH@|$lnd_config_path|g" /var/lib/rtl/RTL-Config.json
sed -i "s|@RTL_SRC_PATH@|$rtl_src_path|g" /var/lib/rtl/RTL-Config.json

sudo cp -v $HOME/bitcoin-scripts/rtl.service /etc/systemd/system/
sudo sed -i "s|@RTL_SRC_PATH@|$rtl_src_path|g" /etc/systemd/system/rtl.service
sudo sed -i "s|@RTL_USR@|rtl|g" /etc/systemd/system/rtl.service
sudo sed -i "s|@RTL_GRP@|rtl|g" /etc/systemd/system/rtl.service

sudo chown rtl:rtl -R /home/rtl
