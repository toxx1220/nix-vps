# Deployment Plan

## Phase A: Init (nixos-anywhere)

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

---

## Phase C: Ongoing Operations

Once set up, the system updates automatically via an update action and comin.

### Weekly dependency updates (Sunday 03:00 UTC)

```
Scheduled GitHub Action: update-flake.yml
  → Checks out repo
  → Runs nix flake update
  → Creates a PR with the updated flake.lock
  → You review and merge (or configure auto-merge)
  (→ Comin automatically pulls & rebuilds)
```

Uses [DeterminateSystems/update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock). Can also be triggered manually via `workflow_dispatch`.

---

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
