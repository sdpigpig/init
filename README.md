# Init Debian 12

互動式 TUI 腳本，用於全新 VPS（DD 或原裝 Debian 12）的一鍵初始化。

## 功能

| Phase | 內容 |
|-------|------|
| A | 🔧 Root 密碼、主機名、Cloudflare DNS、官方源升級 |
| B | ⚡ BBR 網路優化、SWAP、系統調優、Journal 日誌限制 |
| C | 📦 安裝基礎工具包 |
| D | 🔒 SSHD 改 Port → UFW 防火墻 → Fail2ban |
| E | 🛠 Chrony 時區 + FZF 模糊搜尋 |
| F | 🐳 Docker 安裝 + 全局日誌控制 + 網路 |
| G | 👤 建立操作員用戶 + /data 目錄 |

## 快速開始

DD 完畢、SSH 登入 root 後，執行這一行：

```bash
apt update && apt install -y curl && mkdir -p /opt/init && curl -fsSL https://github.com/sdpigpig/init/archive/refs/heads/main.tar.gz | tar xz --strip-components=1 -C /opt/init && cd /opt/init && bash init.sh
```

> **提示**：腳本解壓到 `/opt/init-debian`，不會弄亂 `~` 目錄。

## 使用方式

- 選 `0` → 全部執行（先收集所有設定，確認後一氣呵成）
- 選 `A`~`G` → 單獨執行某個模組
- 選 `I` → IPv6 開關（可選）
- 選 `Q` → 退出

## 檔案結構

```
init-debian/
├── init.sh              # 主入口
├── lib/
│   ├── ui.sh            # TUI 色彩與互動函數
│   └── config.sh        # 預設值（無密碼）
└── modules/
    ├── base.sh          # Phase A
    ├── optimize.sh      # Phase B
    ├── packages.sh      # Phase C
    ├── security.sh      # Phase D
    ├── apps.sh          # Phase E
    ├── docker.sh        # Phase F
    ├── user.sh          # Phase G
    └── ipv6.sh          # 附錄
```

## 密碼安全

- 所有密碼皆為執行時互動輸入，**不存儲在任何檔案中**
- 密碼輸入採用靜默模式（不回顯）+ 二次確認
- 預設值（主機名、端口等非機密設定）集中於 `lib/config.sh`

## 需求

- Debian 12 (Bookworm)
- root 權限
- 網路連線
