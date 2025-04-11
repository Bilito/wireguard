#!/bin/bash

# Comprobación de privilegios (debe ejecutarse como root o con sudo)
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script debe ejecutarse con privilegios de root."
  exit 1
fi

# Preguntar por el endpoint (DDNS o IP pública)
read -p "🌐 Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT

# Comprobar si WireGuard ya está configurado
if [ -f /etc/wireguard/server_privatekey ]; then
  read -p "⚠️ Ya existe una configuración previa de WireGuard. ¿Deseas sobrescribirla? (s/n): " RESP
  if [[ "$RESP" != "s" && "$RESP" != "S" ]]; then
    echo "🚪 Saliendo sin cambios."
    exit 0
  fi
  echo "🧹 Borrando configuración anterior..."
  rm -f /etc/wireguard/wg0.conf /etc/wireguard/*_key /etc/wireguard/*_config*
fi

# Instalación de WireGuard y qrencode
echo "📦 Instalando WireGuard y herramientas necesarias..."
apt update && apt install -y wireguard qrencode || { echo "❌ Error al instalar paquetes."; exit 1; }

# Obtener interfaz de red predeterminada
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
echo "📡 Interfaz detectada: $DEFAULT_IFACE"

# Generar claves del servidor
echo "🔐 Generando claves del servidor..."
wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey > /etc/wireguard/server_publickey

# Crear configuración inicial del servidor
SERVER_CONF="/etc/wireguard/wg0.conf"
cat <<EOF > $SERVER_CONF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_privatekey)
Address = 10.6.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

# Función para agregar un peer
add_peer() {
  read -p "👤 Introduce el nombre del peer (por ejemplo, 'Cliente1'): " PEER_NAME

  echo "🔐 Generando claves para '$PEER_NAME'..."
  wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey

  PEER_COUNT=$(grep -c "\[Peer\]" "$SERVER_CONF")
  CLIENT_IP="10.6.0.$((PEER_COUNT + 2))/32"

  CLIENT_CONFIG_PATH="/etc/wireguard/${PEER_NAME}_config.conf"
  cat <<EOF > $CLIENT_CONFIG_PATH
[Interface]
PrivateKey = $(cat /etc/wireguard/${PEER_NAME}_privatekey)
Address = $CLIENT_IP
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat /etc/wireguard/server_publickey)
Endpoint = $ENDPOINT:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  echo "➕ Añadiendo '$PEER_NAME' al servidor..."
  CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/${PEER_NAME}_publickey)
  cat <<EOF >> $SERVER_CONF

[Peer]
# Nombre del Peer: $PEER_NAME
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = ${CLIENT_IP}
EOF

  echo "🖨️ Generando código QR..."
  qrencode -t png -o /etc/wireguard/${PEER_NAME}_config_qr.png < $CLIENT_CONFIG_PATH
  qrencode -t ansiutf8 < $CLIENT_CONFIG_PATH

  echo "📁 Configuración del cliente guardada en: $CLIENT_CONFIG_PATH"
  echo "🖼️ Código QR PNG en: /etc/wireguard/${PEER_NAME}_config_qr.png"
}

# Bucle para agregar múltiples peers
while true; do
  add_peer
  read -p "➕ ¿Deseas agregar otro peer? (s/n): " ADD_MORE
  [[ "$ADD_MORE" != "s" && "$ADD_MORE" != "S" ]] && break
done

# Habilitar reenvío de IP
echo "🛠️ Habilitando el reenvío de IP..."
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi
sysctl -p

# Activar WireGuard
echo "🚀 Iniciando WireGuard..."
wg-quick up wg0

# Habilitar al arranque
systemctl enable wg-quick@wg0

# Mostrar estado
echo "📡 Estado de la interfaz WireGuard:"
wg show

echo "✅ WireGuard instalado y configurado correctamente."
