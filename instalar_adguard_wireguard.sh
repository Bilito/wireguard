#!/bin/bash

# =====================
#  Verificación root
# =====================
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse con privilegios de root."
  exit 1
fi

# =====================
#  Actualización del sistema
# =====================
echo "Actualizando los paquetes del sistema..."
apt update && apt upgrade -y

# =====================
#  Docker
# =====================
echo "Verificando Docker..."
if ! command -v docker &> /dev/null; then
  echo "❌ Docker no está instalado. Instalándolo..."
  curl -sSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  usermod -aG docker "$SUDO_USER"
  echo "⚠️ Reinicia la sesión del usuario para usar Docker sin sudo."
fi

# =====================
#  Docker Compose
# =====================
echo "Verificando docker-compose..."
if ! command -v docker-compose &> /dev/null; then
  echo "❌ docker-compose no está instalado. Instalándolo..."
  apt install -y docker-compose || { echo "Error al instalar docker-compose"; exit 1; }
fi

# =====================
#  AdGuard Home
# =====================
echo "Configurando AdGuard Home..."
if docker ps -a --format '{{.Names}}' | grep -q "^adguard-home$"; then
  echo "✅ El contenedor 'adguard-home' ya existe. Saltando la creación."
else
  mkdir -p ./adguard/config ./adguard/workingdir
  cd ./adguard || exit 1
  echo "Creando docker-compose.yml para AdGuard..."
  cat <<EOF > docker-compose.yml
services:
  adguardhome:
    container_name: adguard-home
    environment:
      - TZ=Europe/Madrid
    volumes:
      - ./config:/opt/adguardhome/conf
      - ./workingdir:/opt/adguardhome/work
    restart: always
    network_mode: host
    image: adguard/adguardhome
EOF
  docker-compose up -d
  cd ..
  echo "✅ ¡AdGuard está listo! Accede a la interfaz web en http://localhost:3000"
fi

# =====================
# Configuración de DNS para AdGuard Home
# =====================
echo "Configurando DNS para AdGuard Home..."

# Crear el directorio si no existe
mkdir -p /etc/systemd/resolved.conf.d

# Crear el archivo de configuración para desactivar DNSStubListener y establecer DNS a 127.0.0.1
cat <<EOF > /etc/systemd/resolved.conf.d/adguardhome.conf
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF

# Respaldar el archivo resolv.conf existente
mv /etc/resolv.conf /etc/resolv.conf.backup

# Crear un enlace simbólico para que systemd use el resolv.conf adecuado
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Reiniciar el servicio de systemd-resolved para aplicar los cambios
systemctl restart systemd-resolved

echo "✅ DNS configurado correctamente para AdGuard Home."

# =====================
#  WireGuard
# =====================
echo "Configurando WireGuard..."
read -p "Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT

apt install -y wireguard qrencode
modprobe wireguard

mkdir -p /etc/wireguard

wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey > /etc/wireguard/server_publickey
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')

SERVER_CONF="/etc/wireguard/wg0.conf"
cat <<EOF > $SERVER_CONF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_privatekey)
Address = 10.6.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

add_peer() {
  PEER_COUNT=$(grep -c "\[Peer\]" $SERVER_CONF)
  read -p "Introduce el nombre del peer (por ejemplo, 'Cliente1'): " PEER_NAME

  wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey
  LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

  PEER_IP="10.6.0.$((PEER_COUNT + 2))"
  CLIENT_CONFIG_PATH="/etc/wireguard/${PEER_NAME}.conf"

  cat <<EOF > $CLIENT_CONFIG_PATH
[Interface]
PrivateKey = $(cat /etc/wireguard/${PEER_NAME}_privatekey)
Address = ${PEER_IP}/32
DNS = $LOCAL_IP

[Peer]
PublicKey = $(cat /etc/wireguard/server_publickey)
Endpoint = $ENDPOINT:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  echo -e "\n[Peer]" >> $SERVER_CONF
  echo "# Nombre del Peer: $PEER_NAME" >> $SERVER_CONF
  echo "PublicKey = $(cat /etc/wireguard/${PEER_NAME}_publickey)" >> $SERVER_CONF
  echo "AllowedIPs = ${PEER_IP}/32" >> $SERVER_CONF

  qrencode -t png -o /etc/wireguard/${PEER_NAME}_qr.png < $CLIENT_CONFIG_PATH
  echo "Código QR guardado en: /etc/wireguard/${PEER_NAME}_qr.png"
  qrencode -t ansiutf8 < $CLIENT_CONFIG_PATH
}

while true; do
  add_peer
  read -p "¿Deseas agregar otro peer? (s/n): " ADD_MORE
  [[ "$ADD_MORE" =~ ^[sS]$ ]] || break
done

# =====================
#  Reenvío IP y activación
# =====================
echo "🛠️ Habilitando el reenvío de IP..."
grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf && \
  sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

wg-quick up wg0
systemctl enable wg-quick@wg0

echo "Estado de la interfaz WireGuard:"
wg show

echo "✅ WireGuard instalado y configurado correctamente."
echo "Recuerda compartir las configuraciones y códigos QR con los dispositivos clientes."
