#!/bin/bash

if [ "$#" -lt 6 ]; then
    echo "Usage: setup-btcpay-node.sh -d <domain> -h <proxy_host> -u <proxy_user> -p <db_password>"
    echo "Example: setup-btcpay-node.sh -d example.com -p ec2-host -u ubuntu -p yoursecret"
    echo "Parameters:"
    echo "    -d,--domain      DNS domain for the server"
    echo "    -h,--proxy-host  Hostname for proxy host (from this machine's /etc/host file)"
    echo "    -u,--proxy-user  SSH user for proxy host"
    echo "    -p,--db-pass     Postgresql password"
    exit 22
fi

# Initialize variables for storing option values
while getopts ":d:h:u:p:" opt; do
  case $opt in
    d)
      btcpay_domain="$OPTARG"
      ;;
    h)
      proxy_host="$OPTARG"
      ;;
    u)
      proxy_user="$OPTARG"
      ;;
    p)
      db_pass="$OPTARG"
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
      btcpay-domain)
        btcpay_domain=$value
        ;;
      proxy-host)
        proxy_host=$value
        ;;
      proxy-user)
        proxy_user=$value
        ;;
      db-pass)
        db_pass=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

dir="$HOME/dotfiles"

# Create btcpay user:group
group_check=$(getent group btcpay)
if [ "$?" -ne 0 ]; then
    sudo adduser --gecos "" --disabled-password btcpay
    sudo usermod -aG btcpay $USER
    sudo usermod -aG lnd btcpay
fi

# Install NBXplorer
sudo apt update
sudo apt install -y apt-transport-https dotnet-sdk-8.0
sudo apt install -y postgresql postgresql-contrib

cd $HOME
if [ ! -d NBXplorer ];
then
    git clone https://github.com/dgarage/NBXplorer
fi

# Checkout the latest tag and build
cd NBXplorer
tag=$(git tag --sort -version:refname | awk 'match($0, /^v[0-9]+\./)' | head -n 1)
git checkout $tag
./build.sh

cd $HOME
sudo rm -rf /home/btcpay/NBXplorer
sudo mv NBXplorer /home/btcpay/
sudo chown -R btcpay:btcpay /home/btcpay/

nbxplorer_dir=/home/btcpay/NBXplorer
nbxplorer_usr=btcpay
nbxplorer_grp=btcpay

# Create postgresql database
cd $HOME
psql -U postgresql -c CREATE DATABASE nbxplorer TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';
psql -U postgresql -c CREATE USER nbxplorer WITH ENCRYPTED PASSWORD "$db_pass";
psql -U postgresql -c GRANT ALL PRIVILEGES ON DATABASE nbxplorer TO nbxplorer;
psql -U postgresql -c ALTER DATABASE nbxplorer OWNER TO nbxplorer;

sudo mkdir -p /etc/nbxplorer
sudo cp $dir/nbxplorer.config /etc/nbxplorer/
sudo chown -R btcpay:btcpay /etc/nbxplorer
sudo chmod 640 /etc/nbxplorer/nbxplorer.config
sudo cp $dir/nbxplorer.service /etc/systemd/system/

sudo sed -i "s|@NBXPLORER_DIR@|$nbxplorer_dir|" /etc/systemd/system/nbxplorer.service
sudo sed -i "s|@NBXPLORER_USR@|$nbxplorer_usr|" /etc/systemd/system/nbxplorer.service
sudo sed -i "s|@NBXPLORER_GRP@|$nbxplorer_grp|" /etc/systemd/system/nbxplorer.service

sudo systemctl enable --now nbxplorer

cd $HOME
if [ ! -d btcpayserver ];
then
    git clone https://github.com/btcpayserver/btcpayserver
fi

cd btcpayserver
tag=$(git tag --sort -version:refname | awk 'match($0, /^v[0-9]+\.[0-9]+\.[0-9]+$/)' | head -n 1)
git checkout $tag
./build.sh

cd $HOME
psql -U postgresql -c CREATE DATABASE btcpay TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';
psql -U postgresql -c CREATE USER btcpay WITH ENCRYPTED PASSWORD "$db_pass";
psql -U postgresql -c GRANT ALL PRIVILEGES ON DATABASE btcpay TO btcpay;
psql -U postgresql -c ALTER DATABASE btcpay OWNER TO btcpay;

lnd_macaroon_path=/home/lnd/.lnd/data/chain/bitcoin/mainnet/admin.macaroon

sudo mkdir -p /etc/btcpay
sudo cp $dir/btcpay.config /etc/btcpay/
sudo sed -i "s|@LND_MACAROON_PATH@|$lnd_macaroon_path|g" /etc/btcpay/btcpay.config
sudo chown -R btcpay:btcpay /etc/btcpay
sudo chmod 640 /etc/btcpay/btcpay.config
sudo cp $dir/btcpay.service /etc/systemd/system/

btcpay_dir=/home/btcpay/btcpayserver
btcpay_usr=btcpay
btcpay_grp=btcpay
nbxplorer_cookie=/home/btcpay/.nbxplorer/Main/.cookie

sudo mv $HOME/btcpayserver /home/btcpay/
sudo chown -R btcpay:btcpay $btcpay_dir

sudo sed -i "s|@BTCPAY_DOMAIN@|$btcpay_domain|g" /etc/systemd/system/btcpay.service
sudo sed -i "s|@BTCPAY_DIR@|$btcpay_dir|g" /etc/systemd/system/btcpay.service
sudo sed -i "s|@BTCPAY_USR@|$btcpay_usr|g" /etc/systemd/system/btcpay.service
sudo sed -i "s|@BTCPAY_GRP@|$btcpay_grp|g" /etc/systemd/system/btcpay.service
sudo sed -i "s|@NBXPLORER_COOKIE@|$nbxplorer_cookie|g" /etc/systemd/system/btcpay.service

sudo systemctl enable --now btcpay

# Setup SSH Tunnel
btcpay_port=23000
rtl_port=3000

sudo apt install autossh
sudo cp $dir/autossh-tunnel.service /etc/systemd/system/

sudo sed -i "s|@BTCPAY_PROXY_HOST@|$proxy_host|g" /etc/systemd/system/autossh-tunnel.service
sudo sed -i "s|@BTCPAY_PROXY_USR@|$proxy_user|g" /etc/systemd/system/autossh-tunnel.service
sudo sed -i "s|@BTCPAY_PORT@|$btcpay_port|g" /etc/systemd/system/autossh-tunnel.service
sudo sed -i "s|@RTL_PORT@|$rtl_port|g" /etc/systemd/system/autossh-tunnel.service
sudo sed -i "s|@AUTOSSH_USR@|$USER|g" /etc/systemd/system/autossh-tunnel.service
sudo sed -i "s|@AUTOSSH_GRP@|$USER|g" /etc/systemd/system/autossh-tunnel.service

sudo systemctl enable --now autossh-tunnel
