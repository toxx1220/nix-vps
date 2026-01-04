2. The Deployment Plan

Phase A: Initial "Big Bang" (nixos-anywhere)
This is for a fresh VPS. It will wipe the disk and install your config.
1. Command: nix run github:nix-community/nixos-anywhere -- --flake .#vps root@<YOUR_VPS_IP>
2. What happens:
    * It connects via SSH.
    * It runs Disko to partition your drive.
    * It installs NixOS.
    * It reboots into your new system.

Phase B: Iterative Updates
Once NixOS is running, you don't need nixos-anywhere anymore.
1. Command: nixos-rebuild switch --flake .#vps --target-host root@<YOUR_VPS_IP>
2. What happens:
    * Nix builds the new configuration (locally or on the VPS).
    * It copies only the changed files to the VPS.
    * It switches the running services to the new versions.
    * Zero downtime for services that didn't change.

  ---

3. What happens when you change things?

* Changing `host.nix` or `microvms/*.nix`: When you run nixos-rebuild switch, Nix calculates the "diff". If you changed a port in Caddy, only Caddy restarts. If you updated the Kotlin backend code, only that MicroVM restarts.
* Changing `disko.nix`: Be careful here. Disko defines your physical hard drive layout (partitions, filesystems).
    * If you change a mount point, Nix will try to adjust it.
    * If you change partition sizes or types, nixos-rebuild usually cannot do this on a live system. You would typically need to re-run a fresh install or manually resize partitions (which is risky).
    * Rule of thumb: Get your disko.nix right once, then leave it alone.