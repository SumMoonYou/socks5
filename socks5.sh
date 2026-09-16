#!/bin/bash
# ============================================================
# Dante SOCKS5 一键管理脚本
# 支持 Debian/Ubuntu/CentOS/RHEL/Rocky/Alma/Fedora
# 功能：安装、修改、状态、重启、链接、日志、测试、配置、卸载
#
# v2rayN 格式：
# socks://Base64(username:password)@IP:PORT#URL编码备注
#
# 注意：这里只 Base64 编码 用户名:密码，IP:端口在 Base64 外。
# ============================================================

SERVICE="danted"
CONF="/etc/danted.conf"
ENV="/etc/danted-socks5.env"
UNIT="/etc/systemd/system/danted.service"
REMARK="Dante SOCKS5"

# -------------------- 颜色 --------------------
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

info(){ echo -e "${B}[信息]${N} $*"; }
ok(){ echo -e "${G}[成功]${N} $*"; }
warn(){ echo -e "${Y}[警告]${N} $*"; }
err(){ echo -e "${R}[错误]${N} $*"; }
title(){ echo -e "\n${C}============================================================${N}\n${C} $*${N}\n${C}============================================================${N}\n"; }

# -------------------- Root / 系统 --------------------
root(){ [ "$(id -u)" = 0 ] || { err "请使用 root 运行。"; exit 1; }; }

os_detect(){
    [ -f /etc/os-release ] || { err "无法检测系统。"; exit 1; }
    . /etc/os-release
    OS="$ID"
    case "$OS" in
        debian|ubuntu) PM=apt;;
        centos|rhel|rocky|almalinux) command -v dnf >/dev/null 2>&1 && PM=dnf || PM=yum;;
        fedora) PM=dnf;;
        *) err "不支持的系统：$OS"; exit 1;;
    esac
}

# -------------------- 随机值 --------------------
rand(){
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"
}

rand_port(){
    while :; do
        P=$((RANDOM%50001+10000))
        ss -lntup 2>/dev/null | grep -qE ":$P([[:space:]]|$)" || { echo "$P"; return; }
    done
}

# -------------------- 安装依赖 --------------------
deps(){
    info "安装系统依赖..."
    case "$PM" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y dante-server curl iproute2 iptables iptables-persistent \
                ca-certificates procps netcat-openbsd python3
            ;;
        dnf)
            dnf install -y dante-server curl iproute iptables ca-certificates procps-ng nc python3
            ;;
        yum)
            yum install -y dante-server curl iproute iptables ca-certificates procps nc python3
            ;;
    esac

    DANTE_BIN="$(command -v danted || command -v dante-server || true)"
    [ -n "$DANTE_BIN" ] || { err "未找到 danted 程序。"; exit 1; }
    ok "Dante：$DANTE_BIN"
}

# -------------------- 网络信息 --------------------
net_detect(){
    IFACE="$(ip route get 1.1.1.1 2>/dev/null |
        awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')"

    [ -n "$IFACE" ] || IFACE="$(ip route | awk '$1=="default"{print $5;exit}')"
    [ -n "$IFACE" ] || { err "无法检测出口网卡。"; exit 1; }

    IPV4="$(ip -4 addr show dev "$IFACE" 2>/dev/null |
        awk '/inet /{print $2;exit}' | cut -d/ -f1)"

    IPV6="$(ip -6 addr show dev "$IFACE" scope global 2>/dev/null |
        awk '/inet6/{print $2;exit}' | cut -d/ -f1)"

    ok "出口网卡：$IFACE"
    [ -n "$IPV4" ] && ok "IPv4：$IPV4" || warn "没有 IPv4"
    [ -n "$IPV6" ] && ok "IPv6：$IPV6" || warn "没有公网 IPv6"
}

