#!/bin/bash
#
# Copyright (c) 2019-2025 SmallProgram <https://github.com/smallprogram>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/smallprogram/OpenWrtAction
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
# Modified by ametliu003 for custom build

# Add patches
if [ "$GITHUB_ACTIONS" = "true" ] && [ -n "$GITHUB_RUN_ID" ] && [ -n "$GITHUB_WORKFLOW" ]; then
    PATCHES_SRC_DIR="$GITHUB_WORKSPACE"
else
    PATCHES_SRC_DIR="../OpenWrtAction"
fi


# rm appfilter
rm -rf ./feeds/packages/net/open-app-filter

# Disable shadowsocksr-libev (mbedtls 3.x incompatible)
rm -rf ./feeds/passwall_packages/shadowsocksr-libev 2>/dev/null
sed -i 's/CONFIG_PACKAGE_shadowsocksr_libev=y/# CONFIG_PACKAGE_shadowsocksr_libev is not set/g' .config 2>/dev/null
sed -i '/CONFIG_PACKAGE_shadowsocksr_libev/d' .config 2>/dev/null

# =============================================
# NOT modifying default IP — keep 192.168.1.1
# =============================================

# inject download package
mkdir -p dl
cp -r $PATCHES_SRC_DIR/library/* ./dl/


# =============================================
# Modify SSH Configuration (Dropbear -> 2222, OpenSSH -> 22)
# =============================================
mkdir -p files/etc/uci-defaults

cat << 'SSHEOF' > files/etc/uci-defaults/99-custom-ssh-config
#!/bin/sh
/etc/init.d/dropbear stop
/etc/init.d/sshd stop 2>/dev/null
uci set dropbear.@dropbear[0].Port='2222'
uci commit dropbear
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    sed -i 's/^#*Port.*/Port 22/' "$SSHD_CONFIG"
fi
/etc/init.d/dropbear start
/etc/init.d/sshd enable
/etc/init.d/sshd start
exit 0
SSHEOF
chmod +x files/etc/uci-defaults/99-custom-ssh-config


# =============================================
# Set Hostname to "Kevin Network"
# =============================================
sed -i "s/hostname='.*'/hostname='Kevin Network'/g" package/base-files/files/bin/config_generate


# =============================================
# Disable IPv6
# =============================================
# Remove IPv6 from LAN interface
sed -i "/option ip6assign/d" package/base-files/files/bin/config_generate 2>/dev/null

# Create uci-defaults to disable IPv6 on first boot
cat << 'IPV6EOF' > files/etc/uci-defaults/90-disable-ipv6
#!/bin/sh
# Disable IPv6 on all interfaces
uci set network.lan.ip6assign=''
uci del network.lan.ip6assign 2>/dev/null
uci set network.wan6=interface
uci set network.wan6.proto='none'
uci set network.wan6.device='@wan'
uci commit network

# Disable DHCPv6 on LAN
uci set dhcp.lan.dhcpv6=''
uci del dhcp.lan.dhcpv6 2>/dev/null
uci set dhcp.lan ra=''
uci del dhcp.lan ra 2>/dev/null
uci set dhcp.lan.ndp=''
uci del dhcp.lan ndp 2>/dev/null
uci commit dhcp

# Disable IPv6 in firewall
uci set network.globals.ipv6=0
uci commit network

exit 0
IPV6EOF
chmod +x files/etc/uci-defaults/90-disable-ipv6


# =============================================
# Dual WAN PPPoE + mwan3 Pre-Configuration
# =============================================
cat << 'WANEOF' > files/etc/uci-defaults/10-network-config
#!/bin/sh

# --- Configure WAN (eth1) - PPPoE ---
uci set network.wan=interface
uci set network.wan.proto='pppoe'
uci set network.wan.username='86430887'
uci set network.wan.password='86430887'
uci set network.wan.device='eth1'
uci set network.wan.metric='10'
uci set network.wan.keepalive='5 3'

