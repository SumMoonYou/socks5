# Dante SOCKS5 一键安装管理脚本

一个基于 **Dante** 的 SOCKS5 服务器一键安装与管理脚本。

支持 **IPv4 / IPv6、TCP / UDP、用户名密码认证、防火墙自动配置、systemd 开机启动以及 v2rayN 导入链接生成**。

适合 Debian、Ubuntu、CentOS、Rocky Linux、AlmaLinux、RHEL、Fedora 等常见 Linux 服务器使用。

---

## ✨ 功能特性

* 🚀 一键安装 Dante SOCKS5
* 🗑️ 一键卸载 SOCKS5
* 🔄 一键重启 SOCKS5
* 📊 查看 SOCKS5 服务状态
* ⚙️ 在线修改 SOCKS5 配置
* 🔐 用户名 + 密码认证
* 🎲 端口支持随机生成
* 🎲 用户名支持随机生成
* 🎲 密码支持随机生成
* 🌐 IPv4 支持
* 🌐 IPv6 支持
* 🚀 TCP 支持
* 🚀 UDP 支持
* 🔥 自动配置防火墙
* 🔥 支持 firewalld
* 🔥 支持 UFW
* 🔥 支持 iptables / ip6tables
* ⚡ systemd 管理
* 🔌 开机自动启动
* 📋 自动生成 `socks5://` 连接链接
* 📱 支持 v2rayN 导入
* 🔑 自动生成 Base64 内容
* 🖥️ 自动检测服务器出口网卡
* 🌍 自动获取公网 IPv4 / IPv6
* 📝 配置文件自动备份

---

## 📦 支持系统

目前支持以下 Linux 发行版：

| 系统          | 包管理器      |
| ----------- | --------- |
| Debian      | APT       |
| Ubuntu      | APT       |
| CentOS      | YUM / DNF |
| RHEL        | YUM / DNF |
| Rocky Linux | DNF       |
| AlmaLinux   | DNF       |
| Fedora      | DNF       |

> 建议使用较新的 Debian / Ubuntu / Rocky Linux / AlmaLinux 等系统。

---

## 🚀 快速开始

### 1. 下载脚本

```bash
wget -O socks5.sh https://raw.githubusercontent.com/SumMoonYou/socks5/main/socks5.sh
```

或者：

```bash
curl -o socks5.sh https://raw.githubusercontent.com/SumMoonYou/socks5/main/socks5.sh
```

### 2. 添加执行权限

```bash
chmod +x socks5.sh
```

### 3. 运行脚本

```bash
sudo ./socks5.sh
```

运行后会进入交互式管理菜单。

---

# 📋 菜单

启动脚本后：

```text
============================================================
              Dante SOCKS5 IPv4 / IPv6
============================================================

  1. 安装 SOCKS5
  2. 卸载 SOCKS5
  3. 查看状态
  4. 重启 SOCKS5
  5. 查看 v2rayN 导入链接
  6. 修改 SOCKS5 配置
  0. 退出

============================================================
请选择 [0-6]：
```

---

# 🔧 安装 SOCKS5

选择：

```text
1. 安装 SOCKS5
```

脚本会自动完成：

1. 检测 Linux 系统
2. 检测包管理器
3. 安装 Dante
4. 安装网络工具
5. 安装 iptables 等依赖
6. 自动检测出口网卡
7. 检测 IPv4
8. 检测 IPv6
9. 设置 SOCKS5 端口
10. 创建认证用户
11. 创建 Dante 配置
12. 创建 systemd 服务
13. 配置防火墙
14. 启动 Dante
15. 检查 SOCKS5 监听
16. 生成 v2rayN 导入信息

---

# 🔐 SOCKS5 配置

安装过程中会要求输入：

```text
请输入 SOCKS5 端口 [回车随机]：
请输入 SOCKS5 用户名 [回车随机]：
请输入 SOCKS5 密码 [回车随机]：
```

### 手动设置

例如：

```text
端口：2080
用户名：myproxy
密码：123456789
```

### 自动随机

如果直接按回车：

```text
端口：随机生成
用户名：随机生成
密码：随机生成
```

随机密码默认生成 16 位字母数字组合。

---

# 🌐 IPv4 / IPv6

脚本会自动检测服务器网络环境。

例如：

```text
IPv4       : 1.2.3.4
IPv6       : 2001:db8::1234
```

如果服务器没有 IPv6：

```text
IPv6       : 未检测到公网 IPv6
```

不会影响 IPv4 SOCKS5 的正常使用。

---

# 🚀 TCP / UDP

Dante 配置同时支持：

```text
TCP
UDP
```

IPv4 和 IPv6 均进行相应配置。

因此可以用于支持 SOCKS5 UDP 的客户端。

---

# 🔥 防火墙

脚本会自动检测服务器使用的防火墙。

支持：

### firewalld

自动开放：

```text
TCP SOCKS5端口
UDP SOCKS5端口
```

### UFW

自动添加：

```text
PORT/tcp
PORT/udp
```

### iptables

自动添加 IPv4：

```text
INPUT TCP PORT ACCEPT
INPUT UDP PORT ACCEPT
```

### ip6tables

自动添加 IPv6：

```text
INPUT TCP PORT ACCEPT
INPUT UDP PORT ACCEPT
```

---

# 📱 v2rayN

安装完成后会自动生成 SOCKS5 URI。

例如：

```text
socks5://username:password@1.2.3.4:2080
```

