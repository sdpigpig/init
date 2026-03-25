#!/bin/bash

# ==========================================
# Debian 12 Server Init
# ==========================================

# 確保腳本以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 root 權限執行此腳本 (sudo bash init.sh)"
    exit 1
fi

# 檢查是否已安裝 gum，若無則自動安裝 (Bootstrap)
if ! command -v gum &> /dev/null; then
    echo "🔄 偵測到系統尚未安裝 gum，正在為您自動安裝基礎環境..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl gnupg
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
    apt-get update -y
    apt-get install -y gum
    
    if ! command -v gum &> /dev/null; then
        echo "❌ gum 自動安裝失敗，請檢查網路或手動排除問題。"
        exit 1
    fi
    echo "✅ 基礎環境安裝完成！即將啟動外腦..."
    sleep 1
fi

# --- UI 樣式設定 ---
COLOR_PRIMARY="212"   # 粉紫色 (主題色)
COLOR_SUCCESS="46"    # 綠色
COLOR_ERROR="196"     # 紅色
COLOR_WARN="214"      # 橘黃色

print_header() {
    clear
    gum style --border normal --margin "1" --padding "1 2" --border-foreground $COLOR_PRIMARY --bold "$1"
}

print_success() {
    gum style --foreground $COLOR_SUCCESS "✅ $1"
}

print_error() {
    gum style --foreground $COLOR_ERROR "❌ $1"
}

print_warn() {
    gum style --foreground $COLOR_WARN "⚠️ $1"
}

pause_to_return() {
    echo ""
    gum style --foreground 240 "按 Enter 鍵返回主選單..."
    read -r
}

# ==========================================
# 模組功能區 (Functions)
# ==========================================

# 1. 修改 Root 密碼
fn_change_password() {
    print_header "🔑 修改 Root 密碼"
    
    echo "請貼上您的強密碼 (輸入時不會顯示字元)："
    NEW_PASS=$(gum input --password --placeholder "請輸入新密碼...")
    # 檢測是否按下 ESC
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    echo "請再次輸入以確認："
    CONFIRM_PASS=$(gum input --password --placeholder "請再次輸入新密碼...")
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    if [ -z "$NEW_PASS" ]; then
        print_error "密碼不能為空！已取消修改。"
    elif [ "$NEW_PASS" == "$CONFIRM_PASS" ]; then
        # 靜默修改密碼
        echo "root:$NEW_PASS" | chpasswd
        if [ $? -eq 0 ]; then
            print_success "Root 密碼修改成功！"
        else
            print_error "密碼修改失敗，請檢查系統日誌。"
        fi
    else
        print_error "兩次輸入的密碼不一致！已取消修改。"
    fi
    pause_to_return
}

