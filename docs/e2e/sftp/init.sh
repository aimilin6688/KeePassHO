#!/bin/sh
# atmoz/sftp 启动钩子：entrypoint 在创建用户后、启动 sshd 前以 root 身份 source 本文件。
# 由 e2e/docker-compose.yml 挂载到 /etc/sftp.d/init.sh。

# chroot 根目录必须 root:root 755（sshd 硬性要求）。
# 错误做法：把 /home/e2e 整体 chown 给用户 -> "bad ownership or modes for chroot directory"
# -> 密码认证成功后会话立即断开（App 侧表现为连接卡死，极易误判为客户端 bug）
chown root:root /home/e2e
chmod 755 /home/e2e

# 用户可写数据目录（SFTP 客户端视角为 /data/）
mkdir -p /home/e2e/data
chown 1001:100 /home/e2e/data

# 空闲 15 秒主动断开连接（SFTPHandlerTest 空闲断连场景专用）。
# 不需要该场景的设备可删除本段。
if ! grep -q '^ClientAliveInterval' /etc/ssh/sshd_config; then
  printf '\nClientAliveInterval 15\nClientAliveCountMax 1\n' >> /etc/ssh/sshd_config
fi
