#!/bin/bash

if [ "$#" -ne 10 ]; then
    echo "Usage: setup-lnd-node.sh -a <alias> -r <release> -s <signer> -u <rpcuser> -p <rpcpass>"
    echo "Example: setup-lnd-node.sh -a mynode -r v0.18.3-beta -k roasbeef -u user -p pass"
    echo "Parameters:"
    echo "    -a,--alias                   node alias"
    echo "    -r,--release                 release version"
    echo "    -s,--signer                  GPG signing key to use"
    echo "    -u,--rpcuser                 RPC user for local bitcoin node"
    echo "    -p,--rpcpass                 RPC password for local bitcoin node"
    exit 22
fi

# Initialize variables for storing option values
while getopts ":a:r:s:u:p:" opt; do
  case $opt in
    a)
      lnd_alias="$OPTARG"
      ;;
    r)
      release="$OPTARG"
      ;;
    s)
      signer="$OPTARG"
      ;;
    u)
      rpcuser="$OPTARG"
      ;;
    p)
      rpcpass="$OPTARG"
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
      alias)
        lnd_alias=$value
        ;;
      release)
        release=$value
        ;;
      signer)
        signer=$value
        ;;
      rpcuser)
        rpcuser=$value
        ;;
      rpcpass)
        rpcpass=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

# Create lnd user:group
group_check=$(getent group lnd)
if [ "$?" -ne 0 ]; then
    sudo adduser --gecos "" --disabled-password lnd
    sudo usermod -aG lnd $USER
    sudo usermod -aG bitcoin lnd
    sudo usermod -aG debian-tor lnd
fi

pip3 install opentimestamps-client --break-system-packages

download_url=https://github.com/lightningnetwork/lnd/releases/download

sudo chown $USER:$USER -R /home/lnd
cd /home/lnd

curl https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/$signer.asc | gpg --import

curl -L -O $download_url/$release/manifest-$signer-$release.sig
curl -L -O $download_url/$release/manifest-$signer-$release.sig.ots
curl -L -O $download_url/$release/manifest-$release.txt
curl -L -O $download_url/$release/manifest-$release.txt.ots
curl -L -O $download_url/$release/lnd-linux-amd64-$release.tar.gz

gpg --verify manifest-$signer-$release.sig manifest-$release.txt
if [ $? -ne 0 ]; then
    echo "[-] GPG verification failed!"
    exit 42
fi

echo "[+] GPG signature verified"

our_hash=$(sha256sum lnd-linux-amd64-$release.tar.gz)
lnd_hash=$(cat manifest-$release.txt | grep lnd-linux-amd64-$release.tar.gz)

if [ "$our_hash" != "$lnd_hash" ]; then
    echo "[-] SHA256 verification failed!"
    echo "[-]     our_hash: $our_hash"
    echo "[-]     lnd_hash: $lnd_hash"
    exit 42
fi

echo "[+] SHA256 verified"

ots --bitcoin-node http://$rpcuser:$rpcpass@127.0.0.1:8332/ verify manifest-$signer-$release.sig.ots
if [ $? -ne 0 ]; then
    echo "[-] OTS verification of manifest signature failed!"
    exit 42
fi

ots --bitcoin-node http://$rpcuser:$rpcpass@127.0.0.1:8332/ verify manifest-$release.txt.ots
if [ $? -ne 0 ]; then
    echo "[-] OTS verification of manifest failed!"
    exit 42
fi

echo "[+] Timestamps verified"
echo "[+] Installing binaries..."

tar xvf lnd-linux-amd64-$release.tar.gz
cp -v lnd-linux-amd64-$release/lnd /usr/bin/
cp -v lnd-linux-amd64-$release/lncli /usr/bin/

mkdir -p /home/lnd/.lnd
cp -v $HOME/bitcoin-scripts/lnd.conf /home/lnd/.lnd/
sed -i "s|; alias=@LND_ALIAS@|alias=@LND_ALIAS@|g" /home/lnd/.lnd/lnd.conf
sed -i "s|@LND_ALIAS@|$lnd_alias|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; listen=localhost|listen=localhost|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; rpcmiddleware.enable=false|rpcmiddleware.enable=true|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; bitcoind.dir=~/.bitcoin|bitcoind.dir=/var/lib/bitcoind|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; bitcoind.config=|bitcoind.config=/etc/bitcoin/bitcoin.conf|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; bitcoind.rpccookie=/var/lib/bitcoind/.cookie|bitcoind.rpccookie=/var/lib/bitcoind/.cookie|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.active=false|tor.active=true|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.socks=localhost:9050|tor.socks=localhost:9050|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.control=localhost:9051|tor.control=localhost:9051|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.v3=true|tor.v3=true|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.privatekeypath=|tor.privatekeypath=~/.lnd/v3_onion_private_key|g" /home/lnd/.lnd/lnd.conf
sed -i "s|; tor.encryptkey=false|tor.encryptkey=true|g" /home/lnd/.lnd/lnd.conf

sudo cp -v $HOME/bitcoin-scripts/lnd.service /etc/systemd/system/

lnd_bin=/usr/bin/lnd
lncli_bin=/usr/bin/lncli
lnd_datadir=/home/lnd/.lnd
lnd_config=/home/lnd/.lnd/lnd.conf

sudo sed -i "s|@LND_BIN@|$lnd_bin|g" /etc/systemd/system/lnd.service
sudo sed -i "s|@LNCLI_BIN@|$lncli_bin|g" /etc/systemd/system/lnd.service
sudo sed -i "s|@LND_CONFIG@|$lnd_config|g" /etc/systemd/system/lnd.service
sudo sed -i "s|@LND_DATADIR@|$lnd_datadir|g" /etc/systemd/system/lnd.service
sudo sed -i "s|@LND_USR@|lnd|g" /etc/systemd/system/lnd.service
sudo sed -i "s|@LND_GRP@|lnd|g" /etc/systemd/system/lnd.service

sudo chown lnd:lnd -R /home/lnd
sudo find /home/lnd -type d -exec chmod g+rx {} +
sudo systemctl enable --now lnd
