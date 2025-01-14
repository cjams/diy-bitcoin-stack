#!/bin/bash

# This is needed for _sending_ zaps to npubs on nostr. Receiving
# zaps is accomplished with LN-URL from the BTCPay instance.

sudo apt update
sudo apt install cargo

mkdir -p $HOME/.nwc/
cd $HOME

if [ ! -d nostr-wallet-connect-lnd ]; then
    git clone https://github.com/benthecarman/nostr-wallet-connect-lnd.git
fi

#cd nostr-wallet-connect-lnd
#cargo build --release
#sudo cp -v target/release/nostr-wallet-connect-lnd /usr/local/bin/
sudo cp $HOME/bitcoin-scripts/nwc.service /etc/systemd/system/

sudo sed -i "s|@NWC_USR@|$USER|" /etc/systemd/system/nwc.service
sudo sed -i "s|@NWC_GRP@|$USER|" /etc/systemd/system/nwc.service
sudo sed -i "s|@KEYS_FILE@|$HOME/.nwc/keys.json|" /etc/systemd/system/nwc.service
