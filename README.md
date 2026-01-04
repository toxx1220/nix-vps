# NixOS VPS with MicroVMs

This project manages a NixOS VPS host and its MicroVMs using Flakes, Disko, and SOPS-nix.

## Secrets & SOPS
Decryption requires a SOPS-compatible private key (Age or SSH) at `/var/lib/sops-nix/key.txt` on the target host.

## 1. Initial Deployment (Fresh Install)
Use `nixos-anywhere` to partition the disk and install NixOS.

1. Prepare the key locally:
   `mkdir -p secrets-init/keys/var/lib/sops-nix`
   `cp /path/to/your/private/key secrets-init/keys/var/lib/sops-nix/key.txt`
   *(Note: The key must be the one used to encrypt `secrets.yaml`)*

2. Run deployment:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#vps-arm \
     --extra-files secrets-init/keys \
     passwordless-sudo@[host-ip]
   ```
Note: This uses the `vps-arm` flake configuration. Adjust as needed.

## 2. Rebuild / Update (Existing System)
Once installed, apply changes using `nixos-rebuild`:

```bash
nixos-rebuild switch --flake .#vps-arm \
  --target-host root@[host-ip] \
  --use-remote-sudo
```

## 3. MicroVMs
VMs are defined in `microvms/` and toggled in `host.nix`. They share a common base configuration in `microvms/common.nix`.