# 2. 基礎工具、時區與微調
fn_install_base() {
    print_header "🛠️ 安裝基礎工具與系統微調 (+Fail2ban)"

    # [互動階段] 選擇時區
    echo "請問要將伺服器設定為哪個時區？"
    TZ_CHOICE=$(gum choose "UTC (世界協調時間)" "Asia/Taipei (台北)" "Asia/Tokyo (東京)" "Asia/Singapore (新加坡)" "Asia/Hong_Kong (香港)" "America/New_York (紐約)" "Europe/London (倫敦)" "自訂輸入" "略過時區設定")
    
    # 檢測是否按下 ESC
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    if [ "$TZ_CHOICE" == "略過時區設定" ]; then
        TZ=""
        print_warn "將略過時區修改。"
    elif [ "$TZ_CHOICE" == "自訂輸入" ]; then
        TZ=$(gum input --placeholder "例如: Asia/Tokyo")
        if [ $? -ne 0 ] || [ -z "$TZ" ]; then
            print_warn "已取消操作，返回主選單。"
            pause_to_return
            return
        fi
    else
        # 萃取英文時區名稱
        TZ=$(echo "$TZ_CHOICE" | awk '{print $1}')
    fi

    echo ""
    gum spin --spinner dot --title "正在更新 apt 索引..." -- \
        bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -y > /dev/null 2>&1"
    print_success "apt 索引更新完成"

    echo ""
    TOOLS=("wget" "nano" "btop" "tmux" "fzf" "chrony" "fail2ban" "rsyslog")
    TOTAL=${#TOOLS[@]}
    COUNT=0
    for tool in "${TOOLS[@]}"; do
        COUNT=$((COUNT + 1))
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y "$tool" > /dev/null 2>&1
        if dpkg -s "$tool" > /dev/null 2>&1; then
            echo " [${COUNT}/${TOTAL}] ✅ ${tool}"
        else
            echo " [${COUNT}/${TOTAL}] ❌ ${tool} (安裝失敗)"
        fi
    done
    echo ""
    print_success "基礎工具安裝流程完成！"

    # 重啟 rsyslog 以生成 auth.log，接著再啟動 Fail2ban (防禦 SSH 爆破)
    systemctl restart rsyslog > /dev/null 2>&1
    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1

    # 設定時區與 Chrony
    if [ -n "$TZ" ]; then
        timedatectl set-timezone "$TZ"
        systemctl restart chrony
        systemctl enable chrony > /dev/null 2>&1
    else
        systemctl restart chrony
        systemctl enable chrony > /dev/null 2>&1
    fi

    # 強化修改 DNS 的邏輯 (處理 resolv.conf 被鎖定或為軟連結的問題)
    if systemctl is-active --quiet systemd-resolved; then
        mkdir -p /etc/systemd/resolved.conf.d
        echo -e "[Resolve]\nDNS=8.8.8.8 1.1.1.1" > /etc/systemd/resolved.conf.d/custom-dns.conf
        systemctl restart systemd-resolved
    else
        # 解除不可變屬性 (不報錯)
        chattr -i /etc/resolv.conf 2>/dev/null
        # 強制刪除軟連結
        rm -f /etc/resolv.conf
        # 寫入 DNS
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
        # 重新鎖定，防止重啟被 DHCP 覆蓋
        chattr +i /etc/resolv.conf 2>/dev/null
    fi

    # 精簡 Bash 主機名顯示與 Alias (僅針對 root)
    if ! grep -q "alias ll=" ~/.bashrc; then
        echo "alias ll='ls -alF'" >> ~/.bashrc
        echo "alias la='ls -A'" >> ~/.bashrc
    fi

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 設定結果驗證報告："

    # 1. 檢查時區
    CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "無法取得")
    echo " 🕒 系統時區: $(gum style --foreground "$COLOR_SUCCESS" "$CURRENT_TZ")"

    # 2. 檢查 Chrony 狀態
    if systemctl is-active --quiet chrony; then
        echo " ⏱️  NTP 服務 (chrony): $(gum style --foreground "$COLOR_SUCCESS" "運行中 (active)")"
    else
        echo " ⏱️  NTP 服務 (chrony): $(gum style --foreground "$COLOR_ERROR" "未運行")"
    fi

    # 3. 檢查 DNS
    CURRENT_DNS=$(grep -m 2 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || echo "無法取得")
    echo " 🌐 系統 DNS: $(gum style --foreground "$COLOR_SUCCESS" "$CURRENT_DNS")"

    # 4. 檢查 Alias
    if grep -q "alias ll=" ~/.bashrc; then
        echo " 💻 Root Bash Alias: $(gum style --foreground "$COLOR_SUCCESS" "已生效")"
    else
        echo " 💻 Root Bash Alias: $(gum style --foreground "$COLOR_ERROR" "未生效")"
    fi

    # 5. 檢查 Fail2ban
    if systemctl is-active --quiet fail2ban; then
        echo " 🛡️  防爆破 (fail2ban): $(gum style --foreground "$COLOR_SUCCESS" "運行中 (active)")"
    else
        echo " 🛡️  防爆破 (fail2ban): $(gum style --foreground "$COLOR_ERROR" "未運行 (可能是缺少日誌檔，建議重啟後再確認)")"
    fi

    pause_to_return
}

