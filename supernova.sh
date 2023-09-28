#!/bin/bash

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
echo
echo -e "${GREEN}Brook${PLAIN}":
echo -e "${YELLOW}https://www.txthinking.com/brook.html${PLAIN}"
echo
echo -e "${GREEN}Mieru (Sagernet + Mieru plugin)${PLAIN}":
echo -e "${YELLOW}https://github.com/SagerNet/SagerNet/releases/download/0.8.1-rc03/SN-0.8.1-rc03-arm64-v8a.apk${PLAIN}"
echo -e "${YELLOW}https://github.com/SagerNet/SagerNet/releases/download/mieru-plugin-1.15.1/mieru-plugin-1.15.1-arm64-v8a.apk${PLAIN}"
echo -e "${BLUE}========================================================${PLAIN}"
echo

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

install_dependencies() {
  sudo apt update 
  sudo apt install net-tools uuid-runtime wget qrencode -y
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

uninstall_hysteria() {
  sudo docker rm -f hysteria
  rm temp/hy.txt
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


install_hysteria() {
rm temp/hy.txt
clear
if [ $( docker ps -a | grep hysteria | wc -l ) -gt 0 ]; then
  read -p "hysteria proxy container is already running would you like to reinstall? (Y/n)" hy_reinstall
  if [[ -z "$hy_reinstall" || $hy_reinstall = "Y" || $hy_reinstall = "y" ]]; then 
    uninstall_hysteria
  else
    exit 0
  fi
fi
install_dependencies
get_cert
rm hysteria/config.yaml
auth_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(curl api.ipify.org)
ipv6=$(curl -s6m8 ip.sb -k)
clear
read -p "Enter the port to be used for hysteria (default 443) : " hy_port
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
hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com#Hysteria
"
if [ ! -z "$ipv6" ]; then
yellow "Irancell (Ipv6) : 
hy2://$auth_pass@[$ipv6]:$hy_port/?insecure=1&sni=google.com#Hysteria
"
fi

qrencode -m 2 -t utf8 <<< "hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com#Hysteria"

cat <<EOF > temp/hy.txt
hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com#Hysteria

Irancell (Ipv6) : 
hy2://$auth_pass@[$ipv6]:$hy_port/?insecure=1&sni=google.com#Hysteria
EOF
else
blue "
hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com&obfs-password=$obfs_pass#Hysteria%20%2B%20Obfs
"
if [ ! -z "$ipv6" ]; then
yellow "Irancell (Ipv6) : 
hy2://$auth_pass@[$ipv6]:$hy_port/?insecure=1&sni=google.com#Hysteria
"
fi
# Prints the qrcode for the specified link
qrencode -m 2 -t utf8 <<< "hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com&obfs-password=$obfs_pass#Hysteria%20%2B%20Obfs"
fi


# Puts the link inside of temp file to be used in show_hysteria_conf function
cat <<EOF > temp/hy.txt
hy2://$auth_pass@$server_ip:$hy_port/?insecure=1&sni=google.com&obfs-password=$obfs_pass#Hysteria%20%2B%20Obfs

Irancell (Ipv6) : 
hy2://$auth_pass@[$ipv6]:$hy_port/?insecure=1&sni=google.com#Hysteria
EOF
}

############################ Tuic Section

install_tuic() {
rm temp/tuic.txt
clear
if [ $( docker ps -a | grep tuic-server | wc -l ) -gt 0 ]; then
  read -p "Tuic proxy container is already running would you like to reinstall? (Y/n)" tuic_reinstall
  if [[ -z "$tuic_reinstall" || $tuic_reinstall = "Y" || $tuic_reinstall = "y" ]]; then 
    uninstall_tuic
  else
    exit 0
  fi
fi


install_dependencies
get_cert

tuic_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(curl api.ipify.org)
ipv6=$(curl -s6m8 ip.sb -k)
uuid=$(uuidgen)
clear
read -p "Enter the port to be used for tuic (default 8443) : " tuic_port
[ -z "$tuic_port" ] && tuic_port=8443

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

blue "tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic"
echo
echo
if [ ! -z "$ipv6" ]; then
yellow "Irancell (Ipv6) : 
tuic://$uuid:$tuic_pass@[$ipv6]:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic
"
fi

qrencode -m 2 -t utf8 <<< "tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic"


cat <<EOF > temp/tuic.txt
tuic://$uuid:$tuic_pass@$server_ip:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic

Irancell (Ipv6) : 
tuic://$uuid:$tuic_pass@[$ipv6]:$tuic_port/?congestion_control=bbr&udp_relay_mode=native&alpn=h3%2Cspdy%2F3.1&allow_insecure=1#Tuic
EOF
}

######################## Tuic Section End

install_brook() {
rm temp/br.txt
clear
if [ $( docker ps -a | grep brook | wc -l ) -gt 0 ]; then
  read -p "Brook proxy container is already running would you like to reinstall? (Y/n)" br_reinstall
  if [[ -z "$br_reinstall" || $br_reinstall = "Y" || $br_reinstall = "y" ]]; then 
    uninstall_Brook
  else
    exit 0
  fi
fi
install_dependencies
get_cert
br_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30 ; echo '')
server_ip=$(curl api.ipify.org)
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

}

install_mieru() {
rm temp/mi.txt
if [ $( systemctl status mia | grep active | wc -l ) -gt 0 ]; then
  read -p "Mieru proxy is already running would you like to reinstall? (Y/n)" mi_reinstall
  if [[ -z "$mi_reinstall" || $mi_reinstall = "Y" || $mi_reinstall = "y" ]]; then 
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

  server_ip=$(curl api.ipify.org)
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
################################ Show configurations
show_hysteria_conf() {
clear
clients
cat temp/hy.txt
echo
hy_qr=$(cat temp/hy.txt)
qrencode -m 2 -t utf8 <<< "$hy_qr"
}

show_tuic_conf() {
clear
cat temp/tuic.txt
echo
tuic_qr=$(cat temp/tuic.txt)
qrencode -m 2 -t utf8 <<< "$tuic_qr"
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
echo ""

read -p $'\033[1;32m Please select an option [0-12]: ' menuInput


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
    * ) exit 1 ;;
esac

}

menu