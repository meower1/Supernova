#!/usr/bin/env bash
#
# Supernova: Hysteria-only one-file installer

export LANG=en_US.UTF-8

CYAN="\033[36m\033[01m"
BLUE="\033[34m\033[01m"
PINK="\033[95m\033[01m"
GREEN="\033[32m\033[01m"
PLAIN="\033[0m"
RESET="\033[0m"
RED="\033[31m\033[01m"
YELLOW="\033[33m\033[01m"

SUPERNOVA_HOME="${SUPERNOVA_HOME:-/opt/supernova}"
HY_DIR="$SUPERNOVA_HOME/hysteria"
CERT_DIR="$SUPERNOVA_HOME/certs"
STATE_DIR="$SUPERNOVA_HOME/state"
HY_MASQ_DIR="$HY_DIR/masq"
HY_CONFIG="$HY_DIR/config.yaml"
HY_COMPOSE="$HY_DIR/compose.yaml"
HY_LINK_FILE="$STATE_DIR/hy.txt"

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  SUDO="sudo"
fi

reset_terminal() {
  printf "%b" "$RESET"
  if [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && command -v tput >/dev/null 2>&1; then
    tput sgr0 2>/dev/null || true
  fi
}

handle_interrupt() {
  reset_terminal
  echo
  exit 130
}

handle_terminate() {
  reset_terminal
  echo
  exit 143
}

trap reset_terminal EXIT
trap handle_interrupt INT
trap handle_terminate TERM

cyan() { echo -e "${CYAN}$1${PLAIN}"; }
blue() { echo -e "${BLUE}$1${PLAIN}"; }
pink() { echo -e "${PINK}$1${PLAIN}"; }
red() { echo -e "${RED}$1${PLAIN}"; }
green() { echo -e "${GREEN}$1${PLAIN}"; }
yellow() { echo -e "${YELLOW}$1${PLAIN}"; }

is_yes() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_yes() {
  local answer
  read -rp "$1 (y/N) : " answer
  is_yes "$answer"
}

require_privileges() {
  if [ -n "$SUDO" ] && ! command -v sudo >/dev/null 2>&1; then
    red "This installer needs root privileges, but sudo is not installed."
    red "Run it as root or install sudo first."
    exit 1
  fi
}

random_alnum() {
  local length="$1"
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
  echo
}

install_file() {
  local source_file="$1"
  local target_file="$2"
  local mode="$3"
  local owner="${4:-}"

  if [ -n "$owner" ]; then
    $SUDO install -D -m "$mode" -o "$owner" -g "$owner" "$source_file" "$target_file"
  else
    $SUDO install -D -m "$mode" "$source_file" "$target_file"
  fi
}

sudo_cat() {
  local file="$1"
  if [ -r "$file" ]; then
    cat "$file"
  else
    $SUDO cat "$file"
  fi
}

ensure_runtime_dirs() {
  require_privileges
  $SUDO mkdir -p "$HY_DIR" "$CERT_DIR" "$STATE_DIR" "$HY_MASQ_DIR"
  $SUDO chmod 755 "$SUPERNOVA_HOME" "$HY_DIR" "$CERT_DIR" "$STATE_DIR" "$HY_MASQ_DIR"
}

select_hysteria_obfs_mode() {
  local answer

  while true; do
    echo
    echo -e "Select obfuscation mode:"
    echo -e "  ${BLUE}[1]${PLAIN} Salamander  ${GREEN}(default)${PLAIN}"
    echo -e "  ${BLUE}[2]${PLAIN} Gecko"
    read -rp "Choice: " answer
    [ -z "$answer" ] && answer=1

    case "$answer" in
      1)
        hysteria_obfs_mode=salamander
        return 0
        ;;
      2)
        hysteria_obfs_mode=gecko
        return 0
        ;;
      *)
        red "Invalid obfuscation mode. Please select 1 or 2."
        ;;
    esac
  done
}

