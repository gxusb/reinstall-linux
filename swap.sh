#!/usr/bin/env bash

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Font="\033[0m"

root_need() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${Red}❌ 错误：此脚本必须以 root 身份运行！${Font}" >&2
    exit 1
  fi
}

ovz_no() {
  if [[ -d "/proc/vz" ]] && ! grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
    echo -e "${Red}🚫 检测到您的 VPS 基于 OpenVZ，不支持 Swap 操作！${Font}" >&2
    exit 1
  fi
}

show_swap_status() {
  echo -e "\n${Green}📊 当前 Swap 信息：${Font}"
  if swapon --show | grep -q "/swapfile"; then
    swapon --show
    grep -i "swaptotal\|swapfree" /proc/meminfo
  else
    echo -e "${Yellow}⚠️  当前未启用 Swap。${Font}"
  fi
}

# 获取物理内存（MB）
get_ram_mb() {
  awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

# 自动推荐 Swap 大小（MB）
get_recommended_swap() {
  local ram_mb swap_mb
  ram_mb=$(get_ram_mb)

  if ((ram_mb <= 2048)); then
    swap_mb=$((ram_mb * 2))
  elif ((ram_mb <= 8192)); then
    swap_mb=$ram_mb
  elif ((ram_mb <= 65536)); then
    swap_mb=$((ram_mb / 2))
  else
    swap_mb=8192 # >64GB RAM，固定 8GB
  fi

  # 最小 512MB 保障
  ((swap_mb < 512)) && swap_mb=512
  echo "$swap_mb"
}

add_swap() {
  local ram_mb recommended swapsize input
  ram_mb=$(get_ram_mb)
  recommended=$(get_recommended_swap)

  echo -e "\n${Green}💡 当前物理内存：${ram_mb} MB${Font}"
  echo -e "${Green}✅ 推荐 Swap 大小：${recommended} MB${Font}"
  echo -e "${Yellow}📌 按回车使用推荐值，或输入自定义大小（单位：MB）${Font}"

  while true; do
    read -rp "请输入 Swap 大小（默认 ${recommended}）: " input
    swapsize=${input:-$recommended}
    if [[ "$swapsize" =~ ^[1-9][0-9]*$ ]]; then
      break
    fi
    echo -e "${Red}❌ 请输入正整数！${Font}"
  done

  if swapon --show | grep -q "/swapfile"; then
    echo -e "${Red}🚫 Swap 已启用，无法重复创建！${Font}"
    show_swap_status
    return 1
  fi

  if [[ -e /swapfile ]]; then
    echo -e "${Red}⚠️  /swapfile 已存在，请手动删除后再试。${Font}"
    return 1
  fi

  echo -e "${Green}🛠️  正在创建 /swapfile（${swapsize}MB）...${Font}"
  if ! fallocate -l "${swapsize}M" /swapfile 2>/dev/null; then
    echo -e "${Yellow}🔄 fallocate 不可用，回退使用 dd...${Font}"
    dd if=/dev/zero of=/swapfile bs=1M count="$swapsize" status=progress 2>/dev/null || {
      echo -e "${Red}❌ 创建 swapfile 失败！${Font}"
      return 1
    }
  fi

  chmod 600 /swapfile
  mkswap /swapfile >/dev/null || {
    echo -e "${Red}❌ mkswap 失败！${Font}"
    rm -f /swapfile
    return 1
  }

  if ! swapon /swapfile; then
    echo -e "${Red}❌ 启用 Swap 失败！${Font}"
    rm -f /swapfile
    return 1
  fi

  if ! grep -q "^/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >>/etc/fstab
  fi

  echo -e "${Green}✅ Swap 创建成功！${Font}"
  show_swap_status
}

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
  echo 3 >/proc/sys/vm/drop_caches

  echo -e "${Green}✅ Swap 已成功删除！${Font}"
  show_swap_status
}

show_menu() {
  while true; do
    echo -e "\n=============================================="
    echo -e "${Green}✨ Linux VPS 一键 Swap 管理工具 ✨${Font}"
    echo -e "=============================================="
    echo -e "${Green}(1) 添加 Swap（自动推荐大小 $(get_recommended_swap)MB）${Font}"
    echo -e "${Green}(2) 删除 Swap${Font}"
    echo -e "${Green}(3) 查看当前 Swap 状态${Font}"
    echo -e "${Green}(4) 退出${Font}"
    echo -e "=============================================="
    read -rp "👉 请选择操作 [1-4]: " choice

    case "$choice" in
    1) add_swap ;;
    2) del_swap ;;
    3) show_swap_status ;;
    4)
      echo -e "${Green}👋 再见！${Font}"
      exit 0
      ;;
    *)
      echo -e "${Red}❌ 无效输入！请输入 1-4。${Font}"
      sleep 1
      ;;
    esac
  done
}

main() {
  root_need
  ovz_no
  show_menu
}

main
