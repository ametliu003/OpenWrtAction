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
uci set dhcp.lan.ra=''
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

# --- Configure mwan3 (用户自定义配置) ---
uci set mwan3.globals=globals
uci set mwan3.globals.mmx_mask='0x3F00'

# balanced policy
uci set mwan3.balanced=policy
uci delete mwan3.balanced.use_member 2>/dev/null
uci add_list mwan3.balanced.use_member='wan_w10'
uci add_list mwan3.balanced.use_member='wan2_w5'
uci set mwan3.balanced.last_resort='default'

# HTTPS rule (sticky)
uci set mwan3.https=rule
uci set mwan3.https.sticky='1'
uci set mwan3.https.dest_port='443'
uci set mwan3.https.proto='tcp'
uci set mwan3.https.use_policy='balanced'

# Default rule v4
uci set mwan3.default_rule_v4=rule
uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule_v4.use_policy='balanced'
uci set mwan3.default_rule_v4.family='ipv4'

# Default rule v6
uci set mwan3.default_rule_v6=rule
uci set mwan3.default_rule_v6.dest_ip='::/0'
uci set mwan3.default_rule_v6.use_policy='balanced'
uci set mwan3.default_rule_v6.family='ipv6'

# WAN interface
uci set mwan3.wan=interface
uci set mwan3.wan.enabled='1'
uci set mwan3.wan.initial_state='online'
uci set mwan3.wan.family='ipv4'
uci set mwan3.wan.track_method='ping'
uci set mwan3.wan.reliability='1'
uci set mwan3.wan.count='1'
uci set mwan3.wan.size='56'
uci set mwan3.wan.max_ttl='60'
uci set mwan3.wan.timeout='4'
uci set mwan3.wan.interval='10'
uci set mwan3.wan.failure_interval='5'
uci set mwan3.wan.recovery_interval='5'
uci set mwan3.wan.down='5'
uci set mwan3.wan.up='5'
uci delete mwan3.wan.track_ip 2>/dev/null
uci add_list mwan3.wan.track_ip='223.5.5.5'
uci add_list mwan3.wan.track_ip='119.29.29.29'

# WAN2 interface
uci set mwan3.wan2=interface
uci set mwan3.wan2.enabled='1'
uci set mwan3.wan2.initial_state='online'
uci set mwan3.wan2.family='ipv4'
uci set mwan3.wan2.track_method='ping'
uci set mwan3.wan2.reliability='1'
uci set mwan3.wan2.count='1'
uci set mwan3.wan2.size='56'
uci set mwan3.wan2.max_ttl='60'
uci set mwan3.wan2.timeout='4'
uci set mwan3.wan2.interval='10'
uci set mwan3.wan2.failure_interval='5'
uci set mwan3.wan2.recovery_interval='5'
uci set mwan3.wan2.down='5'
uci set mwan3.wan2.up='5'
uci delete mwan3.wan2.track_ip 2>/dev/null
uci add_list mwan3.wan2.track_ip='223.5.5.5'
uci add_list mwan3.wan2.track_ip='119.29.29.29'

# WAN member (weight 10)
uci set mwan3.wan_w10=member
uci set mwan3.wan_w10.interface='wan'
uci set mwan3.wan_w10.weight='10'

# WAN2 member (weight 5)
uci set mwan3.wan2_w5=member
uci set mwan3.wan2_w5.interface='wan2'
uci set mwan3.wan2_w5.weight='5'

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


# =============================================
# Disable banip
# =============================================
cat << 'BANIPEOF' > files/etc/uci-defaults/91-disable-banip
#!/bin/sh
# Disable banip service
/etc/init.d/banip stop 2>/dev/null
/etc/init.d/banip disable 2>/dev/null
uci set banip.config.enabled='0'
uci commit banip
logger "banip 已禁用"
BANIPEOF
chmod +x files/etc/uci-defaults/91-disable-banip


# =============================================
# OpenClash/HomeProxy - 安装但不启动
# =============================================
cat << 'OPENCLASH_UCI' > files/etc/uci-defaults/97-openclash-homeproxy
#!/bin/sh
# OpenClash/HomeProxy 配置 - 安装但不启动

# 等待系统启动完成
sleep 10

# ========== OpenClash 配置 ==========
# 下载 mihomo 核心 (Clash.Meta)
OPENCLASH_DIR="/etc/openclash"
mkdir -p "$OPENCLASH_DIR/core"

