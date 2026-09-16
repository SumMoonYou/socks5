```bash
#!/bin/bash

# ============================================================
#                 Dante SOCKS5 一键管理脚本
# ============================================================
#
# 项目说明：
#   使用 Dante 搭建标准 SOCKS5 代理服务器。
#
# 主要功能：
#   1. 一键安装 SOCKS5
#   2. 一键卸载 SOCKS5
#   3. 查看 SOCKS5 运行状态
#   4. 重启 SOCKS5 服务
#   5. 查看 v2rayN SOCKS5 导入链接
#   6. 修改 SOCKS5 端口、用户名、密码
#
# 网络支持：
#   - IPv4
#   - IPv6
#   - TCP
#   - UDP
#
# 认证方式：
#   - 用户名 + 密码
#
# 参数支持：
#   - 端口可以手动输入，也可以随机生成
#   - 用户名可以手动输入，也可以随机生成
#   - 密码可以手动输入，也可以随机生成
#
# 防火墙支持：
#   - firewalld
#   - UFW
#   - iptables
#   - ip6tables
#
# 系统支持：
#   - Debian
#   - Ubuntu
#   - CentOS
#   - RHEL
#   - Rocky Linux
#   - AlmaLinux
#   - Fedora
#
# 使用方法：
#
#   chmod +x socks5.sh
#   ./socks5.sh
#
# 也可以直接使用命令：
#
#   ./socks5.sh install
#   ./socks5.sh uninstall
#   ./socks5.sh status
#   ./socks5.sh restart
#   ./socks5.sh links
#   ./socks5.sh modify
#
# ============================================================


# ============================================================
#                    基础配置
# ============================================================

# systemd 服务名称
SERVICE_NAME="danted"

# Dante 主配置文件
CONFIG_FILE="/etc/danted.conf"

# SOCKS5 参数保存文件
# 用于保存端口、用户名、密码等配置
ENV_FILE="/etc/danted-socks5.env"

# 自定义 systemd 服务文件
SYSTEMD_FILE="/etc/systemd/system/danted.service"


# ============================================================
#                    全局变量
# ============================================================

DANTE_BIN=""

SOCKS_PORT=""
SOCKS_USER=""
SOCKS_PASS=""

# SOCKS5 出口网卡
OUT_IFACE=""

# 本机 IPv4 / IPv6
IPV4_ADDR=""
IPV6_ADDR=""

# 公网 IPv4 / IPv6
PUBLIC_IPV4=""
PUBLIC_IPV6=""

# 包管理器
PKG_MANAGER=""

# 系统 ID
OS=""


# ============================================================
#                    彩色输出
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
#                    输出函数
# ============================================================

# 普通信息
info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

# 成功信息
success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

# 警告信息
warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 错误信息
error() {
    echo -e "${RED}[错误]${NC} $1"
}


# ============================================================
#                    检查 Root
# ============================================================

# SOCKS5、iptables、systemd 等操作都需要 root 权限。
check_root() {

    if [ "$(id -u)" != "0" ]; then

        error "请使用 root 用户运行此脚本。"

        echo
        echo "例如："
        echo "sudo ./socks5.sh"

        exit 1
    fi
}


# ============================================================
#                    检测操作系统
# ============================================================

detect_os() {

    # /etc/os-release 是绝大多数现代 Linux 发行版
    # 用来描述系统信息的标准文件。
    if [ ! -f /etc/os-release ]; then

        error "无法检测系统。"

        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    OS="$ID"

    case "$OS" in

        debian|ubuntu)

            PKG_MANAGER="apt"

            ;;

        centos|rhel|rocky|almalinux)

            # 新版本系统通常使用 dnf。
            if command -v dnf >/dev/null 2>&1; then

                PKG_MANAGER="dnf"

            else

                PKG_MANAGER="yum"

            fi

            ;;

        fedora)

            PKG_MANAGER="dnf"

            ;;

        *)

            error "暂不支持的系统：$OS"

            exit 1

            ;;

    esac

    info "系统：${PRETTY_NAME:-$OS}"
    info "包管理器：$PKG_MANAGER"
}


# ============================================================
#                    随机字符串
# ============================================================

# 用于生成随机用户名和密码。
#
# 参数：
#   $1 = 随机字符串长度
#
# 示例：
#   random_string 16
#
random_string() {

    local LENGTH="$1"

    tr -dc 'A-Za-z0-9' </dev/urandom |
        head -c "$LENGTH"
}


# ============================================================
#                    随机端口
# ============================================================

# 自动生成一个未被 TCP / UDP 占用的端口。
#
# 默认随机范围：
#   10000 - 60000
#
random_port() {

    local PORT

    while true; do

        # RANDOM 最大值约为 32767。
        # 因此使用计算方式生成 10000-60000 范围。
        PORT=$((RANDOM % 50001 + 10000))

        # 检查 TCP 端口是否已经被占用。
        if ss -lnt 2>/dev/null |
            awk '{print $4}' |
            grep -Eq ":${PORT}$"; then

            continue
        fi

        # 检查 UDP 端口是否已经被占用。
        if ss -lnu 2>/dev/null |
            awk '{print $4}' |
            grep -Eq ":${PORT}$"; then

            continue
        fi

        echo "$PORT"

        return
    done
}


# ============================================================
#                    安装系统依赖
# ============================================================

install_dependencies() {

    info "开始安装 Dante 和系统依赖..."

    # --------------------------------------------------------
    # Debian / Ubuntu
    # --------------------------------------------------------

    if [ "$PKG_MANAGER" = "apt" ]; then

        export DEBIAN_FRONTEND=noninteractive

        apt-get update

        apt-get install -y \
            dante-server \
            curl \
            iproute2 \
            iptables \
            iptables-persistent \
            procps \
            ca-certificates


    # --------------------------------------------------------
    # Fedora / Rocky / AlmaLinux / RHEL
    # --------------------------------------------------------

    elif [ "$PKG_MANAGER" = "dnf" ]; then

        dnf install -y \
            dante-server \
            curl \
            iproute \
            iptables \
            procps-ng \
            ca-certificates


    # --------------------------------------------------------
    # 老版本 CentOS / RHEL
    # --------------------------------------------------------

    elif [ "$PKG_MANAGER" = "yum" ]; then

        yum install -y \
            dante-server \
            curl \
            iproute \
            iptables \
            procps \
            ca-certificates

    fi


    # --------------------------------------------------------
    # 检查 Dante 程序
    # --------------------------------------------------------

    if command -v danted >/dev/null 2>&1; then

        DANTE_BIN="$(command -v danted)"

    elif command -v dante-server >/dev/null 2>&1; then

        DANTE_BIN="$(command -v dante-server)"

    else

        error "Dante 安装失败。"

        exit 1

    fi

    success "Dante 程序：$DANTE_BIN"
}


# ============================================================
#                    检测出口网卡
# ============================================================

# Dante 的 external 参数需要指定服务器访问外网时
# 使用的网络接口。
#
# 优先使用：
#   ip route get 1.1.1.1
#
# 如果失败，再使用：
#   ip route
#
detect_interface() {

    info "检测服务器出口网卡..."

    # 根据默认访问路径自动判断网卡。
    OUT_IFACE="$(
        ip route get 1.1.1.1 2>/dev/null |
        awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                }
            }
        }' |
        head -n1
    )"


    # 如果上面的方式失败，
    # 再从默认路由中寻找网卡。
    if [ -z "$OUT_IFACE" ]; then

        OUT_IFACE="$(
            ip route 2>/dev/null |
            awk '$1=="default" {print $5; exit}'
        )"

    fi


    # 如果还是无法检测，则停止安装。
    if [ -z "$OUT_IFACE" ]; then

        error "无法检测出口网卡。"

        echo
        echo "当前路由："

        ip route || true

        exit 1
    fi

    success "出口网卡：$OUT_IFACE"
}


# ============================================================
#                    检测 IPv4
# ============================================================

detect_ipv4() {

    IPV4_ADDR="$(
        ip -4 addr show dev "$OUT_IFACE" 2>/dev/null |
        awk '/inet / {
            print $2
            exit
        }' |
        cut -d/ -f1
    )"


    if [ -n "$IPV4_ADDR" ]; then

        success "检测到 IPv4：$IPV4_ADDR"

    else

        warn "没有检测到 IPv4 地址。"

    fi
}


# ============================================================
#                    检测 IPv6
# ============================================================

detect_ipv6() {

    IPV6_ADDR="$(
        ip -6 addr show dev "$OUT_IFACE" scope global 2>/dev/null |
        awk '/inet6/ {
            print $2
            exit
        }' |
        cut -d/ -f1
    )"


    if [ -n "$IPV6_ADDR" ]; then

        success "检测到 IPv6：$IPV6_ADDR"

    else

        warn "没有检测到公网 IPv6。"

    fi
}


# ============================================================
#                    获取公网 IPv4
# ============================================================

get_public_ipv4() {

    PUBLIC_IPV4=""

    # 优先使用 ipify。
    PUBLIC_IPV4="$(
        curl -4 -s \
            --connect-timeout 5 \
            https://api.ipify.org \
            2>/dev/null || true
    )"


    # 如果失败，使用备用接口。
    if [ -z "$PUBLIC_IPV4" ]; then

        PUBLIC_IPV4="$(
            curl -4 -s \
                --connect-timeout 5 \
                https://ifconfig.me \
                2>/dev/null || true
        )"

    fi
}


# ============================================================
#                    获取公网 IPv6
# ============================================================

get_public_ipv6() {

    PUBLIC_IPV6=""

    PUBLIC_IPV6="$(
        curl -6 -s \
            --connect-timeout 5 \
            https://api6.ipify.org \
            2>/dev/null || true
    )"
}


# ============================================================
#                    输入 SOCKS5 配置
# ============================================================

input_config() {

    echo
    echo "============================================================"
    echo "                    SOCKS5 配置"
    echo "============================================================"
    echo
    echo "直接按回车可以自动生成随机值。"
    echo


    # --------------------------------------------------------
    # SOCKS5 端口
    # --------------------------------------------------------

    while true; do

        read -rp \
            "请输入 SOCKS5 端口 [回车随机]： " \
            SOCKS_PORT


        # 如果没有输入端口，则自动随机。
        if [ -z "$SOCKS_PORT" ]; then

            SOCKS_PORT="$(random_port)"

            success "随机端口：$SOCKS_PORT"

            break
        fi


        # 检查是否为数字。
        if ! [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then

            error "端口必须是数字。"

            continue
        fi


        # 检查端口范围。
        if [ "$SOCKS_PORT" -lt 1 ] ||
            [ "$SOCKS_PORT" -gt 65535 ]; then

            error "端口范围必须是 1-65535。"

            continue
        fi


        # 检查 TCP。
        if ss -lnt 2>/dev/null |
            awk '{print $4}' |
            grep -Eq ":${SOCKS_PORT}$"; then

            error "TCP 端口 $SOCKS_PORT 已被占用。"

            continue
        fi


        # 检查 UDP。
        if ss -lnu 2>/dev/null |
            awk '{print $4}' |
            grep -Eq ":${SOCKS_PORT}$"; then

            error "UDP 端口 $SOCKS_PORT 已被占用。"

            continue
        fi


        break

    done


    # --------------------------------------------------------
    # SOCKS5 用户名
    # --------------------------------------------------------

    while true; do

        read -rp \
            "请输入 SOCKS5 用户名 [回车随机]： " \
            SOCKS_USER


        # 自动生成用户名。
        if [ -z "$SOCKS_USER" ]; then

            SOCKS_USER="socks$(random_string 8)"

            success "随机用户名：$SOCKS_USER"

            break
        fi


        # 用户名只允许常见安全字符。
        if [[ "$SOCKS_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then

            break

        fi


        error "用户名只能包含：字母、数字、点、下划线、横线。"

    done


    # --------------------------------------------------------
    # SOCKS5 密码
    # --------------------------------------------------------

    read -rsp \
        "请输入 SOCKS5 密码 [回车随机]： " \
        SOCKS_PASS

    echo


    # 如果密码为空，则随机生成。
    if [ -z "$SOCKS_PASS" ]; then

        SOCKS_PASS="$(random_string 16)"

        success "随机密码：$SOCKS_PASS"

    fi
}


# ============================================================
#                    创建 SOCKS5 用户
# ============================================================

create_user() {

    info "创建 SOCKS5 认证用户..."


    # 如果用户已经存在，只修改密码。
    if id "$SOCKS_USER" >/dev/null 2>&1; then

        echo "$SOCKS_USER:$SOCKS_PASS" |
            chpasswd

        info "用户已存在，密码已更新。"

    else

        # 创建系统用户。
        #
        # --system：
        #   创建系统用户。
        #
        # --no-create-home：
        #   不创建 Home 目录。
        #
        # --shell /usr/sbin/nologin：
        #   禁止该用户直接登录 SSH。
        useradd \
            --system \
            --no-create-home \
            --shell /usr/sbin/nologin \
            "$SOCKS_USER"


        # 设置用户密码。
        echo "$SOCKS_USER:$SOCKS_PASS" |
            chpasswd

    fi


    success "认证用户：$SOCKS_USER"
}


# ============================================================
#                    保存配置
# ============================================================

# 将 SOCKS5 参数保存到单独文件。
#
# 权限设置为 600：
#   只有 root 可以读取。
#
save_env() {

    cat > "$ENV_FILE" <<EOF
SOCKS_PORT='$SOCKS_PORT'
SOCKS_USER='$SOCKS_USER'
SOCKS_PASS='$SOCKS_PASS'
OUT_IFACE='$OUT_IFACE'
EOF

    chmod 600 "$ENV_FILE"

    success "SOCKS5 参数已保存。"
}


# ============================================================
#                    创建 Dante 配置
# ============================================================

create_config() {

    info "生成 Dante 配置..."


    # 如果原配置存在，先进行备份。
    if [ -f "$CONFIG_FILE" ]; then

        cp "$CONFIG_FILE" \
            "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"

    fi


    # --------------------------------------------------------
    # 写入 Dante 配置
    # --------------------------------------------------------

    cat > "$CONFIG_FILE" <<EOF

# ============================================================
# Dante SOCKS5 Server
# ============================================================
#
# 自动生成的配置文件。
#
# 支持：
#   IPv4
#   IPv6
#   TCP
#   UDP
#
# ============================================================


# ------------------------------------------------------------
# 日志
# ------------------------------------------------------------

logoutput: syslog


# ------------------------------------------------------------
# SOCKS5 监听地址
# ------------------------------------------------------------

# IPv4
internal: 0.0.0.0 port = ${SOCKS_PORT}

# IPv6
internal: :: port = ${SOCKS_PORT}


# ------------------------------------------------------------
# 外网出口网卡
# ------------------------------------------------------------

external: ${OUT_IFACE}


# ------------------------------------------------------------
# SOCKS5 认证方式
# ------------------------------------------------------------

# 使用系统用户名和密码认证。
socksmethod: username

# 客户端连接 Dante 本身不需要认证。
clientmethod: none


# ============================================================
#                    IPv4 客户端规则
# ============================================================

client pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0

    log: connect error
}


# ============================================================
#                    IPv6 客户端规则
# ============================================================

client pass {
    from: ::/0
    to: ::/0

    log: connect error
}


# ============================================================
#                    IPv4 TCP CONNECT
# ============================================================

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0

    command: connect

    socksmethod: username

    log: connect error
}


# ============================================================
#                    IPv4 TCP BIND
# ============================================================

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0

    command: bind

    socksmethod: username

    log: connect error
}


# ============================================================
#                    IPv4 UDP
# ============================================================

socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0

    command: udpassociate

    socksmethod: username

    log: connect error
}


# ============================================================
#                    IPv6 TCP CONNECT
# ============================================================

socks pass {
    from: ::/0
    to: ::/0

    command: connect

    socksmethod: username

    log: connect error
}


# ============================================================
#                    IPv6 TCP BIND
# ============================================================

socks pass {
    from: ::/0
    to: ::/0

    command: bind

    socksmethod: username

    log: connect error
}


# ============================================================
#                    IPv6 UDP
# ============================================================

socks pass {
    from: ::/0
    to: ::/0

    command: udpassociate

    socksmethod: username

    log: connect error
}

EOF


    # 配置文件只允许 root 读取。
    chmod 600 "$CONFIG_FILE"

    success "Dante 配置创建完成。"
}


# ============================================================
#                    创建 systemd 服务
# ============================================================

create_systemd() {

    info "配置 systemd 服务..."


    cat > "$SYSTEMD_FILE" <<EOF

[Unit]
Description=Dante SOCKS5 Proxy Server

# 等待网络准备完成后再启动 Dante。
After=network-online.target
Wants=network-online.target


[Service]

# Dante 前台运行。
Type=simple

# 启动 Dante。
ExecStart=${DANTE_BIN} -f ${CONFIG_FILE}

# 如果异常退出，自动重启。
Restart=on-failure
RestartSec=3

# 提高文件描述符限制，
# 避免高并发连接时出现 fd 不足。
LimitNOFILE=1048576

# 降低服务权限风险。
NoNewPrivileges=true

# 使用独立临时目录。
PrivateTmp=true


[Install]

# 设置为开机自动启动。
WantedBy=multi-user.target

EOF


    # 重新加载 systemd。
    systemctl daemon-reload


    # 设置开机自动启动。
    systemctl enable "$SERVICE_NAME" \
        >/dev/null 2>&1 || true


    success "systemd 配置完成。"
}


# ============================================================
#                    firewalld 防火墙
# ============================================================

configure_firewalld() {

    # 系统没有 firewalld。
    if ! command -v firewall-cmd >/dev/null 2>&1; then

        return 1

    fi


    # firewalld 没有运行。
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then

        return 1

    fi


    info "检测到 firewalld。"


    # 开放 TCP。
    firewall-cmd \
        --permanent \
        --add-port="${SOCKS_PORT}/tcp" \
        >/dev/null


    # 开放 UDP。
    firewall-cmd \
        --permanent \
        --add-port="${SOCKS_PORT}/udp" \
        >/dev/null


    # 重新加载防火墙配置。
    firewall-cmd --reload >/dev/null


    success "firewalld 已开放 TCP/UDP $SOCKS_PORT"

    return 0
}


# ============================================================
#                    UFW 防火墙
# ============================================================

configure_ufw() {

    if ! command -v ufw >/dev/null 2>&1; then

        return 1

    fi


    # 只有 UFW 正在运行才进行配置。
    if ! ufw status 2>/dev/null |
        grep -q "Status: active"; then

        return 1

    fi


    info "检测到 UFW。"


    # TCP
    ufw allow "${SOCKS_PORT}/tcp" >/dev/null

    # UDP
    ufw allow "${SOCKS_PORT}/udp" >/dev/null


    success "UFW 已开放 TCP/UDP $SOCKS_PORT"

    return 0
}


# ============================================================
#                    IPv4 iptables
# ============================================================

configure_iptables() {

    if ! command -v iptables >/dev/null 2>&1; then

        warn "没有检测到 iptables。"

        return 1

    fi


    info "配置 IPv4 防火墙..."


    # --------------------------------------------------------
    # TCP
    # --------------------------------------------------------

    # -C 用于检查规则是否已经存在。
    if ! iptables -C INPUT \
        -p tcp \
        --dport "$SOCKS_PORT" \
        -j ACCEPT 2>/dev/null; then

        iptables -I INPUT \
            -p tcp \
            --dport "$SOCKS_PORT" \
            -j ACCEPT

    fi


    # --------------------------------------------------------
    # UDP
    # --------------------------------------------------------

    if ! iptables -C INPUT \
        -p udp \
        --dport "$SOCKS_PORT" \
        -j ACCEPT 2>/dev/null; then

        iptables -I INPUT \
            -p udp \
            --dport "$SOCKS_PORT" \
            -j ACCEPT

    fi


    success "IPv4 防火墙配置完成。"
}


# ============================================================
#                    IPv6 ip6tables
# ============================================================

configure_ip6tables() {

    if ! command -v ip6tables >/dev/null 2>&1; then

        warn "没有检测到 ip6tables。"

        return 1

    fi


    info "配置 IPv6 防火墙..."


    # IPv6 TCP
    if ! ip6tables -C INPUT \
        -p tcp \
        --dport "$SOCKS_PORT" \
        -j ACCEPT 2>/dev/null; then

        ip6tables -I INPUT \
            -p tcp \
            --dport "$SOCKS_PORT" \
            -j ACCEPT

    fi


    # IPv6 UDP
    if ! ip6tables -C INPUT \
        -p udp \
        --dport "$SOCKS_PORT" \
        -j ACCEPT 2>/dev/null; then

        ip6tables -I INPUT \
            -p udp \
            --dport "$SOCKS_PORT" \
            -j ACCEPT

    fi


    success "IPv6 防火墙配置完成。"
}


# ============================================================
#                    保存防火墙规则
# ============================================================

save_firewall() {

    # Debian / Ubuntu：
    # 如果安装了 netfilter-persistent，
    # 优先使用官方工具保存。
    if command -v netfilter-persistent >/dev/null 2>&1; then

        netfilter-persistent save \
            >/dev/null 2>&1 || true

        return

    fi


    # --------------------------------------------------------
    # 保存 IPv4
    # --------------------------------------------------------

    if command -v iptables-save >/dev/null 2>&1; then

        mkdir -p /etc/iptables

        iptables-save \
            > /etc/iptables/rules.v4 \
            2>/dev/null || true

    fi


    # --------------------------------------------------------
    # 保存 IPv6
    # --------------------------------------------------------

    if command -v ip6tables-save >/dev/null 2>&1; then

        mkdir -p /etc/iptables

        ip6tables-save \
            > /etc/iptables/rules.v6 \
            2>/dev/null || true

    fi
}


# ============================================================
#                    自动配置防火墙
# ============================================================

configure_firewall() {

    info "检测服务器防火墙..."


    # 优先使用 firewalld。
    if configure_firewalld; then

        return

    fi


    # 其次使用 UFW。
    if configure_ufw; then

        return

    fi


    # 最后使用 iptables。
    configure_iptables || true
    configure_ip6tables || true

    save_firewall
}


# ============================================================
#                    删除防火墙端口
# ============================================================

remove_firewall_port() {

    local PORT="$1"


    # 没有端口直接退出。
    [ -z "$PORT" ] && return


    # --------------------------------------------------------
    # firewalld
    # --------------------------------------------------------

    if command -v firewall-cmd >/dev/null 2>&1; then

        if systemctl is-active --quiet firewalld 2>/dev/null; then

            firewall-cmd \
                --permanent \
                --remove-port="${PORT}/tcp" \
                >/dev/null 2>&1 || true

            firewall-cmd \
                --permanent \
                --remove-port="${PORT}/udp" \
                >/dev/null 2>&1 || true

            firewall-cmd --reload \
                >/dev/null 2>&1 || true

        fi

    fi


    # --------------------------------------------------------
    # UFW
    # --------------------------------------------------------

    if command -v ufw >/dev/null 2>&1; then

        if ufw status 2>/dev/null |
            grep -q "Status: active"; then

            ufw delete allow "${PORT}/tcp" \
                >/dev/null 2>&1 || true

            ufw delete allow "${PORT}/udp" \
                >/dev/null 2>&1 || true

        fi

    fi


    # --------------------------------------------------------
    # IPv4 iptables
    # --------------------------------------------------------

    if command -v iptables >/dev/null 2>&1; then

        while iptables -C INPUT \
            -p tcp \
            --dport "$PORT" \
            -j ACCEPT 2>/dev/null; do

            iptables -D INPUT \
                -p tcp \
                --dport "$PORT" \
                -j ACCEPT

        done


        while iptables -C INPUT \
            -p udp \
            --dport "$PORT" \
            -j ACCEPT 2>/dev/null; do

            iptables -D INPUT \
                -p udp \
                --dport "$PORT" \
                -j ACCEPT

        done

    fi


    # --------------------------------------------------------
    # IPv6 ip6tables
    # --------------------------------------------------------

    if command -v ip6tables >/dev/null 2>&1; then

        while ip6tables -C INPUT \
            -p tcp \
            --dport "$PORT" \
            -j ACCEPT 2>/dev/null; do

            ip6tables -D INPUT \
                -p tcp \
                --dport "$PORT" \
                -j ACCEPT

        done


        while ip6tables -C INPUT \
            -p udp \
            --dport "$PORT" \
            -j ACCEPT 2>/dev/null; do

            ip6tables -D INPUT \
                -p udp \
                --dport "$PORT" \
                -j ACCEPT

        done

    fi


    save_firewall
}


# ============================================================
#                    启动 SOCKS5
# ============================================================

start_service() {

    info "启动 Dante SOCKS5..."


    # 重启服务。
    systemctl restart "$SERVICE_NAME"


    # 给服务一点启动时间。
    sleep 2


    # 检查运行状态。
    if systemctl is-active --quiet "$SERVICE_NAME"; then

        success "Dante SOCKS5 启动成功。"

    else

        error "Dante SOCKS5 启动失败。"


        echo
        echo "---------------- 服务状态 ----------------"

        systemctl status \
            "$SERVICE_NAME" \
            --no-pager \
            -l || true


        echo
        echo "---------------- 最近日志 ----------------"

        journalctl \
            -u "$SERVICE_NAME" \
            -n 50 \
            --no-pager || true


        exit 1
    fi
}


# ============================================================
#                    检查监听端口
# ============================================================

check_listener() {

    echo
    info "检查 SOCKS5 监听："
    echo


    # 查看 Dante 是否监听 TCP / UDP。
    ss -lntup 2>/dev/null |
        grep -E "danted|:${SOCKS_PORT}" ||
        true
}


# ============================================================
#                    生成 SOCKS5 URI
# ============================================================

# 根据 IP 类型自动生成：
#
# IPv4：
# socks5://user:password@1.2.3.4:1080
#
# IPv6：
# socks5://user:password@[2001:db8::1]:1080
#
generate_uri() {

    local HOST="$1"


    # IPv6 地址必须使用 [] 包起来。
    if [[ "$HOST" == *:* ]]; then

        echo \
            "socks5://${SOCKS_USER}:${SOCKS_PASS}@[${HOST}]:${SOCKS_PORT}"

    else

        echo \
            "socks5://${SOCKS_USER}:${SOCKS_PASS}@${HOST}:${SOCKS_PORT}"

    fi
}


# ============================================================
#                    Base64 编码
# ============================================================

generate_base64() {

    local URI="$1"


    # GNU coreutils 的 base64 支持 -w 0。
    #
    # 某些系统没有 -w 参数，
    # 所以这里提供备用方案。
    printf '%s' "$URI" |
        base64 -w 0 2>/dev/null ||
        printf '%s' "$URI" |
        base64
}


# ============================================================
#                    读取已有配置
# ============================================================

load_config() {

    if [ ! -f "$ENV_FILE" ]; then

        return 1

    fi


    # shellcheck disable=SC1090
    source "$ENV_FILE"

    return 0
}


# ============================================================
#                    显示 v2rayN 链接
# ============================================================

show_v2rayn_links() {

    # 读取已经保存的配置。
    if ! load_config; then

        error "没有检测到 SOCKS5 配置。"

        echo "请先安装 SOCKS5。"

        return
    fi


    # 获取公网 IP。
    get_public_ipv4
    get_public_ipv6


    echo
    echo "============================================================"
    echo "                 v2rayN SOCKS5 导入信息"
    echo "============================================================"
    echo


    echo "协议：SOCKS5"
    echo "端口：$SOCKS_PORT"
    echo "用户名：$SOCKS_USER"
    echo "密码：$SOCKS_PASS"

    echo


    # --------------------------------------------------------
    # IPv4
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV4" ]; then

        IPV4_URI="$(generate_uri "$PUBLIC_IPV4")"


        echo "------------------------------------------------------------"
        echo "IPv4 SOCKS5"
        echo "------------------------------------------------------------"

        echo
        echo "$IPV4_URI"

        echo
        echo "Base64："

        generate_base64 "$IPV4_URI"

        echo
        echo

    fi


    # --------------------------------------------------------
    # IPv6
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV6" ]; then

        IPV6_URI="$(generate_uri "$PUBLIC_IPV6")"


        echo "------------------------------------------------------------"
        echo "IPv6 SOCKS5"
        echo "------------------------------------------------------------"

        echo
        echo "$IPV6_URI"

        echo
        echo "Base64："

        generate_base64 "$IPV6_URI"

        echo
        echo

    fi


    echo "============================================================"
    echo
    echo "v2rayN 使用方法："
    echo
    echo "1. 复制 socks5:// 开头的链接。"
    echo "2. 在 v2rayN 中使用剪贴板导入。"
    echo
    echo "============================================================"
}


# ============================================================
#                    修改 SOCKS5 配置
# ============================================================

modify_config() {

    check_root


    # 必须存在旧配置。
    if ! load_config; then

        error "没有检测到 SOCKS5 配置。"

        echo "请先安装 SOCKS5。"

        return
    fi


    # 保存旧端口和旧用户名，
    # 用于后续清理旧配置。
    local OLD_PORT="$SOCKS_PORT"
    local OLD_USER="$SOCKS_USER"


    echo
    echo "============================================================"
    echo "                   修改 SOCKS5 配置"
    echo "============================================================"
    echo

    echo "当前端口：$SOCKS_PORT"
    echo "当前用户名：$SOCKS_USER"

    echo


    # --------------------------------------------------------
    # 修改端口
    # --------------------------------------------------------

    while true; do

        read -rp \
            "新端口 [回车保持 ${SOCKS_PORT}]： " \
            NEW_PORT


        # 空输入保持原端口。
        NEW_PORT="${NEW_PORT:-$SOCKS_PORT}"


        # 必须是数字。
        if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then

            error "端口必须是数字。"

            continue
        fi


        # 检查范围。
        if [ "$NEW_PORT" -lt 1 ] ||
            [ "$NEW_PORT" -gt 65535 ]; then

            error "端口必须是 1-65535。"

            continue
        fi


        # 如果端口没有改变，
        # 则无需检查占用情况。
        if [ "$NEW_PORT" != "$OLD_PORT" ]; then


            # TCP
            if ss -lnt 2>/dev/null |
                awk '{print $4}' |
                grep -Eq ":${NEW_PORT}$"; then

                error "TCP $NEW_PORT 已被占用。"

                continue
            fi


            # UDP
            if ss -lnu 2>/dev/null |
                awk '{print $4}' |
                grep -Eq ":${NEW_PORT}$"; then

                error "UDP $NEW_PORT 已被占用。"

                continue
            fi

        fi


        SOCKS_PORT="$NEW_PORT"

        break

    done


    # --------------------------------------------------------
    # 修改用户名
    # --------------------------------------------------------

    while true; do

        read -rp \
            "新用户名 [回车保持 ${SOCKS_USER}]： " \
            NEW_USER


        NEW_USER="${NEW_USER:-$SOCKS_USER}"


        if [[ "$NEW_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then

            SOCKS_USER="$NEW_USER"

            break

        fi


        error "用户名只能包含字母、数字、点、下划线和横线。"

    done


    # --------------------------------------------------------
    # 修改密码
    # --------------------------------------------------------

    read -rsp \
        "新密码 [回车保持原密码]： " \
        NEW_PASS

    echo


    # 输入新密码才修改。
    if [ -n "$NEW_PASS" ]; then

        SOCKS_PASS="$NEW_PASS"

    fi


    # --------------------------------------------------------
    # 应用新配置
    # --------------------------------------------------------

    create_user

    save_env

    create_config


    # 如果端口改变，
    # 删除旧端口的防火墙规则。
    if [ "$OLD_PORT" != "$SOCKS_PORT" ]; then

        info "删除旧端口防火墙规则..."

        remove_firewall_port "$OLD_PORT"

    fi


    # 添加新端口规则。
    configure_firewall


    # 重启 Dante。
    start_service


    echo
    success "SOCKS5 配置修改完成。"


    # 显示新的 v2rayN 链接。
    show_v2rayn_links
}


# ============================================================
#                    安装 SOCKS5
# ============================================================

install_socks5() {

    # 必须 root。
    check_root


    # 检测系统。
    detect_os


    # 自动安装依赖。
    install_dependencies


    # 检测出口网卡。
    detect_interface


    # 检测本地 IP。
    detect_ipv4
    detect_ipv6


    # 输入端口、用户名、密码。
    input_config


    # 创建认证用户。
    create_user


    # 保存配置。
    save_env


    # 创建 Dante 配置。
    create_config


    # 创建 systemd 服务。
    create_systemd


    # 配置防火墙。
    configure_firewall


    # 启动 Dante。
    start_service


    # 检查监听状态。
    check_listener


    # 显示最终结果。
    show_result
}


# ============================================================
#                    卸载 SOCKS5
# ============================================================

uninstall_socks5() {

    check_root

    detect_os


    # 尝试读取现有配置。
    load_config || true


    echo
    echo "============================================================"
    echo "                  卸载 Dante SOCKS5"
    echo "============================================================"
    echo


    if [ -n "$SOCKS_PORT" ]; then

        echo "当前端口：$SOCKS_PORT"

    fi


    if [ -n "$SOCKS_USER" ]; then

        echo "当前用户：$SOCKS_USER"

    fi


    echo


    # 防止误操作。
    read -rp \
        "确认卸载？请输入 YES： " \
        CONFIRM


    if [ "$CONFIRM" != "YES" ]; then

        echo "已取消。"

        return
    fi


    # --------------------------------------------------------
    # 停止服务
    # --------------------------------------------------------

    info "停止 Dante..."

    systemctl stop "$SERVICE_NAME" \
        >/dev/null 2>&1 || true


    # --------------------------------------------------------
    # 禁止开机启动
    # --------------------------------------------------------

    systemctl disable "$SERVICE_NAME" \
        >/dev/null 2>&1 || true


    # --------------------------------------------------------
    # 删除防火墙规则
    # --------------------------------------------------------

    if [ -n "$SOCKS_PORT" ]; then

        info "删除防火墙规则..."

        remove_firewall_port "$SOCKS_PORT"

    fi


    # --------------------------------------------------------
    # 删除 systemd 服务
    # --------------------------------------------------------

    rm -f "$SYSTEMD_FILE"

    systemctl daemon-reload


    # --------------------------------------------------------
    # 卸载 Dante
    # --------------------------------------------------------

    info "卸载 Dante..."


    if [ "$PKG_MANAGER" = "apt" ]; then

        apt-get remove -y dante-server \
            >/dev/null 2>&1 || true


    elif [ "$PKG_MANAGER" = "dnf" ]; then

        dnf remove -y dante-server \
            >/dev/null 2>&1 || true


    elif [ "$PKG_MANAGER" = "yum" ]; then

        yum remove -y dante-server \
            >/dev/null 2>&1 || true

    fi


    # --------------------------------------------------------
    # 删除 SOCKS5 用户
    # --------------------------------------------------------

    if [ -n "$SOCKS_USER" ]; then

        if id "$SOCKS_USER" >/dev/null 2>&1; then

            userdel "$SOCKS_USER" \
                >/dev/null 2>&1 || true

        fi

    fi


    # --------------------------------------------------------
    # 删除配置
    # --------------------------------------------------------

    rm -f "$CONFIG_FILE"
    rm -f "$ENV_FILE"


    success "Dante SOCKS5 已卸载。"
}


# ============================================================
#                    查看状态
# ============================================================

show_status() {

    check_root


    echo
    echo "============================================================"
    echo "                   Dante SOCKS5 状态"
    echo "============================================================"
    echo


    # 服务状态。
    if systemctl is-active --quiet "$SERVICE_NAME"; then

        success "Dante 正在运行。"

    else

        error "Dante 未运行。"

    fi


    echo


    # systemd 状态。
    systemctl status \
        "$SERVICE_NAME" \
        --no-pager \
        -l || true


    echo
    echo "============================================================"
    echo "监听端口"
    echo "============================================================"
    echo


    # 读取当前配置中的端口。
    load_config || true


    # 查看监听情况。
    ss -lntup 2>/dev/null |
        grep -E "danted|:${SOCKS_PORT}" ||
        true


    echo
}


# ============================================================
#                    重启 SOCKS5
# ============================================================

restart_socks5() {

    check_root


    # 检查服务是否存在。
    if ! systemctl list-unit-files |
        grep -q "^${SERVICE_NAME}.service"; then

        error "Dante 尚未安装。"

        return
    fi


    info "重启 Dante..."


    systemctl restart "$SERVICE_NAME"

    sleep 2


    if systemctl is-active --quiet "$SERVICE_NAME"; then

        success "Dante 重启成功。"

    else

        error "Dante 重启失败。"


        journalctl \
            -u "$SERVICE_NAME" \
            -n 50 \
            --no-pager ||
            true

        return 1

    fi
}


# ============================================================
#                    显示安装结果
# ============================================================

show_result() {

    # 获取公网 IP。
    get_public_ipv4
    get_public_ipv6


    echo
    echo "============================================================"
    echo -e "${GREEN}                 SOCKS5 安装完成${NC}"
    echo "============================================================"
    echo


    echo "协议       : SOCKS5"
    echo "端口       : $SOCKS_PORT"
    echo "用户名     : $SOCKS_USER"
    echo "密码       : $SOCKS_PASS"
    echo "出口网卡   : $OUT_IFACE"


    echo


    # IPv4
    if [ -n "$PUBLIC_IPV4" ]; then

        echo "IPv4       : $PUBLIC_IPV4"

    else

        echo "IPv4       : 未获取"

    fi


    # IPv6
    if [ -n "$PUBLIC_IPV6" ]; then

        echo "IPv6       : $PUBLIC_IPV6"

    else

        echo "IPv6       : 未检测到公网 IPv6"

    fi


    echo


    echo "TCP        : 支持"
    echo "UDP        : 支持"
    echo "IPv4       : 支持"
    echo "IPv6       : 支持"


    echo


    echo "配置文件   : $CONFIG_FILE"
    echo "认证信息   : $ENV_FILE"


    echo
    echo "============================================================"
    echo "                v2rayN 导入链接"
    echo "============================================================"
    echo


    # --------------------------------------------------------
    # IPv4 SOCKS5 URI
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV4" ]; then

        IPV4_URI="$(generate_uri "$PUBLIC_IPV4")"

        echo "IPv4："
        echo "$IPV4_URI"

        echo

    fi


    # --------------------------------------------------------
    # IPv6 SOCKS5 URI
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV6" ]; then

        IPV6_URI="$(generate_uri "$PUBLIC_IPV6")"

        echo "IPv6："
        echo "$IPV6_URI"

        echo

    fi


    echo "============================================================"
    echo "                 Base64 导入内容"
    echo "============================================================"
    echo


    # --------------------------------------------------------
    # IPv4 Base64
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV4" ]; then

        echo "IPv4 Base64："

        generate_base64 "$IPV4_URI"

        echo
        echo

    fi


    # --------------------------------------------------------
    # IPv6 Base64
    # --------------------------------------------------------

    if [ -n "$PUBLIC_IPV6" ]; then

        echo "IPv6 Base64："

        generate_base64 "$IPV6_URI"

        echo
        echo

    fi


    echo "============================================================"
    echo "                 常用管理命令"
    echo "============================================================"
    echo


    echo "查看状态："
    echo "./socks5.sh status"
    echo


    echo "重启："
    echo "./socks5.sh restart"
    echo


    echo "查看 v2rayN 链接："
    echo "./socks5.sh links"
    echo


    echo "修改配置："
    echo "./socks5.sh modify"
    echo


    echo "卸载："
    echo "./socks5.sh uninstall"
    echo


    echo "============================================================"
}


# ============================================================
#                    主菜单
# ============================================================

menu() {

    clear


    echo "============================================================"
    echo "              Dante SOCKS5 IPv4 / IPv6"
    echo "============================================================"
    echo

    echo "  1. 安装 SOCKS5"
    echo "  2. 卸载 SOCKS5"
    echo "  3. 查看状态"
    echo "  4. 重启 SOCKS5"
    echo "  5. 查看链接"
    echo "  6. 修改配置"
    echo "  0. 退出"

    echo

    echo "============================================================"


    read -rp "请选择 [0-6]： " CHOICE


    case "$CHOICE" in

        1)

            install_socks5

            ;;


        2)

            uninstall_socks5

            ;;


        3)

            show_status

            ;;


        4)

            restart_socks5

            ;;


        5)

            show_v2rayn_links

            ;;


        6)

            modify_config

            ;;


        0)

            exit 0

            ;;


        *)

            error "无效选择。"

            ;;

    esac
}


# ============================================================
#                    命令行参数
# ============================================================

# 支持直接通过参数操作，
# 方便以后放进自动化脚本或者服务器管理工具。

case "${1:-}" in

    install)

        install_socks5

        ;;


    uninstall)

        uninstall_socks5

        ;;


    status)

        show_status

        ;;


    restart)

        restart_socks5

        ;;


    links)

        show_v2rayn_links

        ;;


    modify)

        modify_config

        ;;


    *)

        # 没有参数时进入交互式菜单。
        menu

        ;;

esac
```
