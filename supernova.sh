#!/bin/bash
#
# Setup multiple udp based proxies


export LANG=en_US.UTF-8
####################### Color pallete
CYAN="\033[36m\033[01m"
BLUE="\033[34m\033[01m"
PINK="\033[95m\033[01m"
GREEN="\033[32m\033[01m"
PLAIN="\033[0m"
RESET="\033[0m"
RED="\033[31m\033[01m"
YELLOW="\033[33m\033[01m"

reset_terminal() {
  printf "%b" "$RESET"
  if [ -n "$TERM" ] && [ "$TERM" != "dumb" ] && command -v tput >/dev/null 2>&1; then
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


cyan() { echo -e "\033[36m\033[01m$1\033[0m"; }
blue() { echo -e "\033[34m\033[01m$1\033[0m"; }
pink() { echo -e "\033[95m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
magenta() { echo -e "\033[35m\033[01m$1\033[0m"; }
#######################

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

ensure_cert_file() {
  local cert_file="$1"
  if [ -d "$cert_file" ]; then
    rm -rf "$cert_file"
  fi
}

validate_cert_files() {
  if [ ! -s certs/cert.crt ] || [ ! -f certs/cert.crt ]; then
    red "Certificate generation failed: certs/cert.crt is missing or invalid."
    exit 1
  fi

  if [ ! -s certs/private.key ] || [ ! -f certs/private.key ]; then
    red "Certificate generation failed: certs/private.key is missing or invalid."
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
  local service_name="$1"
  local compose_dir="$2"

  green "Management commands for $service_name:"
  echo -e "${BLUE}Start:${PLAIN}   cd $compose_dir && docker compose up -d"
  echo -e "${BLUE}Stop:${PLAIN}    cd $compose_dir && docker compose stop"
  echo -e "${BLUE}Restart:${PLAIN} cd $compose_dir && docker compose restart"
  echo -e "${BLUE}Logs:${PLAIN}    cd $compose_dir && docker compose logs -f"
}

print_systemd_commands() {
  local service_name="$1"
  local unit_name="$2"

  green "Management commands for $service_name:"
  echo -e "${BLUE}Start:${PLAIN}   sudo systemctl start $unit_name"
  echo -e "${BLUE}Stop:${PLAIN}    sudo systemctl stop $unit_name"
  echo -e "${BLUE}Restart:${PLAIN} sudo systemctl restart $unit_name"
  echo -e "${BLUE}Status:${PLAIN}  sudo systemctl status $unit_name"
  echo -e "${BLUE}Logs:${PLAIN}    sudo journalctl -u $unit_name -f"
}

print_qr_code() {
  local config_link="$1"

  if [ -x "$(command -v qrencode)" ]; then
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
  [ ${#code} -eq 2 ] && [ "$code" != "XX" ]
}

extract_country_code() {
  local response="$1"
  local code

  code=$(printf '%s' "$response" | tr -d '\r\n[:space:]')
  if is_valid_country_code "$(normalize_country_code "$code")" && [ ${#code} -eq 2 ]; then
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
    sudo env "ALL_PROXY=${ALL_PROXY:-}" "all_proxy=${all_proxy:-}" "HTTPS_PROXY=${HTTPS_PROXY:-}" "https_proxy=${https_proxy:-}" "HTTP_PROXY=${HTTP_PROXY:-}" "http_proxy=${http_proxy:-}" timeout 120s bash "$installer_file"
  else
    sudo env "ALL_PROXY=${ALL_PROXY:-}" "all_proxy=${all_proxy:-}" "HTTPS_PROXY=${HTTPS_PROXY:-}" "https_proxy=${https_proxy:-}" "HTTP_PROXY=${HTTP_PROXY:-}" "http_proxy=${http_proxy:-}" bash "$installer_file"
  fi
  local install_status=$?
  rm -f "$installer_file"
  return $install_status
}

install_hysteria_systemd_service_file() {
  if ! id hysteria >/dev/null 2>&1; then
    sudo useradd -r -d /var/lib/hysteria -m hysteria
  fi

  sudo mkdir -p /var/lib/hysteria
  sudo chown hysteria:hysteria /var/lib/hysteria

  cat <<EOF | sudo tee /etc/systemd/system/hysteria-server.service >/dev/null
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
}

validate_hysteria_binary() {
  local hysteria_binary="$1"

  if [ ! -f "$hysteria_binary" ]; then
    return 1
  fi

  if [ ! -x "$hysteria_binary" ]; then
    sudo chmod 755 "$hysteria_binary" || return 1
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
    return
  fi

  show_hysteria_manual_install_instructions
  exit 1
}

clients(){

echo -e "${BLUE}========================================================${PLAIN}"
echo -e "${RED}Recommended clients${PLAIN}"
echo
echo -e "${GREEN}Android${PLAIN}":
echo -e "${YELLOW}https://github.com/MatsuriDayo/NekoBoxForAndroid/releases${PLAIN}"
echo
echo -e "${GREEN}Windows/Linux/Macos${PLAIN}":
echo -e "${YELLOW}https://github.com/MatsuriDayo/nekoray/releases${PLAIN}"
echo
echo -e "${GREEN}Brook${PLAIN}":
echo -e "${YELLOW}https://www.txthinking.com/brook.html${PLAIN}"
echo
echo -e "${GREEN}Mieru (Sagernet + Mieru plugin)${PLAIN}":
echo -e "${YELLOW}https://github.com/SagerNet/SagerNet/releases/download/0.8.1-rc03/SN-0.8.1-rc03-arm64-v8a.apk${PLAIN}"
echo -e "${YELLOW}https://github.com/SagerNet/SagerNet/releases/download/mieru-plugin-1.15.1/mieru-plugin-1.15.1-arm64-v8a.apk${PLAIN}"
echo
echo -e "${GREEN}Naive (Naive plugin for Nekobox)${PLAIN}":
echo -e "${YELLOW}https://github.com/SagerNet/SagerNet/releases/download/naive-plugin-116.0.5845.92-2/naive-plugin-116.0.5845.92-2-arm64-v8a.apk${PLAIN}"
echo
echo -e "${GREEN}Juicity (Juicity plugin for Nekobox)${PLAIN}":
echo -e "${YELLOW}https://github.com/MatsuriDayo/plugins/releases/download/juicity-v0.3.0/juicity-plugin-v0.3.0-arm64-v8a.apk${PLAIN}"
echo -e "${BLUE}========================================================${PLAIN}"
}

# ipv4_to_6() {   #work in progress...

# str=$server_ip  #reading string value  
  
# IFS='.' #setting space as delimiter  
# read -ra ADDR <<<"$str" #reading str as an array as tokens separated by IFS  

# arrVar=()
  
# for i in "${ADDR[@]}"; do #accessing each element of array   

# hexadecimal=$(printf "%X" "$i")
# arrVar+=($hexadecimal)

# done  

# ipv6_sub="::ffff:${arrVar[0]}${arrVar[1]}:${arrVar[2]}${arrVar[3]}"

# }

install_base_dependencies() {

  sudo apt update || yellow "apt update failed; continuing with available package metadata."
  sudo apt install --no-upgrade net-tools uuid-runtime wget qrencode jq curl lsof openssl -y || yellow "Some dependencies could not be installed; continuing with installed tools."

  for required_cmd in curl lsof openssl; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
      red "$required_cmd is required but is not installed."
      exit 1
    fi
  done
}

install_hysteria_base_dependencies() {
  local missing_packages=()

  for required_cmd in curl lsof openssl; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
      missing_packages+=("$required_cmd")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    sudo apt update || yellow "apt update failed; continuing with available package metadata."
    sudo apt install --no-upgrade "${missing_packages[@]}" -y || yellow "Some Hysteria dependencies could not be installed; verifying installed tools."
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

install_docker_dependencies() {
  install_base_dependencies

  if [ -x "$(command -v docker)" ]; then
    cyan "Docker is installed. Continueing..."
  else
    if [ "$SUPERNOVA_SKIP_DOCKER_INSTALL" = "1" ]; then
      red "Docker is not installed and SUPERNOVA_SKIP_DOCKER_INSTALL=1 was set."
      exit 1
    fi
    pink "Installing Docker..."
    curl -fsSL https://get.docker.com -o install-docker.sh
    sudo sh install-docker.sh
  fi 
}

install_hysteria_docker_dependencies() {
  install_hysteria_base_dependencies

  if [ -x "$(command -v docker)" ]; then
    cyan "Docker is installed. Continueing..."
  else
    if [ "$SUPERNOVA_SKIP_DOCKER_INSTALL" = "1" ]; then
      red "Docker is not installed and SUPERNOVA_SKIP_DOCKER_INSTALL=1 was set."
      exit 1
    fi
    pink "Installing Docker..."
    curl -fsSL https://get.docker.com -o install-docker.sh
    sudo sh install-docker.sh
  fi
}

install_dependencies() {
  install_docker_dependencies
}

country_code=$(get_country_code)

get_cert() {

mkdir -p certs
ensure_cert_file certs/cert.crt
ensure_cert_file certs/private.key

if [ -s certs/cert.crt ] && [ -f certs/cert.crt ] && [ -s certs/private.key ] && [ -f certs/private.key ]; then 
  cyan "Found certificates. continuing..."
  return
fi

# Generate self signed certificate
rm -f certs/cert.crt certs/private.key

if ! openssl ecparam -genkey -name prime256v1 -out certs/private.key; then
  red "Failed to generate certs/private.key."
  exit 1
fi

if ! openssl req -new -x509 -days 36500 -key certs/private.key -out certs/cert.crt -subj "/CN=bing.com"; then
  red "Failed to generate certs/cert.crt."
  exit 1
fi

validate_cert_files
}

uninstall_hysteria() {
  if [ -x "$(command -v docker)" ]; then
    sudo docker rm -f hysteria >/dev/null 2>&1 || true
  fi

  if [ -f /etc/hysteria/.supernova-managed ]; then
    sudo systemctl disable --now hysteria-server.service >/dev/null 2>&1 || true
    sudo rm -rf /etc/hysteria
    sudo rm -f /etc/systemd/system/hysteria-server.service
    sudo rm -f /etc/systemd/system/hysteria-server@.service
    sudo rm -rf /etc/systemd/system/hysteria-server.service.d
    sudo rm -f /usr/local/bin/hysteria
    sudo rm -rf /var/lib/hysteria
    if id hysteria >/dev/null 2>&1; then
      sudo userdel hysteria >/dev/null 2>&1 || true
    fi
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  rm -f temp/hy.txt
  green "Hysteria has been uninstalled."
}

uninstall_tuic() {
  sudo docker rm -f tuic-server
  rm temp/tuic.txt
  green "Tuic has been uninstalled."
}

uninstall_Brook() {
  sudo docker rm -f brook
  rm temp/br.txt
  green "Brook has been uninstalled."
}

uninstall_mieru() {
  mita stop
  rm temp/mi.txt
  sudo apt remove mita -y
}

uninstall_naive() {
  sudo docker rm -f naiveproxy
  rm temp/na.txt
  rm -r /etc/naiveproxy
  rm -r /var/www/html
  rm -r /var/log/caddy
  green "Naiveproxy has been uninstalled."
}

uninstall_juicity() {
  sudo rm juicity/juicity-server
  rm /etc/systemd/system/juicity-server.service
  rm temp/ju.txt
  green "Juicity has been uninstalled."
}


install_hysteria() {
rm -f temp/hy.txt
clear

# Detect any existing Hysteria installation (Docker or systemd) before asking setup method
_hy_docker_exists=false
_hy_systemd_exists=false

if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx hysteria; then
  _hy_docker_exists=true
fi

if systemctl list-unit-files hysteria-server.service --no-legend 2>/dev/null | grep -q hysteria-server.service || [ -f /etc/systemd/system/hysteria-server.service ]; then
  _hy_systemd_exists=true
fi

if [ "$_hy_docker_exists" = true ] || [ "$_hy_systemd_exists" = true ]; then
  if [ "$_hy_docker_exists" = true ] && [ "$_hy_systemd_exists" = true ]; then
    yellow "An existing Hysteria installation was detected (Docker container + systemd service)."
  elif [ "$_hy_docker_exists" = true ]; then
    yellow "An existing Hysteria Docker container was detected."
  else
    yellow "An existing Hysteria systemd service was detected."
  fi

  if confirm_yes "Would you like to reinstall Hysteria?"; then
    uninstall_hysteria
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
rm -f hysteria/config.yaml
auth_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
obfs_pass=""
hysteria_obfs_mode=""
server_ip=$(get_public_ip)
hy_country_code=$(get_country_code "$server_ip")
hy_location_label=$(country_code_to_label "$hy_country_code")
ipv6=$(curl -s6m8 ip.sb -k)
clear
read -rp "Hysteria port [default: 443]: " hy_port
[ -z "$hy_port" ] && hy_port=443
[ $(lsof -i :$hy_port | grep :$hy_port | wc -l) -gt 0 ] && red "Port $hy_port is occupied. Please try another port." && exit 1


cat <<EOF > hysteria/config.yaml
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
  obfs_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')

  if [ "$hysteria_obfs_mode" = "gecko" ]; then
cat <<EOF >> hysteria/config.yaml
obfs:
  type: gecko
  gecko:
    password: $obfs_pass
    minPacketSize: 512
    maxPacketSize: 1200
EOF
  else
cat <<EOF >> hysteria/config.yaml
obfs:
  type: salamander
  salamander:
    password: $obfs_pass
EOF
  fi
fi

if confirm_yes "Would you like to enable HTTP/HTTPS masquerade? [allocates ports 80/443]"; then

  if tcp_port_in_use 80; then
    red "Port 80 is occupied. Disable masquerade or free port 80 before continuing."
    exit 1
  fi

  if tcp_port_in_use 443; then
    red "Port 443 is occupied. Disable masquerade or free port 443 before continuing."
    exit 1
  fi

  echo
  echo -e "Select masquerade mode:"
  echo -e "  ${BLUE}[1]${PLAIN} Proxy  ${GREEN}(default)${PLAIN} — mirror a real website"
  echo -e "  ${BLUE}[2]${PLAIN} String — return a static API-like response"
  echo -e "  ${BLUE}[3]${PLAIN} File   — serve a local static site"
  read -rp "Choice: " masq_type
  [ -z "$masq_type" ] && masq_type=1

  case "$masq_type" in
    1)
      read -rp "Masquerade website address [default: vipofilm.com]: " masq_addr
      [ -z "$masq_addr" ] && masq_addr=vipofilm.com
      cat <<EOF >> hysteria/config.yaml
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
      cat <<'EOF' >> hysteria/config.yaml
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
      mkdir -p hysteria/masq
      cat <<'HTMLEOF' > hysteria/masq/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Welcome to nginx!</title>
  <style>
    body { font-family: Arial, sans-serif; background: #fff; color: #333; margin: 0; padding: 40px; }
    h1 { font-size: 2em; border-bottom: 1px solid #ddd; padding-bottom: 12px; }
    p  { line-height: 1.6; }
    a  { color: #067df7; text-decoration: none; }
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
HTMLEOF
      cat <<'EOF' >> hysteria/config.yaml
masquerade:
  type: file
  file:
    dir: /www/masq
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF
      cyan "Static masquerade site written to hysteria/masq/index.html"
      ;;
    *)
      red "Invalid masquerade mode. Skipping masquerade configuration."
      ;;
  esac
fi

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Set both buffers to 16 MB
    sudo sysctl -w net.core.rmem_max=16777216
    sudo sysctl -w net.core.wmem_max=16777216
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # UDP send buffer doesn't exist on BSD, so there's no "sendspace" to set
    sudo sysctl -w kern.ipc.maxsockbuf=20971520
    sudo sysctl -w net.inet.udp.recvspace=16777216
fi

if [ "$hy_runtime" = "docker" ]; then
  (cd hysteria && docker compose up -d)
else
  install_hysteria_systemd_runtime
  sudo mkdir -p /etc/hysteria/certs /etc/systemd/system/hysteria-server.service.d
  sudo install -m 0640 hysteria/config.yaml /etc/hysteria/config.yaml
  sudo install -m 0644 certs/cert.crt /etc/hysteria/certs/cert.crt
  sudo install -m 0640 certs/private.key /etc/hysteria/certs/private.key
  if [ "${masq_type:-}" = "3" ] && [ -d hysteria/masq ]; then
    sudo mkdir -p /etc/hysteria/masq
    sudo cp -r hysteria/masq/. /etc/hysteria/masq/
    cyan "Masquerade static files installed to /etc/hysteria/masq/"
  fi
  if id hysteria >/dev/null 2>&1; then
    sudo chown -R hysteria:hysteria /etc/hysteria
  fi
  echo "managed_by=supernova" | sudo tee /etc/hysteria/.supernova-managed >/dev/null
  cat <<EOF | sudo tee /etc/systemd/system/hysteria-server.service.d/supernova.conf >/dev/null
[Service]
Restart=on-failure
RestartSec=5s
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now hysteria-server.service
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

if [ ! -z "$ipv6" ]; then
hy_ipv6_link="hy2://$auth_pass@[$ipv6]:$hy_port/?$hy_query#$hy_fragment"
yellow "Irancell (Ipv6) : 
$hy_ipv6_link
"
fi

print_qr_code "$hy_link"

# Puts the link inside of temp file to be used in show_hysteria_conf function
cat <<EOF > temp/hy.txt
$hy_link
EOF

if [ ! -z "$hy_ipv6_link" ]; then
cat <<EOF >> temp/hy.txt

Irancell (Ipv6) : 
$hy_ipv6_link
EOF
fi

if [ "$hy_runtime" = "docker" ]; then
  print_docker_commands "Hysteria" "hysteria"
else
  print_systemd_commands "Hysteria" "hysteria-server.service"
fi
}

############################ Tuic Section

install_tuic() {
rm temp/tuic.txt
clear
if [ $( docker ps -a | grep tuic-server | wc -l ) -gt 0 ]; then
  if confirm_yes "Tuic proxy container is already running would you like to reinstall?"; then 
    uninstall_tuic
  else
    exit 0
  fi
fi


install_dependencies
get_cert

tuic_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(get_public_ip)
ipv6=$(curl -s6m8 ip.sb -k)
uuid=$(uuidgen)
clear
read -p "Enter the port to be used for tuic (default 443) : " tuic_port
[ -z "$tuic_port" ] && tuic_port=443
[ $(lsof -i :$tuic_port | grep :$tuic_port | wc -l) -gt 0 ] && red "Port $tuic_port is occupied. Please try another port" && exit 1


cat <<EOF > tuic/config.json
{
  "server": "[::]:$tuic_port",
  "users": {
    "$uuid": "$tuic_pass"
  },
  "certificate": "/etc/tuic/cert.crt",
  "private_key": "/etc/tuic/private.key",
  "congestion_control": "bbr",
  "alpn": ["h3", "spdy/3.1"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "dual_stack": true,
  "auth_timeout": "3s",
  "task_negotiation_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500,
  "send_window": 16777216,
  "receive_window": 8388608,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "warn"
}
EOF

(cd tuic && docker compose up -d)

clear
clients

blue "tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic%20($country_code)"
echo
echo
if [ ! -z "$ipv6" ]; then
yellow "Irancell (Ipv6) : 
tuic://$uuid:$tuic_pass@[$ipv6]:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic%20($country_code)
"
fi

print_qr_code "tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic%20($country_code)"


cat <<EOF > temp/tuic.txt
tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic%20($country_code)

Irancell (Ipv6) : 
tuic://$uuid:$tuic_pass@[$ipv6]:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic%20($country_code)
EOF

print_docker_commands "Tuic" "tuic"
}

######################## Tuic Section End.

install_brook() {
rm temp/br.txt
clear
if [ $( docker ps -a | grep brook | wc -l ) -gt 0 ]; then
  if confirm_yes "Brook proxy container is already running would you like to reinstall?"; then 
    uninstall_Brook
  else
    exit 0
  fi
fi
install_dependencies
get_cert
br_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(get_public_ip)
clear


yellow "Brook installation : "
echo
echo -e " ${GREEN}1.${PLAIN} Brook Server"
echo -e " ${GREEN}2.${PLAIN} Brook WS Server"
echo -e " ${GREEN}3.${PLAIN} Brook WSS Server"
echo -e " ${GREEN}4.${PLAIN} Brook Quic Server"
echo ""

read -rp "Pick your preffered brook installation [0-4] : " brook_pick
if [ ! $brook_pick -ge 1 ] || [ ! $brook_pick -le 4 ]; then 
  red "Invalid input"
  exit 1
fi
[ -z "$brook_pick" ] && red "Invalid option" && exit 1


read -rp "Enter the port to be used for Brook (default 2096) : " br_port
[ -z "$br_port" ] && br_port=2096
[ $(lsof -i :$br_port | grep :$br_port | wc -l) -gt 0 ] && red "Port $br_port is occupied. Please try another port" && exit 1


if [ $brook_pick -eq 3 ] || [ $brook_pick -eq 4 ]; then 
  read -p "Please enter your domain name : " br_domain
  [ -z "$br_domain" ] && red "Domain name cannot be empty" && exit 1

  curl https://get.acme.sh/ | sh
  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
  ~/.acme.sh/acme.sh --register-account -m test69moa@gmail.com
  ~/.acme.sh/acme.sh --issue -d $br_domain --standalone
    ~/.acme.sh/acme.sh --installcert -d $br_domain --key-file /root/Supernova/domain_certs/private.key --fullchain-file /root/Supernova/domain_certs/cert.crt
  clear
fi  



case $brook_pick in 
  1 ) ARGS="server -l :$br_port -p $br_pass --blockGeoIP="IR"" ;;
  2 ) ARGS="wsserver -l :$br_port -p $br_pass --blockGeoIP="IR"" ;;
  3 ) ARGS="wssserver -p $br_pass --cert="/etc/brook/cert.crt" --certkey="/etc/brook/private.key" --domainaddress="$br_domain:$br_port" --blockGeoIP="IR"" ;;
  4 ) ARGS="quicserver -p $br_pass -cert="/etc/brook/cert.crt" --certkey="/etc/brook/private.key" --domainaddress="$br_domain:$br_port" --blockGeoIP="IR"" ;;
esac

rm brook/compose.yaml
cat <<EOF > brook/compose.yaml
version: '3'
services:
  brook:
    image: teddysun/brook
    container_name: brook
    restart: always
    volumes:
      - ../domain_certs/cert.crt:/etc/brook/cert.crt:ro
      - ../domain_certs/private.key:/etc/brook/private.key:ro
    ports:
      - "$br_port:$br_port"
      - "$br_port:$br_port/udp"
    environment:
      - ARGS=$ARGS
EOF

(cd brook && docker compose up -d)

if [ $brook_pick -eq 1 ]; then 
  clear
  clients
  blue "brook://server?password=$br_pass&server=$server_ip%3A$br_port"
  echo
  echo
  blue "brook://server?password=$br_pass&server=$server_ip%3A$br_port&udpovertcp=true"
  echo
  echo
cat <<EOF > temp/br.txt
brook://server?password=$br_pass&server=$server_ip%3A$br_port

brook://server?password=$br_pass&server=$server_ip%3A$br_port&udpovertcp=true
EOF

elif [ $brook_pick -eq 2 ]; then
  clear
  clients
  blue "brook://wsserver?password=$br_pass&wsserver=ws%3A%2F%2F$server_ip%3A$br_port"
  echo
  echo
cat <<EOF > temp/br.txt
brook://wsserver?password=$br_pass&wsserver=ws%3A%2F%2F$server_ip%3A$br_port
EOF
elif [ $brook_pick -eq 3 ]; then
  clear
  clients
  blue "brook://wssserver?wssserver=wss%3A%2F%2F$br_domain%3A$br_port&username&password=$br_pass"
  echo
  echo
cat <<EOF > temp/br.txt
brook://wssserver?wssserver=wss%3A%2F%2F$br_domain%3A$br_port&username&password=$br_pass
EOF
elif [ $brook_pick -eq 4 ]; then
  clear
  clients
  blue "brook://quicserver?quicserver=quic%3A%2F%2F$br_domain%3A$br_port&username&password=$br_pass"
  echo
  echo
cat <<EOF > temp/br.txt
brook://quicserver?quicserver=quic%3A%2F%2F$br_domain%3A$br_port&username&password=$br_pass
EOF

fi

print_docker_commands "Brook" "brook"

}

install_mieru() {
rm temp/mi.txt
if [ $( systemctl status mia | grep active | wc -l ) -gt 0 ]; then
  if confirm_yes "Mieru proxy is already running would you like to reinstall?"; then 
    uninstall_mieru
  else
    exit 0
  fi
fi

  clear
  install_dependencies

  # Installs mita (server software for mieru)
  curl -LSO https://github.com/enfein/mieru/releases/download/v1.15.1/mita_1.15.1_amd64.deb
  sudo dpkg -i mita_1.15.1_amd64.deb

  server_ip=$(get_public_ip)
  clear

  pink "Mieru installation : "
  echo
  echo -e " ${PINK}1.${PLAIN} Mieru + ${BLUE}TCP${PLAIN}"
  echo -e " ${PINK}2.${PLAIN} Mieru + ${YELLOW}UDP${PLAIN}"
  echo ""

  read -rp "Pick your preffered mieru installation [0-2] : " mieru_pick

if [ ! $mieru_pick -ge 1 ] || [ ! $mieru_pick -le 2 ] || [ -z "$mieru_pick" ]; then 
  red "Invalid input"
  exit 1
fi

case $mieru_pick in 
  1 ) udp_tcp="TCP" ;;
  2 ) udp_tcp="UDP" ;;
esac

  read -rp "Please select your mieru username (Default random) ：" user_name
  [[ -z $user_name ]] && user_name=$(date +%s%N | md5sum | cut -c 1-8)

  read -rp "Please select your mieru password (default random) : " auth_pass
  [[ -z $auth_pass ]] && auth_pass=$(date +%s%N | md5sum | cut -c 1-8)

  read -rp "Enter the port to be used for Mieru (default [2000-65535]) : " mi_port
  [ -z "$mi_port" ] && mi_port=$(shuf -i 2000-65535 -n 1)
  [ $(lsof -i :$mi_port | grep :$mi_port | wc -l) -gt 0 ] && red "Port $mi_port is occupied. Please try another port" && exit 1


rm mieru/server_config.json
cat <<EOF > mieru/server_config.json
{
    "portBindings": [
        {
            "port": $mi_port,
            "protocol": "$udp_tcp"
        }
    ],
    "users": [
        {
            "name": "$user_name",
            "password": "$auth_pass"
        }
    ],
    "loggingLevel": "INFO",
    "mtu": 1400
}
EOF

mita stop
mita apply config mieru/server_config.json
mita start

cat <<EOF > mieru/client_config.json
{
    "profiles": [
        {
            "profileName": "default",
            "user": {
                "name": "$user_name",
                "password": "$auth_pass"
            },
            "servers": [
                {
                    "ipAddress": "$server_ip",
                    "domainName": "",
                    "portBindings": [
                        {
                            "port": $mi_port,
                            "protocol": "$udp_tcp"
                        }
                    ]
                }
            ],
            "mtu": 1400
        }
    ],
    "activeProfile": "default",
    "rpcPort": 8964,
    "socks5Port": 3080,
    "loggingLevel": "INFO"
}
EOF

clear
clients

blue "Mieru client config :"
echo
cat mieru/client_config.json
echo 
pink "================================="
pink "Manual configuration for sagernet"
pink "server : $server_ip"
pink "port : $mi_port"
pink "Protocol : $udp_tcp"
pink "username : $user_name"
pink "password : $auth_pass"
pink "================================="

cat <<EOF > temp/mi.txt
=================================
Manual configuration for sagernet
server : $server_ip
port : $mi_port
Protocol : $udp_tcp
username : $user_name
password : $auth_pass
=================================

EOF
}

install_naive() {
rm temp/na.txt
clear
if [ $( docker ps -a | grep naiveproxy | wc -l ) -gt 0 ]; then
  if confirm_yes "naiveproxy proxy container is already running would you like to reinstall?"; then 
    uninstall_naive
  else
    exit 0
  fi
fi
install_dependencies
get_cert
rm /etc/naiveproxy/Caddyfile
mkdir -p /etc/naiveproxy /var/www/html /var/log/caddy
auth_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(get_public_ip)
ipv6=$(curl -s6m8 ip.sb -k)
clear

read -rp "Please enter your domain name : " naive_domain
[ -z "$naive_domain" ] && red "Domain name cannot be empty" && exit 1

read -rp "Please enter the port to be used for Caddy [Default 80] : " caddy_port
[ -z "$caddy_port" ] && caddy_port=80
[ $(lsof -i :$caddy_port | grep :$caddy_port | wc -l) -gt 0 ] && red "Port $caddy_port is occupied. Please try another port" && exit 1

read -rp "Please enter the port to be used for Naive proxy [Default 443] : " naive_port
[ -z "$naive_port" ] && naive_port=443
[ $(lsof -i :$naive_port | grep :$naive_port | wc -l) -gt 0 ] && red "Port $naive_port is occupied. Please try another port" && exit 1

read -rp "Please enter the username for Naive proxy [Default random] : " naive_usr
[ -z "$naive_usr" ] && naive_usr=$(date +%s%N | md5sum | cut -c 1-8)

read -rp "Please enter the password for Naive proxy [Default random] : " naive_pass
[ -z "$naive_pass" ] && naive_pass=$(date +%s%N | md5sum | cut -c 1-8)

read -rp "Please enter the forward domain for Naive proxy [Default vipofilm.com] : " naive_forward_domain
[ -z "$naive_forward_domain" ] && naive_forward_domain=vipofilm.com

cat <<EOF > /etc/naiveproxy/Caddyfile
{
http_port $caddy_port
}
:$naive_port, $naive_domain:$naive_port
tls moamaema3e@gmail.com
route {
 forward_proxy {
   basic_auth $naive_usr $naive_pass
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://$naive_forward_domain {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}
EOF

(cd naive && docker compose up -d)

clear
clients

blue "naive+https://$naive_usr:$naive_pass@$naive_domain:$naive_port"
echo
echo

print_qr_code "naive+https://$naive_usr:$naive_pass@$naive_domain:$naive_port"


cat <<EOF > temp/na.txt
naive+https://$naive_usr:$naive_pass@$naive_domain:$naive_port
EOF

print_docker_commands "Naive" "naive"
}


install_juicity() {
rm temp/ju.txt
clear
if [ $( systemctl status juicity-server | grep active | wc -l ) -gt 0 ]; then
  if confirm_yes "juicity proxy service is already running would you like to reinstall?"; then 
    uninstall_juicity
  else
    exit 0
  fi
fi

install_dependencies
get_cert
rm juicity/server.json
auth_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
uuid=$(uuidgen)
server_ip=$(get_public_ip)
ipv6=$(curl -s6m8 ip.sb -k)


if [ ! -f juicity/juicity-server ]; then 
  wget https://github.com/juicity/juicity/releases/download/v0.4.3/juicity-linux-x86_64.zip
  mv juicity-linux-x86_64.zip juicity
  (cd juicity && unzip juicity-linux-x86_64.zip)
  rm juicity/juicity-server.service
  rm juicity/example-server.json
  rm juicity/juicity-client.service
  rm juicity/example-client.json
  rm juicity/juicity-client
  rm juicity/juicity-linux-x86_64.zip
fi

clear
read -p "Enter the port to be used for Juicity [default 2087] : " ju_port
[ -z "$ju_port" ] && ju_port=2087
[ $(lsof -i :$ju_port | grep :$ju_port | wc -l) -gt 0 ] && red "Port $ju_port is occupied. Please try another port" && exit 1

read -p "Enter the Sni to be used for Juicity [default hub.docker.com] : " ju_sni
[ -z "$ju_sni" ] && ju_sni=hub.docker.com


cat <<EOF > juicity/server.json
{
    "listen": ":$ju_port",
    "users": {
        "$uuid": "$auth_pass"
    },
    "certificate": "/root/Supernova/certs/cert.crt",
    "private_key": "/root/Supernova/certs/private.key",
    "congestion_control": "bbr",
    "log_level": "info"
}
EOF

cat <<EOF > /etc/systemd/system/juicity-server.service
[Unit]
Description=juicity-server Service
Documentation=https://github.com/juicity/juicity
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/root/Supernova/juicity/juicity-server run -c /root/Supernova/juicity/server.json --disable-timestamp
Restart=on-failure
LimitNPROC=512
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable juicity-server
sudo systemctl start juicity-server

clear
clients

blue "juicity://$uuid:$auth_pass@$server_ip:$ju_port/?congestion_control=bbr&sni=$ju_sni&allow_insecure=1#Juicity%20($country_code)"
echo
red "Please manually enable allow insecure in your client or else it will not work"
echo
echo
if [ ! -z "$ipv6" ]; then
yellow "Irancell (Ipv6) : 
juicity://$uuid:$auth_pass@$[$ipv6]:$ju_port/?congestion_control=bbr&sni=$ju_sni&allow_insecure=1#Juicity%20($country_code)
"
echo "juicity://$uuid:$auth_pass@$[$ipv6]:$ju_port/?congestion_control=bbr&sni=$ju_sni&allow_insecure=1#Juicity%20($country_code)" > temp/ju.txt
fi

print_qr_code "juicity://$uuid:$auth_pass@$server_ip:$ju_port/?congestion_control=bbr&sni=$ju_sni&allow_insecure=1#Juicity%20($country_code)"


cat <<EOF > temp/ju.txt
juicity://$uuid:$auth_pass@$server_ip:$ju_port/?congestion_control=bbr&sni=$ju_sni&allow_insecure=1#Juicity%20($country_code)
EOF

print_systemd_commands "Juicity" "juicity-server.service"

}





################################ Show configurations
show_hysteria_conf() {
clear
clients
cat temp/hy.txt
echo
hy_qr=$(cat temp/hy.txt)
print_qr_code "$hy_qr"
}

show_tuic_conf() {
clear
cat temp/tuic.txt
echo
tuic_qr=$(cat temp/tuic.txt)
print_qr_code "$tuic_qr"
}

show_brook_conf() {
clear
cat temp/br.txt
}

show_mieru_conf() {
clear
cat mieru/client_config.json
echo
cat temp/mi.txt
}

show_naive_conf() {
clear
cat temp/na.txt
}

show_juicity_conf() {
clear
cat temp/ju.txt
}




################################ Show configurations (END)


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
blue " ----------------------"
echo -e " ${GREEN}4.${PLAIN} Install ${PINK}Tuic${PLAIN}"
echo -e " ${GREEN}5.${PLAIN} ${RED}Uninstall Tuic${PLAIN}"
echo -e " ${GREEN}6.${PLAIN} Show configuration link for Tuic"
blue " ----------------------"
echo -e " ${GREEN}7.${PLAIN} Install ${PINK}Brook${PLAIN}"
echo -e " ${GREEN}8.${PLAIN} ${RED}Uninstall Brook${PLAIN}"
echo -e " ${GREEN}9.${PLAIN} Show configuration link for Brook"
blue " ----------------------"
echo -e " ${GREEN}10.${PLAIN} Install ${PINK}Mieru${PLAIN}"
echo -e " ${GREEN}11.${PLAIN} ${RED}Uninstall Mieru${PLAIN}"
echo -e " ${GREEN}12.${PLAIN} Show configuration link for Mieru"
blue " ----------------------"
echo -e " ${GREEN}13.${PLAIN} Install ${PINK}Naive${PLAIN}"
echo -e " ${GREEN}14.${PLAIN} ${RED}Uninstall Naive${PLAIN}"
echo -e " ${GREEN}15.${PLAIN} Show configuration link for Naive"
blue " ----------------------"
echo -e " ${GREEN}16.${PLAIN} Install ${PINK}Juicity${PLAIN}"
echo -e " ${GREEN}17.${PLAIN} ${RED}Uninstall Juicity${PLAIN}"
echo -e " ${GREEN}18.${PLAIN} Show configuration link for Juicity"
echo ""
read -p $'\033[1;32m Please select an option [0-15]: ' menuInput


case $menuInput in
    1 ) install_hysteria ;;
    2 ) uninstall_hysteria ;;
    3 ) show_hysteria_conf ;;
    4 ) install_tuic ;;
    5 ) uninstall_tuic ;;
    6 ) show_tuic_conf ;;
    7 ) install_brook ;;
    8 ) uninstall_Brook ;;
    9 ) show_brook_conf ;;
    10 ) install_mieru ;;
    11 ) uninstall_mieru ;;
    12 ) show_mieru_conf ;;
    13 ) install_naive ;;
    14 ) uninstall_naive ;;
    15 ) show_naive_conf ;;
    16 ) install_juicity ;;
    17 ) uninstall_juicity ;;
    18 ) show_juicity_conf ;;
    * ) exit 1 ;;
esac

}

menu
