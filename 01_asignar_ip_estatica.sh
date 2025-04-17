#!/bin/bash

# Pedir la IP estática
read -p "Introduce la IP estática (ej: 192.168.1.100): " static_ip
if ! [[ $static_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "❌ IP no válida. Asegúrate de escribir algo como 192.168.1.123"
  exit 1
fi

# Detectar interfaz de red (toma la primera activa que no sea loopback)
interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)

# Calcular gateway (asume que el router es .1)
gateway=$(echo $static_ip | sed 's/\.[0-9]*$/.1/')

# Crear archivo de configuración Netplan
config_file="/etc/netplan/01-static-ip.yaml"

sudo bash -c "cat > $config_file" <<EOF
network:
  ethernets:
    $interface:
      addresses:
        - $static_ip/24
      nameservers:
        addresses:
        - 8.8.8.8
        - 1.1.1.1
      routes:
        - to: default
          via: $gateway
  version: 2
EOF

# Ajustar permisos seguros
sudo chmod 600 $config_file

# Aplicar configuración
echo "Aplicando configuración..."
sudo netplan apply

echo "✅ IP estática configurada correctamente: $static_ip en $interface"