validate_cert_files() {
  if [ ! -s "$CERT_DIR/cert.crt" ] || [ ! -f "$CERT_DIR/cert.crt" ]; then
    red "Certificate generation failed: $CERT_DIR/cert.crt is missing or invalid."
    exit 1
  fi

  if [ ! -s "$CERT_DIR/private.key" ] || [ ! -f "$CERT_DIR/private.key" ]; then
    red "Certificate generation failed: $CERT_DIR/private.key is missing or invalid."
    exit 1
  fi
}

tcp_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$port" 2>/dev/null | awk 'NR > 1 { found=1 } END { exit !found }'
    return
  fi

  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

print_docker_commands() {
  green "Management commands for Hysteria:"
  echo -e "${BLUE}Start:${PLAIN}   docker compose -f $HY_COMPOSE up -d"
  echo -e "${BLUE}Stop:${PLAIN}    docker compose -f $HY_COMPOSE stop"
  echo -e "${BLUE}Restart:${PLAIN} docker compose -f $HY_COMPOSE restart"
  echo -e "${BLUE}Logs:${PLAIN}    docker compose -f $HY_COMPOSE logs -f"
}

print_systemd_commands() {
  green "Management commands for Hysteria:"
  echo -e "${BLUE}Start:${PLAIN}   sudo systemctl start hysteria-server.service"
  echo -e "${BLUE}Stop:${PLAIN}    sudo systemctl stop hysteria-server.service"
  echo -e "${BLUE}Restart:${PLAIN} sudo systemctl restart hysteria-server.service"
  echo -e "${BLUE}Status:${PLAIN}  sudo systemctl status hysteria-server.service"
  echo -e "${BLUE}Logs:${PLAIN}    sudo journalctl -u hysteria-server.service -f"
}

print_qr_code() {
  local config_link="$1"

  if command -v qrencode >/dev/null 2>&1; then
    qrencode -m 2 -t utf8 <<< "$config_link"
  else
    yellow "qrencode is not installed; skipping QR code output."
  fi
}

curl_without_proxy() {
  env -u ALL_PROXY -u all_proxy -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy curl "$@"
}

