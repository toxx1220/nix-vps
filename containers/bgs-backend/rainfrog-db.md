```bash
sudo nixos-container root-login bgs-backend
su -s /bin/sh postgres
rainfrog --driver postgres --host /var/run/postgresql --database bgs_db
```