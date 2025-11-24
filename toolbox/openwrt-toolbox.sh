#!/bin/bash
# OpenWrt 工具箱 v2.2（模块化交互框架 + 完整备份还原模块）
clear

# ==========================================
# 模块1：基础配置（颜色、常量、环境检测）
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
TOOL_VERSION="v2.2"
TOOL_AUTHOR="自定义作者"
TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 60)  # 自适应终端宽度
BORDER_CHAR="="
SEPARATOR_CHAR="-"

# 备份核心配置
DEFAULT_BACKUP_DIR="/mnt/mmc0-1/istore_backup"  # 默认备份目录
COMPRESS_MODES=("xz" "zstd" "gzip")             # 支持的压缩模式
COMPRESS_LEVELS=("-9" "-1" "-9")                # 对应压缩级别（高/快/标准）
COMPRESS_DESCS=("高压缩（体积最小，速度最慢）" "快速压缩（速度优先，压缩比适中）" "标准压缩（平衡速度与体积）")
BACKUP_TYPES=("disk" "system")                  # 备份类型：硬盘/系统
SYSTEM_BACKUP_CMD="/usr/libexec/istore/overlay-backup backup"  # 系统备份命令
SYSTEM_RESTORE_CMD="/usr/libexec/istore/overlay-backup to /var/run/cloned-overlay-backup when restore restoring from"  # 系统还原命令