proxy_env_is_set() {
  [ -n "${ALL_PROXY:-}${all_proxy:-}${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]
}

fetch_url() {
  local url="$1"
  local response

  response=$(curl -fsSL --connect-timeout 4 --max-time 8 "$url" 2>/dev/null || true)
  if [ -z "$response" ] && proxy_env_is_set; then
    response=$(curl_without_proxy -fsSL --connect-timeout 4 --max-time 8 "$url" 2>/dev/null || true)
  fi

  printf '%s' "$response"
}

get_public_ip() {
  local public_ip

  public_ip=$(fetch_url https://api.ipify.org)
  if [ -z "$public_ip" ]; then
    public_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  printf '%s' "$public_ip"
}

normalize_country_code() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z' | cut -c 1-2
}

is_valid_country_code() {
  local code="$1"
  [ "${#code}" -eq 2 ] && [ "$code" != "XX" ]
}

extract_country_code() {
  local response="$1"
  local code

  code=$(printf '%s' "$response" | tr -d '\r\n[:space:]')
  if is_valid_country_code "$(normalize_country_code "$code")" && [ "${#code}" -eq 2 ]; then
    normalize_country_code "$code"
    return
  fi

  code=$(printf '%s\n' "$response" | sed -nE 's/^loc=([A-Za-z]{2})$/\1/p' | head -1)
  if is_valid_country_code "$(normalize_country_code "$code")"; then
    normalize_country_code "$code"
    return
  fi

  code=$(printf '%s' "$response" | grep -Eo '"(country_code|country_code2|countryCode|country|cc)"[[:space:]]*:[[:space:]]*"[A-Za-z]{2}"' | head -1 | sed -E 's/.*"([A-Za-z]{2})"$/\1/')
  if is_valid_country_code "$(normalize_country_code "$code")"; then
    normalize_country_code "$code"
  fi
}

get_country_code() {
  local lookup_ip="$1"
  local detected_country
  local response
  local url
  local geo_urls=()

  if [ -n "$lookup_ip" ]; then
    geo_urls=(
      "https://ipinfo.io/$lookup_ip/country"
      "https://get.geojs.io/v1/ip/country/$lookup_ip.json"
      "https://api.iplocation.net/?ip=$lookup_ip"
      "https://ipwho.is/$lookup_ip"
      "https://ip.guide/$lookup_ip"
      "https://ipapi.co/$lookup_ip/country/"
      "http://ip-api.com/json/$lookup_ip?fields=status,countryCode"
    )
  else
    geo_urls=(
      "https://ipinfo.io/country"
      "https://ifconfig.co/country-iso"
      "https://www.cloudflare.com/cdn-cgi/trace"
      "https://api.country.is"
      "https://get.geojs.io/v1/ip/country.json"
      "https://api.myip.com"
      "https://ipwho.is/"
    )
  fi

  for url in "${geo_urls[@]}"; do
    response=$(fetch_url "$url")
    detected_country=$(extract_country_code "$response")
    if is_valid_country_code "$detected_country"; then
      printf '%s' "$detected_country"
      return
    fi
  done

  printf 'XX'
}

country_code_to_flag() {
  local code
  local flag=""
  local char
  local ascii
  local byte
  local escape
  local i

  code=$(normalize_country_code "$1")
  if ! is_valid_country_code "$code"; then
    return 1
  fi

  for i in 0 1; do
    char=${code:$i:1}
    printf -v ascii '%d' "'$char"
    byte=$((0xA6 + ascii - 65))
    printf -v escape '\\xF0\\x9F\\x87\\x%02X' "$byte"
    flag="$flag$(printf '%b' "$escape")"
  done

  printf '%s' "$flag"
}

country_code_to_label() {
  local code
  local flag

  code=$(normalize_country_code "$1")
  flag=$(country_code_to_flag "$code" || true)

  if [ -n "$flag" ]; then
    printf '%s' "$flag"
  else
    printf '%s' "${code:-XX}"
  fi
}

install_hysteria_official_systemd() {
  local installer_file
  installer_file=$(mktemp)

  if ! curl -fsSL --connect-timeout 10 --max-time 30 https://get.hy2.sh -o "$installer_file"; then
    rm -f "$installer_file"
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    $SUDO env "ALL_PROXY=${ALL_PROXY:-}" "all_proxy=${all_proxy:-}" "HTTPS_PROXY=${HTTPS_PROXY:-}" "https_proxy=${https_proxy:-}" "HTTP_PROXY=${HTTP_PROXY:-}" "http_proxy=${http_proxy:-}" timeout 120s bash "$installer_file"
  else
    $SUDO env "ALL_PROXY=${ALL_PROXY:-}" "all_proxy=${all_proxy:-}" "HTTPS_PROXY=${HTTPS_PROXY:-}" "https_proxy=${https_proxy:-}" "HTTP_PROXY=${HTTP_PROXY:-}" "http_proxy=${http_proxy:-}" bash "$installer_file"
  fi
  local install_status=$?
  rm -f "$installer_file"
  return $install_status
}

install_hysteria_systemd_service_file() {
  if ! id hysteria >/dev/null 2>&1; then
    $SUDO useradd -r -d /var/lib/hysteria -m hysteria
  fi

  $SUDO mkdir -p /var/lib/hysteria
  $SUDO chown hysteria:hysteria /var/lib/hysteria

  local service_file
  service_file=$(mktemp)
  cat > "$service_file" <<'EOF'
[Unit]
Description=Hysteria Server Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
WorkingDirectory=/var/lib/hysteria
User=hysteria
Group=hysteria
Environment=HYSTERIA_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
  install_file "$service_file" /etc/systemd/system/hysteria-server.service 0644
  rm -f "$service_file"
}

validate_hysteria_binary() {
  local hysteria_binary="$1"

  if [ ! -f "$hysteria_binary" ]; then
    return 1
  fi

  if [ ! -x "$hysteria_binary" ]; then
    $SUDO chmod 755 "$hysteria_binary" || return 1
  fi

  "$hysteria_binary" version >/dev/null 2>&1
}

show_hysteria_manual_install_instructions() {
  red "Failed to download or install the official Hysteria core for systemd."
  yellow "Download the Hysteria Linux binary manually, install it at /usr/local/bin/hysteria, then restart this script and select the systemd method again."
  yellow "Example for amd64:"
  yellow "  curl -fL -o hysteria-linux-amd64 https://github.com/apernet/hysteria/releases/download/app/v2.9.3/hysteria-linux-amd64"
  yellow "  sudo install -Dm755 hysteria-linux-amd64 /usr/local/bin/hysteria"
  yellow "  /usr/local/bin/hysteria version"
}

install_hysteria_systemd_runtime() {
  if [ -f /usr/local/bin/hysteria ]; then
    if ! validate_hysteria_binary /usr/local/bin/hysteria; then
      red "/usr/local/bin/hysteria exists but does not look like a valid Hysteria binary."
      show_hysteria_manual_install_instructions
      exit 1
    fi
    install_hysteria_systemd_service_file
    return
  fi

  if install_hysteria_official_systemd; then
    install_hysteria_systemd_service_file
    return
  fi

  show_hysteria_manual_install_instructions
  exit 1
}

clients() {
  echo -e "${BLUE}========================================================${PLAIN}"
  echo -e "${RED}Recommended Hysteria clients${PLAIN}"
  echo
  echo -e "${GREEN}Android${PLAIN}:"
  echo -e "${YELLOW}https://github.com/MatsuriDayo/NekoBoxForAndroid/releases${PLAIN}"
  echo
  echo -e "${GREEN}Windows/Linux/macOS${PLAIN}:"
  echo -e "${YELLOW}https://github.com/MatsuriDayo/nekoray/releases${PLAIN}"
  echo -e "${BLUE}========================================================${PLAIN}"
}

apt_install_if_available() {
  local packages=("$@")

  if command -v apt >/dev/null 2>&1; then
    $SUDO apt update || yellow "apt update failed; continuing with available package metadata."
    $SUDO apt install --no-upgrade "${packages[@]}" -y || yellow "Some dependencies could not be installed; verifying installed tools."
  fi
}

install_hysteria_base_dependencies() {
  local missing_packages=()
  local required_cmd

  for required_cmd in curl lsof openssl; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
      missing_packages+=("$required_cmd")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    apt_install_if_available "${missing_packages[@]}"
  fi

  for required_cmd in curl lsof openssl; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
      red "$required_cmd is required for Hysteria but is not installed."
      exit 1
    fi
  done

  if ! command -v qrencode >/dev/null 2>&1; then
    yellow "qrencode is not installed; QR code output will be skipped."
  fi
}

install_hysteria_docker_dependencies() {
  install_hysteria_base_dependencies

  if command -v docker >/dev/null 2>&1; then
    cyan "Docker is installed. Continuing..."
  else
    if [ "${SUPERNOVA_SKIP_DOCKER_INSTALL:-}" = "1" ]; then
      red "Docker is not installed and SUPERNOVA_SKIP_DOCKER_INSTALL=1 was set."
      exit 1
    fi
    pink "Installing Docker..."
    local installer_file
    installer_file=$(mktemp)
    curl -fsSL https://get.docker.com -o "$installer_file" || {
      rm -f "$installer_file"
      red "Failed to download Docker installer."
      exit 1
    }
    $SUDO sh "$installer_file"
    rm -f "$installer_file"
  fi

  if ! docker compose version >/dev/null 2>&1 && ! $SUDO docker compose version >/dev/null 2>&1; then
    red "Docker Compose v2 is required but was not found."
    exit 1
  fi
}

