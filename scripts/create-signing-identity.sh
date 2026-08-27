#!/usr/bin/env bash
set -euo pipefail

# 创建 / 复用一张稳定的本机自签 code-signing 身份，供 IntentCapture 打包使用。
#
# 为什么需要它：ad-hoc 签名（codesign --sign -）每次编译 cdhash 都变，macOS TCC
# 会把辅助功能 / 屏幕录制授权视为“换了个 App”而失效，逼你每装新版都移除旧条目再重加。
# 用一张固定不变的签名身份，Designated Requirement 跨版本保持一致，授权就能保留。
#
# 设计要点：
# - 用独立 keychain（intentcapture-signing），不碰 login keychain 密码，全程非交互。
# - set-key-partition-list 预授权 codesign 访问私钥，构建时不弹“允许使用密钥”对话框。
# - 幂等：身份已存在则直接复用退出。
#
# 卸载：security delete-keychain intentcapture-signing.keychain

IDENTITY_CN="IntentCapture Local Signing"
KEYCHAIN_NAME="intentcapture-signing.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_PW="intentcapture-local"   # 本机自用固定口令，非机密；仅解锁这张专用 keychain

# 已存在则复用（幂等）
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_CN"; then
  echo "已存在签名身份：$IDENTITY_CN（复用，未改动）"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "缺少 openssl" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. 生成私钥 + 自签证书（含 Code Signing 扩展用途）
cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY_CN
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$KEYCHAIN_PW" -name "$IDENTITY_CN" >/dev/null 2>&1

# 2. 独立 keychain（重建以保证干净）
security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN_NAME"
security set-keychain-settings "$KEYCHAIN_PATH"          # 去掉自动锁 / 超时
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN_PATH"

# 3. 导入身份并预授权 codesign 无提示访问私钥
security import "$WORK/identity.p12" -k "$KEYCHAIN_PATH" -P "$KEYCHAIN_PW" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,unsigned: -s -k "$KEYCHAIN_PW" "$KEYCHAIN_PATH" >/dev/null

# 4. 加入用户 keychain 搜索列表，让 codesign / find-identity 找得到
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
# shellcheck disable=SC2086
security list-keychains -d user -s $EXISTING "$KEYCHAIN_PATH"

echo "已创建稳定签名身份：$IDENTITY_CN"
security find-identity -v -p codesigning "$KEYCHAIN_PATH"
