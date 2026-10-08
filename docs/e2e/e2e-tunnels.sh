#!/bin/sh
# 存储回归测试 hdc 反向隧道自动 setup（S3 / WebDAV / SFTP）
#
# 用法：
#   sh docs/e2e/e2e-tunnels.sh                 # 为所有已连接设备建立隧道（幂等，可重复执行）
#   sh docs/e2e/e2e-tunnels.sh --containers    # 宿主端口不通时自动拉起 e2e 容器
#   sh docs/e2e/e2e-tunnels.sh --reset         # 强制清理重建（含僵尸监听清理）
#   sh docs/e2e/e2e-tunnels.sh -t 127.0.0.1:5555   # 仅指定设备
#
# DevEco Studio 挂钩方式见 docs/e2e/e2e-tunnels.md
# 原理与故障恢复说明见 docs/storage-regression-test.md §4
#
# 关键事实（实测，hdc command-line-tools 版本）：
# 1. rport 规则登记在宿主 hdc 服务进程，`hdc kill` / 服务重启后注册表清空；
#    设备侧 hdcd 的监听 socket 可能残留 → 成为"僵尸监听"（表面 LISTEN 实际黑洞）。
# 2. 本版本 hdc 没有 rport rm（`fport rm` 只管正向）；
#    清理僵尸监听的唯一手段是 `hdc killall-sub`（全局，异步生效）。
# 3. 可靠判据 = 主机注册表（fport ls 含本设备+端口）与设备侧 netstat 双条件同时满足。

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 隧道清单：设备端口:宿主端口:名称（新增存储后端时在此追加一行）
PORTS="9000:9000:S3
8800:8800:WebDAV
2223:2222:SFTP"

RESET=0
AUTO_CONTAINERS=0
TARGET_FILTER=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-t" ]; then
    TARGET_FILTER="$arg"; prev=""; continue
  fi
  case "$arg" in
    --reset) RESET=1 ;;
    --containers) AUTO_CONTAINERS=1 ;;
    -t) prev="-t" ;;
  esac
done