get_cert() {
  local private_key_tmp
  local cert_tmp

  ensure_runtime_dirs

  if [ -s "$CERT_DIR/cert.crt" ] && [ -f "$CERT_DIR/cert.crt" ] && [ -s "$CERT_DIR/private.key" ] && [ -f "$CERT_DIR/private.key" ]; then
    cyan "Found certificates. Continuing..."
    return
  fi

  private_key_tmp=$(mktemp)
  cert_tmp=$(mktemp)

  if ! openssl ecparam -genkey -name prime256v1 -out "$private_key_tmp"; then
    rm -f "$private_key_tmp" "$cert_tmp"
    red "Failed to generate private key."
    exit 1
  fi

  if ! openssl req -new -x509 -days 36500 -key "$private_key_tmp" -out "$cert_tmp" -subj "/CN=bing.com"; then
    rm -f "$private_key_tmp" "$cert_tmp"
    red "Failed to generate certificate."
    exit 1
  fi

  install_file "$private_key_tmp" "$CERT_DIR/private.key" 0640
  install_file "$cert_tmp" "$CERT_DIR/cert.crt" 0644
  rm -f "$private_key_tmp" "$cert_tmp"

  validate_cert_files
}

docker_container_exists() {
  command -v docker >/dev/null 2>&1 || return 1

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx hysteria; then
    return 0
  fi

  $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx hysteria
}

