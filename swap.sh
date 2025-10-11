#!/usr/bin/env bash

# 颜色定义
Green=$'\033[32m'
Red=$'\033[31m'
Yellow=$'\033[33m'
Font=$'\033[0m'

[[ -e /proc/version ]] || {
  echo -e "${Red}❌ 仅支持 Linux 系统！${Font}" >&2
  exit 1
}
((EUID == 0)) || {
  echo -e "${Red}❌ 此脚本必须以 root 身份运行！${Font}" >&2
  exit 1
}
[[ -d /proc/vz ]] && ! grep -qE 'docker|lxc' /proc/1/cgroup 2>/dev/null && {
  echo -e "${Red}🚫 检测到 OpenVZ 架构，不支持 Swap 操作！${Font}" >&2
  exit 1
}

# 获取物理内存（MB）
get_ram_mb() {
  awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

# 推荐 Swap 大小（MB）
get_recommended_swap() {
  local ram_mb=$1
  if ((ram_mb <= 2048)); then
    echo $((ram_mb * 3 / 2))
  elif ((ram_mb <= 8192)); then
    echo "$ram_mb"
  elif ((ram_mb <= 65536)); then
    echo $((ram_mb * 2 / 3))
  else
    echo 8192
  fi
}

# 显示 Swap 状态
show_swap_status() {
  echo -e "\n${Green}📊 当前 Swap 信息：${Font}"
  if swapon --show --noheadings | grep -q '/swapfile'; then
    swapon --show
    grep -i 'swaptotal\|swapfree' /proc/meminfo
  else
    echo -e "${Yellow}⚠️  当前未启用 Swap。${Font}"
  fi
}

# 检查是否已有 /swapfile
has_swapfile() {
  swapon --show --noheadings | grep -q '/swapfile'
}

# 添加 Swap
add_swap() {
  local ram_mb recommended swapsize input
  ram_mb=$(get_ram_mb)
  recommended=$(get_recommended_swap "$ram_mb")

  echo -e "\n${Green}💡 物理内存：${ram_mb} MB${Font}"
  echo -e "${Green}✅ 推荐 Swap：${recommended} MB${Font}"
  echo -e "${Yellow}📌 按回车使用推荐值，或输入自定义大小（MB）${Font}"

  while true; do
    read -rp "请输入 Swap 大小（默认 ${recommended}）: " input
    swapsize=${input:-$recommended}
    if [[ "$swapsize" =~ ^[1-9][0-9]*$ ]]; then
      break
    fi
    echo -e "${Red}❌ 请输入正整数！${Font}"
  done

  if has_swapfile; then
    echo -e "${Red}🚫 Swap 已启用，无法重复创建！${Font}"
    show_swap_status
    return 1
  fi

  if [[ -e /swapfile ]]; then
    echo -e "${Red}⚠️  /swapfile 已存在，请手动删除后再试。${Font}"
    return 1
  fi

  echo -e "${Green}🛠️  创建 /swapfile（${swapsize}MB）...${Font}"
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

  swapon /swapfile || {
    echo -e "${Red}❌ 启用 Swap 失败！${Font}"
    rm -f /swapfile
    return 1
  }

  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  echo -e "${Green}✅ Swap 创建成功！${Font}"
  show_swap_status
}

# 删除 Swap
del_swap() {
  if ! has_swapfile; then
    echo -e "${Red}❌ 未检测到活动的 /swapfile Swap！${Font}"
    show_swap_status
    return 1
  fi

  echo -e "${Green}🗑️  关闭并删除 Swap...${Font}"
  swapoff /swapfile
  rm -f /swapfile
  sed -i '\|/swapfile|d' /etc/fstab
  echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
  echo -e "${Green}✅ Swap 已成功删除！${Font}"
  show_swap_status
}

# 主菜单
show_menu() {
  local rec_swap
  rec_swap=$(get_recommended_swap "$(get_ram_mb)")

  while true; do
    cat <<EOF

==============================================
${Green}✨ Linux 一键 Swap 管理工具 ✨${Font}
==============================================
${Green}(1) 添加 Swap（推荐：${rec_swap} MB）${Font}
${Green}(2) 删除 Swap${Font}
${Green}(3) 查看 Swap 状态${Font}
${Green}(4) 退出${Font}
==============================================
EOF

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

show_menu
