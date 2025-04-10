


# Wireguard

WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
KEYS_DIR="$WG_DIR/keys"
CLIENTS_DIR="$WG_DIR/clients"
CONFIG="$WG_DIR/$WG_INTERFACE.conf"
PORT=51820
SUBNET="10.0.0"
DDNS_FILE="$WG_DIR/ddns.txt"

# Función para obtener o pedir el DDNS
get_ddns() {
  if [[ -f $DDNS_FILE ]]; then
    SERVER_DDNS=$(cat $DDNS_FILE)
  else
    read -rp "Introduce tu DDNS o IP pública (ej: ejemplo.ddns.net): " SERVER_DDNS
    echo "$SERVER_DDNS" > $DDNS_FILE
  fi
}

# Instalación inicial
setup_server() {
  echo "Instalando WireGuard y qrencode..."
  apt update && apt install -y wireguard qrencode

  mkdir -p $KEYS_DIR $CLIENTS_DIR
  chmod 700 $KEYS_DIR

  echo "Generando claves del servidor..."
  wg genkey | tee $KEYS_DIR/server_private.key | wg pubkey > $KEYS_DIR/server_public.key
  SERVER_PRIVATE_KEY=$(cat $KEYS_DIR/server_private.key)

  get_ddns

  echo "Creando configuración del servidor..."
  cat > $CONFIG <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = ${SUBNET}.1/24
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
ListenPort = $PORT
EOF

  chmod 600 $CONFIG
  # systemctl enable wg-quick@$WG_INTERFACE
  # systemctl start wg-quick@$WG_INTERFACE
  # echo "Servidor WireGuard configurado y funcionando en $WG_INTERFACE"
}

# Añadir nuevo peer
add_peer() {
  get_ddns
  SERVER_PUBLIC_KEY=$(cat $KEYS_DIR/server_public.key)

  CLIENT_ID=$(ls $CLIENTS_DIR | grep -c '\.conf')
  CLIENT_NAME="peer$CLIENT_ID"
  CLIENT_IP="${SUBNET}.$((CLIENT_ID + 2))/32"

  echo "Generando claves para $CLIENT_NAME..."
  wg genkey | tee $CLIENTS_DIR/${CLIENT_NAME}_private.key | wg pubkey > $CLIENTS_DIR/${CLIENT_NAME}_public.key
  CLIENT_PRIVATE_KEY=$(cat $CLIENTS_DIR/${CLIENT_NAME}_private.key)
  CLIENT_PUBLIC_KEY=$(cat $CLIENTS_DIR/${CLIENT_NAME}_public.key)

  echo "Añadiendo $CLIENT_NAME al servidor..."
  wg set $WG_INTERFACE peer $CLIENT_PUBLIC_KEY allowed-ips $CLIENT_IP
  wg-quick save $WG_INTERFACE
  wg-quick up $WG_INTERFACE
  systemctl enable wg-quick@$WG_INTERFACE
  systemctl start wg-quick@$WG_INTERFACE
  echo "Servidor WireGuard configurado y funcionando en $WG_INTERFACE"

  # Habilitar reenvío de IP
  echo "Habilitando el reenvío de IP..."
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p

  echo "Creando archivo de configuración para $CLIENT_NAME..."
  cat > $CLIENTS_DIR/$CLIENT_NAME.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_DDNS:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  echo "Generando código QR para $CLIENT_NAME:"
  qrencode -t ansiutf8 < $CLIENTS_DIR/$CLIENT_NAME.conf
  echo "Archivo de configuración guardado en: $CLIENTS_DIR/$CLIENT_NAME.conf"
}

# Menú principal
case "$1" in
  setup)
    setup_server
    ;;
  add)
    add_peer
    ;;
  *)
    echo "Uso: $0 {setup|add}"
    echo "  setup: instala y configura el servidor"
    echo "  add: añade un nuevo peer y muestra el QR"
    ;;
esac


