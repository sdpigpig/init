#!/usr/bin/env bash
# ═══════════════════════════════════════════
# UI 工具函數 — 色彩、提示框、狀態報告
# ═══════════════════════════════════════════

# ─── 色彩定義 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ─── 畫面元素 ───

print_line() {
  printf "  ${DIM}──────────────────────────────────────────${NC}\n"
}

print_header() {
  local title="$1"
  clear
  echo ""
  printf "${CYAN}${BOLD}"
  echo "  ╔════════════════════════════════════════════╗"
  printf "  ║  %-42s║\n" "$title"
  echo "  ╚════════════════════════════════════════════╝"
  printf "${NC}"
  echo ""
}

print_phase() {
  local title="$1"
  echo ""
  printf "${MAGENTA}${BOLD}  ▶ %s${NC}\n" "$title"
  print_line
}

# ─── 狀態回饋（步驟完成後呼叫）───

step_ok() {
  local title="$1"
  local body="$2"
  printf "\n${GREEN}  ┌─ ✓ %s${NC}\n" "$title"
  if [ -n "$body" ]; then
    while IFS= read -r line; do
      printf "  ${DIM}│${NC} %s\n" "$line"
    done <<< "$body"
  fi
  printf "  ${DIM}└──────────────────────────────────────${NC}\n"
}

step_fail() {
  local title="$1"
  local body="$2"
  printf "\n${RED}  ┌─ ✗ %s${NC}\n" "$title"
  if [ -n "$body" ]; then
    while IFS= read -r line; do
      printf "  ${DIM}│${NC} %s\n" "$line"
    done <<< "$body"
  fi
  printf "  ${DIM}└──────────────────────────────────────${NC}\n"
}

step_info() {
  local title="$1"
  local body="$2"
  printf "\n${CYAN}  ┌─ ℹ %s${NC}\n" "$title"
  if [ -n "$body" ]; then
    while IFS= read -r line; do
      printf "  ${DIM}│${NC} %s\n" "$line"
    done <<< "$body"
  fi
  printf "  ${DIM}└──────────────────────────────────────${NC}\n"
}

# ─── 進度提示（步驟開始時呼叫）───

step_start() {
  printf "${BLUE}  ▸ %s ...${NC}\n" "$1"
}

# ─── 互動式輸入 ───

# 一般輸入（帶預設值，Enter 使用預設）
prompt_input() {
  local __var="$1"
  local __prompt="$2"
  local __default="$3"
  local __input

  if [ -n "$__default" ]; then
    printf "${CYAN}  [?]${NC} %s ${DIM}[預設: %s]${NC}: " "$__prompt" "$__default"
  else
    printf "${CYAN}  [?]${NC} %s: " "$__prompt"
  fi

  read __input

  if [ -z "$__input" ]; then
    if [ -n "$__default" ]; then
      eval "$__var='$__default'"
    else
      printf "${YELLOW}      ⚠ 此欄位為必填${NC}\n"
      prompt_input "$__var" "$__prompt" "$__default"
      return
    fi
  else
    eval "$__var='$__input'"
  fi
}

# 密碼輸入（無預設值，強制二次確認）
prompt_password() {
  local __var="$1"
  local __prompt="$2"
  local __input __confirm

  while true; do
    printf "${CYAN}  [?]${NC} %s: " "$__prompt"
    read -s __input
    echo ""

    if [ -z "$__input" ]; then
      printf "${YELLOW}      ⚠ 密碼不能為空，請重新輸入${NC}\n"
      continue
    fi

    if [ ${#__input} -lt 6 ]; then
      printf "${YELLOW}      ⚠ 密碼至少需要 6 個字元${NC}\n"
      continue
    fi

    printf "${CYAN}  [?]${NC} 請再次確認密碼: "
    read -s __confirm
    echo ""

    if [ "$__input" = "$__confirm" ]; then
      eval "$__var='$__input'"
      printf "${GREEN}      ✓ 密碼確認成功${NC}\n"
      return
    else
      printf "${RED}      ✗ 兩次輸入不一致，請重新輸入${NC}\n"
    fi
  done
}

# Y/N 確認
prompt_confirm() {
  local __prompt="$1"
  local __default="${2:-y}"
  local __answer

  if [ "$__default" = "y" ]; then
    printf "${CYAN}  [?]${NC} %s ${DIM}[Y/n]${NC}: " "$__prompt"
  else
    printf "${CYAN}  [?]${NC} %s ${DIM}[y/N]${NC}: " "$__prompt"
  fi

  read __answer
  __answer="${__answer:-$__default}"

  case "$__answer" in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

# 選單選擇（帶編號清單）
prompt_select() {
  local __var="$1"
  local __prompt="$2"
  shift 2
  local __options=("$@")
  local __i=1

  echo ""
  for opt in "${__options[@]}"; do
    printf "  ${WHITE}%d)${NC} %s\n" "$__i" "$opt"
    __i=$((__i + 1))
  done
  echo ""
  printf "${CYAN}  [?]${NC} %s: " "$__prompt"
  read __choice

  if [ -z "$__choice" ] || [ "$__choice" -lt 1 ] 2>/dev/null || [ "$__choice" -gt "${#__options[@]}" ] 2>/dev/null; then
    eval "$__var='${__options[0]}'"
  else
    eval "$__var='${__options[$((__choice - 1))]}'"
  fi
}

# ─── 暫停等待 ───

pause() {
  echo ""
  read -p "  按 Enter 繼續..."
}