# ---------- hdc 解析：环境变量 > PATH > 常见 SDK 安装位置 ----------
resolve_hdc() {
  if [ -n "${HDC:-}" ] && [ -x "$HDC" ]; then
    echo "$HDC"; return 0
  fi
  if command -v hdc >/dev/null 2>&1; then
    command -v hdc; return 0
  fi
  for candidate in \
    "$HOME/command-line-tools/sdk/default/openharmony/toolchains/hdc" \
    "$HOME/Library/Huawei/Sdk/openharmony"/*/toolchains/hdc \
    /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc; do
    if [ -x "$candidate" ]; then
      echo "$candidate"; return 0
    fi
  done
  return 1
}

HDC_CMD=$(resolve_hdc) || {
  echo "[错误] 未找到 hdc：请将其加入 PATH，或通过环境变量 HDC 指定绝对路径"
  exit 1
}
echo "hdc: $HDC_CMD"

# ---------- 设备清单 ----------
TARGETS=$("$HDC_CMD" list targets 2>/dev/null | grep -v '^\[Empty' | grep -v '^\s*$' || true)
if [ -z "$TARGETS" ]; then
  echo "[错误] 无已连接设备（hdc list targets 为空）"
  exit 1
fi
if [ -n "$TARGET_FILTER" ]; then
  TARGETS=$(echo "$TARGETS" | grep -F "$TARGET_FILTER" || true)
  if [ -z "$TARGETS" ]; then
    echo "[错误] 设备 $TARGET_FILTER 不在线"
    exit 1
  fi
fi

# ---------- 基础探测 ----------
# 主机注册表是否含 <target> 的 <dport> 反向规则（fport ls 为全局表，按目标列过滤）
registry_has() {
  "$HDC_CMD" fport ls 2>/dev/null | grep -F "$1" | grep -qF "tcp:$2"
}
# 设备侧是否处于 LISTEN <port>（锚定 LISTEN 关键字 + 端口后随空白：
# 部分模拟器 netstat 的 -l 参数失效会列出全部状态，需显式过滤，避免被应用残留的
# ESTABLISHED/CLOSE_WAIT 客户端 socket 误判为"已有隧道"）
device_listening() {
  "$HDC_CMD" -t "$1" shell "netstat -tln 2>/dev/null | grep 'LISTEN' | grep -q '127.0.0.1:$2 '" >/dev/null 2>&1
}

# ---------- 宿主侧连通性（容器发布端口） ----------
host_port_ok() {
  nc -z -w 2 127.0.0.1 "$1" >/dev/null 2>&1
}

containers_down=0
for line in $PORTS; do
  hport=$(echo "$line" | cut -d: -f2)
  host_port_ok "$hport" || containers_down=1
done
if [ "$containers_down" = "1" ]; then
  if [ "$AUTO_CONTAINERS" = "1" ]; then
    echo "[容器] 宿主端口不通，自动拉起 e2e 容器..."
    sh "$SCRIPT_DIR/e2e-fileserver.sh"
    sleep 3
  else
    echo "[警告] 宿主侧存在不通的端口（容器未启动？）"
    echo "        手动拉起：sh $SCRIPT_DIR/e2e-fileserver.sh，或本脚本加 --containers"
  fi
fi

# ---------- Pass 1：逐设备逐端口分类 ----------
# ready    = 注册表 + 设备监听双满足
# zombie   = 设备监听但注册表无（hdc 重启残留黑洞，表面 LISTEN 实际不通）
# missing  = 两侧皆无，需新建
zombie_targets=""
plan_create=""
for target in $TARGETS; do
  for line in $PORTS; do
    dport=$(echo "$line" | cut -d: -f1)
    if registry_has "$target" "$dport" && device_listening "$target" "$dport"; then
      continue
    fi
    if device_listening "$target" "$dport"; then
      zombie_targets="$zombie_targets $target:$dport"
    fi
    plan_create="$plan_create $target:$dport:$line"
  done
done

# ---------- Pass 2：清理僵尸监听 ----------
if [ -n "$zombie_targets" ] || [ "$RESET" = "1" ]; then
  echo "[清理] 检测到僵尸监听（hdc 重启残留黑洞），执行 hdc killall-sub（全局，异步生效）..."
  "$HDC_CMD" killall-sub >/dev/null 2>&1
  # 等待设备侧监听消失（最多 10s），避免 rport 撞上残留 socket
  wait_rounds=0
  while [ $wait_rounds -lt 10 ]; do
    sleep 1
    wait_rounds=$((wait_rounds + 1))
    cleared=1
    for item in $zombie_targets; do
      t=$(echo "$item" | cut -d: -f1)
      p=$(echo "$item" | cut -d: -f2)
      device_listening "$t" "$p" && cleared=0
    done
    [ "$cleared" = "1" ] && break
  done
  if [ "$cleared" = "1" ]; then
    echo "[清理] 僵尸监听已清除（等待 ${wait_rounds}s）"
  else
    echo "[警告] 部分僵尸监听未在 10s 内消失，重建可能失败；可重跑本脚本或重启模拟器"
  fi
  # RESET 语义：注册表里的旧规则一并废弃，全部走重建
  if [ "$RESET" = "1" ]; then
    plan_create=""
    for target in $TARGETS; do
      for line in $PORTS; do
        plan_create="$plan_create $target:$line:$line"
      done
    done
  fi
fi

# ---------- Pass 3：建立隧道并双条件校验 ----------
fail_total=0
for target in $TARGETS; do
  echo ""
  echo "=== 设备 $target ==="
  for line in $PORTS; do
    dport=$(echo "$line" | cut -d: -f1)
    hport=$(echo "$line" | cut -d: -f2)
    name=$(echo "$line" | cut -d: -f3)

    if registry_has "$target" "$dport" && device_listening "$target" "$dport"; then
      echo "  [$name] 设备 $dport → 宿主 $hport ：已就绪"
      continue
    fi

    result=$("$HDC_CMD" -t "$target" rport "tcp:$dport" "tcp:$hport" 2>&1)
    case "$result" in
      *OK*) : ;;
      *)
        echo "  [$name] 建立失败：$result"
        fail_total=$((fail_total + 1))
        continue
        ;;
    esac
    # 建立后双条件复核（注册表立即生效；设备侧监听可能需要短暂时间）
    ok=0
    check_rounds=0
    while [ $check_rounds -lt 5 ]; do
      if registry_has "$target" "$dport" && device_listening "$target" "$dport"; then
        ok=1
        break
      fi
      sleep 1
      check_rounds=$((check_rounds + 1))
    done
    if [ "$ok" = "1" ]; then
      echo "  [$name] 设备 $dport → 宿主 $hport ：建立成功"
    else
      echo "  [$name] 建立后校验未通过（注册表/设备监听缺一），请复查"
      fail_total=$((fail_total + 1))
    fi
  done
done

echo ""
if [ "$fail_total" = "0" ]; then
  echo "全部隧道就绪 ✔（hdc 重启/设备重连后需重跑本脚本；DevEco 挂钩方式见 docs/e2e/e2e-tunnels.md）"
  exit 0
fi
echo "存在 $fail_total 条失败隧道 ✘"
exit 1
