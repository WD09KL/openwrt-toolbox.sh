#!/bin/bash
# OpenWrt 工具箱 v2.5（修复优化版）
clear

# ==========================================
# 模块1：基础配置（修复版）
# ==========================================
# 终端颜色定义
COLOR_PRIMARY="\033[1;34m"   # 主色调（亮蓝）
COLOR_SUCCESS="\033[1;32m"   # 成功色（亮绿）
COLOR_WARN="\033[1;33m"      # 警告色（亮黄）
COLOR_DANGER="\033[1;31m"    # 危险色（亮红）
COLOR_INFO="\033[1;36m"      # 信息色（亮青）
COLOR_RESET="\033[0m"        # 重置色

# 常量配置
TOOL_NAME="OpenWrt 快捷工具箱"
TOOL_VERSION="v2.5"
TOOL_AUTHOR="自定义作者"
TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 60)
BORDER_CHAR="="
SEPARATOR_CHAR="-"

# 备份核心配置
DEFAULT_BACKUP_DIR="/mnt/mmc0-1/istore_backup"
COMPRESS_MODES=("xz" "zstd" "gzip")
COMPRESS_LEVELS=("-9" "-1" "-9")
COMPRESS_DESCS=("高压缩（体积最小，速度最慢）" "快速压缩（速度优先，压缩比适中）" "标准压缩（平衡速度与体积）")
BACKUP_TYPES=("disk" "system")
SYSTEM_BACKUP_CMD="/usr/libexec/istore/overlay-backup backup"
SYSTEM_RESTORE_CMD="/usr/libexec/istore/overlay-backup restore"

# 全局状态变量
HAS_SYSTEM_TOOLS=1
HAS_LSBLK=1

# 环境检测（修复版）
check_env() {
    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 请使用 root 用户执行（sudo -i 或 su root）${COLOR_RESET}"
        exit 1
    fi

    # 检查 OpenWrt 系统（改为警告而非退出）
    if [ ! -f "/etc/openwrt_release" ]; then
        echo -e "\n${COLOR_WARN}[警告] 未检测到 OpenWrt 系统，部分功能可能无法正常使用${COLOR_RESET}"
        read -p "$(echo -e "${COLOR_WARN}是否继续？(y/n) ${COLOR_RESET}")" -n 1 -r
        echo -e "\n"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # 检查必要命令（修复数组定义）
    local required_cmds=("dd" "md5sum" "tar" "mount" "umount" "grep" "awk")
    local missing_cmds=()
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 缺少必要命令：${missing_cmds[*]}${COLOR_RESET}"
        exit 1
    fi

    # 检查 lsblk 命令（非必需但重要）
    if ! command -v "lsblk" &> /dev/null; then
        echo -e "\n${COLOR_WARN}[警告] 缺少 lsblk 命令，硬盘检测功能受限${COLOR_RESET}"
        HAS_LSBLK=0
    fi

    # 检查压缩工具
    for comp in "${COMPRESS_MODES[@]}"; do
        if ! command -v "$comp" &> /dev/null; then
            echo -e "\n${COLOR_WARN}[警告] 缺少压缩工具 $comp，该压缩模式将不可用${COLOR_RESET}"
        fi
    done

    # 检查系统备份工具（改为设置标志而非退出）
    local sys_backup_bin=$(echo "$SYSTEM_BACKUP_CMD" | awk '{print $1}')
    local sys_restore_bin=$(echo "$SYSTEM_RESTORE_CMD" | awk '{print $1}')
    
    if [ ! -x "$sys_backup_bin" ] || [ ! -x "$sys_restore_bin" ]; then
        echo -e "\n${COLOR_WARN}[警告] 系统备份/还原工具不可用，相关功能将禁用${COLOR_RESET}"
        HAS_SYSTEM_TOOLS=0
    fi
    
    echo -e "\n${COLOR_SUCCESS}[环境检测完成] 核心功能正常${COLOR_RESET}"
    sleep 1
}