if [ ! -f "$OPENCLASH_DIR/core/mihomo" ]; then
    logger "OpenClash: 下载 mihomo 核心..."
    wget -q -O /tmp/mihomo.gz "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.0/mihomo-linux-amd64-compatible-v1.19.0.gz" 2>/dev/null
    if [ -f /tmp/mihomo.gz ]; then
        gunzip -f /tmp/mihomo.gz 2>/dev/null
        mv /tmp/mihomo "$OPENCLASH_DIR/core/mihomo" 2>/dev/null
        chmod +x "$OPENCLASH_DIR/core/mihomo"
        logger "OpenClash: mihomo 核心下载完成"
    else
        logger "OpenClash: mihomo 核心下载失败"
    fi
fi

# OpenClash - 禁用自动启动
uci set openclash.config.enable='0'
uci set openclash.config.proxy_mode='rule'
uci set openclash.config.ipv6_proxy='0'
uci set openclash.config.dns_mode='fake-ip'
uci set openclash.config.fake_ip_range='198.18.0.1/16'
uci set openclash.config.log_level='warning'
uci commit openclash

# OpenClash - 添加订阅
uci add openclash.config_subscribe > /dev/null 2>&1
uci set openclash.@config_subscribe[-1].name='Just My Socks'
uci set openclash.@config_subscribe[-1].url='https://jjsubmarines.com/members/getsub.php?service=1392427&id=e1433349-14c2-4464-9d83-26ad1dbaf1d2'
uci set openclash.@config_subscribe[-1].auto_update='1'
uci set openclash.@config_subscribe[-1].week_update='8'
uci set openclash.@config_subscribe[-1].interval_update='6'
uci commit openclash

# ========== HomeProxy 配置 ==========
# HomeProxy - 禁用自动启动
uci set homeproxy.config.enable='0'
uci set homeproxy.config.default_mode='root'
uci set homeproxy.config.tcp_proxy_mode='redirect'
uci set homeproxy.config.udp_proxy_mode='redirect'
uci set homeproxy.config.dns_mode='dns'
uci set homeproxy.config.remote_dns='127.0.0.1#5335'
uci set homeproxy.config.log_level='warn'
uci commit homeproxy

# HomeProxy - 添加订阅
uci add homeproxy.config_subscribe > /dev/null 2>&1
uci set homeproxy.@config_subscribe[-1].name='Just My Socks'
uci set homeproxy.@config_subscribe[-1].url='https://jjsubmarines.com/members/getsub.php?service=1392427&id=e1433349-14c2-4464-9d83-26ad1dbaf1d2'
uci set homeproxy.@config_subscribe[-1].auto_update='1'
uci set homeproxy.@config_subscribe[-1].week_update='8'
uci set homeproxy.@config_subscribe[-1].interval_update='6'
uci commit homeproxy

logger "OpenClash/HomeProxy 配置完成 (禁用自动启动 + 订阅已添加)"
OPENCLASH_UCI

chmod +x files/etc/uci-defaults/97-openclash-homeproxy
echo "✅ 97-openclash-homeproxy 已创建"


# =============================================
# PassWall - 启用 + SmartDNS 集成 + 订阅
# =============================================
# =============================================
# PassWall 完整配置 - 基于用户实际运行配置
# =============================================
cat << 'PASSWALL_UCI' > files/etc/uci-defaults/98-passwall-optimize
#!/bin/sh
# PassWall 完整配置 - 基于用户实际运行配置

# 等待 PassWall 安装完成
sleep 5

# ========== 全局配置 ==========
uci set passwall.@global[0].enabled='1'
uci set passwall.@global[0].socks_enabled='0'
uci set passwall.@global[0].tcp_node_socks_port='1070'
uci set passwall.@global[0].filter_proxy_ipv6='1'
uci set passwall.@global[0].dns_shunt='chinadns-ng'
uci set passwall.@global[0].dns_mode='tcp'
uci set passwall.@global[0].remote_dns='127.0.0.1#5335'
uci set passwall.@global[0].chinadns_ng_default_tag='none'
uci set passwall.@global[0].dns_redirect='1'
uci set passwall.@global[0].chn_list='direct'
uci set passwall.@global[0].tcp_proxy_mode='proxy'
uci set passwall.@global[0].udp_proxy_mode='proxy'
uci set passwall.@global[0].localhost_proxy='1'
uci set passwall.@global[0].client_proxy='1'
uci set passwall.@global[0].acl_enable='0'
uci set passwall.@global[0].log_tcp='0'
uci set passwall.@global[0].log_udp='0'
uci set passwall.@global[0].loglevel='error'
uci set passwall.@global[0].log_chinadns_ng='0'
uci set passwall.@global[0].udp_node='tcp'
uci set passwall.@global[0].dnsmasq_dns_redirect='1'