IPv6 会自动使用标准的 `[]` 格式：

```text
socks5://username:password@[2001:db8::1234]:2080
```

可以复制 `socks5://` 链接，然后在支持该 URI 格式的客户端中导入。

---

# 🔑 Base64

脚本同时提供 Base64 编码结果。

例如：

```text
IPv4 Base64：

c29ja3M1Oi8vdXNlcm5hbWU6cGFzc3dvcmRAMS4yLjMuNDoyMDgw
```

可以复制 Base64 内容用于客户端导入场景。

> 注意：这里的 Base64 是对单个 SOCKS5 URI 进行编码，并不是完整的多节点订阅格式。

---

# 🛠️ 命令行管理

除了交互式菜单，还支持直接使用命令。

## 安装

```bash
./socks5.sh install
```

## 卸载

```bash
./socks5.sh uninstall
```

## 查看状态

```bash
./socks5.sh status
```

## 重启

```bash
./socks5.sh restart
```

## 查看 v2rayN 链接

```bash
./socks5.sh links
```

## 修改配置

```bash
./socks5.sh modify
```

---

# 📂 配置文件

脚本主要使用以下文件：

### Dante 配置

```text
/etc/danted.conf
```

### SOCKS5 参数

```text
/etc/danted-socks5.env
```

该文件包含：

```text
SOCKS_PORT
SOCKS_USER
SOCKS_PASS
OUT_IFACE
```

权限默认为：

```text
600
```

只有 root 用户可以读取。

### systemd

```text
/etc/systemd/system/danted.service
```

---

# 📊 查看服务状态

可以使用：

```bash
./socks5.sh status
```

也可以直接：

```bash
systemctl status danted
```

查看日志：

```bash
journalctl -u danted -n 50 --no-pager
```

实时查看日志：

```bash
journalctl -u danted -f
```

---

# 🔄 修改配置

执行：

```bash
./socks5.sh modify
```

可以修改：

```text
端口
用户名
密码
```

直接按回车可以保持原来的配置。

修改完成后脚本会自动：

```text
更新用户
↓
更新 Dante 配置
↓
更新防火墙
↓
重启 Dante
↓
生成新的 SOCKS5 链接
```

---

# 🗑️ 卸载

执行：

```bash
./socks5.sh uninstall
```

脚本会删除：

* Dante 服务
* systemd 配置
* SOCKS5 用户
* Dante 配置
* SOCKS5 参数
* 对应防火墙端口规则

卸载前需要输入：

```text
YES
```

防止误操作。

---

# 🧩 文件结构

推荐仓库结构：

```text
.
├── socks5.sh
├── README.md
└── LICENSE
```

其中：

```text
socks5.sh
```

为主要安装管理脚本。

---

# ⚠️ 注意事项

### 1. 必须使用 root

脚本需要操作：

* systemd
* iptables
* 用户
* 网络配置
* 系统软件包

因此需要 root 权限。

例如：

```bash
sudo ./socks5.sh
```

---

### 2. 云服务器安全组

除了 Linux 本机防火墙，还需要检查云服务器的安全组。

例如 SOCKS5 使用：

```text
2080
```

则需要在云服务器控制台放行：

```text
TCP 2080
UDP 2080
```

否则即使 iptables 已经放行，外部仍然可能无法连接。

---

### 3. IPv6

服务器必须拥有可用的公网 IPv6 地址。

如果服务器没有公网 IPv6，脚本不会强制创建 IPv6 节点。

---

### 4. SOCKS5 安全

该脚本使用：

```text
用户名 + 密码
```

进行认证。

不要使用过于简单的密码。

不建议：

```text
123456
password
admin
12345678
```

建议使用随机生成的高强度密码。

---

### 5. 不建议开放匿名 SOCKS5

不要随意配置：

```text
无需认证
```

的公网 SOCKS5。

否则服务器可能成为开放代理，被第三方滥用。

---

# 🔍 常见问题

## Dante 启动失败

首先查看：

```bash
systemctl status danted --no-pager -l
```

然后查看日志：

```bash
journalctl -u danted -n 100 --no-pager
```

也可以检查配置文件：

```bash
cat /etc/danted.conf
```

---

## 端口无法连接

依次检查：

```bash
systemctl status danted
```

然后：

```bash
ss -lntup | grep 端口
```

再检查防火墙：

```bash
iptables -L INPUT -n
```

IPv6：

```bash
ip6tables -L INPUT -n
```

最后检查云服务器安全组。

---

## 修改端口后无法连接

执行：

```bash
./socks5.sh status
```

确认 Dante 是否正常运行。

然后：

```bash
./socks5.sh links
```

获取最新的 SOCKS5 链接。

---

# 📝 技术说明

本项目使用：

```text
Dante
systemd
iptables / ip6tables
firewalld / UFW
```

构建标准 SOCKS5 代理服务。

脚本本身不包含 Xray、sing-box 等代理核心。

---

# 📜 License

本项目采用 MIT License。

你可以自由使用、修改和分发本项目。

使用本项目造成的任何问题，请自行承担相关责任。

---

# ⭐ Star

如果这个项目对你有帮助，可以给项目点一个 ⭐ Star。

欢迎提交：

* Issue
* Pull Request
* 功能建议
* Bug 修复

```

这个 README 可以直接作为仓库首页说明。正式上传时，把里面的 `你的用户名/你的仓库` 替换成实际 GitHub 仓库地址即可。
```
