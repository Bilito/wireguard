#!/bin/bash

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_INTERFACE="wg0"
SUBNET="10.0.0"  # Puedes cambiar esto
SERVER_PORT=51820
AUTO_MODE=false  # Modo automático desactivado por defecto

# Comprobamos si estan instalados qr encode y zip
check_dependencies() {
    if ! command -v qrencode &> /dev/null; then
        echo "[*] qrencode no está instalado. Instalándolo..."
        sudo apt update && sudo apt install -y qrencode
    fi

    if ! command -v zip &> /dev/null; then
        echo "[*] zip no está instalado. Instalándolo..."
        sudo apt update && sudo apt install -y zip
    fi
}

# obtenemos la interfaz de red que se esta usando
get_main_interface() {
    ip route | grep default | awk '{print $5}' | head -n1
}

# obtenemos la ip local de la maquina ubuntu
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# generamos las claves
generate_keys() {
    umask 077
    wg genkey | tee "$1" | wg pubkey > "$2"
}

# iniciamos el servidor
init_server() {
    echo "[*] Inicializando servidor WireGuard..."

    mkdir -p "$WG_DIR"
    cd "$WG_DIR" || exit 1

    # Claves
    generate_keys "server_private.key" "server_public.key"
    generate_keys "peer1_private.key" "peer1_public.key"

    SERVER_PRIV_KEY=$(<server_private.key)
    PEER1_PUB_KEY=$(<peer1_public.key)

    INTERFACE=$(get_main_interface)
    LOCAL_IP=$(get_local_ip)

    cat > "$WG_CONF" <<EOF
[Interface]
Address = $SUBNET.1/24
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE

[Peer]
PublicKey = $PEER1_PUB_KEY
AllowedIPs = $SUBNET.2/32
EOF

    echo "[*] Servidor inicializado en $WG_CONF"
}

add_peer() {
    check_dependencies
    echo "[*] Añadiendo nuevo peer..."

    cd "$WG_DIR" || exit 1
    mkdir -p peers

    # obtenemos la ultima IP usada en el peer y la pegamos en el nuevo peer
    LAST_IP=$(grep AllowedIPs "$WG_CONF" | awk -F '[/.]' '{print $4}' | sort -n | tail -n1)
    NEW_IP=$((LAST_IP + 1))

    # variables para creacionista y almacenamiento
    PEER_ID="peer$NEW_IP"
    PRIV_KEY_PATH="peers/${PEER_ID}_private.key"
    PUB_KEY_PATH="peers/${PEER_ID}_public.key"
    CONF_PATH="peers/${PEER_ID}.conf"
    QR_PATH="peers/${PEER_ID}_qr.png"
    ZIP_PATH="peers/${PEER_ID}_config.zip"

    # generamos las claves
    generate_keys "$PRIV_KEY_PATH" "$PUB_KEY_PATH"
    PUB_KEY=$(<"$PUB_KEY_PATH")
    PRIV_KEY=$(<"$PRIV_KEY_PATH")
    SERVER_PUB_KEY=$(<server_public.key)
    LOCAL_IP=$(get_local_ip)

    cat >> "$WG_CONF" <<EOF

[Peer]
PublicKey = $PUB_KEY
AllowedIPs = $SUBNET.$NEW_IP/32
EOF

    # Crear config del cliente
    cat > "$CONF_PATH" <<EOF
[Interface]
PrivateKey = $PRIV_KEY
Address = $SUBNET.$NEW_IP/24
DNS = $LOCAL_IP

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $LOCAL_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    echo "[*] Peer $PEER_ID añadido con IP $SUBNET.$NEW_IP"
    echo "[*] Configuración del cliente:"
    cat "$CONF_PATH"

    echo "[*] Mostrando QR en terminal:"
    qrencode -t ansiutf8 < "$CONF_PATH"

    echo "[*] Guardando QR en archivo $QR_PATH"
    qrencode -o "$QR_PATH" < "$CONF_PATH"

    zip -j "$ZIP_PATH" "$CONF_PATH" "$QR_PATH" > /dev/null
    echo "[*] Archivo comprimido generado: $ZIP_PATH"
}

maybe_restart_server() {
    if [ "$AUTO_MODE" = true ]; then
        echo "[*] Modo automático activado: reiniciando interfaz $WG_INTERFACE..."

        if ip link show "$WG_INTERFACE" &> /dev/null; then
            sudo wg-quick down "$WG_INTERFACE" 2>/dev/null
        fi
        sudo wg-quick up "$WG_INTERFACE"
        echo "[*] Interfaz $WG_INTERFACE reiniciada."

        echo -e "\n[*] Estado actual de WireGuard:"
        sudo wg show "$WG_INTERFACE"
    else
        read -rp "¿Quieres reiniciar el servidor WireGuard ahora? [s/N]: " answer
        case "$answer" in
            [sS]*)
                echo "[*] Verificando estado de la interfaz $WG_INTERFACE..."
                if ip link show "$WG_INTERFACE" &> /dev/null; then
                    sudo wg-quick down "$WG_INTERFACE" 2>/dev/null
                fi
                sudo wg-quick up "$WG_INTERFACE"
                echo "[*] Interfaz $WG_INTERFACE reiniciada."

                echo -e "\n[*] Estado actual de WireGuard:"
                sudo wg show "$WG_INTERFACE"
                ;;
            *)
                echo "[*] No se reinició la interfaz."
                ;;
        esac
    fi
}

# Main
case "$1" in
    init)
        [[ "$2" == "--auto" ]] && AUTO_MODE=true
        init_server
        ;;
    add-peer)
        [[ "$2" == "--auto" ]] && AUTO_MODE=true
        add_peer
        ;;
    *)
        echo "Uso: $0 {init|add-peer} [--auto]"
        ;;
esac