# 环境检测（基础校验）
check_env() {
    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\n${COLOR_DANGER}[错误] 请使用 root 用户执行（sudo -i 或 su root）${COLOR_RESET}"
        exit 1
    fi

    # 检查 OpenWrt 系统
    if [ ! -f "/etc/openwrt_release" ]; then
        echo -e "\n${COLOR_WARN}[警告] 未检测到 OpenWrt 系统，部分功能可能无法正常使用${COLOR_RESET}"
        read -p "$(echo -e "${COLOR_WARN}是否继续？(y/n) ${COLOR_RESET}")" -n 1 -r
        echo -e "\n"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # 检查必要命令
    local required_cmds=("dd" "md5sum" "tar" "mount" "umount" "lsblk" "grep" "awk")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "\n${COLOR_DANGER}[错误] 缺少必要命令：$cmd，请先执行 opkg install $cmd${COLOR_RESET}"
            exit 1
        fi
    done

    # 检查系统备份工具
    if [ ! -x "$(echo "$SYSTEM_BACKUP_CMD" | awk '{print $1}')" ]; then
        echo -e "\n${COLOR_WARN}[警告] 未检测到系统备份工具（${SYSTEM_BACKUP_CMD%% *}），系统备份/还原功能不可用${COLOR_RESET}"
        read -p "$(echo -e "${COLOR_WARN}是否继续使用其他功能？(y/n) ${COLOR_RESET}")" -n 1 -r
        echo -e "\n"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ==========================================
# 模块2：工具函数（备份还原核心逻辑）
# ==========================================
# 绘制边框（自适应宽度）
draw_border() {
    printf "%${TERMINAL_WIDTH}s\n" | tr " " "$1"
}

# 居中显示文本
center_text() {
    local text="$1"
    local padding=$(( (TERMINAL_WIDTH - ${#text}) / 2 ))
    printf "%${padding}s%s%${padding}s\n" "" "$text" ""
}

# 获取设备型号（从系统提取，失败则默认）
get_device_model() {
    local model
    if [ -f "/etc/openwrt_release" ]; then
        model=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | awk -F '"' '{print $2}' | sed 's/ /_/g' | cut -d '_' -f1-2)
    fi
    echo "${model:-OpenWrt_Device}"
}

# 获取主机名（替换空格）
get_hostname() {
    hostname | sed 's/ /_/g'
}

# 生成备份文件名（设备型号+主机名+时间戳）
generate_backup_filename() {
    local backup_type="$1"  # disk/system
    local compress_mode="$2"
    local model=$(get_device_model)
    local hostname=$(get_hostname)
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    
    # 区分备份类型后缀
    local suffix
    if [ "$backup_type" = "disk" ]; then
        suffix="disk.img.${compress_mode}"
    else
        suffix="system.overlay.tar.${compress_mode}"
    fi
    
    echo "${model}_${hostname}_${timestamp}.${suffix}"
}

# 列出可用硬盘（过滤非物理设备）
list_available_disks() {
    echo -e "\n${COLOR_INFO}[可用硬盘设备]${COLOR_RESET}"
    # 过滤 disk/part 类型，排除 loop/tmpfs 等虚拟设备
    local disks=($(lsblk -dn -o NAME,TYPE | grep -E 'disk|part' | awk '{print "/dev/" $1}' | grep -v 'loop' | grep -v 'tmpfs' | grep -v 'sr'))
    
    if [ ${#disks[@]} -eq 0 ]; then
        echo -e "${COLOR_WARN}  未检测到可用物理硬盘${COLOR_RESET}"
        return 1
    fi
    
    # 显示硬盘列表（带容量）
    for i in "${!disks[@]}"; do
        local disk=${disks[$i]}
        local size=$(lsblk -dn -o SIZE "$disk" 2>/dev/null || echo "未知")
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} $disk （容量：$size）"
    done
    echo ""
    echo "${disks[@]}"  # 返回硬盘数组（供选择）
}

# 选择备份目录（默认/自定义）
select_backup_dir() {
    echo -e "\n${COLOR_INFO}[选择备份目录]${COLOR_RESET}"
    echo -e "  ${COLOR_SUCCESS}1.${COLOR_RESET} 使用默认目录：${DEFAULT_BACKUP_DIR}"
    echo -e "  ${COLOR_SUCCESS}2.${COLOR_RESET} 自定义备份目录"
    read -p "$(echo -e "${COLOR_INFO}请选择（默认1）：${COLOR_RESET}")" dir_choice

    # 默认选择1
    if [ -z "$dir_choice" ] || [ "$dir_choice" -eq 1 ]; then
        backup_dir="$DEFAULT_BACKUP_DIR"
    else
        read -p "$(echo -e "${COLOR_INFO}请输入自定义目录路径：${COLOR_RESET}")" backup_dir
        # 校验目录有效性
        if [ -z "$backup_dir" ]; then
            echo -e "${COLOR_WARN}[警告] 目录路径不能为空，使用默认目录${COLOR_RESET}"
            backup_dir="$DEFAULT_BACKUP_DIR"
        fi
    fi

    # 创建目录（若不存在）
    if [ ! -d "$backup_dir" ]; then
        echo -e "\n${COLOR_INFO}[提示] 目录 $backup_dir 不存在，正在创建...${COLOR_RESET}"
        if ! mkdir -p "$backup_dir"; then
            echo -e "${COLOR_DANGER}[错误] 目录创建失败，请检查权限${COLOR_RESET}"
            return 1
        fi
    fi

    echo -e "\n${COLOR_SUCCESS}[确认] 备份目录：$backup_dir${COLOR_RESET}"
    echo "$backup_dir"  # 返回选择的目录
}

# 选择压缩模式
select_compress_mode() {
    echo -e "\n${COLOR_INFO}[选择压缩模式]${COLOR_RESET}"
    for i in "${!COMPRESS_MODES[@]}"; do
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} ${COMPRESS_MODES[$i]} —— ${COMPRESS_DESCS[$i]}（压缩级别：${COMPRESS_LEVELS[$i]}）"
    done
    read -p "$(echo -e "${COLOR_INFO}请选择（默认1）：${COLOR_RESET}")" compress_choice

    # 默认选择1（xz）
    if [ -z "$compress_choice" ] || [ "$compress_choice" -lt 1 ] || [ "$compress_choice" -gt ${#COMPRESS_MODES[@]} ]; then
        compress_choice=1
    fi

    local index=$((compress_choice - 1))
    local compress_mode=${COMPRESS_MODES[$index]}
    local compress_level=${COMPRESS_LEVELS[$index]}

    echo -e "\n${COLOR_SUCCESS}[确认] 压缩模式：$compress_mode（级别：$compress_level）${COLOR_RESET}"
    echo "$compress_mode $compress_level"  # 返回模式和级别
}

# 列出指定目录的备份文件（按时间倒序，区分备份类型）
list_backup_files() {
    local backup_dir="$1"
    local backup_type="$2"  # disk/system
    local file_pattern

    # 匹配对应类型的备份文件
    if [ "$backup_type" = "disk" ]; then
        file_pattern="*.disk.img.*"
    else
        file_pattern="*.system.overlay.tar.*"
    fi

    echo -e "\n${COLOR_INFO}[${backup_type^} 备份文件列表]（目录：$backup_dir）${COLOR_RESET}"
    # 按修改时间倒序排列（最新在前）
    local backups=($(ls -t "$backup_dir"/$file_pattern 2>/dev/null | grep -v ".md5"))

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${COLOR_WARN}  未找到 $backup_type 备份文件${COLOR_RESET}"
        return 1
    fi

    # 显示备份列表（带序号、文件名、大小、修改时间）
    for i in "${!backups[@]}"; do
        local file=${backups[$i]}
        local filename=$(basename "$file")
        local size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
        local mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d ' ' -f1-2)
        echo -e "  ${COLOR_SUCCESS}$((i+1)).${COLOR_RESET} $filename"
        echo -e "      大小：$size | 修改时间：$mtime"
    done
    echo ""
    echo "${backups[@]}"  # 返回备份文件数组
}

# ==========================================
# 模块3：备份还原功能实现
# ==========================================
# 1. 硬盘备份
disk_backup() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}💾 硬盘备份功能${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 步骤1：选择备份硬盘
    local disks=($(list_available_disks))
    if [ ${#disks[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    read -p "$(echo -e "${COLOR_INFO}请选择要备份的硬盘序号（默认1）：${COLOR_RESET}")" disk_choice
    if [ -z "$disk_choice" ] || [ "$disk_choice" -lt 1 ] || [ "$disk_choice" -gt ${#disks[@]} ]; then
        disk_choice=1
    fi
    local source_disk=${disks[$((disk_choice - 1))]}
    echo -e "\n${COLOR_SUCCESS}[确认] 备份源硬盘：$source_disk${COLOR_RESET}"

    # 步骤2：选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤3：选择压缩模式
    local compress_info=$(select_compress_mode)
    local compress_mode=$(echo "$compress_info" | awk '{print $1}')
    local compress_level=$(echo "$compress_info" | awk '{print $2}')

    # 步骤4：生成备份文件名
    local backup_filename=$(generate_backup_filename "disk" "$compress_mode")
    local backup_path="$backup_dir/$backup_filename"
    local md5_path="$backup_path.md5"

    # 步骤5：确认备份信息
    echo -e "\n${COLOR_INFO}[备份信息确认]${COLOR_RESET}"
    echo -e "  源硬盘：$source_disk"
    echo -e "  备份路径：$backup_path"
    echo -e "  压缩模式：$compress_mode $compress_level"
    echo -e "  校验文件：$md5_path"
    read -p "$(echo -e "\n${COLOR_WARN}是否开始备份？(y/n，默认n) ${COLOR_RESET}")" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_INFO}[提示] 备份已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤6：执行备份（umount 避免占用，后台运行+日志）
    echo -e "\n${COLOR_SUCCESS}[开始备份] 正在备份 $source_disk 到 $backup_path...${COLOR_RESET}"
    echo -e "${COLOR_INFO}提示：备份过程可能较长，请耐心等待，请勿中断！${COLOR_RESET}"
    
    # 卸载硬盘分区（避免占用）
    umount "${source_disk}"* 2>/dev/null

    # 执行备份命令（后台运行，输出日志）
    LOG_FILE="$backup_dir/disk_backup_$(date +'%Y%m%d_%H%M%S').log"
    nohup bash -c "
        dd if=$source_disk bs=1M status=progress oflag=direct | $compress_mode $compress_level > '$backup_path' && \
        md5sum '$backup_path' > '$md5_path' && \
        md5sum -c '$md5_path' >> '$LOG_FILE' 2>&1 && \
        echo '[$(date +'%Y-%m-%d %H:%M:%S')] 硬盘备份完成，校验成功' >> '$LOG_FILE'
    " > "$LOG_FILE" 2>&1 &

    echo -e "\n${COLOR_SUCCESS}[备份启动成功]${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 2. 系统备份
system_backup() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🖥️  系统备份功能${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 步骤1：选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤2：选择压缩模式（系统备份命令支持管道压缩）
    local compress_info=$(select_compress_mode)
    local compress_mode=$(echo "$compress_info" | awk '{print $1}')
    local compress_level=$(echo "$compress_info" | awk '{print $2}')

    # 步骤3：生成备份文件名
    local backup_filename=$(generate_backup_filename "system" "$compress_mode")
    local backup_path="$backup_dir/$backup_filename"
    local md5_path="$backup_path.md5"

    # 步骤4：确认备份信息
    echo -e "\n${COLOR_INFO}[备份信息确认]${COLOR_RESET}"
    echo -e "  备份工具：${SYSTEM_BACKUP_CMD%% *}"
    echo -e "  备份路径：$backup_path"
    echo -e "  压缩模式：$compress_mode $compress_level"
    echo -e "  校验文件：$md5_path"
    read -p "$(echo -e "\n${COLOR_WARN}是否开始备份？(y/n，默认n) ${COLOR_RESET}")" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_INFO}[提示] 备份已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤5：执行系统备份（调用 istore 工具+管道压缩）
    echo -e "\n${COLOR_SUCCESS}[开始备份] 正在备份系统到 $backup_path...${COLOR_RESET}"
    LOG_FILE="$backup_dir/system_backup_$(date +'%Y%m%d_%H%M%S').log"

    nohup bash -c "
        $SYSTEM_BACKUP_CMD - | $compress_mode $compress_level > '$backup_path' && \
        md5sum '$backup_path' > '$md5_path' && \
        md5sum -c '$md5_path' >> '$LOG_FILE' 2>&1 && \
        echo '[$(date +'%Y-%m-%d %H:%M:%S')] 系统备份完成，校验成功' >> '$LOG_FILE'
    " > "$LOG_FILE" 2>&1 &

    echo -e "\n${COLOR_SUCCESS}[备份启动成功]${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 3. 硬盘还原
disk_restore() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🔄 硬盘还原功能${COLOR_RESET}"
    echo -e "${COLOR_DANGER}⚠️  警告：还原会覆盖目标硬盘数据，请谨慎操作！${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 步骤1：选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤2：列出硬盘备份文件（默认选最新）
    local backups=($(list_backup_files "$backup_dir" "disk"))
    if [ ${#backups[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择备份文件（默认1=最新）
    read -p "$(echo -e "${COLOR_INFO}请选择要还原的备份序号（默认1=最新）：${COLOR_RESET}")" backup_choice
    if [ -z "$backup_choice" ] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
        backup_choice=1
    fi
    local backup_path=${backups[$((backup_choice - 1))]}
    local md5_path="$backup_path.md5"
    local compress_mode=$(basename "$backup_path" | awk -F '.' '{print $NF}')

    # 步骤3：选择目标硬盘（要还原到的硬盘）
    local disks=($(list_available_disks))
    if [ ${#disks[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi
    read -p "$(echo -e "${COLOR_INFO}请选择目标还原硬盘序号（默认1）：${COLOR_RESET}")" disk_choice
    if [ -z "$disk_choice" ] || [ "$disk_choice" -lt 1 ] || [ "$disk_choice" -gt ${#disks[@]} ]; then
        disk_choice=1
    fi
    local target_disk=${disks[$((disk_choice - 1))]}

    # 步骤4：确认还原信息（二次警告）
    echo -e "\n${COLOR_DANGER}[还原警告] 即将覆盖 $target_disk 的所有数据！${COLOR_RESET}"
    echo -e "${COLOR_INFO}[还原信息确认]${COLOR_RESET}"
    echo -e "  备份文件：$backup_path"
    echo -e "  目标硬盘：$target_disk"
    echo -e "  压缩模式：$compress_mode"
    read -p "$(echo -e "\n${COLOR_DANGER}请输入 'YES' 确认还原（输入其他取消）：${COLOR_RESET}")" confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${COLOR_INFO}[提示] 还原已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤5：校验备份文件完整性
    echo -e "\n${COLOR_INFO}[校验备份] 正在校验 $backup_path 的完整性...${COLOR_RESET}"
    if [ -f "$md5_path" ]; then
        if ! md5sum -c "$md5_path" >/dev/null 2>&1; then
            echo -e "${COLOR_DANGER}[错误] 备份文件校验失败，可能已损坏！${COLOR_RESET}"
            read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
            return
        fi
        echo -e "${COLOR_SUCCESS}[校验成功] 备份文件完整${COLOR_RESET}"
    else
        echo -e "${COLOR_WARN}[警告] 未找到校验文件 $md5_path，将跳过校验${COLOR_RESET}"
    fi

    # 步骤6：执行还原
    echo -e "\n${COLOR_SUCCESS}[开始还原] 正在还原 $backup_path 到 $target_disk...${COLOR_RESET}"
    echo -e "${COLOR_INFO}提示：还原过程不可中断，完成后建议重启设备！${COLOR_RESET}"
    
    # 卸载目标硬盘分区
    umount "${target_disk}"* 2>/dev/null

    # 执行还原命令（根据压缩模式解压并写入硬盘）
    LOG_FILE="$backup_dir/disk_restore_$(date +'%Y%m%d_%H%M%S').log"
    nohup bash -c "
        $compress_mode -d -c '$backup_path' | dd of=$target_disk bs=1M status=progress oflag=direct && \
        echo '[$(date +'%Y-%m-%d %H:%M:%S')] 硬盘还原完成' >> '$LOG_FILE'
    " > "$LOG_FILE" 2>&1 &

    echo -e "\n${COLOR_SUCCESS}[还原启动成功]${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 4. 系统还原
system_restore() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🔄 系统还原功能${COLOR_RESET}"
    echo -e "${COLOR_DANGER}⚠️  警告：系统还原会覆盖当前系统配置，可能需要重启！${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"

    # 步骤1：选择备份目录
    local backup_dir=$(select_backup_dir)
    if [ -z "$backup_dir" ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤2：列出系统备份文件（默认选最新）
    local backups=($(list_backup_files "$backup_dir" "system"))
    if [ ${#backups[@]} -eq 0 ]; then
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 选择备份文件（默认1=最新）
    read -p "$(echo -e "${COLOR_INFO}请选择要还原的备份序号（默认1=最新）：${COLOR_RESET}")" backup_choice
    if [ -z "$backup_choice" ] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
        backup_choice=1
    fi
    local backup_path=${backups[$((backup_choice - 1))]}
    local md5_path="$backup_path.md5"
    local compress_mode=$(basename "$backup_path" | awk -F '.' '{print $NF}')

    # 步骤3：确认还原信息（二次警告）
    echo -e "\n${COLOR_DANGER}[还原警告] 即将还原系统配置，可能导致服务中断！${COLOR_RESET}"
    echo -e "${COLOR_INFO}[还原信息确认]${COLOR_RESET}"
    echo -e "  备份文件：$backup_path"
    echo -e "  压缩模式：$compress_mode"
    echo -e "  还原工具：${SYSTEM_RESTORE_CMD%% *}"
    read -p "$(echo -e "\n${COLOR_DANGER}请输入 'YES' 确认还原（输入其他取消）：${COLOR_RESET}")" confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${COLOR_INFO}[提示] 还原已取消${COLOR_RESET}"
        read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
        return
    fi

    # 步骤4：校验备份文件完整性
    echo -e "\n${COLOR_INFO}[校验备份] 正在校验 $backup_path 的完整性...${COLOR_RESET}"
    if [ -f "$md5_path" ]; then
        if ! md5sum -c "$md5_path" >/dev/null 2>&1; then
            echo -e "${COLOR_DANGER}[错误] 备份文件校验失败，可能已损坏！${COLOR_RESET}"
            read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
            return
        fi
        echo -e "${COLOR_SUCCESS}[校验成功] 备份文件完整${COLOR_RESET}"
    else
        echo -e "${COLOR_WARN}[警告] 未找到校验文件 $md5_path，将跳过校验${COLOR_RESET}"
    fi

    # 步骤5：执行系统还原（解压备份文件并调用 istore 工具）
    echo -e "\n${COLOR_SUCCESS}[开始还原] 正在还原系统配置...${COLOR_RESET}"
    LOG_FILE="$backup_dir/system_restore_$(date +'%Y%m%d_%H%M%S').log"

    nohup bash -c "
        # 解压备份文件到临时目录
        TMP_DIR=\$(mktemp -d)
        $compress_mode -d -c '$backup_path' > \$TMP_DIR/backup.overlay.tar && \
        # 调用 istore 还原命令
        $SYSTEM_RESTORE_CMD \$TMP_DIR/backup.overlay.tar && \
        # 清理临时文件
        rm -rf \$TMP_DIR && \
        echo '[$(date +'%Y-%m-%d %H:%M:%S')] 系统还原完成，建议重启设备' >> '$LOG_FILE'
    " > "$LOG_FILE" 2>&1 &

    echo -e "\n${COLOR_SUCCESS}[还原启动成功]${COLOR_RESET}"
    echo -e "  日志文件：$LOG_FILE"
    echo -e "  查看进度：tail -f $LOG_FILE"
    echo -e "${COLOR_WARN}[提示] 还原完成后请重启设备以应用配置！${COLOR_RESET}"
    read -p "$(echo -e "\n${COLOR_WARN}按 Enter 键返回...${COLOR_RESET}")"
}

# 备份还原子菜单
show_backup_restore_menu() {
    while true; do
        clear
        local border=$(draw_border "$BORDER_CHAR")
        echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
        center_text "${COLOR_SUCCESS}📦 备份与还原模块${COLOR_RESET}"
        echo -e "${COLOR_INFO}  支持硬盘/系统备份，xz/zstd/gzip 压缩${COLOR_RESET}"
        echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
        echo ""

        echo -e "${COLOR_WARN}【备份功能】${COLOR_RESET}"
        echo -e "  ${COLOR_SUCCESS}1.${COLOR_RESET} 💾 硬盘备份   —— 选择硬盘+目录+压缩模式"
        echo -e "  ${COLOR_SUCCESS}2.${COLOR_RESET} 🖥️  系统备份   —— 基于 istore overlay 备份"
        echo ""

        echo -e "${COLOR_WARN}【还原功能】${COLOR_RESET}"
        echo -e "  ${COLOR_SUCCESS}3.${COLOR_RESET} 🔄 硬盘还原   —— 默认最新备份，支持历史选择"
        echo -e "  ${COLOR_SUCCESS}4.${COLOR_RESET} 🔄 系统还原   —— 默认最新备份，支持历史选择"
        echo ""

        echo -e "${COLOR_WARN}【其他】${COLOR_RESET}"
        echo -e "  ${COLOR_SUCCESS}5.${COLOR_RESET} 🚪 返回主菜单"
        echo ""

        echo -e "${COLOR_PRIMARY}$(draw_border "$SEPARATOR_CHAR")${COLOR_RESET}"
        read -p "$(echo -e "${COLOR_INFO}请选择功能 [1-5]：${COLOR_RESET}")" choice

        case $choice in
            1) disk_backup ;;
            2) system_backup ;;
            3) disk_restore ;;
            4) system_restore ;;
            5) return ;;
            *)
                echo -e "\n${COLOR_DANGER}[错误] 无效选择！请输入 1-5 之间的数字${COLOR_RESET}"
                sleep 1.5
                ;;
        esac
    done
}

# ==========================================
# 模块4：主菜单与程序入口
# ==========================================
# 主菜单
show_main_menu() {
    clear
    local border=$(draw_border "$BORDER_CHAR")
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    center_text "${COLOR_SUCCESS}🛠️  $TOOL_NAME $TOOL_VERSION${COLOR_RESET}"
    center_text "${COLOR_INFO}💻 适配 OpenWrt 全场景工具集${COLOR_RESET}"
    center_text "${COLOR_WARN}👤 作者：$TOOL_AUTHOR${COLOR_RESET}"
    echo -e "${COLOR_PRIMARY}$border${COLOR_RESET}"
    echo ""

    echo -e "${COLOR_WARN}【核心功能】${COLOR_RESET}"
    echo -e "  ${COLOR_SUCCESS}1.${COLOR_RESET} 📦 备份与还原   —— 硬盘/系统备份+还原（支持3种压缩）"
    echo ""

    echo -e "${COLOR_WARN}【其他】${COLOR_RESET}"
    echo -e "  ${COLOR_SUCCESS}2.${COLOR_RESET} 🚪 退出工具箱"
    echo ""

    echo -e "${COLOR_PRIMARY}$(draw_border "$SEPARATOR_CHAR")${COLOR_RESET}"
    read -p "$(echo -e "${COLOR_INFO}请选择功能 [1-2]：${COLOR_RESET}")" choice
}

# 主程序入口
main() {
    # 初始化环境检测
    check_env

    # 主循环
    while true; do
        show_main_menu
        case $choice in
            1) show_backup_restore_menu ;;
            2)
                echo -e "\n${COLOR_SUCCESS}👋 感谢使用 $TOOL_NAME $TOOL_VERSION，再见！${COLOR_RESET}"
                echo -e "${COLOR_PRIMARY}$(draw_border "$BORDER_CHAR")${COLOR_RESET}"
                exit 0
                ;;
            *)
                echo -e "\n${COLOR_DANGER}[错误] 无效选择！请输入 1-2 之间的数字${COLOR_RESET}"
                sleep 1.5
                ;;
        esac
    done
}

# 启动程序
main
