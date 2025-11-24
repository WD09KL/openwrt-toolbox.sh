#!/bin/bash
# OpenWrt 快捷工具箱 v1.2（优化版）
clear

# 定义颜色（适配终端）
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RED="\033[1;31m"
RESET="\033[0m"

# 日志配置
LOG_DIR="/tmp/openwrt-toolbox.log"
BACKUP_DIR="/mnt/mmc0-1/istore_backup"  # 可根据实际情况修改

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 用户执行（sudo -i 或 su root）${RESET}"
    exit 1
fi

# 检查 OpenWrt 环境
if [ ! -f "/etc/openwrt_release" ]; then
    echo -e "${YELLOW}警告：未检测到 OpenWrt 系统，部分功能可能无法使用${RESET}"
    read -p "是否继续？(y/n) " -n 1 -r
    echo -e "\n"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 创建备份目录和日志
mkdir -p "$BACKUP_DIR"
touch "$LOG_DIR"
echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] 启动 OpenWrt 快捷工具箱 v1.2" >> "$LOG_DIR"

# ===================== 优化版主菜单函数（替换旧版 show_menu）=====================
show_menu() {
    clear
    # 界面头部（强化标识）
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}        🛠️  OpenWrt 快捷工具箱 v1.2        ${RESET}"
    echo -e "${CYAN}          （功能增强 · 交互优化）          ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo ""

    # 功能列表（分组+图标+颜色区分）
    echo -e "${YELLOW}【网络相关】${RESET}"
    echo -e "  ${GREEN}1.${RESET} 📡 网络工具   —— 端口扫描/测速/IP查询"
    echo ""

    echo -e "${YELLOW}【系统管理】${RESET}"
    echo -e "  ${GREEN}2.${RESET} 📦 系统备份   —— zstd快速/xz高压缩"
    echo -e "  ${GREEN}3.${RESET} 🧹 系统优化   —— 清理缓存/关闭无用服务"
    echo -e "  ${GREEN}4.${RESET} 📊 系统监控   —— CPU/内存/磁盘占用"
    echo ""

    echo -e "${YELLOW}【快捷操作】${RESET}"
    echo -e "  ${GREEN}5.${RESET} ⚡ 快捷操作   —— 重启网络/系统/更新脚本"
    echo -e "  ${GREEN}6.${RESET} 🚪 退出工具箱"
    echo ""

    # 输入提示（强化引导）
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -n -e "${YELLOW}请选择操作 [1-6]：${RESET}"
}

# ===================== 子模块界面同步优化（保持风格统一）=====================
# 1. 网络工具（优化子菜单样式）
network_tools() {
    clear
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}          📡 网络工具模块                     ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "  ${GREEN}1.${RESET} 端口扫描   —— 本地端口开放检测"
    echo -e "  ${GREEN}2.${RESET} 网络测速   —— Speedtest 精简版"
    echo -e "  ${GREEN}3.${RESET} IP 查询    —— 公网/内网IP+DNS信息"
    echo -e "  ${GREEN}4.${RESET} 🚪 回到主菜单"
    echo ""
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -n -e "${YELLOW}请选择操作 [1-4]：${RESET}"
    read -r net_choice

    case $net_choice in
        1)
            echo -e "\n${GREEN}正在扫描本地开放端口（前1000端口）...${RESET}"
            netstat -tuln | grep -E ':([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])'
            echo -e "\n${BLUE}扫描完成，结果如上${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        2)
            echo -e "\n${GREEN}正在进行网络测速（需等待3-5秒）...${RESET}"
            if command -v speedtest-cli &> /dev/null; then
                speedtest-cli --simple
            else
                echo -e "${YELLOW}未安装 speedtest-cli，正在临时安装...${RESET}"
                opkg update && opkg install python3 python3-pip && pip3 install speedtest-cli --break-system-packages
                speedtest-cli --simple
            fi
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        3)
            echo -e "\n${GREEN}IP 信息查询结果：${RESET}"
            echo -e "内网 IP：$(ifconfig br-lan | grep 'inet ' | awk '{print $2}')"
            echo -e "公网 IP：$(curl -s ip.sb)"
            echo -e "DNS 服务器：$(cat /etc/resolv.conf | grep 'nameserver' | awk '{print $2}')"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择！1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
    network_tools
}

