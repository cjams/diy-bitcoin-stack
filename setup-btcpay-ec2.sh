#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "Usage: setup-btcpay-ec2.sh -d <domain> "
    echo "Parameters:"
    echo "    -d,--domain   Domain name of server"
    exit 22
fi

while getopts ":d:" opt; do
    case $opt in
        d)
            domain="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 22
            ;;
        :)
            echo "Option -$OPTARG requires an argument"
            exit 22
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
        domain=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
    esac
  fi
done

get_confirmation() {
    while true; do
        read -r -p "Have you added a DNS A record pointing to $domain? (y/n): " response
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

        case "$response" in
            y | yes)
                return 0
                ;;
            n | no)
                return 1
                ;;
            *)
                return 1
                ;;
        esac
    done
}

if ! get_confirmation; then
    echo "Please add a DNS A record for your domain, then re-run this script"
    exit 1
fi

sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Before running this, need DNS A record pointing to the domain
sudo certbot --nginx -d $domain

sudo cp -v $HOME/dotfiles/nginx-reverse-proxy-btcpay.conf /etc/nginx/conf.d/default.conf
sudo systemctl restart nginx

# Configs needs for autossh tunnel
echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'GatewayPorts yes' >> /etc/ssh/sshd_config
echo 'AllowTcpForwarding yes' >> /etc/ssh/sshd_config
echo 'ClientAliveInterval 60' >> /etc/ssh/sshd_config

sudo systemctl restart ssh