docker_compose_up() {
  if docker ps >/dev/null 2>&1; then
    docker compose -f "$HY_COMPOSE" up -d
  else
    $SUDO docker compose -f "$HY_COMPOSE" up -d
  fi
}

docker_remove_hysteria() {
  command -v docker >/dev/null 2>&1 || return 0

  if docker ps >/dev/null 2>&1; then
    docker rm -f hysteria >/dev/null 2>&1 || true
  else
    $SUDO docker rm -f hysteria >/dev/null 2>&1 || true
  fi
}

systemd_hysteria_exists() {
  systemctl list-unit-files hysteria-server.service --no-legend 2>/dev/null | grep -q hysteria-server.service || [ -f /etc/systemd/system/hysteria-server.service ]
}

write_hysteria_compose() {
  local compose_tmp
  compose_tmp=$(mktemp)

  cat > "$compose_tmp" <<EOF
services:
  hysteria:
    image: tobyxdd/hysteria
    container_name: hysteria
    restart: on-failure
    network_mode: "host"
    volumes:
      - $HY_CONFIG:/etc/hysteria/config.yaml:ro
      - $CERT_DIR/cert.crt:/etc/hysteria/certs/cert.crt:ro
      - $CERT_DIR/private.key:/etc/hysteria/certs/private.key:ro
      - $HY_MASQ_DIR:/www/masq:ro
    command: ["server", "-c", "/etc/hysteria/config.yaml"]
EOF

  install_file "$compose_tmp" "$HY_COMPOSE" 0644
  rm -f "$compose_tmp"
}

