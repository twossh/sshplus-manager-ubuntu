#!/usr/bin/env bash

OVPN_DIR='/etc/openvpn'
OVPN_SERVER_DIR='/etc/openvpn/server'
OVPN_DATA_DIR='/etc/openvpn/sshplus'
OVPN_EASYRSA='/etc/openvpn/sshplus/easy-rsa'
OVPN_CLIENT_DIR='/root/sshplus-clients'
OVPN_NAME='sshplus'

openvpn_unit() {
    if service_exists 'openvpn-server@.service' || [[ -f /lib/systemd/system/openvpn-server@.service || -f /usr/lib/systemd/system/openvpn-server@.service ]]; then
        printf 'openvpn-server@%s.service' "$OVPN_NAME"
    else
        printf 'openvpn@%s.service' "$OVPN_NAME"
    fi
}

openvpn_installed() {
    [[ -f "${OVPN_SERVER_DIR}/${OVPN_NAME}.conf" ]]
}

install_openvpn_server() {
    require_root
    openvpn_installed && { warn 'OpenVPN já está configurado.'; return; }
    local port proto iface endpoint endpoint_input server_proto
    read -r -p 'Porta OpenVPN [1194]: ' port; port="${port:-1194}"
    valid_port "$port" || { error 'Porta inválida.'; return; }
    read -r -p 'Protocolo udp/tcp [udp]: ' proto; proto="${proto:-udp}"
    [[ "$proto" == udp || "$proto" == tcp ]] || { error 'Protocolo inválido.'; return; }
    iface="$(ip route show default | awk '/default/{print $5; exit}')"
    [[ "$iface" =~ ^[A-Za-z0-9_.:-]+$ ]] || { error 'Não foi possível detectar uma interface pública válida.'; return; }
    endpoint="$(get_public_ipv4)"
    read -r -p "IP ou domínio público [$endpoint]: " endpoint_input
    endpoint="${endpoint_input:-$endpoint}"
    valid_endpoint "$endpoint" || { error 'IP ou domínio público inválido.'; return; }

    apt_install openvpn easy-rsa nftables ca-certificates || { error 'Falha ao instalar dependências do OpenVPN.'; return 1; }
    install -d -m 0755 "$OVPN_SERVER_DIR"
    install -d -m 0700 "$OVPN_DATA_DIR" "$OVPN_CLIENT_DIR"
    rm -rf "$OVPN_EASYRSA"
    make-cadir "$OVPN_EASYRSA"
    pushd "$OVPN_EASYRSA" >/dev/null
    EASYRSA_BATCH=1 EASYRSA_REQ_CN='SSHPlus-CA' ./easyrsa init-pki
    EASYRSA_BATCH=1 EASYRSA_REQ_CN='SSHPlus-CA' ./easyrsa build-ca nopass
    EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
    EASYRSA_BATCH=1 ./easyrsa sign-req server server
    EASYRSA_BATCH=1 ./easyrsa gen-dh
    EASYRSA_BATCH=1 ./easyrsa gen-crl
    openvpn --genkey secret pki/ta.key
    popd >/dev/null

    install -m 0644 "$OVPN_EASYRSA/pki/ca.crt" "$OVPN_DATA_DIR/ca.crt"
    install -m 0644 "$OVPN_EASYRSA/pki/issued/server.crt" "$OVPN_DATA_DIR/server.crt"
    install -m 0600 "$OVPN_EASYRSA/pki/private/server.key" "$OVPN_DATA_DIR/server.key"
    install -m 0644 "$OVPN_EASYRSA/pki/dh.pem" "$OVPN_DATA_DIR/dh.pem"
    install -m 0600 "$OVPN_EASYRSA/pki/ta.key" "$OVPN_DATA_DIR/ta.key"
    install -m 0644 "$OVPN_EASYRSA/pki/crl.pem" "$OVPN_DATA_DIR/crl.pem"

    server_proto="$proto"
    [[ "$proto" == tcp ]] && server_proto='tcp-server'
    cat > "${OVPN_SERVER_DIR}/${OVPN_NAME}.conf" <<CONF
port $port
proto $server_proto
dev tun
topology subnet
server 10.8.0.0 255.255.255.0
ca /etc/openvpn/sshplus/ca.crt
cert /etc/openvpn/sshplus/server.crt
key /etc/openvpn/sshplus/server.key
dh /etc/openvpn/sshplus/dh.pem
crl-verify /etc/openvpn/sshplus/crl.pem
tls-crypt /etc/openvpn/sshplus/ta.key
tls-version-min 1.2
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
verb 3
CONF
    [[ "$proto" == udp ]] && echo 'explicit-exit-notify 1' >> "${OVPN_SERVER_DIR}/${OVPN_NAME}.conf"

    cat > /etc/sysctl.d/99-sshplus-openvpn.conf <<'CONF'
net.ipv4.ip_forward = 1
CONF
    sysctl --system >/dev/null

    install -d -m 0755 /etc/nftables.d
    cat > /etc/nftables.d/sshplus-openvpn.nft <<CONF
table ip sshplus_openvpn {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 10.8.0.0/24 oifname "$iface" masquerade
    }
}
CONF
    nft -c -f /etc/nftables.d/sshplus-openvpn.nft
    cat > /etc/systemd/system/sshplus-openvpn-nat.service <<'UNIT'
