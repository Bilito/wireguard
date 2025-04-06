#!/bin/bash

# Navegamos hasta la carpeta adguard,  paramos el contenedor, volvemos atrás  y elimininamos la carpeta

cd ./adguard
sudo docker-compose down
cd
sudo rm -R ./adguard || exit

# Navegamos hasta la carpeta wireguard,  paramos el contenedor, volvemos atrás  y elimininamos la carpeta

cd ./wireguard-docker
sudo docker-compose down
cd
sudo rm -R ./wireguard-docker || exit