write_static_masquerade_site() {
  local index_tmp
  index_tmp=$(mktemp)

  cat > "$index_tmp" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Welcome to nginx!</title>
  <style>
    body { font-family: Arial, sans-serif; background: #fff; color: #333; margin: 0; padding: 40px; }
    h1 { font-size: 2em; border-bottom: 1px solid #ddd; padding-bottom: 12px; }
    p { line-height: 1.6; }
    a { color: #067df7; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .footer { margin-top: 40px; font-size: 0.85em; color: #999; }
  </style>
</head>
<body>
  <h1>Welcome to nginx!</h1>
  <p>If you see this page, the nginx web server is successfully installed and working.
     Further configuration is required.</p>
  <p>For online documentation and support please refer to
     <a href="https://nginx.org/">nginx.org</a>.<br />
     Commercial support is available at <a href="https://nginx.com/">nginx.com</a>.</p>
  <p class="footer"><em>Thank you for using nginx.</em></p>
</body>
</html>
EOF

  install_file "$index_tmp" "$HY_MASQ_DIR/index.html" 0644
  rm -f "$index_tmp"
}

apply_udp_buffer_tuning() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    $SUDO sysctl -w net.core.rmem_max=16777216
    $SUDO sysctl -w net.core.wmem_max=16777216
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    $SUDO sysctl -w kern.ipc.maxsockbuf=20971520
    $SUDO sysctl -w net.inet.udp.recvspace=16777216
  fi
}

uninstall_hysteria() {
  require_privileges
  docker_remove_hysteria

  if [ -f /etc/hysteria/.supernova-managed ]; then
    $SUDO systemctl disable --now hysteria-server.service >/dev/null 2>&1 || true
    $SUDO rm -rf /etc/hysteria
    $SUDO rm -f /etc/systemd/system/hysteria-server.service
    $SUDO rm -f /etc/systemd/system/hysteria-server@.service
    $SUDO rm -rf /etc/systemd/system/hysteria-server.service.d
    $SUDO rm -f /usr/local/bin/hysteria
    $SUDO rm -rf /var/lib/hysteria
    if id hysteria >/dev/null 2>&1; then
      $SUDO userdel hysteria >/dev/null 2>&1 || true
    fi
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  $SUDO rm -rf "$HY_DIR" "$STATE_DIR"
  green "Hysteria has been uninstalled."
}

install_hysteria() {
  local hy_setup_method
  local hy_runtime
  local auth_pass
  local obfs_pass=""
  local server_ip
  local ipv6
  local hy_country_code
  local hy_location_label
  local hy_port
  local config_tmp
  local masq_type=""
  local masq_addr
  local hy_query
  local hy_fragment
  local hy_link
  local hy_ipv6_link=""

  clear
  require_privileges
  ensure_runtime_dirs
  $SUDO rm -f "$HY_LINK_FILE"

  local hy_docker_exists=false
  local hy_systemd_exists=false

  if docker_container_exists; then
    hy_docker_exists=true
  fi

  if systemd_hysteria_exists; then
    hy_systemd_exists=true
  fi

  if [ "$hy_docker_exists" = true ] || [ "$hy_systemd_exists" = true ]; then
    if [ "$hy_docker_exists" = true ] && [ "$hy_systemd_exists" = true ]; then
      yellow "An existing Hysteria installation was detected (Docker container + systemd service)."
    elif [ "$hy_docker_exists" = true ]; then
      yellow "An existing Hysteria Docker container was detected."
    else
      yellow "An existing Hysteria systemd service was detected."
    fi

    if confirm_yes "Would you like to reinstall Hysteria?"; then
      uninstall_hysteria
      ensure_runtime_dirs
    else
      exit 0
    fi
  fi

  echo
  echo -e "Select Hysteria setup method:"
  echo -e "  ${BLUE}[1]${PLAIN} Docker  ${GREEN}(default)${PLAIN}"
  echo -e "  ${BLUE}[2]${PLAIN} systemd service"
  read -rp "Choice: " hy_setup_method
  [ -z "$hy_setup_method" ] && hy_setup_method=1

  case "$hy_setup_method" in
    1) hy_runtime=docker ;;
    2) hy_runtime=systemd ;;
    *) red "Invalid Hysteria setup method." && exit 1 ;;
  esac

  if [ "$hy_runtime" = "docker" ]; then
    install_hysteria_docker_dependencies
  else
    install_hysteria_base_dependencies
  fi

  get_cert

  auth_pass=$(random_alnum 30)
  hysteria_obfs_mode=""
  server_ip=$(get_public_ip)
  hy_country_code=$(get_country_code "$server_ip")
  hy_location_label=$(country_code_to_label "$hy_country_code")
  ipv6=$(curl -s6m8 ip.sb -k 2>/dev/null || true)

  clear
  read -rp "Hysteria port [default: 443]: " hy_port
  [ -z "$hy_port" ] && hy_port=443
  if tcp_port_in_use "$hy_port"; then
    red "Port $hy_port is occupied. Please try another port."
    exit 1
  fi

  config_tmp=$(mktemp)
  cat > "$config_tmp" <<EOF
listen: :$hy_port
tls:
  cert: /etc/hysteria/certs/cert.crt
  key: /etc/hysteria/certs/private.key
auth:
  type: password
  password: $auth_pass
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
bandwidth:
  up: 1 gbps
  down: 1 gbps
ignoreClientBandwidth: true
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: https
  https:
    addr: 1.1.1.1:443
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
acl:
  inline:
    - reject(*.ir)
    - reject(all, udp/443)