public_ip(){
    PUB4="$(curl -4 -s --connect-timeout 5 --max-time 8 https://api.ipify.org 2>/dev/null || true)"
    [ -n "$PUB4" ] || PUB4="$(curl -4 -s --connect-timeout 5 --max-time 8 https://ifconfig.me 2>/dev/null || true)"
    PUB6="$(curl -6 -s --connect-timeout 5 --max-time 8 https://api6.ipify.org 2>/dev/null || true)"

    [[ "$PUB4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || PUB4=""
}

# -------------------- 输入配置 --------------------
input_cfg(){
    title "SOCKS5 配置"

    while :; do
        read -rp "端口 [回车随机]： " SOCKS_PORT
        [ -n "$SOCKS_PORT" ] || SOCKS_PORT="$(rand_port)"
        [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] &&
        [ "$SOCKS_PORT" -ge 1 ] &&
        [ "$SOCKS_PORT" -le 65535 ] && break
        err "端口无效。"
    done

    while :; do
        read -rp "用户名 [回车随机]： " SOCKS_USER
        [ -n "$SOCKS_USER" ] || SOCKS_USER="socks$(rand 8)"
        [[ "$SOCKS_USER" =~ ^[A-Za-z0-9._-]+$ ]] && break
        err "用户名只能使用字母、数字、点、下划线、横线。"
    done

    while :; do
        read -rsp "密码 [回车随机]： " SOCKS_PASS
        echo
        [ -n "$SOCKS_PASS" ] || SOCKS_PASS="$(rand 16)"
        [ "${#SOCKS_PASS}" -ge 4 ] && break
        err "密码至少 4 位。"
    done

    ok "端口：$SOCKS_PORT"
    ok "用户名：$SOCKS_USER"
}

# -------------------- 保存配置 --------------------
save_cfg(){
    cat > "$ENV" <<EOF
SOCKS_PORT='$SOCKS_PORT'
SOCKS_USER='$SOCKS_USER'
SOCKS_PASS='$SOCKS_PASS'
IFACE='$IFACE'
EOF
    chmod 600 "$ENV"
}

load_cfg(){
    [ -f "$ENV" ] || return 1
    . "$ENV"
}

# -------------------- 创建认证用户 --------------------
user_cfg(){
    if id "$SOCKS_USER" >/dev/null 2>&1; then
        echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd
    else
        useradd --system --no-create-home --shell /usr/sbin/nologin "$SOCKS_USER"
        echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd
    fi
}

# -------------------- Dante 配置 --------------------
make_conf(){
    # Dante 同时监听 IPv4/IPv6，开启 CONNECT/BIND/UDP。
    cat > "$CONF" <<EOF
logoutput: syslog

internal: 0.0.0.0 port = $SOCKS_PORT
internal: :: port = $SOCKS_PORT

external: $IFACE

clientmethod: none
socksmethod: username

client pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    log: connect error
}

client pass {
    from: ::/0
    to: ::/0
    log: connect error
}

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    command: connect
    socksmethod: username
    log: connect error
}

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    command: bind
    socksmethod: username
    log: connect error
}

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    command: udpassociate
    socksmethod: username
    log: connect error
}

socks pass {
    from: ::/0
    to: ::/0
    command: connect
    socksmethod: username
    log: connect error
}

socks pass {
    from: ::/0
    to: ::/0
    command: bind
    socksmethod: username
    log: connect error
}

socks pass {
    from: ::/0
    to: ::/0
    command: udpassociate
    socksmethod: username
    log: connect error
}
EOF
    chmod 600 "$CONF"
}

# -------------------- systemd --------------------
make_unit(){
    # 关键：network-online + enable，确保系统启动后自动启动 SOCKS5。
    cat > "$UNIT" <<EOF
[Unit]
Description=Dante SOCKS5 Proxy Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$DANTE_BIN -f $CONF
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE.service" >/dev/null 2>&1
}

# -------------------- 防火墙 --------------------
fw(){
    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 &&
       systemctl is-active --quiet firewalld 2>/dev/null; then

        firewall-cmd --permanent --add-port="$SOCKS_PORT/tcp" >/dev/null
        firewall-cmd --permanent --add-port="$SOCKS_PORT/udp" >/dev/null
        firewall-cmd --reload >/dev/null
        ok "firewalld 已开放 $SOCKS_PORT"
        return
    fi

    # UFW
    if command -v ufw >/dev/null 2>&1 &&
       ufw status 2>/dev/null | grep -q "Status: active"; then

        ufw allow "$SOCKS_PORT/tcp" >/dev/null
        ufw allow "$SOCKS_PORT/udp" >/dev/null
        ok "UFW 已开放 $SOCKS_PORT"
        return
    fi

    # iptables
    command -v iptables >/dev/null 2>&1 && {
        iptables -C INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null ||
            iptables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT
        iptables -C INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null ||
            iptables -I INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT
    }

    # IPv6 防火墙
    command -v ip6tables >/dev/null 2>&1 && {
        ip6tables -C INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null ||
            ip6tables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT
        ip6tables -C INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null ||
            ip6tables -I INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT
    }

    command -v netfilter-persistent >/dev/null 2>&1 &&
        netfilter-persistent save >/dev/null 2>&1 || true
}

