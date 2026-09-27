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

# 检测系统类型
is_alpine() {
  [[ -f /etc/os-release ]] && grep -qi '^ID=alpine' /etc/os-release
}

# OpenVZ 检查（非 Alpine 系统）
if ! is_alpine; then
  [[ -d /proc/vz ]] && ! grep -qE 'docker|lxc' /proc/1/cgroup 2>/dev/null && {
    echo -e "${Red}🚫 检测到 OpenVZ 架构，不支持 Swap 操作！${Font}" >&2
    exit 1
  }
fi

# 获取物理内存（MB）
get_ram_mb() {
  awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

# 推荐 Swap 大小（MB）
get_recommended_swap() {
  local ram_mb=$1
  if ((ram_mb <= 2048)); then
    echo $((ram_mb * 5 / 4))
  elif ((ram_mb <= 8192)); then
    echo $((ram_mb / 4))
  elif ((ram_mb <= 65536)); then
    echo $((ram_mb * 2 / 3))
  else
    echo 8192
  fi
}

# 显示 Swap 状态
show_swap_status() {
  echo -e "\n${Green}📊 当前 Swap 信息：${Font}"
  if command -v swapon &>/dev/null; then
    if swapon --show --noheadings 2>/dev/null | grep -q '/swapfile'; then
      swapon --show 2>/dev/null || swapon --summary 2>/dev/null
      grep -i 'swaptotal\|swapfree' /proc/meminfo
    else
      echo -e "${Yellow}⚠️  当前未启用 Swap。${Font}"
    fi
  else
    echo -e "${Yellow}⚠️  swapon 命令不可用。${Font}"
  fi
}

# 检查是否已有 /swapfile
has_swapfile() {
  if command -v swapon &>/dev/null; then
    swapon --show --noheadings 2>/dev/null | grep -q '/swapfile' && return 0
  fi
  return 1
}

# 创建 Swap 文件
create_swapfile() {
  local swapsize=$1
  echo -e "${Green}🛠️  创建 /swapfile（${swapsize}MB）...${Font}"
  
  # 尝试 fallocate（优先使用，更快）
  if command -v fallocate &>/dev/null; then
    if fallocate -l "${swapsize}M" /swapfile 2>/dev/null; then
      return 0
    fi
  fi
  
  # 回退使用 dd（兼容所有系统包括 Alpine）
  echo -e "${Yellow}🔄 使用 dd 创建交换文件...${Font}"
  if dd if=/dev/zero of=/swapfile bs=1M count="$swapsize" status=progress 2>/dev/null; then
    return 0
  fi
  
  # 最后尝试不显示进度的 dd（Alpine 可能不支持 status）
  if dd if=/dev/zero of=/swapfile bs=1M count="$swapsize" 2>/dev/null; then
    return 0
  fi
  
  return 1
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

  if ! create_swapfile "$swapsize"; then
    echo -e "${Red}❌ 创建 swapfile 失败！${Font}"
    rm -f /swapfile
    return 1
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

  # 兼容不同 sed 版本的 fstab 更新
  if ! grep -q '^/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
  
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
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  
  # 兼容不同 sed 版本
  if command -v sed &>/dev/null; then
    # 尝试 GNU sed 语法
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
    else
      # Alpine 使用 BusyBox sed，需要不同的语法
      sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null || true
    fi
  fi
  
  echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
  echo -e "${Green}✅ Swap 已成功删除！${Font}"
  show_swap_status
}

# 主菜单
show_menu() {
  local rec_swap system_name
  rec_swap=$(get_recommended_swap "$(get_ram_mb)")
  
  if is_alpine; then
    system_name="Alpine Linux"
  else
    system_name="Linux"
  fi

  while true; do
    cat <<EOF

==========================================
${Green}✨ ${system_name} 一键 Swap 管理工具 ✨${Font}
==========================================
${Green}(0) 退出${Font}
${Green}(1) 添加 Swap（推荐：${rec_swap} MB）${Font}
${Green}(2) 删除 Swap${Font}
${Green}(3) 查看 Swap 状态${Font}
==========================================
EOF

    read -rp "请选择操作 [0-3]: " choice
    case "$choice" in
    1) add_swap ;;
    2) del_swap ;;
    3) show_swap_status ;;
    0)
      echo -e "${Green}👋 再见！${Font}"
      exit 0
      ;;
    *)
      echo -e "${Red}❌ 无效输入！请输入 0-3。${Font}"
      sleep 1
      ;;
    esac
  done
}

show_menu
