# Supernova: Hysteria Installer

Supernova is a single-file Bash installer for setting up a private Hysteria v2 server. It can run Hysteria with Docker Compose or as a native systemd service, generates a self-signed certificate, and prints a client import link plus an optional QR code.

This project is intended for personal/private proxy nodes, not production infrastructure.

## Features

- Hysteria v2 only
- Docker Compose or systemd runtime
- Automatic self-signed certificate generation
- Optional Salamander or Gecko obfuscation
- Optional HTTP/HTTPS masquerade
- IPv4 and IPv6 client link output
- Runtime files generated under `/opt/supernova`
- Linux UDP buffer tuning persisted through `/etc/sysctl.d/90-supernova-hysteria.conf`

## One-Command Install

Run this on the server:

```bash
curl -fsSL https://raw.githubusercontent.com/meower1/Supernova/main/supernova.sh -o /tmp/supernova.sh && bash /tmp/supernova.sh install
```

The script is downloaded first instead of piped directly into Bash so the interactive prompts can read from your terminal correctly.

## Local Usage

```bash
git clone https://github.com/meower1/Supernova.git
cd Supernova
bash supernova.sh
```

You can also call actions directly:

```bash
bash supernova.sh install
bash supernova.sh show
bash supernova.sh uninstall
```

## Generated Files

Supernova writes runtime files to:

```text
/opt/supernova/hysteria/config.yaml
/opt/supernova/hysteria/compose.yaml
/opt/supernova/certs/cert.crt
/opt/supernova/certs/private.key
/opt/supernova/state/hy.txt
```

For systemd installs, the active Hysteria config is copied to `/etc/hysteria/config.yaml`.

On Linux, Supernova also writes `/etc/sysctl.d/90-supernova-hysteria.conf` when UDP buffer values need to be persisted for Hysteria performance. The file is removed by `bash supernova.sh uninstall`.

## Management

For Docker installs:

```bash
docker compose -f /opt/supernova/hysteria/compose.yaml up -d
docker compose -f /opt/supernova/hysteria/compose.yaml logs -f
docker compose -f /opt/supernova/hysteria/compose.yaml restart
docker compose -f /opt/supernova/hysteria/compose.yaml stop
```

For systemd installs:

```bash
sudo systemctl status hysteria-server.service
sudo systemctl restart hysteria-server.service
sudo journalctl -u hysteria-server.service -f
```

## License

See [LICENSE](LICENSE).
