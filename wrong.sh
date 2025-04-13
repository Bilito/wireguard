#!/bin/bash

cd /etc/
rm -rf /wireguard
exit

sudo apt autoremove wireguard
sudo rm -rf wireguard_prueba.sh
wget https://raw.githubusercontent.com/Bilito/wireguard/refs/heads/main/wireguard_prueba.sh
sudo chmod +x wireguard_prueba.sh