# ==========================================
# 模块2：工具函数（修复版）
# ==========================================
draw_border() {
    printf "%${TERMINAL_WIDTH}s\n" | tr " " "$1"
}

center_text() {
    local text="$1"
    local text_width=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
    local padding=$(( (TERMINAL_WIDTH - text_width) / 2 ))
    printf "%${padding}s%s%${padding}s\n" "" "$text" ""
}

# 获取设备型号（修复空值处理）
get_device_model() {
    local model
    if [ -f "/etc/openwrt_release" ]; then
        model=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release 2>/dev/null | awk -F '"' '{print $2}' | sed 's/ /_/g' | cut -d '_' -f1-2)
    fi
    echo "${model:-OpenWrt_Device}"
}

get_hostname() {
    hostname 2>/dev/null | sed 's/ /_/g' || echo "unknown"
}

# 生成备份文件名（修复压缩后缀）
generate_backup_filename() {
    local backup_type="$1"
    local compress_mode="$2"
    local model=$(get_device_model)
    local hostname=$(get_hostname)
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    
    local suffix
    if [ "$backup_type" = "disk" ]; then
        suffix="disk.img.${compress_mode}"
    else
        suffix="system.overlay.tar.${compress_mode}"
    fi
    
    echo "${model}_${hostname}_${timestamp}.${suffix}"
}