# 3. 修改主機名稱 Hostname
fn_change_hostname() {
    print_header "🌐 修改主機名稱 Hostname"

    CURRENT_HOSTNAME=$(hostname)
    echo "當前主機名稱為: $(gum style --foreground "$COLOR_WARN" "$CURRENT_HOSTNAME")"
    
    NEW_HOSTNAME=$(gum input --placeholder "請輸入新的主機名稱 (例如: web-server-01)...")
    if [ $? -ne 0 ] || [ -z "$NEW_HOSTNAME" ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    # 防呆：檢查是否包含非法字元 (只允許英數字與連字號)
    if [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_error "主機名稱只能包含英文字母、數字與連字號 (-)。"
        pause_to_return
        return
    fi

    # 防呆：保留字排除列表 (避免與 /etc/hosts 關鍵字或常見系統名稱衝突)
    RESERVED_NAMES=("localhost" "ip6-localhost" "ip6-loopback" "ip6-localnet" "ip6-mcastprefix" "ip6-allnodes" "ip6-allrouters" "ip6-allhosts" "broadcasthost")
    for reserved in "${RESERVED_NAMES[@]}"; do
        if [ "${NEW_HOSTNAME,,}" == "${reserved,,}" ]; then
            print_error "'$NEW_HOSTNAME' 是系統保留名稱，請選擇其他主機名稱。"
            pause_to_return
            return
        fi
    done

    gum spin --spinner dot --title "正在套用新主機名稱..." -- \
        bash -c "hostnamectl set-hostname \"$NEW_HOSTNAME\" && sed -i \"s/\\b$CURRENT_HOSTNAME\\b/$NEW_HOSTNAME/g\" /etc/hosts"

    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 主機名稱驗證報告："
    echo " 🏷️  新主機名稱: $(gum style --foreground "$COLOR_SUCCESS" "$(hostname)")"
    
    if grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo " 📝 /etc/hosts 替換: $(gum style --foreground "$COLOR_SUCCESS" "成功 (避免 sudo 指令變慢)")"
    else
        echo " 📝 /etc/hosts 替換: $(gum style --foreground "$COLOR_ERROR" "未找到或替換失敗，可能需手動檢查")"
    fi
    print_warn "提示：新的主機名稱需要您重新登入 SSH 才會在命令提示字元中生效顯示。"

    pause_to_return
}

# 4. 內核與網路進階優化
fn_optimize_sysctl() {
    print_header "🚀 內核與網路進階優化"
    
    # 顯示當前狀態，讓使用者知道是否需要優化
    echo "【當前系統狀態預覽】"
    CURRENT_BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    echo " 🏎️  TCP BBR: $(gum style --foreground "$COLOR_WARN" "${CURRENT_BBR:-未啟用}")"
    
    CURRENT_IPV6=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
    if [ "$CURRENT_IPV6" == "1" ]; then
        echo " 🌐 IPv6 狀態: $(gum style --foreground "$COLOR_WARN" "已關閉")"
    else
        echo " 🌐 IPv6 狀態: $(gum style --foreground "$COLOR_WARN" "開啟中")"
    fi
    
    CURRENT_ULIMIT=$(ulimit -n 2>/dev/null)
    echo " 📂 用戶層級句柄限制 (ulimit -n): $(gum style --foreground "$COLOR_WARN" "${CURRENT_ULIMIT:-未知}")"
    echo "----------------------------------------"
    echo ""

    gum style --foreground 240 "操作提示：請使用 [上下鍵] 移動，按 [空白鍵] 勾選 (左邊會出現 x)，全部勾選完後再按 [Enter] 確認執行。"
    OPTS=$(gum choose --no-limit "1. 開啟 TCP BBR 壅塞控制 (提升網路吞吐量)" "2. 關閉 IPv6 (若無需求可關閉，避免 DNS 路由問題)" "3. 提升用戶層級句柄限制 (nofile → 65535, 高併發必備)")
    
    # 檢查是否按了 ESC
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    # 檢查是否真的有「打勾」
    if [ -z "$OPTS" ]; then
        print_warn "您沒有勾選任何項目！(記得一定要按 [空白鍵] 讓選項左側出現 x)"
        pause_to_return
        return
    fi

    echo ""
    # 建立暫存標記 (不加引號以便在母 Shell 解析)
    DO_BBR=0
    DO_IPV6=0
    DO_FD=0

    if echo "$OPTS" | grep -q "BBR"; then DO_BBR=1; fi
    if echo "$OPTS" | grep -q "IPv6"; then DO_IPV6=1; fi
    if echo "$OPTS" | grep -q "nofile"; then DO_FD=1; fi

    gum spin --spinner dot --title "正在套用內核與系統配置..." -- bash -c "
        # 1. BBR (修復: 強制載入模組並寫入設定)
        if [ $DO_BBR -eq 1 ]; then
            modprobe tcp_bbr 2>/dev/null
            grep -q 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
            grep -q 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
        fi
        
        # 2. IPv6
        if [ $DO_IPV6 -eq 1 ]; then
            grep -q 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
            grep -q 'net.ipv6.conf.default.disable_ipv6 = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf
            grep -q 'net.ipv6.conf.lo.disable_ipv6 = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf
        fi
        
        # 3. 用戶層級句柄限制 (Debian 12 系統層級 fs.file-max 預設已極大，無需調整)
        if [ $DO_FD -eq 1 ]; then
            # 只調整用戶層級 nofile，這才是實際影響應用程式的限制
            grep -q '^\* soft nofile' /etc/security/limits.conf || echo '* soft nofile 65535' >> /etc/security/limits.conf
            grep -q '^\* hard nofile' /etc/security/limits.conf || echo '* hard nofile 65535' >> /etc/security/limits.conf
            grep -q '^root soft nofile' /etc/security/limits.conf || echo 'root soft nofile 65535' >> /etc/security/limits.conf
            grep -q '^root hard nofile' /etc/security/limits.conf || echo 'root hard nofile 65535' >> /etc/security/limits.conf
        fi
        
        sysctl -p > /dev/null 2>&1
    "

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 內核優化驗證報告："

    if [ $DO_BBR -eq 1 ]; then
        BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
        if [ "$BBR_STATUS" == "bbr" ]; then
            echo " 🏎️  TCP BBR: $(gum style --foreground "$COLOR_SUCCESS" "已啟用 ($BBR_STATUS)")"
        else
            echo " 🏎️  TCP BBR: $(gum style --foreground "$COLOR_ERROR" "未啟用 (請確認內核是否支援)")"
        fi
    fi

    if [ $DO_IPV6 -eq 1 ]; then
        IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
        if [ "$IPV6_STATUS" == "1" ]; then
            echo " 🌐 IPv6 狀態: $(gum style --foreground "$COLOR_SUCCESS" "已關閉")"
        else
            echo " 🌐 IPv6 狀態: $(gum style --foreground "$COLOR_ERROR" "未能完全關閉")"
        fi
    fi

    if [ $DO_FD -eq 1 ]; then
        echo " 📂 用戶層級句柄 (nofile): $(gum style --foreground "$COLOR_SUCCESS" "已設定為 65535")"
        print_warn "提示：ulimit -n 需要重新登入 SSH 才會顯示為 65535。"
    fi

    pause_to_return
}

# 5. 設定虛擬記憶體 Swap
fn_setup_swap() {
    print_header "💾 設定虛擬記憶體 Swap"

    # 檢查當前 Swap
    CURRENT_SWAP=$(swapon --show --noheadings | wc -l)
    if [ "$CURRENT_SWAP" -gt 0 ]; then
        print_warn "系統目前已經有啟用 Swap，資訊如下："
        swapon --show
        echo ""
        gum confirm "確定要繼續並覆蓋/重建 Swap 嗎？"
        if [ $? -ne 0 ]; then
            print_warn "已取消操作，返回主選單。"
            pause_to_return
            return
        fi
    else
        echo "當前系統 $(gum style --foreground "$COLOR_WARN" "尚未配置 Swap")。"
    fi

    echo "請選擇要建立的 Swap 檔案大小："
    SWAP_SIZE=$(gum choose "1G" "2G" "4G" "8G" "取消")
    if [ $? -ne 0 ] || [ "$SWAP_SIZE" == "取消" ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    echo "請輸入虛擬記憶體活躍度 (Swappiness)。"
    echo "提示：數值 0~100，越低表示越傾向使用實體記憶體。伺服器推薦設為 10。"
    SWAPPINESS=$(gum input --value "10" --placeholder "輸入數字 (例如: 10)")
    if [ $? -ne 0 ] || [ -z "$SWAPPINESS" ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    echo ""
    gum spin --spinner dot --title "正在建立並啟用 ${SWAP_SIZE} Swap 空間 (這可能需要幾秒鐘)..." -- bash -c "
        # 關閉並刪除舊的 Swap (如果有的話)
        swapoff -a
        rm -f /swapfile
        
        # 嘗試用 fallocate 快速建立，若失敗則改用 dd
        fallocate -l ${SWAP_SIZE} /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$(echo ${SWAP_SIZE} | sed 's/G/ * 1024/' | bc) status=none
        
        # 設定權限與格式化
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null 2>&1
        swapon /swapfile
        
        # 寫入 fstab 確保重啟生效
        sed -i '/\/swapfile/d' /etc/fstab
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        
        # 設定 Swappiness
        sysctl vm.swappiness=${SWAPPINESS} > /dev/null 2>&1
        sed -i '/vm.swappiness/d' /etc/sysctl.conf
        echo \"vm.swappiness=${SWAPPINESS}\" >> /etc/sysctl.conf
    "

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 Swap 設定驗證報告："

    NEW_SWAP_SIZE=$(free -h | awk '/^Swap:/ {print $2}')
    if [ "$NEW_SWAP_SIZE" != "0B" ] && [ -n "$NEW_SWAP_SIZE" ]; then
        echo " 💾 Swap 總容量: $(gum style --foreground "$COLOR_SUCCESS" "$NEW_SWAP_SIZE")"
        echo " ⚙️  Swappiness 活躍度: $(gum style --foreground "$COLOR_SUCCESS" "$(cat /proc/sys/vm/swappiness)")"
        
        if grep -q "/swapfile none swap" /etc/fstab; then
             echo " 📝 /etc/fstab 寫入: $(gum style --foreground "$COLOR_SUCCESS" "成功 (重啟後依然有效)")"
        fi
    else
        echo " 💾 Swap 狀態: $(gum style --foreground "$COLOR_ERROR" "建立或啟用失敗")"
    fi

    pause_to_return
}

# 6. 配置 UFW 防火牆
fn_setup_ufw() {
    print_header "🔥 配置 UFW 防火牆"

    # 確保 ufw 已安裝
    if ! command -v ufw &> /dev/null; then
        gum spin --spinner dot --title "正在安裝 UFW 防火牆..." -- apt-get install -y ufw
    fi

    # 定義顯示狀態的函數，方便多處呼叫
    show_ufw_status() {
        gum style --foreground "$COLOR_PRIMARY" --bold "【當前防火牆狀態清單】"
        echo "──────────────────────────────────────"
        if LC_ALL=C ufw status 2>/dev/null | grep -qw active; then
            ufw status numbered
        else
            gum style --foreground "$COLOR_WARN" "UFW 尚未啟用 (目前處於全放行狀態，首次新增規則時將自動啟用並切換為預設拒絕)"
        fi
        echo "──────────────────────────────────────"
        echo ""
    }

    # 進入主選單時先印出一次清單
    show_ufw_status

    UFW_ACTION=$(gum choose "1. ➕ 新增放行規則 (Port)" "2. ➖ 刪除現有規則" "3. 返回主選單")
    if [ $? -ne 0 ]; then
        return
    fi

    if [[ "$UFW_ACTION" == "1"* ]]; then
        # 點進新增規則後，清空畫面並再次印出清單 (避免被 gum choose 擠掉)
        print_header "➕ 新增放行規則 (Port)"
        show_ufw_status

        echo "請輸入需要開放的 Ports (例如: 80,443,5522)。如果留空按 Enter，預設將放行 22："
        EXTRA_PORTS=$(gum input --placeholder "以逗號分隔，留空則開 22...")
        
        if [ $? -ne 0 ]; then
            print_warn "已取消操作，返回主選單。"
            pause_to_return
            return
        fi

        # 端口格式驗證 (只允許數字和逗號)
        if [ -n "$EXTRA_PORTS" ]; then
            CLEAN_PORTS=$(echo "$EXTRA_PORTS" | tr -d ' ')
            if [[ ! "$CLEAN_PORTS" =~ ^[0-9,]+$ ]]; then
                print_error "端口格式錯誤！只能輸入數字與逗號 (例如: 80,443,5522)。"
                pause_to_return
                return
            fi
        fi

        export EXTRA_PORTS
        gum spin --spinner dot --title "正在設定防火牆規則..." -- bash -c '
            # 如果是初次設定 (尚未 enable)，先做基礎配置
            if ! LC_ALL=C ufw status | grep -qw active; then
                ufw --force reset > /dev/null 2>&1
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                ufw --force enable > /dev/null 2>&1
            fi
            
            # 如果輸入為空，預設開啟 22
            if [ -z "$EXTRA_PORTS" ]; then
                ufw allow 22/tcp > /dev/null 2>&1
            else
                # 處理使用者額外輸入的 Ports
                IFS="," read -ra PORT_ARRAY <<< "$EXTRA_PORTS"
                for PORT in "${PORT_ARRAY[@]}"; do
                    # 移除前後空白字元
                    PORT=$(echo "$PORT" | xargs)
                    if [ -n "$PORT" ]; then
                        ufw allow "$PORT" > /dev/null 2>&1
                    fi
                done
            fi
        '
    elif [[ "$UFW_ACTION" == "2"* ]]; then
        if ! LC_ALL=C ufw status | grep -qw active; then
            print_error "UFW 尚未啟用，無規則可刪除。"
            pause_to_return
            return
        fi
        
        # 抓取有編號的規則清單
        RULE_LINES=$(ufw status numbered | grep -E "^\[[ 0-9]+\]")
        if [ -z "$RULE_LINES" ]; then
            print_warn "目前沒有任何防火牆規則。"
            pause_to_return
            return
        fi
        
        print_header "➖ 刪除現有規則"
        echo "請使用 [空白鍵] 勾選要刪除的規則，全部勾選完後按 [Enter] 確認："
        SELECTED_RULES=$(echo "$RULE_LINES" | gum choose --no-limit --height 15)
        
        if [ $? -ne 0 ] || [ -z "$SELECTED_RULES" ]; then
            print_warn "已取消或未選擇任何規則。"
            pause_to_return
            return
        fi
        
        export SELECTED_RULES
        gum spin --spinner dot --title "正在刪除防火牆規則..." -- bash -c '
            # 提取數字並由大到小排序 (從後面刪除才不會影響前面的編號順序)
            NUMS=$(echo "$SELECTED_RULES" | grep -oE "^\[[0-9]+\]" | tr -d "[]" | sort -nr)
            for NUM in $NUMS; do
                ufw --force delete $NUM > /dev/null 2>&1
            done
        '
        print_success "選擇的規則已刪除！"
    else
        return
    fi

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 UFW 防火牆操作後狀態："
    echo "--------------------------------------------------"
    ufw status verbose
    echo "--------------------------------------------------"

    pause_to_return
}

# 7. 安裝 Docker 與 Docker Compose
fn_install_docker() {
    print_header "🐳 安裝 Docker 與 Docker Compose"

    gum confirm "即將使用 Docker 官方腳本 (get.docker.com) 進行安裝，這需要幾分鐘的時間。是否繼續？"
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi

    echo ""
    # 執行官方安裝腳本，並將輸出導向日誌檔保持畫面乾淨
    gum spin --spinner dot --title "正在下載並執行 Docker 安裝腳本，請稍候 (約需 1~3 分鐘)..." -- \
        bash -c "curl -fsSL https://get.docker.com | sh > /var/log/docker_install.log 2>&1"

    if command -v docker &> /dev/null; then
        print_success "Docker 安裝成功！"
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker > /dev/null 2>&1
    else
        print_error "Docker 安裝似乎失敗了，請檢查 /var/log/docker_install.log 了解詳情。"
        pause_to_return
        return
    fi

    # 設定全域 Alias (讓所有用戶登入都能使用 docker-compose 指令)
    echo "alias docker-compose='docker compose'" > /etc/profile.d/docker-compose-alias.sh
    chmod +x /etc/profile.d/docker-compose-alias.sh

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 Docker 安裝驗證報告："

    # 1. 檢查 Docker 服務狀態
    if systemctl is-active --quiet docker; then
        echo " 🐳 Docker 服務: $(gum style --foreground "$COLOR_SUCCESS" "運行中 (active)")"
    else
        echo " 🐳 Docker 服務: $(gum style --foreground "$COLOR_ERROR" "未運行")"
    fi

    # 2. 檢查版本
    DOCKER_VER=$(docker --version 2>/dev/null || echo "無法取得")
    echo " 🏷️  Docker 版本: $(gum style --foreground "$COLOR_SUCCESS" "$DOCKER_VER")"

    COMPOSE_VER=$(docker compose version 2>/dev/null || echo "無法取得")
    echo " 📦 Compose 版本: $(gum style --foreground "$COLOR_SUCCESS" "$COMPOSE_VER")"

    # 3. 檢查全域 Alias
    if [ -f /etc/profile.d/docker-compose-alias.sh ]; then
        echo " 💻 全域 Alias (docker-compose): $(gum style --foreground "$COLOR_SUCCESS" "已生效 (下次載入 profile 後可用)")"
    else
        echo " 💻 全域 Alias (docker-compose): $(gum style --foreground "$COLOR_ERROR" "未生效")"
    fi

    pause_to_return
}

# 8. 建立與管理系統用戶
fn_manage_user() {
    print_header "👤 建立與管理系統用戶"

    USER_ACTION=$(gum choose "1. ➕ 建立新用戶" "2. ➖ 刪除現有用戶" "3. 返回主選單")
    if [ $? -ne 0 ]; then
        return
    fi

    if [[ "$USER_ACTION" == "1"* ]]; then
        echo "請輸入要建立的新用戶名稱 (例如: admin, deploy):"
        NEW_USER=$(gum input --placeholder "請輸入全小寫英文數字...")
        if [ $? -ne 0 ] || [ -z "$NEW_USER" ]; then print_warn "已取消操作。"; pause_to_return; return; fi

        if id "$NEW_USER" &>/dev/null; then
            print_error "用戶 '$NEW_USER' 已經存在！請選擇其他名稱。"
            pause_to_return
            return
        fi

        echo "請為 '$NEW_USER' 設定密碼："
        USER_PASS=$(gum input --password --placeholder "請輸入密碼...")
        if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi

        echo "請再次輸入密碼以確認："
        CONFIRM_PASS=$(gum input --password --placeholder "請再次輸入密碼...")
        if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi

        if [ -z "$USER_PASS" ]; then
            print_error "密碼不能為空！已取消建立。"
            pause_to_return
            return
        elif [ "$USER_PASS" != "$CONFIRM_PASS" ]; then
            print_error "兩次輸入的密碼不一致！已取消建立。"
            pause_to_return
            return
        fi

        # 擷取系統現有群組讓使用者選擇 (優化體驗：過濾掉多數無用的底層系統群組，僅保留常用提權與一般用戶群組)
        echo "請使用 [空白鍵] 勾選要加入的群組 (可直接打字過濾，建議勾選 sudo)："
        ALL_GROUPS=$(getent group | awk -F: '$3 >= 1000 || $1 ~ /^(sudo|docker|root|adm|www-data|users)$/ {print $1}' | sort)
        SELECTED_GROUPS=$(echo "$ALL_GROUPS" | gum choose --no-limit --height 10)
        
        if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi

        echo ""
        export NEW_USER USER_PASS SELECTED_GROUPS
        gum spin --spinner dot --title "正在建立用戶並分配權限..." -- bash -c '
            useradd -m -s /bin/bash "$NEW_USER"
            echo "$NEW_USER:$USER_PASS" | chpasswd
            
            if [ -n "$SELECTED_GROUPS" ]; then
                # 將換行符號替換成逗號
                GROUP_LIST=$(echo "$SELECTED_GROUPS" | tr "\n" "," | sed "s/,$//")
                usermod -aG "$GROUP_LIST" "$NEW_USER"
            fi
        '

        # ----------------------------------------
        # 輸出建立報告
        # ----------------------------------------
        echo ""
        gum style --foreground "$COLOR_PRIMARY" --bold "📊 用戶建立驗證報告："
        if id "$NEW_USER" &>/dev/null; then
            echo " 👤 用戶名稱: $(gum style --foreground "$COLOR_SUCCESS" "$NEW_USER (建立成功)")"
            echo " 👥 所屬群組: $(gum style --foreground "$COLOR_WARN" "$(groups "$NEW_USER" | cut -d: -f2)")"
        else
            echo " 👤 用戶名稱: $(gum style --foreground "$COLOR_ERROR" "建立失敗")"
        fi

    elif [[ "$USER_ACTION" == "2"* ]]; then
        # 擷取一般用戶 (UID >= 1000)，並排除 nobody
        NORMAL_USERS=$(awk -F: '($3>=1000 && $1!="nobody" && $1!="root") {print $1}' /etc/passwd)
        if [ -z "$NORMAL_USERS" ]; then
            print_warn "系統中目前沒有可刪除的一般用戶 (UID >= 1000)。"
            pause_to_return
            return
        fi

        echo "請選擇要刪除的用戶 (單選)："
        DEL_USER=$(echo "$NORMAL_USERS" | gum choose --height 10)
        if [ $? -ne 0 ] || [ -z "$DEL_USER" ]; then print_warn "已取消操作。"; pause_to_return; return; fi

        gum confirm "警告：確定要刪除用戶 '$DEL_USER' 及其所有家目錄資料嗎？此操作不可逆！"
        if [ $? -ne 0 ]; then
            print_warn "已取消刪除。"
            pause_to_return
            return
        fi

        echo ""
        gum spin --spinner dot --title "正在刪除用戶..." -- bash -c "userdel -r \"$DEL_USER\" > /dev/null 2>&1"
        
        if ! id "$DEL_USER" &>/dev/null; then
            print_success "用戶 '$DEL_USER' 已成功刪除！"
        else
            print_error "刪除失敗，該用戶可能仍有處理程序正在執行中。"
        fi
    fi

    pause_to_return
}

# 9. SSH 安全與端口修改
fn_setup_ssh() {
    print_header "🛡️ SSH 安全與端口修改"

    # 抓取當前 Port (優先取未被註解的有效行)
    CURRENT_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    if [ -z "$CURRENT_PORT" ]; then
        CURRENT_PORT=22
    fi
    
    echo "當前 SSH 端口為: $(gum style --foreground "$COLOR_WARN" "$CURRENT_PORT")"
    echo "請輸入新的 SSH 端口 (1-65535)，若不修改請直接按 Enter 保留原值："
    NEW_PORT=$(gum input --value "$CURRENT_PORT" --placeholder "例如: 2222")
    if [ $? -ne 0 ] || [ -z "$NEW_PORT" ]; then 
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    echo ""
    echo "請設定 SSH 保持連線 (KeepAlive) 時間 (單位：分鐘，預設 30)："
    KEEPALIVE_MIN=$(gum input --value "30" --placeholder "輸入分鐘數...")
    if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi
    KEEPALIVE_MIN=${KEEPALIVE_MIN:-30}

    echo ""
    echo "請設定單一 SSH 允許的最大會話/Tunnel 數量 (MaxSessions，預設 10，經常 Tunnel 建議加大至 50)："
    MAX_SESSIONS=$(gum input --value "50" --placeholder "例如: 50")
    if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi
    MAX_SESSIONS=${MAX_SESSIONS:-50}

    echo ""
    echo "是否允許 Root 帳號直接透過 SSH 登入？"
    ROOT_LOGIN=$(gum choose "1. 允許 (預設/防手滑)" "2. 禁止 (安全，但需先建立一般用戶)")
    if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi

    echo ""
    echo "是否允許使用【密碼】進行 SSH 登入？"
    PASS_LOGIN=$(gum choose "1. 允許 (預設/防手滑)" "2. 禁止 (強制僅限 SSH 金鑰登入)")
    if [ $? -ne 0 ]; then print_warn "已取消操作。"; pause_to_return; return; fi

    echo ""
    export CURRENT_PORT NEW_PORT ROOT_LOGIN PASS_LOGIN KEEPALIVE_MIN MAX_SESSIONS
    gum spin --spinner dot --title "正在備份並修改 SSH 設定..." -- bash -c '
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        
        # 1. 修改 Port
        sed -i "/^#*Port /d" /etc/ssh/sshd_config
        echo "Port $NEW_PORT" >> /etc/ssh/sshd_config
        
        # 2. 修改 PermitRootLogin
        sed -i "/^#*PermitRootLogin /d" /etc/ssh/sshd_config
        if [[ "$ROOT_LOGIN" == "1"* ]]; then
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        else
            echo "PermitRootLogin no" >> /etc/ssh/sshd_config
        fi
        
        # 3. 修改 PasswordAuthentication
        sed -i "/^#*PasswordAuthentication /d" /etc/ssh/sshd_config
        if [[ "$PASS_LOGIN" == "1"* ]]; then
            echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
        else
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
        fi
        
        # 4. 修改 KeepAlive 持久連線
        sed -i "/^#*ClientAliveInterval /d" /etc/ssh/sshd_config
        sed -i "/^#*ClientAliveCountMax /d" /etc/ssh/sshd_config
        echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
        echo "ClientAliveCountMax $KEEPALIVE_MIN" >> /etc/ssh/sshd_config
        
        # 5. 修改 MaxSessions 與 MaxStartups (提升 Tunnel 與高並發能力)
        sed -i "/^#*MaxSessions /d" /etc/ssh/sshd_config
        sed -i "/^#*MaxStartups /d" /etc/ssh/sshd_config
        echo "MaxSessions $MAX_SESSIONS" >> /etc/ssh/sshd_config
        echo "MaxStartups 100:30:500" >> /etc/ssh/sshd_config
        
        systemctl restart ssh || systemctl restart sshd
    '

    # ----------------------------------------
    # 輸出驗證報告
    # ----------------------------------------
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "📊 SSH 設定驗證報告："
    
    ACTUAL_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    echo " 🚪 SSH 端口: $(gum style --foreground "$COLOR_SUCCESS" "${ACTUAL_PORT:-22}")"
    
    ACTUAL_ROOT=$(grep -E "^PermitRootLogin " /etc/ssh/sshd_config | awk '{print $2}')
    if [ "$ACTUAL_ROOT" == "no" ]; then
        echo " 👑 Root 登入: $(gum style --foreground "$COLOR_SUCCESS" "已禁止 (安全)")"
    else
        echo " 👑 Root 登入: $(gum style --foreground "$COLOR_WARN" "允許")"
    fi

    ACTUAL_PASS=$(grep -E "^PasswordAuthentication " /etc/ssh/sshd_config | awk '{print $2}')
    if [ "$ACTUAL_PASS" == "no" ]; then
        echo " 🔑 密碼登入: $(gum style --foreground "$COLOR_SUCCESS" "已禁止 (僅限金鑰)")"
    else
        echo " 🔑 密碼登入: $(gum style --foreground "$COLOR_WARN" "允許")"
    fi
    
    echo " 🔌 保持連線: $(gum style --foreground "$COLOR_SUCCESS" "${KEEPALIVE_MIN} 分鐘斷線檢測")"
    echo " 🔀 最大會話/Tunnel: $(gum style --foreground "$COLOR_SUCCESS" "${MAX_SESSIONS} (MaxSessions)")"

    if [ "$CURRENT_PORT" != "$NEW_PORT" ]; then
        echo ""
        # 自動將新 SSH 端口加入防火牆 (防止把自己鎖在門外)
        if command -v ufw &> /dev/null && LC_ALL=C ufw status 2>/dev/null | grep -qw active; then
            ufw allow "${ACTUAL_PORT}/tcp" > /dev/null 2>&1
            print_success "已自動將 Port ${ACTUAL_PORT}/tcp 加入 UFW 防火牆放行規則。"
        else
            gum style --foreground "$COLOR_ERROR" --bold "🔥 強烈警告：您已修改 SSH 端口！"
            print_warn "UFW 尚未啟用，請務必到主選單【6. 配置 UFW 防火牆】放行 Port $ACTUAL_PORT，否則將被鎖在門外！"
        fi
    fi
    
    pause_to_return
}

# 10. 網路與效能測試 Bench.sh
fn_run_bench() {
    print_header "📊 網路與效能測試 Bench.sh"
    
    gum confirm "即將執行秋水逸冰的 bench.sh 腳本，這會花費幾分鐘進行硬體與網路測速。是否繼續？"
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    echo ""
    gum style --foreground "$COLOR_WARN" "測試進行中，請耐心等候..."
    wget -qO- bench.sh | bash
    
    pause_to_return
}

# 11. 下載 DD 重裝系統
fn_run_dd() {
    print_header "☠️ 下載 DD 重裝系統"
    
    gum style --foreground "$COLOR_ERROR" --bold "下載 DD 重裝系統"
    echo ""
    
    gum confirm "本工具或會導致系統清除"
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    gum confirm "第二次確認"
    if [ $? -ne 0 ]; then
        print_warn "已取消操作，返回主選單。"
        pause_to_return
        return
    fi
    
    echo ""
    gum style --foreground "$COLOR_WARN" "正在下載並調用 reinstall.sh..."
    curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
    bash reinstall.sh
    
    pause_to_return
}

# ==========================================
# 主選單迴圈 (Main Menu Loop)
# ==========================================

while true; do
    clear
    gum style --border double --margin "1" --padding "1 2" --border-foreground $COLOR_PRIMARY --bold "Debian 12 Server Init"
    
    echo "操作提示: 可使用 [上下鍵] 選擇，或 [直接盲打輸入數字] 快速過濾選項。"
    echo "請選擇要執行的模組，按 [Enter] 確認，按 [ESC] 退出腳本："
    echo ""

    CHOICE=$(gum choose \
        "1. 🔑 修改 Root 密碼" \
        "2. 🛠️ 安裝基礎工具與系統微調 (+Fail2ban)" \
        "3. 🌐 修改主機名稱 Hostname" \
        "4. 🚀 內核與網路進階優化" \
        "5. 💾 設定虛擬記憶體 Swap" \
        "6. 🔥 配置 UFW 防火牆" \
        "7. 🐳 安裝 Docker 與 Docker Compose" \
        "8. 👤 建立與管理系統用戶" \
        "9. 🛡️ SSH 安全與端口修改" \
        "10. 📊 附屬工具：網路與效能測試 Bench.sh" \
        "11. ☠️ 下載 DD 重裝系統" \
        "12. 🚪 退出腳本" \
        --height 15 \
    )

    # 檢測在主選單是否按下 ESC，若按下則直接退出腳本
    if [ $? -ne 0 ]; then
        echo ""
        gum style --foreground $COLOR_SUCCESS "已透過 ESC 退出腳本。再見！"
        exit 0
    fi

    # 根據使用者的選擇呼叫對應的函數
    case "$CHOICE" in
        "1. 🔑 修改 Root 密碼") fn_change_password ;;
        "2. 🛠️ 安裝基礎工具與系統微調 (+Fail2ban)") fn_install_base ;;
        "3. 🌐 修改主機名稱 Hostname") fn_change_hostname ;;
        "4. 🚀 內核與網路進階優化") fn_optimize_sysctl ;;
        "5. 💾 設定虛擬記憶體 Swap") fn_setup_swap ;;
        "6. 🔥 配置 UFW 防火牆") fn_setup_ufw ;;
        "7. 🐳 安裝 Docker 與 Docker Compose") fn_install_docker ;;
        "8. 👤 建立與管理系統用戶") fn_manage_user ;;
        "9. 🛡️ SSH 安全與端口修改") fn_setup_ssh ;;
        "10. 📊 附屬工具：網路與效能測試 Bench.sh") fn_run_bench ;;
        "11. ☠️ 下載 DD 重裝系統") fn_run_dd ;;
        "12. 🚪 退出腳本") 
            echo ""
            gum style --foreground $COLOR_SUCCESS "感謝使用，系統設定已保留。再見！"
            exit 0 
            ;;
    esac
done