# ========== Haproxy 配置 ==========
uci set passwall.@global_haproxy[0].balancing_enable='0'

# ========== Delay 配置 ==========
uci set passwall.@global_delay[0].start_daemon='1'
uci set passwall.@global_delay[0].start_delay='60'

# ========== 转发配置 ==========
uci set passwall.@global_forwarding[0].tcp_no_redir_ports='disable'
uci set passwall.@global_forwarding[0].udp_no_redir_ports='disable'
uci set passwall.@global_forwarding[0].tcp_proxy_drop_ports='disable'
uci set passwall.@global_forwarding[0].udp_proxy_drop_ports='443'
uci set passwall.@global_forwarding[0].tcp_redir_ports='22,25,53,80,143,443,465,587,853,873,993,995,5222,8080,8443,9418'
uci set passwall.@global_forwarding[0].udp_redir_ports='1:65535'
uci set passwall.@global_forwarding[0].accept_icmp='0'
uci set passwall.@global_forwarding[0].prefer_nft='1'
uci set passwall.@global_forwarding[0].tcp_proxy_way='redirect'
uci set passwall.@global_forwarding[0].ipv6_tproxy='0'

# ========== Xray 配置 ==========
uci set passwall.@global_xray[0].sniffing_override_dest='0'

# ========== Other 配置 ==========
uci set passwall.@global_other[0].auto_detection_time='tcping'
uci set passwall.@global_other[0].show_node_info='1'
uci set passwall.@global_other[0].url_test_url='https://www.google.com/generate_204'

# ========== 规则更新 ==========
uci set passwall.@global_rules[0].auto_update='1'
uci set passwall.@global_rules[0].chnlist_update='1'
uci set passwall.@global_rules[0].chnroute_update='1'
uci set passwall.@global_rules[0].chnroute6_update='1'
uci set passwall.@global_rules[0].gfwlist_update='1'
uci set passwall.@global_rules[0].geosite_update='1'
uci set passwall.@global_rules[0].geoip_update='1'

# ========== App 配置 ==========
uci set passwall.@global_app[0].geoview_file='/usr/bin/geoview'
uci set passwall.@global_app[0].sing_box_file='/usr/bin/sing-box'
uci set passwall.@global_app[0].xray_file='/usr/bin/xray'
uci set passwall.@global_app[0].hysteria_file='/usr/bin/hysteria'

# ========== 订阅配置 ==========
uci set passwall.@global_subscribe[0].filter_keyword_mode='1'
uci delete passwall.@global_subscribe[0].filter_discard_list 2>/dev/null
uci add_list passwall.@global_subscribe[0].filter_discard_list='套餐到期'
uci add_list passwall.@global_subscribe[0].filter_discard_list='剩余流量'

# ========== PassWall 订阅 ==========
uci add passwall.subscribe_list > /dev/null 2>&1
uci set passwall.@subscribe_list[-1].remark='Just My Socks'
uci set passwall.@subscribe_list[-1].url='https://jmssub.net/members/getsub.php?service=1392427&id=e1433349-14c2-4464-9d83-26ad1dbaf1d2'
uci set passwall.@subscribe_list[-1].filter_keyword_mode='5'
uci set passwall.@subscribe_list[-1].ss_type='global'
uci set passwall.@subscribe_list[-1].trojan_type='global'
uci set passwall.@subscribe_list[-1].vmess_type='global'
uci set passwall.@subscribe_list[-1].vless_type='global'
uci set passwall.@subscribe_list[-1].hysteria2_type='global'
uci set passwall.@subscribe_list[-1].hysteria_up_mbps='1500'
uci set passwall.@subscribe_list[-1].hysteria_down_mbps='2000'
uci set passwall.@subscribe_list[-1].boot_update='1'
uci set passwall.@subscribe_list[-1].auto_update='1'
uci set passwall.@subscribe_list[-1].user_agent='passwall'
uci set passwall.@subscribe_list[-1].week_update='8'
uci set passwall.@subscribe_list[-1].interval_update='6'

# ========== 保存配置 ==========
uci commit passwall

logger "PassWall 完整配置已应用 (SmartDNS 集成 + 订阅)"
PASSWALL_UCI

chmod +x files/etc/uci-defaults/98-passwall-optimize
echo "✅ 98-passwall-optimize 已创建 (完整配置)"


# =============================================
# SmartDNS - 国内网络优化
# =============================================
cat << 'SMARTDNS_UCI' > files/etc/uci-defaults/99-smartdns-optimize
#!/bin/sh
# SmartDNS 国内网络优化配置