# 列出可用磁盘（修复兼容性）
list_available_disks() {
    echo -e "\n${COLOR_INFO}[可用硬盘设备]${COLOR_RESET}"
    
    if [ "$HAS_LSBLK" -eq 0 ]; then
        echo -e "${COLOR_WARN}  无法检测硬盘设备（缺少 lsblk 命令）${COLOR_RESET}"
        echo -e "${COLOR_INFO}  请手动输入设备路径（如 /dev/sda）${COLOR_RESET}"
        return 1
    fi
    
    local disks=()
    # 更安全的磁盘检测
    while IFS= read -r line; do
        if [ -n "$line" ] && [ -w "$line" ]; then
            disks+=("$line")
        fi
    done < <(lsblk -dn -o NAME,TYPE 2>/dev/null | grep -E 'disk' | awk '{print "/dev/" $1}')
    
    if [ ${#disks[@]} -eq 0 ]; then
        echo -e "${COLOR_WARN}  未检测到可写磁盘设备！${COLOR_RESET}"
        echo -e "${COLOR_INFO}  请检查：1. 设备是否存在 2. 是否有读写权限${COLOR_RESET}"
        return 1
    fi
    
    # 显示硬盘列表
    for i in "${!disks[@]}"; do
        local disk=${disks[$i]}
        local size=$(lsblk -dn -o SIZE "$disk" 2>/dev/null || echo "未知")
        local is_system=""
        
        if lsblk -no MOUNTPOINT "$disk"* 2>/dev/null | grep -q "^/$"; then
            is_system="${COLOR_DANGER} [系统盘]${COLOR_RESET}"
        fi
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} $disk （容量：$size）$is_system"
    done
    echo ""
    
    # 返回数组
    printf '%s\n' "${disks[@]}"
}

# 选择备份目录（修复空输入处理）
select_backup_dir() {
    echo -e "\n${COLOR_INFO}[选择备份目录]${COLOR_RESET}"
    echo -e "  ${COLOR_SUCCESS}1.${COLOR_RESET} 使用默认目录：${DEFAULT_BACKUP_DIR}"
    echo -e "  ${COLOR_SUCCESS}2.${COLOR_RESET} 自定义备份目录"
    
    local dir_choice
    read -p "$(echo -e "${COLOR_INFO}请选择（默认1）：${COLOR_RESET}")" dir_choice

    local backup_dir
    if [ -z "$dir_choice" ] || [ "$dir_choice" = "1" ]; then
        backup_dir="$DEFAULT_BACKUP_DIR"
    else
        read -p "$(echo -e "${COLOR_INFO}请输入自定义目录路径：${COLOR_RESET}")" backup_dir
        if [ -z "$backup_dir" ]; then
            echo -e "${COLOR_WARN}[警告] 目录路径不能为空，使用默认目录${COLOR_RESET}"
            backup_dir="$DEFAULT_BACKUP_DIR"
        fi
    fi

    # 创建目录
    if [ ! -d "$backup_dir" ]; then
        echo -e "\n${COLOR_INFO}[提示] 创建目录 $backup_dir ...${COLOR_RESET}"
        if ! mkdir -p "$backup_dir" 2>/dev/null; then
            echo -e "${COLOR_DANGER}[错误] 目录创建失败：$backup_dir${COLOR_RESET}"
            return 1
        fi
    fi

    # 检查可写性
    if [ ! -w "$backup_dir" ]; then
        echo -e "${COLOR_DANGER}[错误] 目录不可写：$backup_dir${COLOR_RESET}"
        return 1
    fi

    echo -e "\n${COLOR_SUCCESS}[确认] 备份目录：$backup_dir${COLOR_RESET}"
    echo "$backup_dir"
}

# 选择压缩模式（修复索引错误）
select_compress_mode() {
    echo -e "\n${COLOR_INFO}[选择压缩模式]${COLOR_RESET}"
    local available_modes=()
    local available_levels=()
    local available_descs=()
    
    for i in "${!COMPRESS_MODES[@]}"; do
        if command -v "${COMPRESS_MODES[$i]}" &> /dev/null; then
            available_modes+=("${COMPRESS_MODES[$i]}")
            available_levels+=("${COMPRESS_LEVELS[$i]}")
            available_descs+=("${COMPRESS_DESCS[$i]}")
        fi
    done
    
    if [ ${#available_modes[@]} -eq 0 ]; then
        echo -e "${COLOR_DANGER}[错误] 未检测到任何可用的压缩工具${COLOR_RESET}"
        return 1
    fi
    
    for i in "${!available_modes[@]}"; do
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} ${available_modes[$i]} —— ${available_descs[$i]}"
    done
    
    local compress_choice
    read -p "$(echo -e "${COLOR_INFO}请选择（默认1）：${COLOR_RESET}")" compress_choice

    local index=0
    if [ -n "$compress_choice" ] && [ "$compress_choice" -ge 1 ] && [ "$compress_choice" -le ${#available_modes[@]} ]; then
        index=$((compress_choice - 1))
    fi

    local compress_mode=${available_modes[$index]}
    local compress_level=${available_levels[$index]}

    echo -e "\n${COLOR_SUCCESS}[确认] 压缩模式：$compress_mode（级别：$compress_level）${COLOR_RESET}"
    echo "$compress_mode $compress_level"
}

# 列出备份文件（修复文件存在性检查）
list_backup_files() {
    local backup_dir="$1"
    local backup_type="$2"
    local file_pattern

    if [ "$backup_type" = "disk" ]; then
        file_pattern="*.disk.img.*"
    else
        file_pattern="*.system.overlay.tar.*"
    fi

    echo -e "\n${COLOR_INFO}[${backup_type^} 备份文件列表]（目录：$backup_dir）${COLOR_RESET}"
    
    local backups=()
    if [ -d "$backup_dir" ]; then
        while IFS= read -r -d '' file; do
            if [ -f "$file" ]; then
                backups+=("$file")
            fi
        done < <(find "$backup_dir" -maxdepth 1 -name "$file_pattern" -type f ! -name "*.md5" -print0 2>/dev/null | sort -rz)
    fi

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${COLOR_WARN}  未找到 $backup_type 备份文件${COLOR_RESET}"
        return 1
    fi

    for i in "${!backups[@]}"; do
        local file=${backups[$i]}
        local filename=$(basename "$file")
        local size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
        local mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d ' ' -f1-2 || echo "未知")
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} $filename"
        echo -e "      大小：$size | 修改时间：$mtime"
    done
    echo ""
    
    printf '%s\n' "${backups[@]}"
}

# 提取压缩模式（修复正则匹配）
get_compress_mode() {
    local filename="$1"
    case "$filename" in
        *.xz) echo "xz" ;;
        *.zstd) echo "zstd" ;;
        *.gzip|*.gz) echo "gzip" ;;
        *) echo "" ;;
    esac
}