[Unit]
Description=SSHPlus OpenVPN NAT (nftables)
After=network-online.target
Wants=network-online.target
Before=openvpn-server@sshplus.service openvpn@sshplus.service

[Service]
Type=oneshot
ExecStartPre=-/usr/sbin/nft delete table ip sshplus_openvpn
ExecStart=/usr/sbin/nft -f /etc/nftables.d/sshplus-openvpn.nft
ExecStop=-/usr/sbin/nft delete table ip sshplus_openvpn
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now sshplus-openvpn-nat.service

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port/$proto" >/dev/null || true
        ufw route allow in on tun0 out on "$iface" >/dev/null || true
    fi

    set_config_value "$SSHPLUS_CONF" SSHPLUS_OVPN_ENDPOINT "$endpoint"
    set_config_value "$SSHPLUS_CONF" SSHPLUS_OVPN_PORT "$port"
    set_config_value "$SSHPLUS_CONF" SSHPLUS_OVPN_PROTO "$proto"

    local unit
    unit="$(openvpn_unit)"
    if [[ "$unit" == openvpn@* ]]; then
        ln -sfn "${OVPN_SERVER_DIR}/${OVPN_NAME}.conf" "${OVPN_DIR}/${OVPN_NAME}.conf"
    fi
    systemctl enable --now "$unit"
    ok "OpenVPN instalado em $endpoint:$port/$proto."
}

create_openvpn_client() {
    require_root
    openvpn_installed || { error 'Instale o OpenVPN primeiro.'; return; }
    local name endpoint port proto client_proto
    read -r -p 'Nome do cliente: ' name
    valid_username "$name" || { error 'Nome inválido.'; return; }
    [[ ! -f "$OVPN_EASYRSA/pki/issued/${name}.crt" ]] || { error 'Cliente já existe.'; return; }
    pushd "$OVPN_EASYRSA" >/dev/null
    EASYRSA_BATCH=1 ./easyrsa gen-req "$name" nopass
    EASYRSA_BATCH=1 ./easyrsa sign-req client "$name"
    popd >/dev/null
    load_config
    endpoint="${SSHPLUS_OVPN_ENDPOINT:-$(get_public_ipv4)}"
    port="${SSHPLUS_OVPN_PORT:-1194}"
    proto="${SSHPLUS_OVPN_PROTO:-udp}"
    install -d -m 0700 "$OVPN_CLIENT_DIR"
    client_proto="$proto"
    [[ "$proto" == tcp ]] && client_proto='tcp-client'
    {
        cat <<CONF
client
dev tun
proto $client_proto
remote $endpoint $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
auth SHA256
auth-nocache
tls-version-min 1.2
verb 3
<ca>
CONF
        cat "$OVPN_EASYRSA/pki/ca.crt"
        printf '</ca>\n<cert>\n'
        sed -ne '/BEGIN CERTIFICATE/,$ p' "$OVPN_EASYRSA/pki/issued/${name}.crt"
        printf '</cert>\n<key>\n'
        cat "$OVPN_EASYRSA/pki/private/${name}.key"
        printf '</key>\n<tls-crypt>\n'
        cat "$OVPN_EASYRSA/pki/ta.key"
        printf '</tls-crypt>\n'
    } > "$OVPN_CLIENT_DIR/${name}.ovpn"
    chmod 0600 "$OVPN_CLIENT_DIR/${name}.ovpn"
    ok "Cliente criado: $OVPN_CLIENT_DIR/${name}.ovpn"
}

revoke_openvpn_client() {
    require_root
    local name
    read -r -p 'Nome do cliente: ' name
    [[ -f "$OVPN_EASYRSA/pki/issued/${name}.crt" ]] || { error 'Cliente não encontrado.'; return; }
    confirm "Revogar o cliente $name?" || return
    pushd "$OVPN_EASYRSA" >/dev/null
    EASYRSA_BATCH=1 ./easyrsa revoke "$name"
    EASYRSA_BATCH=1 ./easyrsa gen-crl
    popd >/dev/null
    install -m 0644 "$OVPN_EASYRSA/pki/crl.pem" "$OVPN_DATA_DIR/crl.pem"
    rm -f "$OVPN_CLIENT_DIR/${name}.ovpn"
    systemctl restart "$(openvpn_unit)"
    ok 'Cliente revogado.'
}

show_openvpn_status() {
    header 'Status do OpenVPN'
    local unit
    unit="$(openvpn_unit)"
    systemctl --no-pager --full status "$unit" 2>/dev/null || true
    printf '\nClientes gerados:\n'
    ls -1 "$OVPN_CLIENT_DIR"/*.ovpn 2>/dev/null || echo 'Nenhum.'
}

vpn_menu() {
    local option
    while true; do
        header 'OpenVPN'
        printf '  1) Instalar servidor OpenVPN\n  2) Criar cliente\n  3) Revogar cliente\n  4) Status\n  0) Voltar\n\n'
        read -r -p 'Opção: ' option
        case "$option" in
            1) install_openvpn_server; pause ;;
            2) create_openvpn_client; pause ;;
            3) revoke_openvpn_client; pause ;;
            4) show_openvpn_status; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