# --- Configure WAN2 (eth2) - PPPoE ---
uci set network.wan2=interface
uci set network.wan2.proto='pppoe'
uci set network.wan2.username='02202551341'
uci set network.wan2.password='879189'
uci set network.wan2.device='eth2'
uci set network.wan2.metric='20'
uci set network.wan2.keepalive='5 3'

# --- Remove default WAN6 ---
uci delete network.wan6 2>/dev/null

# --- Configure Firewall zones ---
uci set firewall.@zone[1].name='wan'
uci set firewall.@zone[1].network='wan wan2'
uci set firewall.@zone[1].input='REJECT'
uci set firewall.@zone[1].output='ACCEPT'
uci set firewall.@zone[1].forward='REJECT'

# --- Configure firewall WAN forwarding ---
uci set firewall.@forwarding[0].src='lan'
uci set firewall.@forwarding[0].dest='wan'

uci commit network
uci commit firewall

# --- Configure mwan3 ---
# WAN interface
uci set mwan3.wan=interface
uci set mwan3.wan.enabled='1'
uci set mwan3.wan.family='ipv4'
uci add_list mwan3.wan.track_ip='114.114.114.114'
uci add_list mwan3.wan.track_ip='223.5.5.5'
uci add_list mwan3.wan.track_ip='119.29.29.29'
uci set mwan3.wan.reliability='2'
uci set mwan3.wan.count='1'
uci set mwan3.wan.timeout='2'
uci set mwan3.wan.interval='5'
uci set mwan3.wan.down='3'
uci set mwan3.wan.up='3'

# WAN2 interface
uci set mwan3.wan2=interface
uci set mwan3.wan2.enabled='1'
uci set mwan3.wan2.family='ipv4'
uci add_list mwan3.wan2.track_ip='114.114.114.114'
uci add_list mwan3.wan2.track_ip='223.5.5.5'
uci add_list mwan3.wan2.track_ip='119.29.29.29'
uci set mwan3.wan2.reliability='2'
uci set mwan3.wan2.count='1'
uci set mwan3.wan2.timeout='2'
uci set mwan3.wan2.interval='5'
uci set mwan3.wan2.down='3'
uci set mwan3.wan2.up='3'

# mwan3 member (balanced 1:1)
uci set mwan3.balanced=member
uci set mwan3.balanced.interface='wan'
uci set mwan3.balanced.metric='1'
uci set mwan3.balanced.weight='1'

uci set mwan3.balanced2=member
uci set mwan3.balanced2.interface='wan2'
uci set mwan3.balanced2.metric='1'
uci set mwan3.balanced2.weight='1'

# mwan3 policy (balanced 1:1)
uci set mwan3.balanced_policy=policy
uci set mwan3.balanced_policy.use_member[0]='balanced'
uci set mwan3.balanced_policy.use_member[1]='balanced2'
uci set mwan3.balanced_policy.last_resort='unreachable'

# mwan3 rule (default balanced)
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.src='0.0.0.0/0'
uci set mwan3.default_rule.dest='0.0.0.0/0'
uci set mwan3.default_rule.proto='all'
uci set mwan3.default_rule.sticky='0'
uci set mwan3.default_rule.use_policy='balanced_policy'

# Enable mwan3 service
uci set mwan3.globals.enabled='1'

uci commit mwan3

# Start mwan3
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart

exit 0
WANEOF
chmod +x files/etc/uci-defaults/10-network-config


# =============================================
# Static DHCP Leases (13 devices)
# =============================================
cat << 'DHCPEOF' > files/etc/uci-defaults/20-static-dhcp
#!/bin/sh

# Nas
uci add dhcp host
uci set dhcp.@host[-1].name='Nas'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.5'
uci set dhcp.@host[-1].leasetime='infinite'
uci set dhcp.@host[-1].mac='D8:FC:93:8B:30:D2'