# 校验备份文件完整性
verify_backup_file() {
    local backup_path="$1"
    local md5_path="$backup_path.md5"
    
    if [ ! -f "$backup_path" ]; then
        echo -e "${COLOR_DANGER}[错误] 备份文件不存在：$backup_path${COLOR_RESET}"
        return 1
    fi
    
    if [ -f "$md5_path" ]; then
        echo -e "${COLOR_INFO}[校验] 正在验证备份文件完整性...${COLOR_RESET}"
        if md5sum -c "$md5_path" >/dev/null 2>&1; then
            echo -e "${COLOR_SUCCESS}[校验成功] 备份文件完整${COLOR_RESET}"
            return 0
        else
            echo -e "${COLOR_DANGER}[错误] 备份文件校验失败，可能已损坏！${COLOR_RESET}"
            return 1
        fi
    else
        echo -e "${COLOR_WARN}[警告] 未找到校验文件，跳过完整性检查${COLOR_RESET}"
        return 0
    fi
}

# ==========================================
# 模块3：备份还原功能（修复版）
# ==========================================
# 硬盘备份功能
disk_backup() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}💾 硬盘备份功能${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 选择备份硬盘
    local disks=($(list_available_disks))
    if [ ${#disks[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    local disk_choice
    read -p "$(echo -e "${COLOR_INFO}请选择要备份的硬盘序号（默认1）：${COLOR_RESET}")" disk_choice
    
    local disk_index=0
    if [ -n "$disk_choice" ] && [ "$disk_choice" -ge 1 ] && [ "$disk_choice" -le ${#disks[@]} ]; then
        disk_index=$((disk_choice - 1))
    fi
    
    local source_disk=${disks[$disk_index]}
    echo -e "\n${COLOR_SUCCESS}[确认] 备份源硬盘：$source_disk${COLOR_RESET}"

    # 选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ $? -ne 0 ] || [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择压缩模式
    local compress_info=$(select_compress_mode)
    if [ $? -ne 0 ] || [ -z "$compress_info" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    local compress_mode=$(echo "$compress_info" | awk '{print $1}')
    local compress_level=$(echo "$compress_info" | awk '{print $2}')

    # 生成备份文件名
    local backup_filename=$(generate_backup_filename "disk" "$compress_mode")
    local backup_path="$backup_dir/$backup_filename"
    local md5_path="$backup_path.md5"

    # 确认信息
    echo -e "\n${COLOR_INFO}[备份信息确认]${COLOR_RESET}"
    echo -e "  源硬盘：$source_disk"
    echo -e "  备份路径：$backup_path"
    echo -e "  压缩模式：$compress_mode $compress_level"
    echo -e "  校验文件：$md5_path"
    
    local confirm
    read -p "$(echo -e "\n${COLOR_WARN}是否开始备份？(y/n，默认n) ${COLOR_RESET}")" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_INFO}[提示] 备份已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 执行备份
    echo -e "\n${COLOR_SUCCESS}[开始备份] 正在备份 $source_disk ...${COLOR_RESET}"
    echo -e "${COLOR_INFO}提示：备份过程可能较长，请耐心等待！${COLOR_RESET}"
    
    # 卸载硬盘分区
    umount "${source_disk}"* 2>/dev/null

    local LOG_FILE="$backup_dir/disk_backup_$(date +'%Y%m%d_%H%M%S').log"
    
    # 更安全的备份执行
    {
        echo "=== 硬盘备份开始 ==="
        echo "时间: $(date)"
        echo "源硬盘: $source_disk"
        echo "目标文件: $backup_path"
        echo "压缩模式: $compress_mode $compress_level"
        
        if dd if="$source_disk" bs=1M status=progress 2>&1 | \
           $compress_mode $compress_level > "$backup_path" 2>> "$LOG_FILE"; then
            echo "备份完成，生成MD5校验文件..."
            if md5sum "$backup_path" > "$md5_path" 2>> "$LOG_FILE"; then
                if md5sum -c "$md5_path" >> "$LOG_FILE" 2>&1; then
                    echo "✅ 硬盘备份完成，校验成功"
                    echo "备份文件: $backup_path"
                    echo "校验文件: $md5_path"
                    echo "文件大小: $(du -sh "$backup_path" | awk '{print $1}')"
                else
                    echo "❌ 备份完成，但校验失败"
                    exit 1
                fi
            else
                echo "❌ MD5文件生成失败"
                exit 1
            fi
        else
            echo "❌ 备份过程失败"
            # 清理不完整的备份文件
            [ -f "$backup_path" ] && rm -f "$backup_path"
            exit 1
        fi
        echo "=== 硬盘备份结束 ==="
    } > "$LOG_FILE" 2>&1 &
    
    local backup_pid=$!
    echo -e "\n${COLOR_SUCCESS}[备份启动成功] PID: $backup_pid${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    echo -e "  终止备份：kill $backup_pid"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 系统备份功能
system_backup() {
    if [ "$HAS_SYSTEM_TOOLS" -eq 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 系统备份工具不可用${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🖥️  系统备份功能${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ $? -ne 0 ] || [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择压缩模式
    local compress_info=$(select_compress_mode)
    if [ $? -ne 0 ] || [ -z "$compress_info" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    local compress_mode=$(echo "$compress_info" | awk '{print $1}')
    local compress_level=$(echo "$compress_info" | awk '{print $2}')

    # 生成备份文件名
    local backup_filename=$(generate_backup_filename "system" "$compress_mode")
    local backup_path="$backup_dir/$backup_filename"
    local md5_path="$backup_path.md5"

    # 确认信息
    echo -e "\n${COLOR_INFO}[备份信息确认]${COLOR_RESET}"
    echo -e "  备份工具：${SYSTEM_BACKUP_CMD%% *}"
    echo -e "  备份路径：$backup_path"
    echo -e "  压缩模式：$compress_mode $compress_level"
    echo -e "  校验文件：$md5_path"
    
    local confirm
    read -p "$(echo -e "\n${COLOR_WARN}是否开始备份？(y/n，默认n) ${COLOR_RESET}")" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_INFO}[提示] 备份已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 执行系统备份
    echo -e "\n${COLOR_SUCCESS}[开始备份] 正在备份系统配置...${COLOR_RESET}"
    
    local LOG_FILE="$backup_dir/system_backup_$(date +'%Y%m%d_%H%M%S').log"
    
    {
        echo "=== 系统备份开始 ==="
        echo "时间: $(date)"
        echo "备份文件: $backup_path"
        echo "压缩模式: $compress_mode $compress_level"
        
        if $SYSTEM_BACKUP_CMD - | $compress_mode $compress_level > "$backup_path" 2>> "$LOG_FILE"; then
            echo "系统备份完成，生成MD5校验文件..."
            if md5sum "$backup_path" > "$md5_path" 2>> "$LOG_FILE"; then
                if md5sum -c "$md5_path" >> "$LOG_FILE" 2>&1; then
                    echo "✅ 系统备份完成，校验成功"
                    echo "备份文件: $backup_path"
                    echo "校验文件: $md5_path"
                    echo "文件大小: $(du -sh "$backup_path" | awk '{print $1}')"
                else
                    echo "❌ 备份完成，但校验失败"
                    exit 1
                fi
            else
                echo "❌ MD5文件生成失败"
                exit 1
            fi
        else
            echo "❌ 系统备份过程失败"
            [ -f "$backup_path" ] && rm -f "$backup_path"
            exit 1
        fi
        echo "=== 系统备份结束 ==="
    } > "$LOG_FILE" 2>&1 &
    
    local backup_pid=$!
    echo -e "\n${COLOR_SUCCESS}[备份启动成功] PID: $backup_pid${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 硬盘还原功能
disk_restore() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🔄 硬盘还原功能${COLOR_RESET}"
    echo -e "${COLOR_DANGER}⚠️  警告：还原会覆盖目标硬盘数据，请谨慎操作！${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ $? -ne 0 ] || [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 列出硬盘备份文件
    local backups=($(list_backup_files "$backup_dir" "disk"))
    if [ ${#backups[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择备份文件
    local backup_choice
    read -p "$(echo -e "${COLOR_INFO}请选择要还原的备份序号（默认1=最新）：${COLOR_RESET}")" backup_choice
    
    local backup_index=0
    if [ -n "$backup_choice" ] && [ "$backup_choice" -ge 1 ] && [ "$backup_choice" -le ${#backups[@]} ]; then
        backup_index=$((backup_choice - 1))
    fi
    
    local backup_path=${backups[$backup_index]}
    local md5_path="$backup_path.md5"
    local compress_mode=$(get_compress_mode "$(basename "$backup_path")")
    
    if [ -z "$compress_mode" ] || ! command -v "$compress_mode" &> /dev/null; then
        echo -e "${COLOR_DANGER}[错误] 不支持的压缩格式或缺少解压工具：$compress_mode${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择目标硬盘
    local disks=($(list_available_disks))
    if [ ${#disks[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    local disk_choice
    read -p "$(echo -e "${COLOR_INFO}请选择目标还原硬盘序号（默认1）：${COLOR_RESET}")" disk_choice
    
    local disk_index=0
    if [ -n "$disk_choice" ] && [ "$disk_choice" -ge 1 ] && [ "$disk_choice" -le ${#disks[@]} ]; then
        disk_index=$((disk_choice - 1))
    fi
    
    local target_disk=${disks[$disk_index]}

    # 确认还原信息（二次警告）
    echo -e "\n${COLOR_DANGER}[还原警告] 即将覆盖 $target_disk 的所有数据！${COLOR_RESET}"
    echo -e "${COLOR_INFO}[还原信息确认]${COLOR_RESET}"
    echo -e "  备份文件：$(basename "$backup_path")"
    echo -e "  目标硬盘：$target_disk"
    echo -e "  压缩模式：$compress_mode"
    echo -e "  文件大小：$(du -sh "$backup_path" | awk '{print $1}')"
    
    local confirm
    read -p "$(echo -e "\n${COLOR_DANGER}请输入 'YES' 确认还原（输入其他取消）：${COLOR_RESET}")" confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${COLOR_INFO}[提示] 还原已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 校验备份文件完整性
    if ! verify_backup_file "$backup_path"; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 执行还原
    echo -e "\n${COLOR_SUCCESS}[开始还原] 正在还原到 $target_disk ...${COLOR_RESET}"
    echo -e "${COLOR_INFO}提示：还原过程不可中断，完成后建议重启设备！${COLOR_RESET}"
    
    # 卸载目标硬盘分区
    umount "${target_disk}"* 2>/dev/null

    # 执行还原命令
    local LOG_FILE="$backup_dir/disk_restore_$(date +'%Y%m%d_%H%M%S').log"
    
    {
        echo "=== 硬盘还原开始 ==="
        echo "时间: $(date)"
        echo "备份文件: $backup_path"
        echo "目标硬盘: $target_disk"
        echo "压缩模式: $compress_mode"
        
        if $compress_mode -d -c "$backup_path" | dd of="$target_disk" bs=1M status=progress oflag=direct 2>> "$LOG_FILE"; then
            echo "✅ 硬盘还原完成"
            echo "建议执行：sync && reboot"
        else
            echo "❌ 硬盘还原失败"
            exit 1
        fi
        echo "=== 硬盘还原结束 ==="
    } > "$LOG_FILE" 2>&1 &
    
    local restore_pid=$!
    echo -e "\n${COLOR_SUCCESS}[还原启动成功] PID: $restore_pid${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    echo -e "  终止还原：kill $restore_pid"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 系统还原功能
system_restore() {
    if [ "$HAS_SYSTEM_TOOLS" -eq 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 系统还原工具不可用${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🔄 系统还原功能${COLOR_RESET}"
    echo -e "${COLOR_DANGER}⚠️  警告：系统还原会覆盖当前系统配置，可能需要重启！${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ $? -ne 0 ] || [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 列出系统备份文件
    local backups=($(list_backup_files "$backup_dir" "system"))
    if [ ${#backups[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择备份文件
    local backup_choice
    read -p "$(echo -e "${COLOR_INFO}请选择要还原的备份序号（默认1=最新）：${COLOR_RESET}")" backup_choice
    
    local backup_index=0
    if [ -n "$backup_choice" ] && [ "$backup_choice" -ge 1 ] && [ "$backup_choice" -le ${#backups[@]} ]; then
        backup_index=$((backup_choice - 1))
    fi
    
    local backup_path=${backups[$backup_index]}
    local md5_path="$backup_path.md5"
    local compress_mode=$(get_compress_mode "$(basename "$backup_path")")
    
    if [ -z "$compress_mode" ] || ! command -v "$compress_mode" &> /dev/null; then
        echo -e "${COLOR_DANGER}[错误] 不支持的压缩格式或缺少解压工具：$compress_mode${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 确认还原信息
    echo -e "\n${COLOR_DANGER}[还原警告] 即将覆盖当前系统配置，操作前请确保已备份重要数据！${COLOR_RESET}"
    echo -e "${COLOR_INFO}[还原信息确认]${COLOR_RESET}"
    echo -e "  备份文件：$(basename "$backup_path")"
    echo -e "  压缩模式：$compress_mode"
    echo -e "  还原工具：${SYSTEM_RESTORE_CMD%% *}"
    echo -e "  文件大小：$(du -sh "$backup_path" | awk '{print $1}')"
    
    local confirm
    read -p "$(echo -e "\n${COLOR_DANGER}请输入 'YES' 确认还原（输入其他取消）：${COLOR_RESET}")" confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${COLOR_INFO}[提示] 还原已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 校验备份文件完整性
    if ! verify_backup_file "$backup_path"; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 执行系统还原
    echo -e "\n${COLOR_SUCCESS}[开始还原] 正在还原系统配置...${COLOR_RESET}"
    echo -e "${COLOR_INFO}提示：还原过程可能需要几分钟，完成后建议重启设备！${COLOR_RESET}"
    
    local LOG_FILE="$backup_dir/system_restore_$(date +'%Y%m%d_%H%M%S').log"
    
    {
        echo "=== 系统还原开始 ==="
        echo "时间: $(date)"
        echo "备份文件: $backup_path"
        echo "压缩模式: $compress_mode"
        
        local TMP_DIR=$(mktemp -d)
        echo "临时目录: $TMP_DIR"
        
        # 解压备份文件
        if $compress_mode -d -c "$backup_path" > "$TMP_DIR/backup.overlay.tar" 2>> "$LOG_FILE"; then
            echo "解压完成，验证tar文件..."
            
            # 校验tar文件完整性
            if tar tf "$TMP_DIR/backup.overlay.tar" >/dev/null 2>&1; then
                echo "tar文件验证通过，开始系统还原..."
                
                if $SYSTEM_RESTORE_CMD "$TMP_DIR/backup.overlay.tar" >> "$LOG_FILE" 2>&1; then
                    echo "✅ 系统还原完成"
                    echo "建议执行：reboot 重启设备"
                else
                    echo "❌ 系统还原失败"
                    exit 1
                fi
            else
                echo "❌ tar文件损坏或格式不正确"
                exit 1
            fi
        else
            echo "❌ 解压过程失败"
            exit 1
        fi
        
        # 清理临时文件
        rm -rf "$TMP_DIR"
        echo "临时文件已清理"
        echo "=== 系统还原结束 ==="
    } > "$LOG_FILE" 2>&1 &
    
    local restore_pid=$!
    echo -e "\n${COLOR_SUCCESS}[还原启动成功] PID: $restore_pid${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# ==========================================
# 模块4：主菜单（修复版）
# ==========================================
show_main_menu() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}${TOOL_NAME} ${TOOL_VERSION}${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    
    echo -e "  ${COLOR_SUCCESS}1.${COLOR_RESET} 硬盘备份（完整克隆硬盘）"
    
    if [ "$HAS_SYSTEM_TOOLS" -eq 1 ]; then
        echo -e "  ${COLOR_SUCCESS}2.${COLOR_RESET} 系统备份（备份overlay配置）"
        echo -e "  ${COLOR_SUCCESS}4.${COLOR_RESET} 系统还原（恢复overlay配置）"
    else
        echo -e "  ${COLOR_WARN}2. 系统备份（功能禁用）${COLOR_RESET}"
        echo -e "  ${COLOR_WARN}4. 系统还原（功能禁用）${COLOR_RESET}"
    fi
    
    echo -e "  ${COLOR_SUCCESS}3.${COLOR_RESET} 硬盘还原（恢复完整硬盘）"
    echo -e "  ${COLOR_SUCCESS}5.${COLOR_RESET} 查看备份文件"
    echo -e "  ${COLOR_SUCCESS}0.${COLOR_RESET} 退出工具"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
}

# 查看备份文件功能
view_backups() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}📁 查看备份文件${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ $? -ne 0 ] || [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    echo -e "\n${COLOR_INFO}[备份文件概览]${COLOR_RESET}"
    
    # 显示硬盘备份
    local disk_backups=($(list_backup_files "$backup_dir" "disk"))
    if [ $? -eq 0 ]; then
        echo -e "\n${COLOR_SUCCESS}硬盘备份文件：${#disk_backups[@]} 个${COLOR_RESET}"
    else
        echo -e "\n${COLOR_WARN}硬盘备份文件：0 个${COLOR_RESET}"
    fi
    
    # 显示系统备份
    local system_backups=($(list_backup_files "$backup_dir" "system"))
    if [ $? -eq 0 ]; then
        echo -e "${COLOR_SUCCESS}系统备份文件：${#system_backups[@]} 个${COLOR_RESET}"
    else
        echo -e "${COLOR_WARN}系统备份文件：0 个${COLOR_RESET}"
    fi
    
    # 显示目录信息
    echo -e "\n${COLOR_INFO}目录信息：${COLOR_RESET}"
    echo -e "  路径：$backup_dir"
    echo -e "  总大小：$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo "未知")"
    echo -e "  可用空间：$(df -h "$backup_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "未知")"
    
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

main() {
    check_env
    while true; do
        show_main_menu
        read -p "$(echo -e "${COLOR_INFO}请选择功能（0-5）：${COLOR_RESET}")" choice
        
        case $choice in
            1) disk_backup ;;
            2) 
                if [ "$HAS_SYSTEM_TOOLS" -eq 1 ]; then
                    system_backup 
                else
                    echo -e "\n${COLOR_WARN}系统备份功能不可用${COLOR_RESET}"
                    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键继续...${COLOR_RESET}")"
                fi
                ;;
            3) disk_restore ;;
            4) 
                if [ "$HAS_SYSTEM_TOOLS" -eq 1 ]; then
                    system_restore 
                else
                    echo -e "\n${COLOR_WARN}系统还原功能不可用${COLOR_RESET}"
                    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键继续...${COLOR_RESET}")"
                fi
                ;;
            5) view_backups ;;
            0) 
                echo -e "\n${COLOR_INFO}[提示] 感谢使用，再见！${COLOR_RESET}\n"
                exit 0 
                ;;
            *) 
                echo -e "\n${COLOR_WARN}[警告] 请输入有效的选项（0-5）${COLOR_RESET}"
                read -p "$(echo -e "${COLOR_WARN}按 Enter 键继续...${COLOR_RESET}")"
                ;;
        esac
    done
}

# 启动主程序
main "$@"
