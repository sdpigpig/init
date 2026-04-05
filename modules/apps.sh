#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase E：應用配置
# Chrony 時區 → FZF 模糊搜尋
# ═══════════════════════════════════════════

module_apps_collect() {
  print_phase "Phase E：應用配置 — 收集設定"

  printf "${DIM}  常用時區: UTC / America/New_York / Asia/Tokyo / Asia/Singapore${NC}\n"
  prompt_input CFG_TIMEZONE "時區" "$DEFAULT_TIMEZONE"
}

module_apps_run() {
  print_phase "Phase E：應用配置"

  # ── Step 1: Chrony + 時區 ──
  step_start "設定時區為 $CFG_TIMEZONE"

  timedatectl set-timezone "$CFG_TIMEZONE" 2>&1

  local tz_body
  tz_body="$(timedatectl 2>&1 | grep -E 'Time zone|Local time|Universal time')"
  tz_body+=$'\n'"────────"
  tz_body+=$'\n'"$(chronyc tracking 2>&1 | grep -E 'Reference ID|System time|Last offset')"

  step_ok "時區與時間同步完成" "$tz_body"

  # ── Step 2: FZF ──
  step_start "設定 FZF 模糊搜尋"

  # 防止重複寫入
  if ! grep -q 'fzf/examples/key-bindings.bash' ~/.bashrc 2>/dev/null; then
    echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> ~/.bashrc
  fi

  step_ok "FZF 設定完成" "快捷鍵: Ctrl+R (歷史搜尋) / Ctrl+T (檔案搜尋)
生效方式: 重新登入或執行 source ~/.bashrc"
}
