#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase C：安裝套件
# 無需互動輸入
# ═══════════════════════════════════════════

module_packages_collect() {
  : # 此模組無需收集輸入
}

module_packages_run() {
  print_phase "Phase C：安裝套件"

  step_start "安裝基礎工具包 (這可能需要幾分鐘)"

  apt install -y \
    xz-utils \
    openssl \
    gawk \
    file \
    sudo \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    tmux \
    btop \
    git \
    chrony \
    fzf \
    ufw \
    fail2ban

  if [ $? -eq 0 ]; then
    step_ok "套件安裝完成" "已安裝: xz-utils openssl gawk file sudo curl
ca-certificates gnupg lsb-release jq tmux btop
git chrony fzf ufw fail2ban"
  else
    step_fail "部分套件安裝失敗" "請手動執行 apt install 檢查"
  fi
}
