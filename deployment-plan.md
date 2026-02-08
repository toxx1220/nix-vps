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
  
  # For VPS with enough RAM (more than 1.5GB) and cpu, the flag --build-on-remote passwordless-sudo@[host-ip] can be used to avoid cross-compilation issues.
```

### What happens
1. Connects via SSH
2. Runs Disko to partition your drive
3. **Copies the pre-generated SSH keys to `/persistent/etc/ssh`** (needed for SOPS to decrypt secrets)
4. Installs NixOS
5. Reboots into your new system

---

## Phase B: GitOps Auto-Updates

Once NixOS is running, the system updates automatically via a GitOps workflow:

### Automatic Updates
- **On Git Push:** Garnix CI builds the system closure → Webhook triggers the host → VPS switches to the new configuration using `nh`.
- **Weekly Timer:** Every Sunday at 03:00, the VPS updates all flake inputs and applies updates automatically.

### Manual Update (if needed)
If you need to manually update the system:
```bash
ssh root@[host-ip]
sudo nh os switch --update github:toxx1220/nix-vps -- -L
```

---

## What Happens When You Change Things?

### Changing `host.nix` or `containers/*.nix`
When the system rebuilds, Nix calculates the "diff":
- If you changed a port in Caddy → Only Caddy restarts
- If you updated the bot/backend code → Only that container restarts
- Services that didn't change experience **zero downtime**
- Nix handles granular restarts, ensuring only the affected units are touched.

### Changing `disko.nix`
**⚠️ Be careful here.** Disko defines your physical hard drive layout (partitions, filesystems).
- If you change a mount point, Nix will try to adjust it
- If you change partition sizes or types, the system **cannot** do this on a live system
  - You would need to re-run a fresh install or manually resize partitions (risky)
- **Rule of thumb:** Get your `disko.nix` right once, then leave it alone