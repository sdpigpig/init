#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase D：安全加固
# SSHD → UFW → Fail2ban（依賴鏈正確）
# ═══════════════════════════════════════════

module_security_collect() {
  print_phase "Phase D：安全加固 — 收集設定"

  prompt_input CFG_SSH_PORT "SSH 端口" "$DEFAULT_SSH_PORT"
}

module_security_run() {
  print_phase "Phase D：安全加固"

  # ── Step 1: SSHD ──
  step_start "修改 SSHD 設定 (Port $CFG_SSH_PORT)"

  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

  sed -i "s/^#\?Port .*/Port $CFG_SSH_PORT/" /etc/ssh/sshd_config
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 60/' /etc/ssh/sshd_config
  sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 120/' /etc/ssh/sshd_config
  sed -i 's/^#\?MaxSessions .*/MaxSessions 100/' /etc/ssh/sshd_config
  sed -i 's/^#\?MaxStartups .*/MaxStartups 100:30:200/' /etc/ssh/sshd_config

  if sshd -t 2>&1; then
    systemctl restart ssh
    step_ok "SSHD 設定完成" "監聽端口: $CFG_SSH_PORT
⚠ 請勿關閉當前 SSH！先用 Port $CFG_SSH_PORT 測試連線。"
  else
    step_fail "SSHD 設定語法錯誤" "已還原備份，請手動檢查"
    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    return 1
  fi

  # ── Step 2: UFW ──
  step_start "設定防火墻 (UFW)"

  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  # 永遠保留 22 (安全回退) + 自訂 SSH 端口
  ufw allow 22/tcp >/dev/null 2>&1
  ufw allow "$CFG_SSH_PORT/tcp" >/dev/null 2>&1

  # 額外端口
  for port in $DEFAULT_UFW_EXTRA_PORTS; do
    ufw allow "$port" >/dev/null 2>&1
  done

  echo 'y' | ufw enable >/dev/null 2>&1

  local ufw_status
  ufw_status="$(ufw status verbose 2>&1)"
  step_ok "UFW 防火墻已啟用" "$ufw_status"

  # ── Step 3: Fail2ban ──
  step_start "設定 Fail2ban"

  cat > /etc/fail2ban/jail.local <<F2BEOF
[sshd]
enabled = true
port = 22,$CFG_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 10m
bantime = 1h
F2BEOF

  systemctl restart fail2ban

  if systemctl is-active --quiet fail2ban; then
    local f2b_status
    f2b_status="$(fail2ban-client status sshd 2>&1)"
    step_ok "Fail2ban 設定完成" "$f2b_status"
  else
    step_fail "Fail2ban 啟動失敗" "請手動檢查: systemctl status fail2ban"
  fi
}