# -------------------- 删除旧防火墙规则 --------------------
fw_del(){
    local P="$1"
    [ -z "$P" ] && return

    if command -v firewall-cmd >/dev/null 2>&1 &&
       systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --remove-port="$P/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port="$P/udp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi

    if command -v ufw >/dev/null 2>&1 &&
       ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw delete allow "$P/tcp" >/dev/null 2>&1 || true
        ufw delete allow "$P/udp" >/dev/null 2>&1 || true
    fi

    command -v iptables >/dev/null 2>&1 && {
        while iptables -C INPUT -p tcp --dport "$P" -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -p tcp --dport "$P" -j ACCEPT
        done
        while iptables -C INPUT -p udp --dport "$P" -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -p udp --dport "$P" -j ACCEPT
        done
    }

    command -v ip6tables >/dev/null 2>&1 && {
        while ip6tables -C INPUT -p tcp --dport "$P" -j ACCEPT 2>/dev/null; do
            ip6tables -D INPUT -p tcp --dport "$P" -j ACCEPT
        done
        while ip6tables -C INPUT -p udp --dport "$P" -j ACCEPT 2>/dev/null; do
            ip6tables -D INPUT -p udp --dport "$P" -j ACCEPT
        done
    }

    command -v netfilter-persistent >/dev/null 2>&1 &&
        netfilter-persistent save >/dev/null 2>&1 || true
}

# -------------------- 启动服务 --------------------
start(){
    systemctl daemon-reload

    # 每次启动都检查一次开机自启，避免被人为 disable 后失效。
    systemctl enable "$SERVICE.service" >/dev/null 2>&1

    systemctl restart "$SERVICE.service"
    sleep 2

    if systemctl is-active --quiet "$SERVICE.service"; then
        ok "Dante 运行正常。"
    else
        err "Dante 启动失败。"
        journalctl -u "$SERVICE.service" -n 50 --no-pager
        return 1
    fi

    systemctl is-enabled "$SERVICE.service" >/dev/null 2>&1 &&
        ok "开机自启：已启用" ||
        warn "开机自启：未启用"
}

# -------------------- Base64 / URL 编码 --------------------
b64(){
    printf '%s' "$1" | base64 -w 0 2>/dev/null ||
        printf '%s' "$1" | base64 | tr -d '\r\n'
}

urlencode(){
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
    else
        printf '%s' "$1" |
            sed -e 's/%/%25/g' -e 's/#/%23/g' -e 's/ /%20/g' -e 's/|/%7C/g'
    fi
}

# -------------------- v2rayN 链接 --------------------
link(){
    local HOST="$1"
    local AUTH
    local B64
    local REMARK_ENC

    # 关键格式：
    # Base64 只编码 username:password
    AUTH="${SOCKS_USER}:${SOCKS_PASS}"
    B64="$(b64 "$AUTH")"
    REMARK_ENC="$(urlencode "$REMARK")"

    if [[ "$HOST" == *:* ]]; then
        echo "socks://${B64}@[${HOST}]:${SOCKS_PORT}#${REMARK_ENC}"
    else
        echo "socks://${B64}@${HOST}:${SOCKS_PORT}#${REMARK_ENC}"
    fi
}

# -------------------- 查看链接 --------------------
links(){
    root
    load_cfg || { err "未安装 SOCKS5。"; return; }

    public_ip
    title "v2rayN 导入链接"

    echo "备注：$REMARK"
    echo

    if [ -n "$PUB4" ]; then
        echo "IPv4："
        link "$PUB4"
        echo
    else
        warn "公网 IPv4 获取失败。"
    fi

    if [ -n "$PUB6" ]; then
        echo "IPv6："
        link "$PUB6"
        echo
    fi
}

# -------------------- 安装 --------------------
install_socks(){
    root
    os_detect

    title "安装 Dante SOCKS5"

    deps
    net_detect
    input_cfg
    user_cfg
    save_cfg
    make_conf
    make_unit
    fw
    start

    show_result
}

