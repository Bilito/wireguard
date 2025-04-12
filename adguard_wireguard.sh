#!/bin/bash

set -e
trap 'echo "\n❌ Error en la línea $LINENO. Abortando."' ERR

# =====================
# Variables globales
# =====================
ADGUARD_DIR="./adguard"
WG_CONF_DIR="/etc/wireguard"
TZ="Europe/Madrid"
WG_SUBNET="10.6.0"

# =====================
# Verificación root
# =====================
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse con privilegios de root."
  exit 1
fi

# =====================
# Actualización del sistema
# =====================
apt update && apt upgrade -y

# =====================
# Funciones
# =====================
instalar_docker() {
  echo "\n🔧 Verificando Docker..."
  if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    curl -sSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker "$SUDO_USER"
    echo "⚠️ Reinicia la sesión del usuario para usar Docker sin sudo."
  else
    echo "✅ Docker ya está instalado."
  fi

  echo "Verificando docker-compose..."
  if ! command -v docker-compose &> /dev/null; then
    apt install -y docker-compose
  fi
}

instalar_adguard() {
  echo "\n📦 Instalando AdGuard Home..."
  if docker ps -a --format '{{.Names}}' | grep -q "^adguard-home$"; then
    echo "✅ Contenedor 'adguard-home' ya existe."
  else
    mkdir -p "$ADGUARD_DIR/config" "$ADGUARD_DIR/workingdir"
    pushd "$ADGUARD_DIR"
    cat <<EOF > docker-compose.yml
services:
  adguardhome:
    container_name: adguard-home
    environment:
      - TZ=$TZ
    volumes:
      - ./config:/opt/adguardhome/conf
      - ./workingdir:/opt/adguardhome/work
    restart: always
    network_mode: host
    image: adguard/adguardhome
EOF
    docker-compose up -d
    popd
    echo "✅ AdGuard está listo en http://localhost:3000"
  fi
}

configurar_dns_adguard() {
  echo "\n🧩 Configurando DNS para AdGuard Home..."
  mkdir -p /etc/systemd/resolved.conf.d
  echo -e "[Resolve]\nDNS=127.0.0.1\nDNSStubListener=no" > /etc/systemd/resolved.conf.d/adguardhome.conf

  mv /etc/resolv.conf /etc/resolv.conf.backup || true
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved
  echo "✅ DNS configurado para AdGuard."
}

instalar_wireguard() {
  echo "\n🔐 Instalando y configurando WireGuard..."
  read -p "Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT

  apt install -y wireguard qrencode
  modprobe wireguard

  mkdir -p "$WG_CONF_DIR"
  wg genkey | tee "$WG_CONF_DIR/server_privatekey" | wg pubkey > "$WG_CONF_DIR/server_publickey"
  DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')

  SERVER_CONF="$WG_CONF_DIR/wg0.conf"
  cat <<EOF > "$SERVER_CONF"
[Interface]
PrivateKey = $(cat "$WG_CONF_DIR/server_privatekey")
Address = ${WG_SUBNET}.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

  systemctl enable wg-quick@wg0
}

agregar_peer() {
  PEER_COUNT=$(grep -c "\[Peer\]" "$WG_CONF_DIR/wg0.conf")
  read -p "Introduce el nombre del peer (ej. Cliente1): " PEER_NAME

  wg genkey | tee "$WG_CONF_DIR/${PEER_NAME}_privatekey" | wg pubkey > "$WG_CONF_DIR/${PEER_NAME}_publickey"
  LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

  PEER_IP="${WG_SUBNET}.$((PEER_COUNT + 2))"
  CLIENT_CONFIG_PATH="$WG_CONF_DIR/${PEER_NAME}.conf"

  cat <<EOF > "$CLIENT_CONFIG_PATH"
[Interface]
PrivateKey = $(cat "$WG_CONF_DIR/${PEER_NAME}_privatekey")
Address = ${PEER_IP}/32
DNS = $LOCAL_IP

[Peer]
PublicKey = $(cat "$WG_CONF_DIR/server_publickey")
Endpoint = $ENDPOINT:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  cat <<EOF >> "$WG_CONF_DIR/wg0.conf"

[Peer]
# Nombre del Peer: $PEER_NAME
PublicKey = $(cat "$WG_CONF_DIR/${PEER_NAME}_publickey")
AllowedIPs = ${PEER_IP}/32
EOF

  qrencode -t png -o "$WG_CONF_DIR/${PEER_NAME}_qr.png" < "$CLIENT_CONFIG_PATH"
  qrencode -t ansiutf8 < "$CLIENT_CONFIG_PATH"

  echo "🎉 Peer $PEER_NAME agregado con éxito."
}

configurar_reenvio_ip() {
  echo "\n🛠️ Activando reenvío de IP..."
  grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf && \
    sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p
}

mostrar_resumen() {
  echo "\n📋 Resumen de configuraciones creadas:"
  echo "Archivos .conf:"
  ls "$WG_CONF_DIR"/*.conf
  echo "\nCódigos QR generados:"
  ls "$WG_CONF_DIR"/*_qr.png
}

# =====================
# Main
# =====================
instalar_docker
instalar_adguard
configurar_dns_adguard

instalar_wireguard

while true; do
  agregar_peer
  read -p "¿Deseas agregar otro peer? (s/n): " ADD_MORE
  [[ "$ADD_MORE" =~ ^[sS]$ ]] || break
done

configurar_reenvio_ip
wg-quick up wg0

mostrar_resumen

echo "\n✅ Instalación completada. Recuerda compartir los archivos y QR con los dispositivos clientes."
reboot

