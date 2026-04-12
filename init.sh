#!/usr/bin/env bash
# ═══════════════════════════════════════════
#  Init Debian 12 — 互動式 TUI 初始化腳本
#  零依賴，純 Bash + ANSI 色彩
# ═══════════════════════════════════════════
set -o pipefail

# ─── 定位腳本目錄 ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Root 權限檢查 ───
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 請以 root 身份執行此腳本: sudo bash init.sh"
  exit 1
fi

# ─── 載入函式庫 ───
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/config.sh"

# ─── 載入所有模組 ───
for _mod in "$SCRIPT_DIR"/modules/*.sh; do
  source "$_mod"
done

# ═══════════════════════════════════════════
# 主選單
# ═══════════════════════════════════════════

show_menu() {
  print_header "🚀 Init Debian 12"
  printf "  ${BOLD}A${NC} ) 🔧 基礎系統     ${DIM}密碼 / 主機名 / 官方源${NC}\n"
  printf "  ${BOLD}B${NC} ) ⚡ 核心優化     ${DIM}BBR / SWAP / 調優 / Journal${NC}\n"
  printf "  ${BOLD}C${NC} ) 📦 安裝套件\n"
  printf "  ${BOLD}D${NC} ) 🔒 安全加固     ${DIM}SSHD / UFW / Fail2ban${NC}\n"
  printf "  ${BOLD}E${NC} ) 🛠  應用配置     ${DIM}Chrony / FZF${NC}\n"
  printf "  ${BOLD}F${NC} ) 🐳 Docker 環境\n"
  printf "  ${BOLD}G${NC} ) 👤 建立操作員\n"
  echo ""
  print_line
  printf "  ${BOLD}0${NC} ) 🚀 ${GREEN}全部執行 (A → G)${NC}\n"
  printf "  ${BOLD}N${NC} ) 🌐 Cloudflare DNS ${DIM}可選 (GCP 等嚴格環境慎用)${NC}\n"
  printf "  ${BOLD}I${NC} ) 🌐 IPv6 開關     ${DIM}可選${NC}\n"
  printf "  ${BOLD}Q${NC} ) 退出\n"
  echo ""
}

# ═══════════════════════════════════════════
# 全部執行模式
# ═══════════════════════════════════════════

run_all() {
  print_header "📋 收集全部設定"
  printf "${DIM}  以下將依序詢問所有需要的設定，全部收集完畢後才開始執行。${NC}\n"
  echo ""

  # ── 收集所有互動輸入 ──
  module_base_collect
  module_optimize_collect
  module_security_collect
  module_apps_collect
  module_user_collect

  # ── 顯示設定預覽 ──
  print_header "📋 設定確認"
  printf "  ${WHITE}Root 密碼:${NC}   ${DIM}(已輸入，隱藏顯示)${NC}\n"
  printf "  ${WHITE}主機名:${NC}     %s\n" "$CFG_HOSTNAME"
  printf "  ${WHITE}SSH 端口:${NC}   %s\n" "$CFG_SSH_PORT"
  printf "  ${WHITE}SWAP 大小:${NC}  %s\n" "$CFG_SWAP_SIZE"
  printf "  ${WHITE}時區:${NC}       %s\n" "$CFG_TIMEZONE"
  printf "  ${WHITE}操作員:${NC}     %s\n" "$CFG_USER_NAME"
  printf "  ${WHITE}操作員密碼:${NC} ${DIM}(已輸入，隱藏顯示)${NC}\n"
  echo ""

  if ! prompt_confirm "以上設定正確，開始執行？"; then
    printf "${YELLOW}  已取消${NC}\n"
    return
  fi

  # ── 依序執行所有模組 ──
  module_base_run
  module_optimize_run
  module_packages_run
  module_security_run
  module_apps_run
  module_docker_run
  module_user_run

  # ── 完成報告 ──
  print_header "🎉 全部完成！"
  printf "  ${GREEN}所有初始化步驟已執行完畢。${NC}\n"
  echo ""
  printf "  ${YELLOW}⚠ 重要提醒：${NC}\n"
  printf "    1. 請開一個新終端，用 Port ${WHITE}%s${NC} 測試 SSH 連線\n" "$CFG_SSH_PORT"
  printf "    2. 確認能登入後再關閉當前終端\n"
  printf "    3. 建議重啟一次以確保所有設定生效: ${WHITE}reboot${NC}\n"
  echo ""
}

# ═══════════════════════════════════════════
# 單一模組執行（收集 + 執行）
# ═══════════════════════════════════════════

run_single() {
  local module="$1"

  case "$module" in
    base)
      module_base_collect && module_base_run ;;
    optimize)
      module_optimize_collect && module_optimize_run ;;
    packages)
      module_packages_run ;;
    security)
      module_security_collect && module_security_run ;;
    apps)
      module_apps_collect && module_apps_run ;;
    docker)
      module_docker_run ;;
    user)
      module_user_collect && module_user_run ;;
    ipv6)
      module_ipv6_menu ;;
    dns)
      module_dns_menu ;;
  esac
}

# ═══════════════════════════════════════════
# 主迴圈
# ═══════════════════════════════════════════

while true; do
  show_menu
  printf "${CYAN}  [?]${NC} 請選擇: "
  read choice

  case "$choice" in
    [aA]) run_single base ;;
    [bB]) run_single optimize ;;
    [cC]) run_single packages ;;
    [dD]) run_single security ;;
    [eE]) run_single apps ;;
    [fF]) run_single docker ;;
    [gG]) run_single user ;;
    0)    run_all ;;
    [nN]) run_single dns ;;
    [iI]) run_single ipv6 ;;
    [qQ]) printf "\n  ${DIM}Bye!${NC}\n"; exit 0 ;;
    *)    printf "${YELLOW}  無效選擇，請重新輸入${NC}\n" ;;
  esac

  pause
done
