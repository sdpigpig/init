#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase A：基礎系統
# 修改 Root 密碼 → 主機名 → 官方源升級
# ═══════════════════════════════════════════

module_base_collect() {
  print_phase "Phase A：基礎系統 — 收集設定"

  prompt_password CFG_ROOT_PASSWORD "設定 Root 密碼"
  prompt_input    CFG_HOSTNAME      "主機名" "$DEFAULT_HOSTNAME"
}

module_base_run() {
  print_phase "Phase A：基礎系統"

  # ── Step 1: Root 密碼 ──
  step_start "修改 Root 密碼"
  echo "root:$CFG_ROOT_PASSWORD" | chpasswd 2>&1
  if [ $? -eq 0 ]; then
    step_ok "Root 密碼已更新"
  else
    step_fail "Root 密碼更新失敗"
    return 1
  fi

  # ── Step 2: 主機名 ──
  step_start "修改主機名為 $CFG_HOSTNAME"
  hostnamectl set-hostname "$CFG_HOSTNAME"
  sed -i "s/127.0.1.1.*/127.0.1.1 $CFG_HOSTNAME/g" /etc/hosts
  step_ok "主機名已設定" "新主機名: $CFG_HOSTNAME"

  # ── Step 3: 官方源 + 更新套件清單 ──
  step_start "切換官方源並更新套件清單"
  mv /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null

  cat > /etc/apt/sources.list <<SRCEOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
SRCEOF

  apt update && apt autoremove -y && apt clean

  if [ $? -eq 0 ]; then
    step_ok "官方源切換完成" "核心版本: $(uname -r)"
  else
    step_fail "套件清單更新出現問題" "請手動檢查 apt 日誌"
  fi
}