# -------------------- 安装结果 --------------------
show_result(){
    load_cfg || return
    public_ip

    title "安装完成"

    echo "协议       ：SOCKS5"
    echo "端口       ：$SOCKS_PORT"
    echo "用户名     ：$SOCKS_USER"
    echo "密码       ：$SOCKS_PASS"
    echo "出口网卡   ：$IFACE"
    echo "TCP/UDP    ：支持"
    echo "IPv4/IPv6  ：支持"

    systemctl is-enabled "$SERVICE.service" >/dev/null 2>&1 &&
        echo -e "开机自启   ：${G}已启用${N}" ||
        echo -e "开机自启   ：${R}未启用${N}"

    echo

    [ -n "$PUB4" ] && {
        echo "IPv4 v2rayN："
        link "$PUB4"
        echo
    }

    [ -n "$PUB6" ] && {
        echo "IPv6 v2rayN："
        link "$PUB6"
        echo
    }
}

# -------------------- 修改配置 --------------------
modify(){
    root
    load_cfg || { err "未安装 SOCKS5。"; return; }

    local OLD_PORT="$SOCKS_PORT"

    title "修改 SOCKS5 配置"

    echo "当前端口：$SOCKS_PORT"
    echo "当前用户：$SOCKS_USER"
    echo

    while :; do
        read -rp "新端口 [回车保持 $SOCKS_PORT]： " P
        P="${P:-$SOCKS_PORT}"
        [[ "$P" =~ ^[0-9]+$ ]] &&
        [ "$P" -ge 1 ] &&
        [ "$P" -le 65535 ] && break
        err "端口无效。"
    done

    read -rp "新用户名 [回车保持 $SOCKS_USER]： " U
    U="${U:-$SOCKS_USER}"
    [[ "$U" =~ ^[A-Za-z0-9._-]+$ ]] || {
        err "用户名格式错误。"
        return
    }

    read -rsp "新密码 [回车保持原密码]： " PW
    echo

    SOCKS_PORT="$P"
    SOCKS_USER="$U"
    [ -n "$PW" ] && SOCKS_PASS="$PW"

    user_cfg
    save_cfg
    make_conf

    [ "$OLD_PORT" != "$SOCKS_PORT" ] && fw_del "$OLD_PORT"

    fw
    make_unit
    start

    ok "配置修改完成。"
    links
}

# -------------------- 状态 --------------------
status(){
    root
    load_cfg || true

    title "Dante SOCKS5 状态"

    systemctl is-active --quiet "$SERVICE.service" &&
        ok "运行状态：运行中" ||
        err "运行状态：未运行"

    systemctl is-enabled "$SERVICE.service" >/dev/null 2>&1 &&
        ok "开机自启：已启用" ||
        warn "开机自启：未启用"

    [ -n "$SOCKS_PORT" ] && echo "端口：$SOCKS_PORT"
    [ -n "$SOCKS_USER" ] && echo "用户：$SOCKS_USER"

    echo
    echo "监听："
    ss -lntup 2>/dev/null | grep -E "danted|:${SOCKS_PORT}" || true

    echo
    systemctl status "$SERVICE.service" --no-pager -l || true
}

# -------------------- 重启 --------------------
restart_socks(){
    root
    systemctl list-unit-files "$SERVICE.service" >/dev/null 2>&1 ||
        { err "Dante 尚未安装。"; return; }

    systemctl daemon-reload
    systemctl enable "$SERVICE.service" >/dev/null 2>&1
    systemctl restart "$SERVICE.service"
    sleep 2

    systemctl is-active --quiet "$SERVICE.service" &&
        ok "Dante 重启成功。" ||
        { err "重启失败。"; journalctl -u "$SERVICE.service" -n 50 --no-pager; }

    systemctl is-enabled "$SERVICE.service" >/dev/null 2>&1 &&
        ok "开机自启：已启用"
}

# -------------------- 日志 --------------------
logs(){
    root
    title "Dante 日志"
    journalctl -u "$SERVICE.service" -n 100 --no-pager -l
}

# -------------------- 测试 --------------------
test_proxy(){
    root
    load_cfg || { err "未安装 SOCKS5。"; return; }

    title "SOCKS5 测试"

    if ! systemctl is-active --quiet "$SERVICE.service"; then
        err "Dante 当前未运行。"
        return
    fi

    echo "测试 127.0.0.1:$SOCKS_PORT ..."
    echo

    OUT="$(
        curl --socks5-hostname \
        "${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:${SOCKS_PORT}" \
        -4 -s \
        --connect-timeout 10 \
        --max-time 15 \
        https://api.ipify.org \
        2>/tmp/dante_test.err
    )"

    if [ $? -eq 0 ] && [ -n "$OUT" ]; then
        ok "SOCKS5 测试成功。"
        echo "代理出口 IPv4：$OUT"
    else
        err "SOCKS5 测试失败。"
        cat /tmp/dante_test.err 2>/dev/null || true
    fi

    rm -f /tmp/dante_test.err
}

