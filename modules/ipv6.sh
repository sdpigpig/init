#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 附錄：IPv6 開關（可選）
# ═══════════════════════════════════════════

module_ipv6_menu() {
  print_phase "IPv6 開關"

  printf "  ${WHITE}1)${NC} 關閉 IPv6\n"
  printf "  ${WHITE}2)${NC} 開啟 IPv6\n"
  printf "  ${WHITE}0)${NC} 返回主選單\n"
  echo ""
  printf "${CYAN}  [?]${NC} 請選擇: "
  read choice

  case "$choice" in
    1) ipv6_disable ;;
    2) ipv6_enable ;;
    0|*) return ;;
  esac
}

ipv6_disable() {
  step_start "關閉 IPv6"

  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
  sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1

  # 持久化
  sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
  sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
  sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
  cat >> /etc/sysctl.conf <<IPV6EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
IPV6EOF
  sysctl -p >/dev/null 2>&1

  local ipv6_val
  ipv6_val="$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)"
  local ipv6_addr
  ipv6_addr="$(ip addr show | grep inet6)"

  local body="內核參數 (1=關閉): $ipv6_val"
  if [ -z "$ipv6_addr" ]; then
    body+=$'\n'"IPv6 地址: 已清空 (無 IPv6)"
  else
    body+=$'\n'"$ipv6_addr"
  fi

  step_ok "IPv6 已關閉" "$body"
}

ipv6_enable() {
  step_start "開啟 IPv6"

  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1

  # 持久化
  sed -i 's/net.ipv6.conf.all.disable_ipv6 = 1/net.ipv6.conf.all.disable_ipv6 = 0/g' /etc/sysctl.conf
  sed -i 's/net.ipv6.conf.default.disable_ipv6 = 1/net.ipv6.conf.default.disable_ipv6 = 0/g' /etc/sysctl.conf
  sed -i 's/net.ipv6.conf.lo.disable_ipv6 = 1/net.ipv6.conf.lo.disable_ipv6 = 0/g' /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1

  local ipv6_val
  ipv6_val="$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)"
  local ipv6_addr
  ipv6_addr="$(ip addr show | grep inet6)"

  local body="內核參數 (0=開啟): $ipv6_val"
  if [ -z "$ipv6_addr" ]; then
    body+=$'\n'"IPv6 已啟用，但主機未分配有效 IP"
  else
    body+=$'\n'"$ipv6_addr"
  fi

  step_ok "IPv6 已開啟" "$body"
}
