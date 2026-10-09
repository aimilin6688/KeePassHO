#!/bin/sh
# 切到脚本所在目录执行，避免依赖调用方的当前工作目录
#（原写法 -f e2e/docker-compose.yml 只能在 docs/ 下运行）
cd "$(dirname "$0")" || exit 1

podman compose -f docker-compose.yml up -d