#!/bin/bash

# feeds扩展内容 — 只保留需要的
export repos=(
  "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main"
  "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git;main"
  "src-git OpenClash https://github.com/vernesong/OpenClash;master"
  "src-git homeproxy https://github.com/immortalwrt/homeproxy;master"
  "src-git lucky https://github.com/sirpdboy/luci-app-lucky.git;main"
  "src-git ghfu https://github.com/smallprogram/luci-app-ghfu.git;main"
)

# 自定义软件包列表
clone_custom_packages () {
    local path="./package/custom_packages/"

    if [ "$GITHUB_ACTIONS" = "true" ] && [ -n "$GITHUB_RUN_ID" ] && [ -n "$GITHUB_WORKFLOW" ]; then
        PATCHES_SRC_DIR="$GITHUB_WORKSPACE"
    else
        PATCHES_SRC_DIR="../OpenWrtAction"
    fi

    rm -rf ${path}
    mkdir -p ${path}

    # 只保留 Argon 主题和配置
    git clone https://github.com/jerrykuku/luci-theme-argon.git ${path}luci-theme-argon
    git clone https://github.com/jerrykuku/luci-app-argon-config.git ${path}luci-app-argon-config

    local target="luci.main.mediaurlbase="

    echo "Scanning and commenting default theme auto-set..."
    find "$path" -type f \( -name "Makefile" -o -path "*/etc/uci-defaults/*" \) | while read -r file; do
        if grep -q "$target" "$file"; then
            echo "Hit: $file"
            sed -i "/$target/s/^\([[:blank:]]*\)\([^#[:blank:]]\)/\1# \2/" "$file"
        fi
    done

    echo "Comment processing complete."

    #-------------------------------------------设置默认主题------------------------------------------
    mkdir -p files/etc/uci-defaults
cat << "EOF" > files/etc/uci-defaults/zz-set-default-theme
#!/bin/sh
uci set luci.themes.Argon=/luci-static/argon
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit luci
exit 0
EOF
    chmod +x files/etc/uci-defaults/zz-set-default-theme
    echo "Default theme set!"
    #-------------------------------------------end设置默认主题------------------------------------------

    echo "Custom packages cloned (argon only, no extra themes)"
}