EOF

  if confirm_yes "Would you like to enable obfuscation?"; then
    select_hysteria_obfs_mode
    obfs_pass=$(random_alnum 30)

    if [ "$hysteria_obfs_mode" = "gecko" ]; then
      cat >> "$config_tmp" <<EOF
obfs:
  type: gecko
  gecko:
    password: $obfs_pass
    minPacketSize: 512
    maxPacketSize: 1200
EOF
    else
      cat >> "$config_tmp" <<EOF
obfs:
  type: salamander
  salamander:
    password: $obfs_pass
EOF
    fi
  fi

  if confirm_yes "Would you like to enable HTTP/HTTPS masquerade? [allocates ports 80/443]"; then
    if tcp_port_in_use 80; then
      rm -f "$config_tmp"
      red "Port 80 is occupied. Disable masquerade or free port 80 before continuing."
      exit 1
    fi

    if tcp_port_in_use 443; then
      rm -f "$config_tmp"
      red "Port 443 is occupied. Disable masquerade or free port 443 before continuing."
      exit 1
    fi

    echo
    echo -e "Select masquerade mode:"
    echo -e "  ${BLUE}[1]${PLAIN} Proxy  ${GREEN}(default)${PLAIN} - mirror a real website"
    echo -e "  ${BLUE}[2]${PLAIN} String - return a static API-like response"
    echo -e "  ${BLUE}[3]${PLAIN} File   - serve a local static site"
    read -rp "Choice: " masq_type
    [ -z "$masq_type" ] && masq_type=1

    case "$masq_type" in
      1)
        read -rp "Masquerade website address [default: vipofilm.com]: " masq_addr
        [ -z "$masq_addr" ] && masq_addr=vipofilm.com
        cat >> "$config_tmp" <<EOF
masquerade:
  type: proxy
  proxy:
    url: https://$masq_addr
    rewriteHost: true
    insecure: false
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF
        ;;
      2)
        cat >> "$config_tmp" <<'EOF'
masquerade:
  type: string
  string:
    content: '{"status":"healthy","version":"1.0.0","timestamp":0}'
    headers:
      content-type: application/json
      cache-control: no-store
      x-request-id: 00000000-0000-0000-0000-000000000000
    statusCode: 200
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF
        ;;
      3)
        write_static_masquerade_site
        cat >> "$config_tmp" <<'EOF'
masquerade:
  type: file
  file:
    dir: /www/masq
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF
        cyan "Static masquerade site written to $HY_MASQ_DIR/index.html"
        ;;
      *)
        yellow "Invalid masquerade mode. Skipping masquerade configuration."
        ;;
    esac
  fi

  install_file "$config_tmp" "$HY_CONFIG" 0640
  rm -f "$config_tmp"

  apply_udp_buffer_tuning

  if [ "$hy_runtime" = "docker" ]; then
    write_hysteria_compose
    docker_compose_up
  else
    install_hysteria_systemd_runtime
    $SUDO mkdir -p /etc/hysteria/certs /etc/systemd/system/hysteria-server.service.d
    install_file "$HY_CONFIG" /etc/hysteria/config.yaml 0640 hysteria
    install_file "$CERT_DIR/cert.crt" /etc/hysteria/certs/cert.crt 0644 hysteria
    install_file "$CERT_DIR/private.key" /etc/hysteria/certs/private.key 0640 hysteria
    if [ "${masq_type:-}" = "3" ] && [ -d "$HY_MASQ_DIR" ]; then
      $SUDO mkdir -p /etc/hysteria/masq
      $SUDO cp -R "$HY_MASQ_DIR/." /etc/hysteria/masq/
      $SUDO chown -R hysteria:hysteria /etc/hysteria/masq
      cyan "Masquerade static files installed to /etc/hysteria/masq/"
    fi
    echo "managed_by=supernova" | $SUDO tee /etc/hysteria/.supernova-managed >/dev/null
    $SUDO chown -R hysteria:hysteria /etc/hysteria

    local override_file
    override_file=$(mktemp)
    cat > "$override_file" <<'EOF'
