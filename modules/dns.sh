#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 附錄：綁定 Cloudflare DNS（可選）
# ⚠ 部分 DNS 管控嚴格的主機（如 GCP）可能
#   在重啟後出現 DNS 解析失敗，請謹慎使用。
# ═══════════════════════════════════════════

module_dns_menu() {
  print_phase "Cloudflare DNS 綁定"

  printf "  ${YELLOW}⚠ 注意：${NC}部分 DNS 管控嚴格的主機（如 GCP）\n"
  printf "           可能在重啟後出現 DNS 解析失敗。\n"
  echo ""
  printf "  ${WHITE}1)${NC} 綁定 Cloudflare DNS\n"
  printf "  ${WHITE}2)${NC} 還原系統 DNS（解除綁定）\n"
  printf "  ${WHITE}0)${NC} 返回主選單\n"
  echo ""
  printf "${CYAN}  [?]${NC} 請選擇: "
  read choice

  case "$choice" in
    1) dns_bind ;;
    2) dns_restore ;;
    0|*) return ;;
  esac
}

dns_bind() {
  step_start "綁定 Cloudflare DNS"

  systemctl disable --now systemd-resolved 2>/dev/null
  chattr -i /etc/resolv.conf 2>/dev/null

  cat > /etc/resolv.conf <<DNSEOF
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
DNSEOF
  chattr +i /etc/resolv.conf

  local dns_body
  dns_body="$(grep nameserver /etc/resolv.conf)"
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    dns_body+=$'\n'"連線測試: OK"
    step_ok "Cloudflare DNS 綁定完成" "$dns_body"
  else
    dns_body+=$'\n'"連線測試: FAIL (可能為網路問題)"
    step_fail "DNS 綁定可能有問題" "$dns_body"
  fi
}

dns_restore() {
  step_start "還原系統 DNS"

  # 解除 immutable 保護
  chattr -i /etc/resolv.conf 2>/dev/null

  # 恢復 systemd-resolved（大多數 Debian 12 的預設機制）
  if systemctl list-unit-files | grep -q systemd-resolved; then
    systemctl enable --now systemd-resolved 2>/dev/null

    # 重建 resolv.conf 軟連結（systemd-resolved 的標準方式）
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null
  fi

  local dns_body
  dns_body="$(grep nameserver /etc/resolv.conf 2>/dev/null)"
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    dns_body+=$'\n'"連線測試: OK"
    step_ok "已還原系統 DNS" "$dns_body"
  else
    dns_body+=$'\n'"連線測試: FAIL (可能需要重啟網路)"
    step_fail "DNS 還原後連線異常" "$dns_body"
  fi
}
