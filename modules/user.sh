#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase G：建立操作員
# 建立用戶 → 加入群組 → /data 目錄
# ═══════════════════════════════════════════

module_user_collect() {
  print_phase "Phase G：建立操作員 — 收集設定"

  prompt_input    CFG_USER_NAME     "操作員用戶名" "$DEFAULT_USER_NAME"
  prompt_password CFG_USER_PASSWORD "設定 $CFG_USER_NAME 的密碼"
}

module_user_run() {
  print_phase "Phase G：建立操作員"

  step_start "建立用戶 $CFG_USER_NAME"

  # 建立用戶（如不存在）
  if ! id "$CFG_USER_NAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$CFG_USER_NAME"
    echo "$CFG_USER_NAME:$CFG_USER_PASSWORD" | chpasswd
  else
    # 用戶已存在，僅更新密碼
    echo "$CFG_USER_NAME:$CFG_USER_PASSWORD" | chpasswd
  fi

  # 加入 sudo 群組（docker 群組可能還不存在）
  usermod -aG sudo "$CFG_USER_NAME" 2>/dev/null
  # 如果 docker 群組存在，一併加入
  if getent group docker >/dev/null 2>&1; then
    usermod -aG docker "$CFG_USER_NAME"
  fi

  # 建立 /data 目錄
  mkdir -p /data
  chown -R "$CFG_USER_NAME:$CFG_USER_NAME" /data
  chmod -R 755 /data

  local user_groups
  user_groups="$(groups "$CFG_USER_NAME" 2>&1)"
  local data_owner
  data_owner="$(ls -ld /data | awk '{print $3":"$4}')"

  step_ok "操作員 $CFG_USER_NAME 配置完成" "用戶群組: $user_groups
數據目錄: /data (所有權: $data_owner)"
}
