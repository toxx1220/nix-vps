# NixOS VPS with Native Containers

This project manages a NixOS VPS host and its lightweight Native Containers using Flakes, Disko, sops-nix, and impermanence.

## 🏗 Architecture

The system is built on a "Lean Host" principle:
- **Host**: Runs only essential services (SSH, Caddy, Webhook for CI/CD).
- **Containers**: Native NixOS containers (`nixos-container`) isolated with private networking and a virtual bridge (`br0`).
- **Shared Identity**: Containers bind-mount the host's SSH host key to `/var/lib/sops-nix/key.txt`, allowing them to decrypt their own unique secrets while sharing the same identity as the host.

## 🔑 Secrets & Identity

We use `sops-nix` for secret management. To maintain a simple setup, we use the host's SSH ED25519 key as the primary decryption key.

- **Host Key**: `/persistent/etc/ssh/ssh_host_ed25519_key`
- **Container Path**: `/var/lib/sops-nix/key.txt` (via read-only bind mount)

This "Shared Identity" pattern ensures that adding a new container doesn't require generating and managing new Age keys.

## 🚀 Deployment

### 1. Initial Install (Fresh VPS)
We use `nixos-anywhere` for a "Big Bang" installation.

1.  **Prepare Keys**: Place your SSH host key at `secrets-init/keys/persistent/etc/ssh/ssh_host_ed25519_key`.
2.  **Deploy**:
    ```bash
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#vps-arm \
      --extra-files secrets-init/keys \
      passwordless-sudo@[host-ip]
    ```

### 2. Updates & Maintenance
The system uses `nh` (Nix Helper) for local updates and a GitOps workflow for automated deployment.

- **Manual Rebuild**:
  ```bash
  ssh root@[host-ip]
  nh os switch /etc/nixos # or your local path
  ```
- **Automated**: Pushes to `main` trigger a Garnix CI build, which notifies the host via Webhook to pull and switch to the new configuration.

## 🛠 Management & Troubleshooting

- **Debugging**: See [DEBUGGING.md](./DEBUGGING.md) for a cheat sheet on managing containers and logs.
- **Deployment Plan**: See [deployment-plan.md](./deployment-plan.md) for the full lifecycle strategy.

## 📦 Containers

Containers are defined using the `mkContainer` helper in `host.nix`.
- **bgs-backend**: Background search backend.
- **nannuo-bot**: Discord bot service.
- **test-container**: Sandbox for testing new configurations.
