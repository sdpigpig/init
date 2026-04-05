#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase B：核心優化
# BBR → SWAP → 系統調優 → Journal 日誌限制
# ═══════════════════════════════════════════

module_optimize_collect() {
  print_phase "Phase B：核心優化 — 收集設定"

  prompt_input CFG_SWAP_SIZE "SWAP 大小" "$DEFAULT_SWAP_SIZE"
}

module_optimize_run() {
  print_phase "Phase B：核心優化"

  # ── Step 1: BBR + 網路優化 ──
  step_start "啟用 BBR 與網路優化"

  sed -i '/net.core.default_qdisc\|net.ipv4.tcp_congestion_control\|net.ipv4.tcp_fastopen\|net.core.somaxconn\|net.ipv4.tcp_max_syn_backlog\|net.ipv4.ip_local_port_range/d' /etc/sysctl.conf

  cat >> /etc/sysctl.conf <<BBREOF
# ── BBR + 網路優化 (由 init-debian 寫入) ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
BBREOF

  sysctl -p >/dev/null 2>&1
  modprobe tcp_bbr >/dev/null 2>&1

  local bbr_algo
  bbr_algo="$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')"
  local bbr_qdisc
  bbr_qdisc="$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')"
  local bbr_conn
  bbr_conn="$(sysctl net.core.somaxconn 2>/dev/null | awk '{print $3}')"
  local bbr_ports
  bbr_ports="$(sysctl net.ipv4.ip_local_port_range 2>/dev/null | awk '{print $3, $4}')"

  local bbr_lsmod="已載入 (lsmod OK)"
  if ! lsmod | grep -q bbr; then
    bbr_lsmod="未在 lsmod 顯示 (可能已編譯進內核)"
  fi

  step_ok "BBR 與網路優化完成" "擁塞控制: $bbr_algo
隊列調度: $bbr_qdisc
最大排隊: $bbr_conn
端口範圍: $bbr_ports
BBR 模組: $bbr_lsmod"

  # ── Step 2: SWAP ──
  step_start "配置 SWAP ($CFG_SWAP_SIZE)"

  swapoff -a 2>/dev/null
  sed -i '/swap/d' /etc/fstab
  rm -f /swapfile

  # 嘗試 fallocate，失敗則用 dd
  local swap_bytes
  swap_bytes=$(echo "$CFG_SWAP_SIZE" | sed 's/G//')
  if ! fallocate -l "$CFG_SWAP_SIZE" /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1M count=$((swap_bytes * 1024)) status=progress
  fi

  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab

  step_ok "SWAP 設定完成" "$(free -h | head -3)"

  # ── Step 3: 系統調優 ──
  step_start "文件句柄與記憶體優化"

  sysctl -w vm.swappiness=10 >/dev/null 2>&1
  sysctl -w fs.file-max=1048576 >/dev/null 2>&1
  sysctl -w vm.dirty_background_ratio=10 >/dev/null 2>&1
  sysctl -w vm.dirty_ratio=20 >/dev/null 2>&1
  sysctl -w vm.max_map_count=262144 >/dev/null 2>&1

  sed -i '/vm.swappiness\|fs.file-max\|vm.dirty_background_ratio\|vm.dirty_ratio\|vm.max_map_count/d' /etc/sysctl.conf

  cat >> /etc/sysctl.conf <<SYSEOF
# ── 系統調優 (由 init-debian 寫入) ──
vm.swappiness=10
fs.file-max=1048576
vm.dirty_background_ratio=10
vm.dirty_ratio=20
vm.max_map_count=262144
SYSEOF

  sysctl -p >/dev/null 2>&1

  sed -i '/nofile/d' /etc/security/limits.conf

  cat >> /etc/security/limits.conf <<LIMEOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMEOF

  step_ok "系統調優完成" "Swappiness:    $(sysctl -n vm.swappiness)
File-max:      $(sysctl -n fs.file-max)
Max map count: $(sysctl -n vm.max_map_count)
Dirty ratio:   $(sysctl -n vm.dirty_ratio)%"

  # ── Step 4: Journal 日誌限制 ──
  step_start "限制 Systemd Journal 日誌大小"

  journalctl --vacuum-size=200M >/dev/null 2>&1
  sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=200M/' /etc/systemd/journald.conf
  systemctl restart systemd-journald

  step_ok "Journal 日誌限制完成" "$(journalctl --disk-usage 2>&1)"
}