[Service]
Restart=on-failure
RestartSec=5s
EOF
    install_file "$override_file" /etc/systemd/system/hysteria-server.service.d/supernova.conf 0644
    rm -f "$override_file"

    $SUDO systemctl daemon-reload
    $SUDO systemctl enable --now hysteria-server.service
  fi

  clear
  clients

  hy_query="insecure=1&sni=google.com"
  hy_fragment="Hysteria%20($hy_location_label)"

  if [ -n "$obfs_pass" ]; then
    hy_query="${hy_query}&obfs=$hysteria_obfs_mode&obfs-password=$obfs_pass"
    hy_fragment="Hysteria%20%2B%20Obfs%20($hy_location_label)"
  fi

  hy_link="hy2://$auth_pass@$server_ip:$hy_port/?$hy_query#$hy_fragment"

  if [ -n "$obfs_pass" ]; then
    blue "Obfuscation mode: $hysteria_obfs_mode"
  fi

  blue "
$hy_link
"

  if [ -n "$ipv6" ]; then
    hy_ipv6_link="hy2://$auth_pass@[$ipv6]:$hy_port/?$hy_query#$hy_fragment"
    yellow "Irancell (IPv6):
$hy_ipv6_link
"
  fi

  print_qr_code "$hy_link"

  {
    printf '%s\n' "$hy_link"
    if [ -n "$hy_ipv6_link" ]; then
      printf '\nIrancell (IPv6):\n%s\n' "$hy_ipv6_link"
    fi
  } | $SUDO tee "$HY_LINK_FILE" >/dev/null
  $SUDO chmod 0640 "$HY_LINK_FILE"

  if [ "$hy_runtime" = "docker" ]; then
    print_docker_commands
  else
    print_systemd_commands
  fi
}

show_hysteria_conf() {
  clear
  clients

  if [ ! -f "$HY_LINK_FILE" ]; then
    red "No saved Hysteria configuration link was found at $HY_LINK_FILE."
    red "Install Hysteria first."
    exit 1
  fi

  sudo_cat "$HY_LINK_FILE"
  echo
  print_qr_code "$(sudo_cat "$HY_LINK_FILE" | head -1)"
}

menu() {
  echo -e "${PINK}         ___---___${RESET}"
  echo -e "${BLUE}      .--         --.${RESET}"
  echo -e "${PINK}    ./   ()      .-. \\ ${RESET}"
  echo -e "${BLUE}   /   o    .   (   )  \\ ${RESET}"
  echo -e "${PINK}  / .            '-'    \\ ${RESET}"
  echo -e "${BLUE} | ()    .  O         .  |${RESET}"
  echo -e "${PINK}|                         |${RESET}"
  echo -e "${BLUE}|    o           ()       |${RESET}"
  echo -e "${PINK}|       .--.          O   |${RESET}"
  echo -e "${BLUE} | .   |    |            |${RESET}"
  echo -e "${PINK}  \\    \`.__.'    o   .  /${RESET}"
  echo -e "${BLUE}   \\                   /${RESET}"
  echo -e "${PINK}    \`\\  o    ()      /' -meower1${RESET}"
  echo -e "${BLUE}      \`--___   ___--'${RESET}"
  echo -e "${PINK}            ---${RESET}"

  blue "############################"
  pink "          Supernova"
  blue "############################"
  echo
  echo -e " ${GREEN}1.${PLAIN} Install ${PINK}Hysteria${PLAIN}"
  echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Hysteria${PLAIN}"
  echo -e " ${GREEN}3.${PLAIN} Show configuration link for Hysteria"
  echo ""
  read -rp $'\033[1;32m Please select an option [1-3]: ' menu_input

  case "$menu_input" in
    1) install_hysteria ;;
    2) uninstall_hysteria ;;
    3) show_hysteria_conf ;;
    *) exit 1 ;;
  esac
}

case "${1:-menu}" in
  install|--install) install_hysteria ;;
  uninstall|--uninstall|remove|--remove) uninstall_hysteria ;;
  show|--show|config|--config) show_hysteria_conf ;;
  menu|--menu) menu ;;
  *)
    red "Usage: $0 [install|uninstall|show|menu]"
    exit 1
    ;;
esac