# -------------------- 查看配置 --------------------
config(){
    root
    load_cfg || { err "未安装 SOCKS5。"; return; }

    title "当前配置"

    echo "端口     ：$SOCKS_PORT"
    echo "用户名   ：$SOCKS_USER"
    echo "密码     ：$SOCKS_PASS"
    echo "出口网卡 ：$IFACE"
    echo "配置文件 ：$CONF"
    echo

    [ -f "$CONF" ] && cat "$CONF"
}

# -------------------- 卸载 --------------------
uninstall(){
    root
    os_detect
    load_cfg || true

    title "卸载 Dante SOCKS5"

    read -rp "确认卸载请输入 YES： " X
    [ "$X" = "YES" ] || { warn "已取消。"; return; }

    systemctl stop "$SERVICE.service" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE.service" >/dev/null 2>&1 || true

    [ -n "$SOCKS_PORT" ] && fw_del "$SOCKS_PORT"

    rm -f "$UNIT"
    systemctl daemon-reload

    case "$PM" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get remove -y dante-server >/dev/null 2>&1 || true;;
        dnf) dnf remove -y dante-server >/dev/null 2>&1 || true;;
        yum) yum remove -y dante-server >/dev/null 2>&1 || true;;
    esac

    [ -n "$SOCKS_USER" ] && id "$SOCKS_USER" >/dev/null 2>&1 &&
        userdel "$SOCKS_USER" >/dev/null 2>&1 || true

    rm -f "$CONF" "$ENV"

    ok "Dante SOCKS5 已卸载。"
}

# ============================================================
# 菜单
# ============================================================

menu(){
    root

    while :; do
        clear

        echo -e "${C}============================================================${N}"
        echo -e "${C}              Dante SOCKS5 一键管理脚本${N}"
        echo -e "${C}============================================================${N}"

        if systemctl is-active --quiet "$SERVICE.service" 2>/dev/null; then
            echo -e "服务状态：${G}运行中${N}"
        else
            echo -e "服务状态：${R}未运行${N}"
        fi

        if systemctl is-enabled "$SERVICE.service" >/dev/null 2>&1; then
            echo -e "开机启动：${G}已启用${N}"
        else
            echo -e "开机启动：${Y}未启用${N}"
        fi

        load_cfg 2>/dev/null && {
            echo "端口：$SOCKS_PORT    用户：$SOCKS_USER"
        }

        echo
        echo "============================================================"
        echo "  1. 安装 SOCKS5"
        echo "  2. 修改 SOCKS5 配置"
        echo "  3. 查看 SOCKS5 状态"
        echo "  4. 重启 SOCKS5"
        echo "  5. 查看链接"
        echo "  6. 查看日志"
        echo "  7. 测试 SOCKS5"
        echo "  8. 查看当前配置"
        echo "  9. 卸载 SOCKS5"
        echo "  0. 退出"
        echo "============================================================"
        echo

        read -rp "请选择 [0-9]： " C

        case "$C" in
            1) install_socks; read -rp "按回车继续..." ;;
            2) modify; read -rp "按回车继续..." ;;
            3) status; read -rp "按回车继续..." ;;
            4) restart_socks; read -rp "按回车继续..." ;;
            5) links; read -rp "按回车继续..." ;;
            6) logs; read -rp "按回车继续..." ;;
            7) test_proxy; read -rp "按回车继续..." ;;
            8) config; read -rp "按回车继续..." ;;
            9) uninstall; read -rp "按回车继续..." ;;
            0) clear; exit 0 ;;
            *) err "无效选择。"; sleep 1 ;;
        esac
    done
}

# ============================================================
# CLI 参数
# ============================================================

case "${1:-}" in
    install)   install_socks ;;
    modify)    modify ;;
    status)    status ;;
    restart)   restart_socks ;;
    links)     links ;;
    logs)      logs ;;
    test)      test_proxy ;;
    config)    config ;;
    uninstall) uninstall ;;
    menu)      menu ;;
    *)         menu ;;
esac
