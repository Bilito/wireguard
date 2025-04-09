version: '3.8'

networks:
  wg_net:
    driver: bridge

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - PASSWORD=${PASSWORD}
      - WG_HOST=${WG_HOST}
      - WG_PORT=${WG_PORT}
    ports:
      - "${WG_PORT}:${WG_PORT}/udp"
      - "51821:51821/tcp"  # Interfaz web de wg-easy
    volumes:
      - ./config:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    networks:
      - wg_net

  adguardhome:
    image: adguard/adguardhome
    container_name: adguard-home
    environment:
      - TZ=Europe/Madrid
    volumes:
      - ./config-adguard:/opt/adguardhome/conf
      - ./work-adguard:/opt/adguardhome/work
    restart: always
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
      - "80:80/tcp"
      - "443:443/tcp"
    networks:
      - wg_net
