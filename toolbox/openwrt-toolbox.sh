#  手动备份命令

### 1. gzip 压缩（兼容性优先）
```bash
BACKUP_DIR="/mnt/mmc0-1/istore_backup"; TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S"); FILENAME="Hlink H28K-iStoreOS ${TIMESTAMP}.img.gz"; FILE_PATH="${BACKUP_DIR}/${FILENAME}"; mkdir -p "${BACKUP_DIR}"; dd if=/dev/mmcblk1 bs=1M status=progress | gzip -6 > "${FILE_PATH}" && md5sum "${FILE_PATH}" > "${FILE_PATH}.md5" && echo "备份完成！文件路径：${FILE_PATH}"
```

### 2. xz 压缩（压缩率优先）
```bash
BACKUP_DIR="/mnt/mmc0-1/istore_backup"; TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S"); FILENAME="Hlink H28K-iStoreOS ${TIMESTAMP}.img.xz"; FILE_PATH="${BACKUP_DIR}/${FILENAME}"; mkdir -p "${BACKUP_DIR}"; dd if=/dev/mmcblk1 bs=1M status=progress | xz -9 > "${FILE_PATH}" && md5sum "${FILE_PATH}" > "${FILE_PATH}.md5" && echo "备份完成！文件路径：${FILE_PATH}"
```

### 3. zstd 压缩（性能平衡，现代首选）
```bash
BACKUP_DIR="/mnt/mmc0-1/istore_backup"; TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S"); FILENAME="Hlink H28K-iStoreOS ${TIMESTAMP}.img.zst"; FILE_PATH="${BACKUP_DIR}/${FILENAME}"; mkdir -p "${BACKUP_DIR}"; dd if=/dev/mmcblk1 bs=1M status=progress | zstd -1 > "${FILE_PATH}" && md5sum "${FILE_PATH}" > "${FILE_PATH}.md5" && echo "备份完成！文件路径：${FILE_PATH}"
```

### 4. lz4 压缩（极速压缩/解压，低资源占用）
```bash
BACKUP_DIR="/mnt/mmc0-1/istore_backup"; TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S"); FILENAME="Hlink H28K-iStoreOS ${TIMESTAMP}.img.lz4"; FILE_PATH="${BACKUP_DIR}/${FILENAME}"; mkdir -p "${BACKUP_DIR}"; dd if=/dev/mmcblk1 bs=1M status=progress | lz4 -1 > "${FILE_PATH}" && md5sum "${FILE_PATH}" > "${FILE_PATH}.md5" && echo "备份完成！文件路径：${FILE_PATH}"
```




## 查看磁盘分区
fdisk -l

1. 更新软件包列表（iStoreOS 基于 OpenWRT，用 opkg 包管理器）
opkg update

2. 安装 lz4 工具
opkg install lz4 gzip xz zstd


---

## 恢复前验证校验码（确保文件未损坏）
```
md5sum -c "  文件目录 "
```

## 恢复命令（如需还原硬盘）
```
gzip -d -c "/mnt/mmc0-1/istore_backup/Hlink H28K-iStoreOS 24.10.4.img.gz" | dd of=/dev/mmcblk1 bs=1M status=progress
```


备份命令
```
/usr/libexec/istore/overlay-backup backup /mnt/nvme0n1-1/istore_backup
```
恢复命令
```
/usr/libexec/istore/overlay-backup to /var/run/cloned-overlay-backup when restore restoring from /mnt/mmc0-1/istore_backup/backup_overlay_iStoreOS_iStoreOS-24.10.4_2025-1117-0628.overlay.tar.gz
```
