#!/bin/bash

# =====================
#  WireGuard
# =====================
echo "Configurando WireGuard..."
read -p "Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT

# Instalación y configuración
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

# =====================
#  Agregar el primer Peer
# =====================
PEER_COUNT=$(grep -c "\[Peer\]" $SERVER_CONF)
read -p "Introduce el nombre del primer peer (por ejemplo, 'Cliente1'): " PEER_NAME

wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey
LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

PEER_IP=10.6.0.2

# Crear la configuración del cliente
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

# Agregar el primer Peer al servidor
echo "[Peer]" >> $SERVER_CONF
echo "# Nombre del Peer: $PEER_NAME" >> $SERVER_CONF
echo "PublicKey = $(cat /etc/wireguard/${PEER_NAME}_publickey)" >> $SERVER_CONF
echo "AllowedIPs = ${PEER_IP}/32" >> $SERVER_CONF

qrencode -t png -o /etc/wireguard/${PEER_NAME}_qr.png < $CLIENT_CONFIG_PATH
echo "Código QR guardado en: /etc/wireguard/${PEER_NAME}_qr.png"
qrencode -t ansiutf8 < $CLIENT_CONFIG_PATH

# =====================
#  Reenvío IP y activación
# =====================
echo "🛠️ Habilitando el reenvío de IP..."
if ! grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
else
  sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
fi
sysctl -p

# Activar WireGuard
wg-quick up wg0
systemctl enable wg-quick@wg0

echo "Estado de la interfaz WireGuard:"
wg show

echo "✅ WireGuard instalado y configurado correctamente."
echo "Recuerda compartir las configuraciones y códigos QR con los dispositivos clientes."

# =====================
#  Función para añadir más peers
# =====================
add_peer() {
    read -p "Introduce el nombre del nuevo peer: " PEER_NAME

    wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey
    LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

    # Obtener la última IP utilizada para los peers
    LAST_IP=$(grep -oP 'AllowedIPs = 10\.6\.0\.\K[0-9]+' "$SERVER_CONF" | sort -n | tail -1)
    if [ -z "$LAST_IP" ]; then
        NEXT_IP=2
    else
        NEXT_IP=$((LAST_IP + 1))
    fi
    PEER_IP="10.6.0.${NEXT_IP}"

    # Crear la configuración del cliente
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

    # Agregar el nuevo Peer al servidor
    echo "[Peer]" >> $SERVER_CONF
    echo "# Nombre del Peer: $PEER_NAME" >> $SERVER_CONF
    echo "PublicKey = $(cat /etc/wireguard/${PEER_NAME}_publickey)" >> $SERVER_CONF
    echo "AllowedIPs = ${PEER_IP}/32" >> $SERVER_CONF

    qrencode -t png -o /etc/wireguard/${PEER_NAME}_qr.png < $CLIENT_CONFIG_PATH
    echo "Código QR guardado en: /etc/wireguard/${PEER_NAME}_qr.png"
    qrencode -t ansiutf8 < $CLIENT_CONFIG_PATH
}

# Preguntar si desea añadir más peers
while true; do
    read -p "¿Deseas agregar otro peer? (s/n): " respuesta
    if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ]; then
        add_peer
    else
        break
    fi
done

# =====================
#  Reiniciar el servidor
# =====================
read -p "¿Deseas reiniciar el servidor ahora? (s/n): " respuesta
if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ]; then
    echo "Reiniciando el servidor..."
    reboot
else
    echo "Reinicio cancelado."
fi
