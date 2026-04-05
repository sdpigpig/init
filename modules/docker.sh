#!/usr/bin/env bash
# ═══════════════════════════════════════════
# Phase F：Docker 環境
# Docker 安裝 → 全局日誌控制 → 網路
# ═══════════════════════════════════════════

module_docker_collect() {
  : # 此模組無需收集輸入
}

module_docker_run() {
  print_phase "Phase F：Docker 環境"

  # ── Step 1: 安裝 Docker ──
  step_start "安裝 Docker (這可能需要幾分鐘)"

  curl -fsSL https://get.docker.com | sh

  if ! command -v docker >/dev/null 2>&1; then
    step_fail "Docker 安裝失敗" "請手動執行: curl -fsSL https://get.docker.com | sh"
    return 1
  fi

  # 建立 docker-compose 軟連結
  if [ -f /usr/libexec/docker/cli-plugins/docker-compose ]; then
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
  fi

  systemctl enable --now docker

  local docker_ver
  docker_ver="$(docker --version 2>&1 | awk '{print $3}' | sed 's/,//')"
  local compose_ver
  compose_ver="$(docker compose version 2>&1 | awk '{print $4}')"

  step_ok "Docker 安裝完成" "Docker:  $docker_ver
Compose: $compose_ver
服務狀態: $(systemctl is-active docker)"

  # ── Step 2: 全局日誌控制 ──
  step_start "設定 Docker 全局日誌控制"

  mkdir -p /etc/docker

  cat > /etc/docker/daemon.json <<DJEOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DJEOF

  systemctl restart docker

  local log_driver
  log_driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)"

  step_ok "Docker 全局日誌控制已啟用" "日誌驅動: $log_driver
單檔上限: 10MB × 3 檔 (每容器最多 30MB)
套用範圍: 所有未在 compose 中自訂 logging 的容器"

  # ── Step 3: Docker 網路 ──
  step_start "建立預設 Docker 網路"

  if docker network inspect docker_net >/dev/null 2>&1; then
    step_info "Docker 網路 docker_net 已存在，跳過"
  else
    docker network create docker_net
    step_ok "Docker 網路建立完成" "網路名稱: docker_net"
  fi
}
