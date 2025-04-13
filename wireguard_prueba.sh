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

exit
sudo wget https://raw.githubusercontent.com/Bilito/wireguard/refs/heads/main/add_peer.sh
sudo chmod +x add_peer.sh
sudo ./add_peer.sh
