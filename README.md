# VLESS Reality Agent

## Prerequisites

The script will automatically detect your OS and install missing dependencies (`wget`, `jq`, `sing-box`) when run. Supported distributions:

- **Alpine Linux** — via `apk` (sing-box from edge/community)
- **Debian / Ubuntu** — `apt-get` for `wget`/`jq`, `sing-box` downloaded from GitHub Releases

Non-root users will be prompted for `sudo` when installing packages.

## Usage

config generation command

```bash
wget https://raw.githubusercontent.com/Wakotu/vless-reality-agent-/refs/heads/main/gen-singbox-vless-reality.sh
chmod +x gen-singbox-vless-reality.sh
./gen-singbox-vless-reality.sh \
  --server-address <ip-or-domain> \
  --local-port 23907 \
  --public-port <public_port> \
  --server-name tesla.com

sing-box check -c config.json
```

sing-box run command:

```bash
wget https://raw.githubusercontent.com/Wakotu/vless-reality-agent-/refs/heads/main/setup-sing-box-logrotate.sh 
chmod +x setup-sing-box-logrotate.sh
./setup-sing-box-logrotate.sh config.json
```

## DDNS (Cloudflare)

If your VPS has a dynamic IP, use the DDNS script to keep a domain pointed to your server. It checks your public IP every few minutes and updates the Cloudflare DNS record when it changes.

### Setup

1. Create a Cloudflare API Token with **Zone → DNS → Edit** permission for your domain
2. Get your **Zone ID** from the Cloudflare dashboard (right sidebar on the domain overview page)
3. Fill in the config:
   ```bash
   cp ddns-update.env.example ddns-update.env
   chmod 600 ddns-update.env
   # Edit ddns-update.env with your values
   ```
4. Test:
   ```bash
   ./ddns-update.sh
   ```

### Cron deployment (recommended)

First, install the script and its config to `/usr/local/bin/`:
```bash
sudo cp ddns-update.sh /usr/local/bin/ddns-update.sh
sudo cp ddns-update.env /usr/local/bin/ddns-update.env
sudo chmod 600 /usr/local/bin/ddns-update.env
```

Then add a cron entry to check every 5 minutes:
```bash
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/ddns-update.sh") | crontab -
```

State is stored in `/var/lib/ddns-agent/last_ip`.

