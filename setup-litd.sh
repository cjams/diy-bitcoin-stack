#!/bin/bash

if [ "$#" -ne 6 ]; then
    echo "Usage: setup-litd.sh -r <release> -u <rpcuser> -p <rpcpass> -t <ui-password>"
    echo "Example: setup-litd-node.sh -r v0.14.0-alpha.rc1 -u user -p pass -t 1337litd"
    echo "Parameters:"
    echo "    -r,--release    release version"
    echo "    -u,--rpcuser    RPC user for local bitcoin node (for OTS verification)"
    echo "    -p,--rpcpass    RPC password for local bitcoin node (for OTS verification)"
    echo "    -t,--uipass     UI password for LitD"
    exit 22
fi

# Initialize variables for storing option values
while getopts ":r:u:p:t:" opt; do
  case $opt in
    r)
      release="$OPTARG"
      ;;
    u)
      rpcuser="$OPTARG"
      ;;
    p)
      rpcpass="$OPTARG"
      ;;
    t)
      uipass="$OPTARG"
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
      release)
        release=$value
        ;;
      rpcuser)
        rpcuser=$value
        ;;
      rpcpass)
        rpcpass=$value
        ;;
      uipass)
        uipass=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

cd $HOME
mkdir -p litd
cd litd

download_url=https://github.com/lightninglabs/lightning-terminal/releases/download

gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys F4FC70F07310028424EFC20A8E4256593F177720

curl -L -O $download_url/$release/manifest-guggero-$release.sig
curl -L -O $download_url/$release/manifest-guggero-$release.sig.ots
curl -L -O $download_url/$release/manifest-$release.txt
curl -L -O $download_url/$release/lightning-terminal-linux-amd64-$release.tar.gz

gpg --verify manifest-guggero-$release.sig manifest-$release.txt
if [ $? -ne 0 ]; then
    echo "[-] GPG verification failed!"
    exit 42
fi

echo "[+] GPG signature verified"

our_hash=$(sha256sum lightning-terminal-linux-amd64-$release.tar.gz)
lit_hash=$(cat manifest-$release.txt | grep lightning-terminal-linux-amd64-$release.tar.gz)

if [ "$our_hash" != "$lit_hash" ]; then
    echo "[-] SHA256 verification failed!"
    echo "[-]     our_hash: $our_hash"
    echo "[-]     lit_hash: $lit_hash"
    exit 42
fi

echo "[+] SHA256 verified"

ots --bitcoin-node http://$rpcuser:$rpcpass@127.0.0.1:8332/ verify manifest-guggero-$release.sig.ots
if [ $? -ne 0 ]; then
    echo "[-] OTS verification of manifest signature failed!"
    exit 42
fi

echo "[+] Timestamps verified"
echo "[+] Installing binaries..."

tar xvf lightning-terminal-linux-amd64-$release.tar.gz

litd_usr=$USER
litd_grp=$USER
litd_bin=$HOME/litd/lightning-terminal-linux-amd64-$release/litd
lnd_macaroon_path=/home/lnd/.lnd/data/chain/bitcoin/mainnet/admin.macaroon
lnd_tls_path=/home/lnd/.lnd/tls.cert

sudo cp -v $HOME/bitcoin-scripts/litd.service /etc/systemd/system/
sudo sed -i "s|@LITD_BIN@|$litd_bin|g" /etc/systemd/system/litd.service
sudo sed -i "s|@LITD_USR@|$litd_usr|g" /etc/systemd/system/litd.service
sudo sed -i "s|@LITD_GRP@|$litd_grp|g" /etc/systemd/system/litd.service
sudo sed -i "s|@LITD_PASS@|$uipass|g" /etc/systemd/system/litd.service
sudo sed -i "s|@LND_MACAROON_PATH@|$lnd_macaroon_path|g" /etc/systemd/system/litd.service
sudo sed -i "s|@LND_TLS_PATH@|$lnd_tls_path|g" /etc/systemd/system/litd.service