# ========== 基本配置 ==========
uci set smartdns.smartdns.enabled='1'
uci set smartdns.smartdns.server_name='SmartDNS-Kevin'
uci set smartdns.smartdns.port='5335'
uci set smartdns.smartdns.bind='[::]:5335'

# ========== 国外 DNS ==========
uci delete smartdns.smartdns.server_tcp 2>/dev/null
uci add_list smartdns.smartdns.server_tcp='8.8.8.8:53'
uci add_list smartdns.smartdns.server_tcp='1.1.1.1:53'

uci delete smartdns.smartdns.server_https 2>/dev/null
uci add_list smartdns.smartdns.server_https='https://1.1.1.1/dns-query'
uci add_list smartdns.smartdns.server_https='https://dns.google/dns-query'

# ========== 测速配置 ==========
uci set smartdns.smartdns.speed_check_mode='ping,tcp:80,tcp:443'
uci set smartdns.smartdns.tcp_concurrent='1'

# ========== 缓存配置 ==========
uci set smartdns.smartdns.cache_size='10000'
uci set smartdns.smartdns.cache_persist='1'
uci set smartdns.smartdns.prefetch_domain='1'
uci set smartdns.smartdns.serve_expired='1'
uci set smartdns.smartdns.serve_expired_ttl='86400'

# ========== TTL 配置 ==========
uci set smartdns.smartdns.rr_ttl_min='300'
uci set smartdns.smartdns.rr_ttl_max='86400'
uci set smartdns.smartdns.rr_ttl_reply_max='300'

# ========== 其他优化 ==========
uci set smartdns.smartdns.force_qtype_SOA='65'
uci set smartdns.smartdns.deny_domain_served='.'

# ========== 删除旧配置 ==========
uci delete smartdns.group_domestic 2>/dev/null
uci delete smartdns.group_foreign 2>/dev/null

# ========== 国内DNS组 ==========
uci set smartdns.group_domestic='server'
uci set smartdns.group_domestic.name='国内DNS组'
uci set smartdns.group_domestic.type='group'
uci set smartdns.group_domestic.strategy='default'
uci delete smartdns.group_domestic.server 2>/dev/null
uci add_list smartdns.group_domestic.server='119.29.29.29'
uci add_list smartdns.group_domestic.server='223.5.5.5'
uci add_list smartdns.group_domestic.server='119.28.28.28'
uci add_list smartdns.group_domestic.server='223.6.6.6'

# ========== 国外DNS组 ==========
uci set smartdns.group_foreign='server'
uci set smartdns.group_foreign.name='国外DNS组'
uci set smartdns.group_foreign.type='group'
uci set smartdns.group_foreign.strategy='default'
uci delete smartdns.group_foreign.server 2>/dev/null
uci add_list smartdns.group_foreign.server='8.8.8.8'
uci add_list smartdns.group_foreign.server='1.1.1.1'
uci add_list smartdns.group_foreign.server='208.67.222.222'

# ========== 删除旧域名规则 ==========
uci delete smartdns.domestic_rule 2>/dev/null
uci delete smartdns.google_cn_rule 2>/dev/null
uci delete smartdns.google_rule 2>/dev/null

# ========== 国内域名走国内DNS ==========
uci set smartdns.domestic_rule='domain-rules'
uci set smartdns.domestic_rule.name='国内域名走国内DNS'
uci set smartdns.domestic_rule.server='group-domestic'
uci set smartdns.domestic_rule.dest_queue='group-domestic'
uci set smartdns.domestic_rule.ipset='chnroute'
uci set smartdns.domestic_rule.nftset='chnroute#4#inet'

# ========== Google CN 走国内DNS ==========
uci set smartdns.google_cn_rule='domain-rules'
uci set smartdns.google_cn_rule.name='Google CN'
uci set smartdns.google_cn_rule.server='group-domestic'

# ========== Google 走国外DNS ==========
uci set smartdns.google_rule='domain-rules'
uci set smartdns.google_rule.name='Google'
uci set smartdns.google_rule.server='group-foreign'
uci set smartdns.google_rule.ipset='gfwlist'
uci set smartdns.google_rule.nftset='gfwlist#4#inet'

# ========== 保存配置 ==========
uci commit smartdns

logger "SmartDNS 国内网络优化配置已应用"
SMARTDNS_UCI

chmod +x files/etc/uci-defaults/99-smartdns-optimize
echo "✅ 99-smartdns-optimize 已创建"


echo "DIY2 is complete!"
