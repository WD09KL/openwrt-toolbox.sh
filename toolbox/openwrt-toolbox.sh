#!/bin/bash
# OpenWrt 工具箱 v2.0（模块化交互框架）
clear

# ==========================================
# 模块1：基础配置（颜色、常量、环境检测）
# ==========================================
# 终端颜色定义（适配 OpenWrt 终端，高对比度+护眼）
COLOR_PRIMARY="\033[1;34m"   # 主色调（亮蓝）
COLOR_SUCCESS="\033[1;32m"   # 成功色（亮绿）
COLOR_WARN="\033[1;33m"      # 警告色（亮黄）
COLOR_DANGER="\033[1;31m"    # 危险色（亮红）
COLOR_INFO="\033[1;36m"      # 信息色（亮青）
COLOR_RESET="\033[0m"        # 重置色

# 常量配置（后续可统一修改）
TOOL_NAME="OpenWrt 快捷工具箱"
TOOL_VERSION="v2.0"
TOOL_AUTHOR="自定义作者"
TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 60)  # 自适应终端宽度
BORDER_CHAR="="
SEPARATOR_CHAR="-"

# 环境检测（基础校验）
check_env() {
    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 请使用 root 用户执行（sudo -i 或 su root）${COLOR_RESET}"
        exit 1
    fi

    # 检查 OpenWrt 系统（可选）
    if [ ! -f "/etc/openwrt_release" ]; then
        echo -e "\n${COLOR_WARN}[警告] 未检测到 OpenWrt 系统，部分功能可能无法正常使用${COLOR_RESET}"
        read -p "$(echo -e "${COLOR_WARN}是否继续？(y/n) ${COLOR_RESET}")" -n 1 -r
        echo -e "\n"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ==========================================
# 模块2：交互界面（核心美化部分）
# ==========================================
# 绘制边框（自适应宽度）
draw_border() {
    local char="$1"
    printf "%${TERMINAL_WIDTH}s\n" | tr " " "$char"
}

# 居中显示文本
center_text() {
    local text="$1"
    local padding=$(( (TERMINAL_WIDTH - ${#text}) / 2 ))
    printf "%${padding}s%s%${padding}s\n" "" "$text" ""
}

# 主菜单界面
show_main_menu() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    local separator=$(draw_border "$SEPARATOR_CHAR")

    # 头部区域（边框+标题+信息）
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}📦 $TOOL_NAME $TOOL_VERSION${COLOR_RESET}"
    center_text "${COLOR_INFO}💻 适配 OpenWrt 全场景工具集${COLOR_RESET}"
    center_text "${COLOR_WARN}👤 作者：$TOOL_AUTHOR${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    echo ""

    # 菜单列表（分组+图标+对齐）
    echo -e "${COLOR_WARN}【网络工具】${COLOR_RESET}"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}1.${COLOR_RESET}" "🌐" "端口扫描 / 网络测速 / IP查询"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}2.${COLOR_RESET}" "🔌" "WiFi 管理 / 连接优化"
    echo ""

    echo -e "${COLOR_WARN}【系统管理】${COLOR_RESET}"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}3.${COLOR_RESET}" "📦" "系统备份（zstd/xz 压缩）"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}4.${COLOR_RESET}" "🧹" "系统优化（缓存清理/服务管理）"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}5.${COLOR_RESET}" "📊" "系统监控（CPU/内存/磁盘）"
    echo ""

    echo -e "${COLOR_WARN}【快捷操作】${COLOR_RESET}"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}6.${COLOR_RESET}" "⚡" "重启网络 / 系统重启"
    printf "  %-2s %-4s %-30s\n" "${COLOR_SUCCESS}7.${COLOR_RESET}" "🔄" "更新工具箱脚本"
    printf "  %-2s %-4s %-30s\n" "${COLOR_DANGER}8.${COLOR_RESET}" "🚪" "退出工具箱"
    echo ""

    # 底部输入区域
    echo -e "${COLOR_PRIMARY}$separator${COLOR_RESET}"
    read -p "$(echo -e "${COLOR_INFO}请选择功能 [1-8]：${COLOR_RESET}")" choice
}

# 功能选择处理（空实现，后续可添加模块调用）
handle_choice() {
    case $choice in
        1) echo -e "\n${COLOR_INFO}[提示] 即将打开「网络工具 - 端口扫描/测速/IP查询」${COLOR_RESET}" ;;
        2) echo -e "\n${COLOR_INFO}[提示] 即将打开「网络工具 - WiFi 管理/连接优化」${COLOR_RESET}" ;;
        3) echo -e "\n${COLOR_INFO}[提示] 即将打开「系统管理 - 系统备份」${COLOR_RESET}" ;;
        4) echo -e "\n${COLOR_INFO}[提示] 即将打开「系统管理 - 系统优化」${COLOR_RESET}" ;;
        5) echo -e "\n${COLOR_INFO}[提示] 即将打开「系统管理 - 系统监控」${COLOR_RESET}" ;;
        6) echo -e "\n${COLOR_INFO}[提示] 即将执行「快捷操作 - 重启网络/系统」${COLOR_RESET}" ;;
        7) echo -e "\n${COLOR_INFO}[提示] 即将执行「快捷操作 - 更新工具箱脚本」${COLOR_RESET}" ;;
        8) 
            echo -e "\n${COLOR_SUCCESS}👋 感谢使用 $TOOL_NAME $TOOL_VERSION，再见！${COLOR_RESET}"
            echo -e "${COLOR_PRIMARY}$(draw_border "$BORDER_CHAR")${COLOR_RESET}"
            exit 0
            ;;
        *) 
            echo -e "\n${COLOR_DANGER}[错误] 无效选择！请输入 1-8 之间的数字${COLOR_RESET}"
            sleep 1.5
            ;;
    esac

    # 操作后停留（按 Enter 返回主菜单）
    if [ "$choice" -ge 1 ] && [ "$choice" -le 7 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回主菜单...${COLOR_RESET}")"
    fi
}

# ==========================================
# 模块3：主程序入口（流程控制）
# ==========================================
main() {
    # 初始化环境检测
    check_env

    # 主循环（持续显示菜单）
    while true; do
        show_main_menu
        handle_choice
    done
}

# 启动程序
main