# IPMI
uci add dhcp host
uci set dhcp.@host[-1].name='IPMI'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.6'
uci set dhcp.@host[-1].leasetime='infinite'
uci set dhcp.@host[-1].mac='AC:1F:6B:1E:07:67'

# Negear
uci add dhcp host
uci set dhcp.@host[-1].name='Negear'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.7'
uci set dhcp.@host[-1].leasetime='infinite'
uci set dhcp.@host[-1].mac='A0:40:A0:6F:33:DA'

# AP1
uci add dhcp host
uci set dhcp.@host[-1].name='AP1'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.9'
uci set dhcp.@host[-1].leasetime='infinite'
uci add_list dhcp.@host[-1].mac='F0:9F:C2:6C:E5:18'

# AP2
uci add dhcp host
uci set dhcp.@host[-1].name='AP2'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.10'
uci set dhcp.@host[-1].leasetime='infinite'
uci add_list dhcp.@host[-1].mac='F0:9F:C2:6C:D7:68'

# CS-C6TC
uci add dhcp host
uci set dhcp.@host[-1].name='CS-C6TC'
uci set dhcp.@host[-1].ip='192.168.1.11'
uci add_list dhcp.@host[-1].mac='18:99:F5:CB:2E:A2'

# C7
uci add dhcp host
uci set dhcp.@host[-1].name='C7'
uci add_list dhcp.@host[-1].mac='20:BB:BC:BA:3C:0D'
uci set dhcp.@host[-1].ip='192.168.1.12'

# lifesmart
uci add dhcp host
uci set dhcp.@host[-1].name='lifesmart'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].mac='BC:34:00:23:4A:B4'
uci set dhcp.@host[-1].ip='192.168.1.14'
uci set dhcp.@host[-1].leasetime='infinite'

# DenonX2400H
uci add dhcp host
uci set dhcp.@host[-1].name='DenonX2400H'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].mac='00:05:CD:99:53:C8'
uci set dhcp.@host[-1].ip='192.168.1.15'
uci set dhcp.@host[-1].leasetime='infinite'

# Pve-Windows11
uci add dhcp host
uci set dhcp.@host[-1].name='Pve-Windows11'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.16'
uci set dhcp.@host[-1].leasetime='infinite'
uci add_list dhcp.@host[-1].mac='BC:24:11:08:7F:20'

# Book-Windows11
uci add dhcp host
uci set dhcp.@host[-1].name='Book-Windows11'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.17'
uci set dhcp.@host[-1].leasetime='infinite'
uci set dhcp.@host[-1].mac='84:7B:57:C6:C8:02'

# Hermes
uci add dhcp host
uci set dhcp.@host[-1].name='Hermes'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].ip='192.168.1.18'
uci set dhcp.@host[-1].leasetime='infinite'
uci add_list dhcp.@host[-1].mac='BC:24:11:91:50:EF'

# Macos
uci add dhcp host
uci set dhcp.@host[-1].name='Macos'
uci add_list dhcp.@host[-1].mac='BC:24:11:28:A6:8E'
uci set dhcp.@host[-1].ip='192.168.1.19'
uci set dhcp.@host[-1].leasetime='infinite'

uci commit dhcp

exit 0
DHCPEOF
chmod +x files/etc/uci-defaults/20-static-dhcp


echo "DIY2 is complete!"


# =============================================
# SmartDNS 国内网络优化
# =============================================
mkdir -p files/etc/uci-defaults

cat << 'SMARTDNS_UCI' > files/etc/uci-defaults/99-smartdns-optimize
#!/bin/sh
# SmartDNS 国内网络优化配置

# 设置基本配置
uci set smartdns.smartdns.enabled='1'
uci set smartdns.smartdns.server_name='SmartDNS-Kevin'
uci set smartdns.smartdns.port='5335'
uci set smartdns.smartdns.bind='[::]:5335'

