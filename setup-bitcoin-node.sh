#!/bin/bash

if [ "$#" -lt 6 ]; then
    echo "Usage: setup-bitcoin-node.sh -p <rpc_pass> -a <mullvad_account_id> -l <mullvad_vpn_location> -d <external_storage>"
    echo "Example: setup-bitcoin-node.sh -p 'fo0bA&' -a 123459038395 -l us-den-wg-002"
    echo "Parameters:"
    echo "    -p,--rpc-pass                rpc password. This is fed through rpcauth.py to generate rpcauth"
    echo "    -a,--mullvad-account-id      mullvad account id"
    echo "    -l,--mullvad-location        mullvad relay location"
    echo "    -d,--mount-device            external storage device (e.g. /dev/sda) on which to mount the datadir [optional]"
    exit 22
fi

# Initialize variables for storing option values
while getopts ":p:a:l:d:" opt; do
  case $opt in
    p)
      rpc_pass="$OPTARG"
      ;;
    a)
      mullvad_account_id="$OPTARG"
      ;;
    l)
      mullvad_location="$OPTARG"
      ;;
    d)
      mount_device="$OPTARG"
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
      rpc-pass)
        rpc_pass=$value
        ;;
      mullvad-account-id)
        mullvad_account_id=$value
        ;;
      mullvad-location)
        mullvad_location=$value
        ;;
      mount-device)
        mount_device=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

dir="$HOME/dotfiles"

sudo apt update
sudo apt install -y zsh vim silversearcher-ag libzmq3-dev

cd $HOME

# Setup mullvad VPN tunnel
sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mullvad.list
sudo apt update
sudo apt install mullvad-vpn

device=$(mullvad account get | grep 'Device name:')
if [ "$?" -ne 0 ]; then
    mullvad account login $mullvad_account_id
else
    echo "Device is already registered with mullvad as $device"
fi

mullvad lan set allow
mullvad relay set tunnel-protocol wireguard
mullvad relay set location $mullvad_location
mullvad connect

# Install bitcoin build dependencies
sudo apt install build-essential cmake pkg-config python3 libevent-dev libboost-dev libsqlite3-dev

# Build. TODO verify signature on commits out of abundance of caution
if [ ! -d $HOME/bitcoin ]; then
    git clone https://github.com/bitcoin/bitcoin
fi
cd bitcoin

# The systemd service expects bitcoind to live under /usr/bin,
# hence we specify -DCMAKE_INSTALL_PREFIX=/usr
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTS=OFF -DBUILD_TESTING=OFF -DWITH_ZMQ=ON
cmake --build build -j$(nproc)
sudo cmake --install build

# Create bitcoin user:group
group_check=$(getent group bitcoin)
if [ "$?" -ne 0 ]; then
    sudo adduser --gecos "" --disabled-password bitcoin
    sudo usermod -aG bitcoin $USER
fi

# Generate configuration
BUILDDIR=build contrib/devtools/gen-bitcoin-conf.sh

rpcauth=$(python3 share/rpcauth/rpcauth.py $USER $rpc_pass | grep 'rpcauth=' | cut -d '=' -f 2)

sed -i 's|#txindex=1|txindex=1|' share/examples/bitcoin.conf
sed -i 's|#listen=1|listen=1|' share/examples/bitcoin.conf
sed -i 's|#listenonion=1|listenonion=1|' share/examples/bitcoin.conf
sed -i 's|#server=1|server=1|' share/examples/bitcoin.conf
sed -i 's|#v2transport=1|v2transport=1|' share/examples/bitcoin.conf
sed -i 's|#dbcache=<n>|dbcache=1024|' share/examples/bitcoin.conf
sed -i 's|#rpccookieperms=<readable-by>|rpccookieperms=group|' share/examples/bitcoin.conf
sed -i 's|#datadir=<dir>|datadir=/var/lib/bitcoind|' share/examples/bitcoin.conf
sed -i "s|#rpcauth=<userpw>|rpcauth=$rpcauth|" share/examples/bitcoin.conf

sudo mkdir -p /etc/bitcoin
sudo cp -v share/examples/bitcoin.conf /etc/bitcoin/
sudo chown -R bitcoin:bitcoin /etc/bitcoin
sudo chmod 750 /etc/bitcoin

# Generate datadir
sudo mkdir -p /var/lib/bitcoind
sudo chown -R bitcoin:bitcoin /var/lib/bitcoind
sudo chmod 750 /var/lib/bitcoind

# Install external drive mount service. Note that since StateDirectory
# is specified in bitcoind.service, systemd automatically adds a Requires=
# and After= dependency on the mount unit.
if [ -n $mount_device ]; then
    cmd=$(lsblk $mount_device)
    if [ "$?" -eq 0 ]; then
        sudo cp -v $dir/var-lib-bitcoind.mount /etc/systemd/system/
        sed -i "s|@DEVICE@|$mount_device|" /etc/systemd/system/var-lib-bitcoind.mount
        sudo systemctl start var-lib-bitcoind.mount
        sudo systemctl enable var-lib-bitcoind.mount
    fi
fi

# Let's geeeet it on
sudo cp -v $dir/bitcoind.service /etc/systemd/system/
sudo systemctl enable bitcoind.service
sudo systemctl start bitcoind.service