# 2. 系统备份（优化子菜单样式）
system_backup() {
    clear
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}          📦 系统备份模块（优化压缩）         ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "备份设备：/dev/mmcblk1（SD卡，可自行修改）"
    echo -e "备份目录：$BACKUP_DIR"
    echo -e "压缩算法：快速模式（zstd -1） | 高压缩模式（xz -9）"
    echo -e "日志文件：/tmp/backup_xxx.log"
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 快速备份   —— zstd -1（极速+高压缩比）"
    echo -e "  ${GREEN}2.${RESET} 高压缩备份 —— xz -9（最小体积）"
    echo -e "  ${GREEN}3.${RESET} 查看日志   —— 备份执行记录"
    echo -e "  ${GREEN}4.${RESET} 🚪 回到主菜单"
    echo ""
    echo -n -e "${YELLOW}请选择操作 [1-4]：${RESET}"
    read -r backup_choice

    case $backup_choice in
        1)
            BACKUP_FILENAME="Hlink_H28K-iStoreOS_$(date +'%Y%m%d_%H%M%S')_FAST.img.zst"
            LOG_FILENAME="/tmp/backup_fast_$(date +'%Y%m%d').log"
            
            echo -e "\n${GREEN}正在启动快速备份（zstd -1，后台运行）...${RESET}"
            echo -e "备份文件：$BACKUP_DIR/$BACKUP_FILENAME"
            echo -e "日志文件：$LOG_FILENAME"
            
            if ! command -v zstd &> /dev/null; then
                echo -e "${YELLOW}未检测到zstd，正在安装...${RESET}"
                opkg update && opkg install zstd
            fi
            
            umount /dev/mmcblk1p* 2>/dev/null
            nohup bash -c "
                dd if=/dev/mmcblk1 bs=4M status=progress oflag=direct | zstd -1 > '$BACKUP_DIR/$BACKUP_FILENAME' && \
                md5sum '$BACKUP_DIR/$BACKUP_FILENAME' > '$BACKUP_DIR/$BACKUP_FILENAME.md5' && \
                md5sum -c '$BACKUP_DIR/$BACKUP_FILENAME.md5' >> '$LOG_FILENAME' 2>&1 && \
                echo '[$(date +'%Y-%m-%d %H:%M:%S')] 快速备份完成，校验成功' >> '$LOG_FILENAME'
            " > "$LOG_FILENAME" 2>&1 &
            
            echo -e "${GREEN}备份已启动！查看进度：tail -f $LOG_FILENAME${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        2)
            BACKUP_FILENAME="Hlink_H28K-iStoreOS_$(date +'%Y%m%d_%H%M%S')_HIGH.img.xz"
            LOG_FILENAME="/tmp/backup_high_$(date +'%Y%m%d').log"
            
            echo -e "\n${GREEN}正在启动高压缩备份（xz -9，后台运行）...${RESET}"
            echo -e "备份文件：$BACKUP_DIR/$BACKUP_FILENAME"
            echo -e "日志文件：$LOG_FILENAME"
            
            if ! command -v xz &> /dev/null; then
                echo -e "${YELLOW}未检测到xz，正在安装...${RESET}"
                opkg update && opkg install xz
            fi
            
            umount /dev/mmcblk1p* 2>/dev/null
            nohup bash -c "
                dd if=/dev/mmcblk1 bs=8M status=progress oflag=direct | xz -9 > '$BACKUP_DIR/$BACKUP_FILENAME' && \
                md5sum '$BACKUP_DIR/$BACKUP_FILENAME' > '$BACKUP_DIR/$BACKUP_FILENAME.md5' && \
                md5sum -c '$BACKUP_DIR/$BACKUP_FILENAME.md5' >> '$LOG_FILENAME' 2>&1 && \
                echo '[$(date +'%Y-%m-%d %H:%M:%S')] 高压缩备份完成，校验成功' >> '$LOG_FILENAME'
            " > "$LOG_FILENAME" 2>&1 &
            
            echo -e "${GREEN}备份已启动！查看进度：tail -f $LOG_FILENAME${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        3)
            echo -e "\n${GREEN}最近备份日志列表：${RESET}"
            ls -lt /tmp/backup_*.log 2>/dev/null | head -5
            echo -n -e "${YELLOW}请输入要查看的日志文件名（如 /tmp/backup_fast_20251124.log）：${RESET}"
            read -r log_file
            if [ -f "$log_file" ]; then
                tail -n 20 "$log_file"
                echo -e "\n${BLUE}如需查看完整日志：cat $log_file${RESET}"
            else
                echo -e "${RED}日志文件不存在！${RESET}"
            fi
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择！1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
    system_backup
}

