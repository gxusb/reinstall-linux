#!/usr/bin/env bash

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Font="\033[0m"

# 检查 root 权限
root_need() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}❌ 错误：此脚本必须以 root 身份运行！${Font}"
        exit 1
    fi
}

# 检查是否为 OpenVZ
ovz_no() {
    if [[ -d "/proc/vz" ]] && ! grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
        echo -e "${Red}🚫 检测到您的 VPS 基于 OpenVZ，不支持 Swap 操作！${Font}"
        exit 1
    fi
}

# 显示当前 swap 状态
show_swap_status() {
    echo -e "${Green}📊 当前 Swap 信息：${Font}"
    if swapon --show | grep -q "/swapfile"; then
        swapon --show
        grep -i "swaptotal\|swapfree" /proc/meminfo
    else
        echo -e "${Yellow}⚠️  当前未启用 Swap。${Font}"
    fi
}

# 添加 swap
add_swap() {
    echo -e "${Green}💡 请输入需要添加的 Swap 大小（单位：MB）${Font}"
    echo -e "${Yellow}📌 建议值：物理内存的 1~2 倍（例如内存 1GB，可设 1024~2048）${Font}"
    while true; do
        read -rp "🔢 请输入 Swap 数值（正整数，如 2048）: " swapsize
        if [[ "$swapsize" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo -e "${Red}❌ 输入无效！请输入一个正整数。${Font}"
        fi
    done

    if swapon --show | grep -q "/swapfile"; then
        echo -e "${Red}🚫 Swapfile 已启用，无法重复创建！${Font}"
        show_swap_status
        return 1
    fi

    if [[ -f /swapfile ]]; then
        echo -e "${Red}⚠️  /swapfile 文件已存在但未启用，请手动清理后再试。${Font}"
        return 1
    fi

    echo -e "${Green}🛠️  正在创建 /swapfile（大小：${swapsize}MB）...${Font}"

    if ! fallocate -l "${swapsize}M" /swapfile 2>/dev/null; then
        echo -e "${Yellow}🔄 fallocate 不可用，回退使用 dd...${Font}"
        dd if=/dev/zero of=/swapfile bs=1M count="$swapsize" status=progress 2>/dev/null
    fi

    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    if ! swapon /swapfile; then
        echo -e "${Red}❌ 启用 Swap 失败！${Font}"
        rm -f /swapfile
        exit 1
    fi

    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    echo -e "${Green}✅ Swap 创建成功！${Font}"
    show_swap_status
}

# 删除 swap
del_swap() {
    if ! swapon --show | grep -q "/swapfile"; then
        echo -e "${Red}❌ 未检测到活动的 /swapfile Swap！${Font}"
        show_swap_status
        return 1
    fi

    echo -e "${Green}🗑️  正在关闭并删除 Swap...${Font}"
    swapoff /swapfile
    rm -f /swapfile
    sed -i '\|/swapfile|d' /etc/fstab
    echo 3 > /proc/sys/vm/drop_caches

    echo -e "${Green}✅ Swap 已成功删除！${Font}"
    show_swap_status
}

# 主菜单
main() {
    root_need
    ovz_no
    # clear
    echo -e "=============================================="
    echo -e "${Green}✨ Linux VPS 一键 Swap 管理工具 ✨${Font}"
    echo -e "=============================================="
    echo -e "${Green}1️⃣  添加 Swap${Font}"
    echo -e "${Green}2️⃣  删除 Swap${Font}"
    echo -e "${Green}3️⃣  查看当前 Swap 状态${Font}"
    echo -e "=============================================="
    read -rp "👉 请选择操作 [1-3]: " num

    case "$num" in
        1)
            add_swap
            ;;
        2)
            del_swap
            ;;
        3)
            show_swap_status
            ;;
        *)
            echo -e "${Red}❌ 无效输入！请输入 1、2 或 3。${Font}"
            sleep 2
            main
            ;;
    esac
}

main