# 国外 DNS
uci delete smartdns.smartdns.server_tcp 2>/dev/null
uci add_list smartdns.smartdns.server_tcp='8.8.8.8:53'
uci add_list smartdns.smartdns.server_tcp='1.1.1.1:53'

uci delete smartdns.smartdns.server_https 2>/dev/null
uci add_list smartdns.smartdns.server_https='https://1.1.1.1/dns-query'
uci add_list smartdns.smartdns.server_https='https://dns.google/dns-query'

# 测速配置
uci set smartdns.smartdns.speed_check_mode='ping,tcp:80,tcp:443'
uci set smartdns.smartdns.tcp_concurrent='1'

# 缓存配置 (优化)
uci set smartdns.smartdns.cache_size='10000'
uci set smartdns.smartdns.cache_persist='1'
uci set smartdns.smartdns.prefetch_domain='1'
uci set smartdns.smartdns.serve_expired='1'
uci set smartdns.smartdns.serve_expired_ttl='86400'

# TTL 配置
uci set smartdns.smartdns.rr_ttl_min='300'
uci set smartdns.smartdns.rr_ttl_max='86400'
uci set smartdns.smartdns.rr_ttl_reply_max='300'

# 其他优化
uci set smartdns.smartdns.force_qtype_SOA='65'
uci set smartdns.smartdns.deny_domain_served='.'

# 删除旧的服务器组配置
uci delete smartdns.group_domestic 2>/dev/null
uci delete smartdns.group_foreign 2>/dev/null

# 创建国内DNS组
uci set smartdns.group_domestic='server'
uci set smartdns.group_domestic.name='国内DNS组'
uci set smartdns.group_domestic.type='group'
uci set smartdns.group_domestic.strategy='default'
uci delete smartdns.group_domestic.server 2>/dev/null
uci add_list smartdns.group_domestic.server='119.29.29.29'
uci add_list smartdns.group_domestic.server='223.5.5.5'
uci add_list smartdns.group_domestic.server='119.28.28.28'
uci add_list smartdns.group_domestic.server='223.6.6.6'

# 创建国外DNS组
uci set smartdns.group_foreign='server'
uci set smartdns.group_foreign.name='国外DNS组'
uci set smartdns.group_foreign.type='group'
uci set smartdns.group_foreign.strategy='default'
uci delete smartdns.group_foreign.server 2>/dev/null
uci add_list smartdns.group_foreign.server='8.8.8.8'
uci add_list smartdns.group_foreign.server='1.1.1.1'
uci add_list smartdns.group_foreign.server='208.67.222.222'

# 删除旧的域名规则
uci delete smartdns.domestic_rule 2>/dev/null
uci delete smartdns.google_cn_rule 2>/dev/null
uci delete smartdns.google_rule 2>/dev/null

# 国内域名走国内DNS
uci set smartdns.domestic_rule='domain-rules'
uci set smartdns.domestic_rule.name='国内域名走国内DNS'
uci set smartdns.domestic_rule.server='group-domestic'
uci set smartdns.domestic_rule.dest_queue='group-domestic'
uci set smartdns.domestic_rule.ipset='chnroute'
uci set smartdns.domestic_rule.nftset='chnroute#4#inet'

# Google CN 走国内DNS
uci set smartdns.google_cn_rule='domain-rules'
uci set smartdns.google_cn_rule.name='Google CN'
uci set smartdns.google_cn_rule.server='group-domestic'

# Google 走国外DNS
uci set smartdns.google_rule='domain-rules'
uci set smartdns.google_rule.name='Google'
uci set smartdns.google_rule.server='group-foreign'
uci set smartdns.google_rule.ipset='gfwlist'
uci set smartdns.google_rule.nftset='gfwlist#4#inet'

# 保存配置
uci commit smartdns

logger "SmartDNS 国内网络优化配置已应用"
SMARTDNS_UCI

chmod +x files/etc/uci-defaults/99-smartdns-optimize
echo "DIY2 + SmartDNS optimization is complete!"
