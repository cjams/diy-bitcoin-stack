# DIY Bitcoin Stack

This repo contains a collection of scripts and configs I've used to stand up a fully self-hosted stack for the Bitcoin ecosystem.
I intentionally avoided pre-canned solutions because I wanted to force myself to learn how everything is wired together.
I also wanted to keep the cost minimal, so everything except nginx is running on a machine I have in one of my closets at home.

The following things are implemented so far:
* bitcoind over tor
* electrs connected to bitcoind and exposed as Tor v3 hidden service with client auth
* electrum app on Android connected to electrs Tor hidden service
* lnd over tor
* lnd connected to litd for lightning terminal web access and zeus for mobile 
* lnd connected to nostr-wallet-connect-lnd for receiving zaps
* BTCPay server for receiving on-chain and LN payments (both zaps and LNURL)
* nginx running in EC2 instance to reverse proxy back to BTCPay server via autossh
* sending zaps from Amethyst through self-hosted lnd
* receiving zaps from others through LN address hosted on BTCPay server

Here is a diagram I made that details the various connections:

![btc-setup drawio](https://github.com/user-attachments/assets/b6e6457b-0c1a-43a2-a56f-1fe6f1bbbe6b)

The digram is interactive. Open this link: https://drive.google.com/file/d/11hgeRHMyvI3baJxWuDpd3M5xtuC8mmmb/view?usp=sharing
in draw.io and click on the green buttons in the bottom left to see what the various flows are through the stack for various 
use cases. If you don't have gmail or drawio, you can also use the [html file directly](https://github.com/cjams/diy-bitcoin-stack/blob/main/btc-setup.drawio.html)

