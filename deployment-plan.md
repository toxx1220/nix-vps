# Deployment Plan

## Phase A: Initial "Big Bang" (nixos-anywhere)

This is for a fresh VPS. **It will wipe the disk** and install your config.

### Pre-requisite

Enable passwordless sudo on target (for Oracle Cloud with `opc` user):

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-nixos-anywhere
```

### Command

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#vps-arm \
  --extra-files ./secrets-init/keys \
  passwordless-sudo@[host-ip]
```

> For VPS with enough RAM (>1.5GB) and CPU, add `--build-on-remote` to avoid cross-compilation issues.

### What happens

1. Connects via SSH
2. Runs Disko to partition the drive
3. Copies pre-generated SSH keys to `/persistent/etc/ssh` (needed for SOPS decryption)
4. Installs NixOS
5. Reboots into the new system

---

## Phase B: Post-Install Setup

After the initial install, set up the persistent repo clone and CI deploy key.

### 1. Clone the repo on the server

```bash
ssh root@[host-ip]
git clone https://github.com/toxx1220/nix-vps.git /persistent/nix-vps
```

### 2. Generate and configure the CI deploy key

On your local machine:

```bash
ssh-keygen -t ed25519 -f deploy-key -N "" -C "ci-deploy"
```

Then:

1. Copy the contents of `deploy-key.pub` and replace the `CHANGE_ME` placeholder in `host.nix` (root's authorized keys, the line with the `command=` prefix).
2. Add two **GitHub Actions secrets** to the repo (`Settings → Secrets and variables → Actions`):
   - `VPS_SSH_KEY` — contents of the `deploy-key` private key file
   - `VPS_HOST` — your server's IP address or hostname
3. Delete the private key from your local machine (it now lives only in GitHub secrets):
   ```bash
   rm deploy-key
   ```
4. Push the `host.nix` change to `main` — this triggers the first automated deploy.

---

## Phase C: Ongoing Operations

Once set up, the system updates automatically via two GitHub Actions workflows.

### On every push to `main`

```
Push to main
  → GitHub Actions: deploy.yml
  → SSH into VPS (forced-command deploy key)
  → git pull origin main
  → nixos-rebuild switch --flake .#vps-arm
```

The deploy key is restricted via SSH `command=` — it can only execute the deploy script. No shell access, no port forwarding.

### Weekly dependency updates (Sunday 03:00 UTC)

```
Scheduled GitHub Action: update-flake.yml
  → Checks out repo
  → Runs nix flake update
  → Creates a PR with the updated flake.lock
  → You review and merge (or configure auto-merge)
  → Merge triggers the deploy workflow above
```

Uses [DeterminateSystems/update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock). Can also be triggered manually via `workflow_dispatch`.

### Manual update (if needed)

```bash
ssh root@[host-ip]
cd /persistent/nix-vps
git pull
nixos-rebuild switch --flake .#vps-arm --accept-flake-config -L
```

---

## Security Model

| Component | Access Level | Notes |
|---|---|---|
| Personal SSH key | Full root access | For administration and debugging |
| CI deploy key | Deploy script only | SSH `command=` restriction — no shell, no forwarding |
| Garnix | Build + cache only | Pre-builds the closure; no deploy access |
| GitHub Actions | SSH via deploy key | Can only trigger a rebuild from current repo state |

### Key principles

- **One-way data flow**: Repo → Server. The server never writes back to the repo.
- **Least privilege**: The CI key can only execute the fixed deploy script, even though it authenticates as root.
- **If the deploy key leaks**: An attacker can only trigger a rebuild from the current state of `main`. They cannot run arbitrary commands, access the shell, or modify the repo.

---

## What Happens When You Change Things?

### Changing `host.nix` or `containers/*.nix`

Nix calculates the diff between the current and new system:

- Changed a port in Caddy → only Caddy restarts
- Updated bot/backend code → only that container restarts
- Services that didn't change → **zero downtime**

### Changing `disko.nix`

**⚠️ Be careful.** Disko defines the physical disk layout (partitions, filesystems).

- Changing mount points: Nix will try to adjust
- Changing partition sizes/types: **impossible on a live system** — requires a fresh install
- **Rule of thumb:** Get `disko.nix` right once, then leave it alone

---

## Rollback

NixOS keeps previous generations. To roll back:

```bash
ssh root@[host-ip]
# List available generations
nix-env --list-generations --profile /nix/var/nix/profiles/system

# Switch to a previous generation
nixos-rebuild switch --rollback

# Or boot into a previous generation via the bootloader
```
