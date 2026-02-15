# NixOS VPS with Native Containers

This project manages a NixOS VPS host and its lightweight Native Containers using Flakes, Disko, sops-nix, and impermanence.

## Architecture

The system is built on a "Lean Host" principle:

- **Host**: Runs only essential services (SSH, Caddy reverse proxy).
- **Containers**: Native NixOS containers (`nixos-container`) isolated with private networking and a virtual bridge (`br0`).
- **Shared Identity**: Containers bind-mount the host's SSH host key to `/var/lib/sops-nix/key.txt`, allowing them to decrypt their own secrets without managing separate Age keys.

## Secrets & Identity

We use `sops-nix` for secret management with the host's SSH ED25519 key as the primary decryption key.

- **Host Key**: `/persistent/etc/ssh/ssh_host_ed25519_key`
- **Container Path**: `/var/lib/sops-nix/key.txt` (via read-only bind mount)

## Deployment

### 1. Initial Install (Fresh VPS)

We use `nixos-anywhere` for a "Big Bang" installation.

1. **Prepare Keys**: Place your SSH host key at `secrets-init/keys/persistent/etc/ssh/ssh_host_ed25519_key`.
2. **Deploy**:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#vps-arm \
     --extra-files secrets-init/keys \
     passwordless-sudo@[host-ip]
   ```
3. **Clone the repo** on the server for future deploys:
   ```bash
   ssh root@[host-ip]
   git clone https://github.com/toxx1220/nix-vps.git /persistent/nix-vps
   ```

### 2. CI Deploy Key Setup

Deployments are triggered via SSH with a **forced-command key** — a restricted SSH key that can only execute the deploy script, nothing else.

1. Generate a deploy key pair:
   ```bash
   ssh-keygen -t ed25519 -f deploy-key -N "" -C "ci-deploy"
   ```
2. Copy the **public key** into `host.nix` (replace the `CHANGE_ME` placeholder in root's `authorizedKeys`).
3. Add these **GitHub Actions secrets** to your repo (`Settings → Secrets and variables → Actions`):
   - `VPS_SSH_KEY` — contents of the private key file (`deploy-key`)
   - `VPS_HOST` — your server's IP address or hostname

### 3. Automated Updates

Two GitHub Actions workflows handle ongoing maintenance:

| Workflow | Trigger | What it does |
|---|---|---|
| **Deploy** (`.github/workflows/deploy.yml`) | Push to `main` | SSHes into VPS → `git pull` → `nixos-rebuild switch` |
| **Update Flake Inputs** (`.github/workflows/update-flake.yml`) | Weekly (Sunday 03:00 UTC) or manual | Runs `nix flake update` → creates a PR with the changes |

The update workflow creates a PR so you can review dependency changes before they're deployed. Merging the PR triggers the deploy workflow automatically.

### 4. Manual Rebuild

If you need to manually update the system:

```bash
ssh root@[host-ip]
cd /persistent/nix-vps
git pull
nixos-rebuild switch --flake .#vps-arm --accept-flake-config -L
```

Or with `nh`:

```bash
ssh root@[host-ip]
nh os switch /persistent/nix-vps
```

## How Changes Propagate

### Changing `host.nix` or `containers/*.nix`

When the system rebuilds, Nix calculates the diff:

- Changed a port in Caddy → only Caddy restarts
- Updated bot/backend code → only that container restarts
- Services that didn't change experience **zero downtime**

### Changing `disko.nix`

**⚠️ Be careful.** Disko defines your physical disk layout. Changing partition sizes or types on a live system is not possible — you'd need a fresh install. Get `disko.nix` right once, then leave it alone.

## Security Model

- **Personal SSH key**: Full root access for administration
- **CI deploy key**: Restricted via SSH `command=` — can _only_ run the deploy script. No shell, no port forwarding, no agent forwarding.
- **Garnix**: Builds and caches the NixOS closure (binary cache). Does _not_ have deploy access.
- **One-way data flow**: Repo → Server, never Server → Repo. The server has no write access to the git remote.

## Containers

Containers are defined using the `mkContainer` helper in `host.nix`:

| Container | Description | Status |
|---|---|---|
| `nannuo-bot` | Discord bot (upstream flake module) | ✅ Enabled |
| `bgs-backend` | Background search backend | ❌ Disabled |
| `test-container` | Sandbox for testing | ✅ Enabled |

## Troubleshooting

See [DEBUGGING.md](./DEBUGGING.md) for a cheat sheet on managing containers and logs.