#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 預設值設定 — 僅包含非機密配置
# 所有密碼皆透過互動式輸入收集
# ═══════════════════════════════════════════

DEFAULT_HOSTNAME='SG'
DEFAULT_SSH_PORT='5522'
DEFAULT_TIMEZONE='Asia/Tokyo'
DEFAULT_SWAP_SIZE='2G'
DEFAULT_USER_NAME='rik'

# UFW 額外開放的端口（SSH 端口會根據 CFG_SSH_PORT 自動加入）
DEFAULT_UFW_EXTRA_PORTS='80/tcp 81/tcp 443/tcp'
