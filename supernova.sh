#!/bin/bash

export LANG=en_US.UTF-8

####################### Color pallete
CYAN="\033[36m\033[01m"
BLUE="\033[34m\033[01m"
PINK="\033[95m\033[01m"
GREEN="\033[32m\033[01m"
PLAIN="\033[0m"
RED="\033[31m\033[01m"
YELLOW="\033[33m\033[01m"
WHITE="\033[97m\033[01m"


cyan() { echo -e "\033[36m\033[01m$1\033[0m"; }
blue() { echo -e "\033[34m\033[01m$1\033[0m"; }
pink() { echo -e "\033[95m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
magenta() { echo -e "\033[35m\033[01m$1\033[0m"; }
white() { echo -e "\033[97m\033[01m$1\033[0m"; }
#######################

clients(){

echo -e "${BLUE}========================================================${PLAIN}"
echo -e "${RED}Recommended clients${PLAIN}"
echo
echo -e "${GREEN}Android${PLAIN}":
echo -e "${YELLOW}https://github.com/MatsuriDayo/NekoBoxForAndroid/releases${PLAIN}"
echo
echo -e "${GREEN}Windows/Linux/Macos${PLAIN}":
echo -e "${YELLOW}https://github.com/MatsuriDayo/nekoray/releases${PLAIN}"
echo -e "${BLUE}========================================================${PLAIN}"

}

install_dependencies() {
  sudo apt update 
  if [ -x "$(command -v docker)" ]; then
    cyan "Docker is installed. Continueing..."
  else
    pink "Installing Docker..."
    curl -fsSL https://get.docker.com -o install-docker.sh
    sudo sh install-docker.sh
  fi 
}

get_cert() {

# Check if certificates exist
if [ -f certs/cert.crt ] && [ -f certs/private.key ]; then 
    cyan "Found certificates. continuing..."
else 

# Generate self signed certificate
openssl ecparam -genkey -name prime256v1 -out certs/private.key
openssl req -new -x509 -days 36500 -key certs/private.key -out certs/cert.crt -subj "/CN=bing.com"

fi
}

install_hysteria() {

install_dependencies
get_cert
rm hysteria/config.yaml
auth_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(curl api.ipify.org)
read -p "Enter the port to be used for hysteria between (default 443) : " hy_port
[ -z "$hy_port" ] && hy_port=443


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
    - reject(geoip:ir)
EOF

read -p "Would you like to enable obfuscation? (Y/n) : " enable_obfs

if [[ -z "$enable_obfs" || $enable_obfs = "Y" || $enable_obfs = "y" ]]; then 
obfs_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
echo "obfs:
  type: salamander
  salamander:
    password: $obfs_pass" >> hysteria/config.yaml
fi

read -p "Would you like to enable HTTP/HTTPS masquerade? (Y/n) : " enable_masq
if [[ -z "$enable_masq" || $enable_masq = "Y" || $enable_masq = "y" ]]; then 

read -p "Enter the address for masquerade website (Default vipofilm.com) : " masq_addr
[ -z "$masq_addr" ] && masq_addr=vipofilm.com

echo "masquerade:
  type: proxy
  proxy:
    url: https://$masq_addr
    rewriteHost: true 
  listenHTTP: :80 
  listenHTTPS: :443 
  forceHTTPS: true
" >> hysteria/config.yaml
fi

(cd hysteria && docker compose up -d)
clear
clients

if [ -z "$obfs_pass" ]; then 
blue "
hy2://$auth_pass@$server_ip:443/?insecure=1&sni=google.com#Hysteria
"
qrencode -m 2 -t utf8 <<< "hy2://$auth_pass@$server_ip:443/?insecure=1&sni=google.com#Hysteria"
else
blue "
hy2://$auth_pass@$server_ip:443/?insecure=1&sni=google.com&obfs-password=$obfs_pass#Hysteria%20%2B%20Obfs
"

# Prints the qrcode for the specified link
qrencode -m 2 -t utf8 <<< "hy2://$auth_pass@$server_ip:443/?insecure=1&sni=google.com&obfs-password=$obfs_pass#Hysteria%20%2B%20Obfs"
fi

}

uninstall_hysteria() {
  docker rm -f hysteria
  green "Hysteria has been uninstalled"
}


