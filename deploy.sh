#!/usr/bin/env bash

# Usage: ./deploy.sh <ip-address>

IP=$1

if [ -z "$IP" ]; then
  echo "Usage: ./deploy.sh <ip-address>"
  exit 1
fi

echo "Deploying to $IP..."

nix run github:nix-community/nixos-anywhere -- \
  --flake .#vps \
  root@$IP

