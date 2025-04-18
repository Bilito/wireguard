#!/bin/bash

# =====================
#  Función para añadir más peers
# =====================

cd /etc/wireguard/

add_peer() {
    read -p "Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT
    read -p "Introduce el nombre del peer: " PEER_NAME

    wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey
    LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

    # Obtener la última IP utilizada para los peers
    SERVER_CONF="/etc/wireguard/wg0.conf"
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
    read -p "¿Deseas agregar un peer? (s/n): " respuesta
    if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ]; then
        add_peer
    else
        break
    fi
done

wg-quick down wg0
wg-quick up wg0

echo "Estado de la interfaz WireGuard:"
wg show

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
