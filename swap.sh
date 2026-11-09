#!/bin/sh

Green=$(printf '\033[32m')
Red=$(printf '\033[31m')
Yellow=$(printf '\033[33m')
Font=$(printf '\033[0m')

info() { printf '%b\n' "${Green}$1${Font}"; }
warn() { printf '%b\n' "${Yellow}$1${Font}"; }
error() { printf '%b\n' "${Red}$1${Font}"; }

if [ "$(uname -s)" != Linux ] || [ ! -r /proc/meminfo ]; then
  error "❌ 仅支持 Linux 系统！" >&2
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  error "❌ 此脚本必须以 root 身份运行！" >&2
  exit 1
fi
if [ -d /proc/vz ] && ! grep -qE 'docker|lxc' /proc/1/cgroup 2>/dev/null; then
  error "🚫 检测到 OpenVZ 架构，不支持 Swap 操作！" >&2
  exit 1
fi

get_ram_mb() {
  awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

get_recommended_swap() {
  if [ "$1" -le 2048 ]; then
    printf '%s\n' "$(($1 * 5 / 4))"
  elif [ "$1" -le 8192 ]; then
    printf '%s\n' "$(($1 / 4))"
  elif [ "$1" -le 65536 ]; then
    printf '%s\n' "$(($1 * 2 / 3))"
  else
    echo 8192
  fi
}

show_swap_status() {
  printf '\n%b\n' "${Green}📊 当前 Swap 信息：${Font}"
  if has_swapfile; then
    swapon --show 2>/dev/null || cat /proc/swaps
    grep -iE 'swaptotal|swapfree' /proc/meminfo
  else
    warn "⚠️  当前未启用 Swap。"
  fi
}

has_swapfile() {
  awk 'NR > 1 && $1 == "/swapfile" { found = 1 }
       END { exit !found }' /proc/swaps
}

add_swap() {
  ram_mb=$(get_ram_mb)
  recommended=$(get_recommended_swap "$ram_mb")

  printf '\n%b\n' "${Green}💡 物理内存：${ram_mb} MB${Font}"
  printf '%b\n' "${Green}✅ 推荐 Swap：${recommended} MB${Font}"
  warn "📌 按回车使用推荐值，或输入自定义大小（MB）"

  while :; do
    printf "请输入 Swap 大小（默认 %s）: " "$recommended"
    read -r input || return 1
    swapsize=${input:-$recommended}
    case "$swapsize" in
      ''|0*|*[!0-9]*) ;;
      *) break ;;
    esac
    error "❌ 请输入正整数！"
  done

  if has_swapfile; then
    error "🚫 Swap 已启用，无法重复创建！"
    show_swap_status
    return 1
  fi

  if [ -e /swapfile ]; then
    error "⚠️  /swapfile 已存在，请手动删除后再试。"
    return 1
  fi

  info "🛠️  创建 /swapfile（${swapsize}MB）..."
  if ! fallocate -l "${swapsize}M" /swapfile 2>/dev/null; then
    warn "🔄 fallocate 不可用，回退使用 dd..."
    rm -f /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count="$swapsize" 2>/dev/null || {
      error "❌ 创建 swapfile 失败！"
      rm -f /swapfile
      return 1
    }
  fi

  chmod 600 /swapfile || {
    error "❌ 设置 swapfile 权限失败！"
    rm -f /swapfile
    return 1
  }
  mkswap /swapfile >/dev/null || {
    error "❌ mkswap 失败！"
    rm -f /swapfile
    return 1
  }
  swapon /swapfile || {
    error "❌ 启用 Swap 失败！"
    rm -f /swapfile
    return 1
  }

  awk '$1 == "/swapfile" { found = 1 } END { exit !found }' /etc/fstab ||
    echo '/swapfile none swap sw 0 0' >>/etc/fstab

  info "✅ Swap 创建成功！"
  show_swap_status
}

del_swap() {
  if ! has_swapfile; then
    error "❌ 未检测到活动的 /swapfile Swap！"
    show_swap_status
    return 1
  fi

  info "🗑️  关闭并删除 Swap..."
  swapoff /swapfile || {
    error "❌ 关闭 Swap 失败，未删除文件。"
    return 1
  }
  rm -f /swapfile || {
    error "❌ 删除 /swapfile 失败！"
    return 1
  }
  sed -i '\|^[[:space:]]*/swapfile[[:space:]]|d' /etc/fstab
  echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
  info "✅ Swap 已成功删除！"
  show_swap_status
}

show_menu() {
  rec_swap=$(get_recommended_swap "$(get_ram_mb)")

  while :; do
    cat <<EOF

==========================================
${Green}✨ Linux 一键 Swap 管理工具 ✨${Font}
==========================================
${Green}(0) 退出${Font}
${Green}(1) 添加 Swap（推荐：${rec_swap} MB）${Font}
${Green}(2) 删除 Swap${Font}
${Green}(3) 查看 Swap 状态${Font}
==========================================
EOF

    printf "请选择操作 [0-3]: "
    read -r choice || exit 0
    case "$choice" in
      1) add_swap ;;
      2) del_swap ;;
      3) show_swap_status ;;
      0)
        info "👋 再见！"
        exit 0
        ;;
      *)
        error "❌ 无效输入！请输入 0-3。"
        sleep 1
        ;;
    esac
  done
}

show_menu
