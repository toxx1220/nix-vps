# NixOS Container & System Management Cheat Sheet

## Containers (`nixos-container`)

- `sudo nixos-container list` - List all defined containers
- `sudo nixos-container status <name>` - Show status of a container
- `sudo nixos-container root-login <name>` - Open a shell inside the container
- `sudo nixos-container run <name> -- <command>` - Run a command inside
- `sudo nixos-container stop <name>` - Stop a container
- `sudo nixos-container start <name>` - Start a container

## Service Management (`systemctl`)

- `systemctl status container@<name>` - Check host-side container service status
- `systemctl restart container@<name>` - Full reboot of a specific container
- `systemctl list-units "container@*"` - List all container services
- `systemctl -M <name> status <service>` - Check service status inside container

## Log Inspection (`journalctl`)

- `journalctl -u container@<name> -f` - Follow host-side container logs
- `journalctl -M <name> -u <service> -f` - Follow service logs **inside** the container
- `journalctl -M <name> -n 100` - See last 100 logs from inside the container

## Machine Management (`machinectl`)

- `machinectl list` - List active containers (machines)
- `machinectl shell <name>` - Open a shell (alternative to root-login)
- `machinectl status <name>` - Detailed runtime status of the container

## Network Debugging

- `ip addr show br0` - Check host bridge status
- `sudo nixos-container run <name> -- ip addr` - Check internal IP
- `curl -v <container-ip>:<port>` - Test connectivity from host
