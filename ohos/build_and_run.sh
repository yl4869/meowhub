#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# MeowHub HarmonyOS 一键构建 + 签名 + 安装 + 启动
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIGN_DIR="$SCRIPT_DIR/debug-signing"
HAP_SIGN_TOOL="${HOS_SDK_HOME:-/home/yunlang/develop/command-line-tools/sdk/default}/openharmony/toolchains/lib/hap-sign-tool.jar"
HDC="${HOS_SDK_HOME:-/home/yunlang/develop/command-line-tools/sdk/default}/openharmony/toolchains/hdc"
FLUTTER_BIN="${FLUTTER_ROOT:-/home/yunlang/develop/flutter/flutter_ohos}/bin/flutter"
STORE_PWD="123456789012345678901234567890AB"

BUILD_MODE="${1:-debug}"
TARGET_ARCH="${2:-ohos-x64}"

SIGNED_HAP="$SCRIPT_DIR/entry/build/default/outputs/default/entry-default-signed.hap"

# 1. 首次使用时生成签名证书
if [ ! -f "$SIGN_DIR/debug.p12" ]; then
    echo "==> 首次运行，生成调试签名证书..."
    mkdir -p "$SIGN_DIR"

    # Generate Root CA
    java -jar "$HAP_SIGN_TOOL" generate-ca \
        -keyAlias "meowhub-root-ca" -keyPwd "$STORE_PWD" \
        -keyAlg RSA -keySize 4096 \
        -subject "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Root CA" \
        -validity 3650 -signAlg SHA384withRSA \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
        -outFile "$SIGN_DIR/root-ca.cer" 2>/dev/null

    # Generate App Signing CA
    java -jar "$HAP_SIGN_TOOL" generate-ca \
        -keyAlias "meowhub-app-ca" -keyPwd "$STORE_PWD" \
        -keyAlg RSA -keySize 2048 \
        -issuer "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Root CA" \
        -issuerKeyAlias "meowhub-root-ca" -issuerKeyPwd "$STORE_PWD" \
        -subject "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub App Signing CA" \
        -validity 3650 -signAlg SHA256withRSA \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
        -outFile "$SIGN_DIR/app-ca.cer" 2>/dev/null

    # Generate Profile Signing CA
    java -jar "$HAP_SIGN_TOOL" generate-ca \
        -keyAlias "meowhub-profile-ca" -keyPwd "$STORE_PWD" \
        -keyAlg RSA -keySize 2048 \
        -issuer "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Root CA" \
        -issuerKeyAlias "meowhub-root-ca" -issuerKeyPwd "$STORE_PWD" \
        -subject "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Profile Signing CA" \
        -validity 3650 -signAlg SHA256withRSA \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
        -outFile "$SIGN_DIR/profile-ca.cer" 2>/dev/null

    # Generate keypairs
    java -jar "$HAP_SIGN_TOOL" generate-keypair \
        -keyAlias "meowhub-app-debug" -keyPwd "$STORE_PWD" \
        -keyAlg ECC -keySize NIST-P-256 \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" 2>/dev/null

    java -jar "$HAP_SIGN_TOOL" generate-keypair \
        -keyAlias "meowhub-profile-debug" -keyPwd "$STORE_PWD" \
        -keyAlg ECC -keySize NIST-P-256 \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" 2>/dev/null

    # Generate app cert
    java -jar "$HAP_SIGN_TOOL" generate-app-cert \
        -keyAlias "meowhub-app-debug" -keyPwd "$STORE_PWD" \
        -issuer "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub App Signing CA" \
        -issuerKeyAlias "meowhub-app-ca" -issuerKeyPwd "$STORE_PWD" \
        -subject "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Debug App" \
        -validity 365 -signAlg SHA256withECDSA \
        -rootCaCertFile "$SIGN_DIR/root-ca.cer" -subCaCertFile "$SIGN_DIR/app-ca.cer" \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
        -outForm certChain -outFile "$SIGN_DIR/app-debug-cert.cer" 2>/dev/null

    # Generate profile cert
    java -jar "$HAP_SIGN_TOOL" generate-profile-cert \
        -keyAlias "meowhub-profile-debug" -keyPwd "$STORE_PWD" \
        -issuer "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Profile Signing CA" \
        -issuerKeyAlias "meowhub-profile-ca" -issuerKeyPwd "$STORE_PWD" \
        -subject "C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Debug Profile" \
        -validity 365 -signAlg SHA256withECDSA \
        -rootCaCertFile "$SIGN_DIR/root-ca.cer" -subCaCertFile "$SIGN_DIR/profile-ca.cer" \
        -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
        -outForm certChain -outFile "$SIGN_DIR/profile-debug-cert.cer" 2>/dev/null

    echo "==> 签名证书生成完成"