# 3. 系统优化（优化子菜单样式）
system_optimize() {
    clear
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}          🧹 系统优化模块                     ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "  ${GREEN}1.${RESET} 清理缓存   —— 临时文件/日志"
    echo -e "  ${GREEN}2.${RESET} 关闭无用服务 —— avahi/zeroconf等"
    echo -e "  ${GREEN}3.${RESET} 优化SSH    —— 禁用DNS反向解析（提速）"
    echo -e "  ${GREEN}4.${RESET} 🚪 回到主菜单"
    echo ""
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -n -e "${YELLOW}请选择操作 [1-4]：${RESET}"
    read -r opt_choice

    case $opt_choice in
        1)
            echo -e "\n${GREEN}正在清理系统缓存...${RESET}"
            rm -rf /tmp/* /var/log/* /var/run/*
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 清理缓存完成" >> "$LOG_DIR"
            echo -e "${GREEN}清理完成！${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        2)
            echo -e "\n${GREEN}正在关闭无用服务...${RESET}"
            for service in avahi-daemon zeroconf; do
                if /etc/init.d/"$service" status &> /dev/null; then
                    /etc/init.d/"$service" stop
                    /etc/init.d/"$service" disable
                    echo "已关闭服务：$service"
                fi
            done
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 关闭无用服务完成" >> "$LOG_DIR"
            echo -e "${GREEN}操作完成！${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        3)
            echo -e "\n${GREEN}正在优化SSH连接...${RESET}"
            if ! grep -q "UseDNS no" /etc/ssh/sshd_config; then
                echo "UseDNS no" >> /etc/ssh/sshd_config
                /etc/init.d/sshd restart
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] SSH优化完成" >> "$LOG_DIR"
            fi
            echo -e "${GREEN}优化完成！SSH连接速度将提升${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择！1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
    system_optimize
}

# 4. 系统监控（优化子菜单样式）
system_monitor() {
    clear
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}          📊 系统监控模块                     ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "CPU 占用：$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1 " %"}')"
    echo -e "内存占用：$(free | grep Mem | awk '{print "已用：" $3 "KB / 总：" $2 "KB (" sprintf("%.1f", $3/$2*100) "%)"}')"
    echo -e "磁盘占用：$(df -h | grep '/mnt/mmc0-1' | awk '{print "已用：" $3 " / 总：" $2 " (" $5 ")"}')"
    echo -e "在线用户：$(who | wc -l) 人"
    echo -e "系统负载：$(uptime | awk -F 'load average: ' '{print $2}')"
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 进程列表   —— top 实时监控"
    echo -e "  ${GREEN}2.${RESET} 磁盘详情   —— df -h 完整信息"
    echo -e "  ${GREEN}3.${RESET} 🚪 回到主菜单"
    echo ""
    echo -n -e "${YELLOW}请选择操作 [1-3]：${RESET}"
    read -r mon_choice

    case $mon_choice in
        1)
            top
            ;;
        2)
            df -h
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}无效选择！1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
    system_monitor
}

# 5. 快捷操作（优化子菜单样式）
quick_actions() {
    clear
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "${GREEN}          ⚡ 快捷操作模块                     ${RESET}"
    echo -e "${BLUE}=============================================${RESET}"
    echo -e "  ${GREEN}1.${RESET} 重启网络   —— 重启 network 服务"
    echo -e "  ${GREEN}2.${RESET} 重启系统   —— 立即重启设备"
    echo -e "  ${GREEN}3.${RESET} 更新脚本   —— 获取最新版工具箱"
    echo -e "  ${GREEN}4.${RESET} 查看日志   —— 工具箱操作记录"
    echo -e "  ${GREEN}5.${RESET} 🚪 回到主菜单"
    echo ""
    echo -e "${BLUE}--------------------------------------------${RESET}"
    echo -n -e "${YELLOW}请选择操作 [1-5]：${RESET}"
    read -r act_choice

    case $act_choice in
        1)
            echo -e "\n${GREEN}正在重启网络服务...${RESET}"
            /etc/init.d/network restart
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 重启网络完成" >> "$LOG_DIR"
            echo -e "${GREEN}操作完成！${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        2)
            read -p "$(echo -e "${YELLOW}确定要重启系统吗？(y/n) ${RESET}")" -n 1 -r
            echo -e "\n"
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] 执行系统重启" >> "$LOG_DIR"
                reboot
            fi
            ;;
        3)
            echo -e "\n${GREEN}正在更新工具箱脚本...${RESET}"
            # 替换为你的自定义域名脚本地址（关键！适配之前的需求）
            curl -sL owt.wdos.us.kg -o /tmp/openwrt-toolbox.sh
            chmod +x /tmp/openwrt-toolbox.sh
            echo -e "${GREEN}更新完成！请重新执行：bash <(curl -sL owt.wdos.us.kg)${RESET}"
            exit 0
            ;;
        4)
            echo -e "\n${GREEN}工具箱日志（最近20条）：${RESET}"
            tail -n 20 "$LOG_DIR"
            echo -e "\n${BLUE}查看完整日志：cat $LOG_DIR${RESET}"
            read -p "$(echo -e "${YELLOW}按 Enter 键返回...${RESET}")"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选择！1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
    quick_actions
}

# ===================== 主循环（保持功能不变）=====================
while true; do
    show_menu
    read -r choice
    case $choice in
        1) network_tools ;;
        2) system_backup ;;
        3) system_optimize ;;
        4) system_monitor ;;
        5) quick_actions ;;
        6)
            echo -e "\n${GREEN}感谢使用 OpenWrt 快捷工具箱 v1.2，再见！${RESET}"
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 退出工具箱" >> "$LOG_DIR"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择！请输入 1-6 之间的数字，1秒后返回...${RESET}"
            sleep 1
            ;;
    esac
done
