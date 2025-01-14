#!/bin/bash

if [ "$#" -lt 4 ]; then
    echo "Usage: gen-tor-v3-client-keys.sh -d <hidden_service_dir> -n <client_name>"
    echo "Example: gen-tor-v3-client-keys.sh -d /var/lib/tor/my_hidden_service -n bob"
    echo "Parameters:"
    echo "    -d,--directory               Hidden service directory"
    echo "    -n,--client-name             Name of the client"
    exit 22
fi

while getopts ":d:n:" opt; do
  case $opt in
    d)
      directory="$OPTARG"
      ;;
    n)
      client_name="$OPTARG"
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
      directory)
        directory=$value
        ;;
      client-name)
        client_name=$value
        ;;
      *)
        echo "Invalid long-form option: $key" >&2
        exit 1
        ;;
    esac
  fi
done

sudo apt update
sudo apt install -y openssl basez

rm -f /tmp/k1.prv.pem /tmp/k1.prv.key /tmp/k1.pub.key
openssl genpkey -algorithm x25519 -out /tmp/k1.prv.pem

# Extract private key
cat /tmp/k1.prv.pem | grep -v " PRIVATE KEY" | base64pem -d | tail --bytes=32 | base32 | sed 's/=//g' > /tmp/k1.prv.key

# Extract public key
openssl pkey -in /tmp/k1.prv.pem -pubout | grep -v " PUBLIC KEY" | base64pem -d | tail --bytes=32 | base32 | sed 's/=//g' > /tmp/k1.pub.key

path=$directory/authorized_clients
sudo mkdir -p $path
echo -n "descriptor:x25519:$(cat /tmp/k1.pub.key)" | sudo tee "$path/$client_name.auth" > /dev/null
echo "Wrote client public key to $path/$client_name.auth"

onion=$(sudo cat $directory/hostname | cut -d'.' -f 1)
echo "Onion host: $onion"
echo "$onion:descriptor:x25519:$(cat /tmp/k1.prv.key)" > "$client_name.auth_private"
echo "Wrote client private key to $client_name.auth_private"

rm -f /tmp/k1.prv.pem /tmp/k1.prv.key /tmp/k1.pub.key