fi

# 2. 生成/刷新 Provision Profile（每次构建都需要，因为时间戳不同）
python3 -c "
import json, base64, time

with open('$SIGN_DIR/app-debug-cert.cer', 'rb') as f:
    cert_data = f.read()
cert_text = cert_data.decode('ascii')
if 'BEGIN CERTIFICATE' in cert_text:
    lines = cert_text.strip().split('\n')
    b64_pem = ''.join(l.strip() for l in lines if not l.startswith('-----'))
    cert_der = base64.b64decode(b64_pem)
else:
    cert_der = cert_data
b64url = base64.urlsafe_b64encode(cert_der).decode('ascii').rstrip('=')

now = int(time.time())
profile = {
    'version-name': '2.0.0', 'version-code': 2,
    'app-distribution-type': 'os_integration',
    'uuid': '00000000-0000-0000-0000-000000000001',
    'validity': {'not-before': now - 86400, 'not-after': now + 31536000},
    'type': 'debug',
    'bundle-info': {
        'developer-id': '',
        'development-certificate': b64url,
        'distribution-certificate': b64url,
        'bundle-name': 'com.example.meowhub',
        'apl': 'normal', 'app-feature': 'hos_normal_app'
    },
    'baseapp-info': {}, 'permissions': {}, 'acls': {},
    'issuer': 'meowhub-debug'
}
with open('$SIGN_DIR/debug-profile.json', 'w') as f:
    json.dump(profile, f, indent=2)
" 2>&1

# Sign profile
java -jar "$HAP_SIGN_TOOL" sign-profile \
    -mode localSign -keyAlias "meowhub-profile-debug" -keyPwd "$STORE_PWD" \
    -profileCertFile "$SIGN_DIR/profile-debug-cert.cer" \
    -inFile "$SIGN_DIR/debug-profile.json" -signAlg SHA256withECDSA \
    -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
    -outFile "$SIGN_DIR/debug-profile.p7b" 2>&1

# 3. 构建 unsigned HAP
echo "==> 构建 $BUILD_MODE HAP ($TARGET_ARCH)..."
cd "$PROJECT_DIR"
$FLUTTER_BIN build hap --"$BUILD_MODE" --target-platform "$TARGET_ARCH" 2>&1 | grep -E "ERROR|FAILED|BUILD" || true

UNSIGNED_HAP="$SCRIPT_DIR/entry/build/default/outputs/default/entry-default-unsigned.hap"

if [ ! -f "$UNSIGNED_HAP" ]; then
    echo "ERROR: 构建失败，未生成 HAP 文件"
    exit 1
fi

# 4. 签名
echo "==> 签名 HAP..."
java -jar "$HAP_SIGN_TOOL" sign-app \
    -mode localSign -keyAlias "meowhub-app-debug" -keyPwd "$STORE_PWD" \
    -appCertFile "$SIGN_DIR/app-debug-cert.cer" \
    -profileFile "$SIGN_DIR/debug-profile.p7b" \
    -inFile "$UNSIGNED_HAP" -signAlg SHA256withECDSA \
    -keystoreFile "$SIGN_DIR/debug.p12" -keystorePwd "$STORE_PWD" \
    -outFile "$SIGNED_HAP" -compatibleVersion 26 -signCode "1" 2>&1 | grep -E "success|ERROR"

# 5. 安装
echo "==> 安装到设备..."
DEVICE=$($HDC list targets 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$DEVICE" ]; then
    echo "ERROR: 未找到鸿蒙设备，请确认模拟器已启动"
    exit 1
fi
$HDC -t "$DEVICE" install "$SIGNED_HAP" 2>&1

# 6. 启动
echo "==> 启动应用..."
$HDC -t "$DEVICE" shell "aa start -a EntryAbility -b com.example.meowhub" 2>&1

echo ""
echo "===== 完成 ====="
ls -lh "$SIGNED_HAP"
