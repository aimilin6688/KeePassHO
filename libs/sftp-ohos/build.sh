#!/usr/bin/env bash
# sftp-ohos 三 ABI 交叉编译 + 产物拷贝到 ohpm HAR 目录
#
# 前置条件：
#   1. rustup 三 target 已安装：
#      rustup target add aarch64-unknown-linux-ohos armv7-unknown-linux-ohos x86_64-unknown-linux-ohos
#   2. .cargo/config.toml 已按本机 NDK 路径配置（参见 .cargo/config.toml.example）
#
# 产物：../sftp/libs/{arm64-v8a,armeabi-v7a,x86_64}/libsftp_ohos.so
# 命名约束：crate 名 sftp-ohos → napi-ohos 以 libsftp_ohos.so 注册模块名，
# ArkTS import 路径必须与文件名逐字符一致：import ... from 'libsftp_ohos.so'
set -euo pipefail

cd "$(dirname "$0")"

SCRIPT_DIR="$(pwd)"
HAR_LIBS_DIR="${SCRIPT_DIR}/../sftp/libs"
NDK_BIN="${NDK_BIN:-$(grep -m1 'linker = ' .cargo/config.toml | sed 's|.*llvm/bin/.*|&|; s|linker = "||; s|/aarch64-unknown-linux-ohos-clang"||')}"

TARGETS=(
  "aarch64-unknown-linux-ohos:arm64-v8a"
  "armv7-unknown-linux-ohos:armeabi-v7a"
  "x86_64-unknown-linux-ohos:x86_64"
)

for pair in "${TARGETS[@]}"; do
  target="${pair%%:*}"
  abi="${pair##*:}"
  echo "==> Building ${target} (${abi})"
  cargo build --target "${target}" --release

  src="target/${target}/release/libsftp_ohos.so"
  dest_dir="${HAR_LIBS_DIR}/${abi}"
  mkdir -p "${dest_dir}"
  cp "${src}" "${dest_dir}/libsftp_ohos.so"

  # 形态校验：动态依赖必须仅为 libace_napi.z.so + libc.so（对齐 @ohos-rs 产物）
  if command -v "${NDK_BIN}/llvm-readelf" >/dev/null 2>&1; then
    echo "==> readelf ${abi}"
    "${NDK_BIN}/llvm-readelf" -d "${dest_dir}/libsftp_ohos.so" | grep NEEDED
  fi
    ls -lh "${dest_dir}/libsftp_ohos.so"
done

# 打包 ohpm HAR 归档：.har 必须是 gzip tar，且根目录前缀为 package/
# （zip 布局会被 ohpm readPkgJsonFromTarball 拒绝；目录 file: 依赖是符号链接，
#   不属于任何 hvigor 模块导致 "Failed to resolve OhmUrl ... imported by undefined"）
HAR_SRC_DIR="${SCRIPT_DIR}/../sftp"
HAR_OUT="${SCRIPT_DIR}/../sftp-ohos.har"
STAGE="$(mktemp -d)/package"
mkdir -p "${STAGE}"
cp "${HAR_SRC_DIR}/oh-package.json5" "${HAR_SRC_DIR}/index.ets" "${STAGE}/"
cp -R "${HAR_SRC_DIR}/libs" "${HAR_SRC_DIR}/src" "${STAGE}/"
rm -f "${HAR_OUT}"
tar -czf "${HAR_OUT}" -C "$(dirname "${STAGE}")" package
rm -rf "$(dirname "${STAGE}")"
echo "==> Packed ${HAR_OUT}"
tar -tzf "${HAR_OUT}" | head -5

echo "==> Done. HAR libs at ${HAR_LIBS_DIR}; archive at ${HAR_OUT}"
