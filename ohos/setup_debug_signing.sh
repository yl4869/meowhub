#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# HarmonyOS Debug Signing Setup Script
# Generates all certificates and signs the debug HAP
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGN_DIR="$SCRIPT_DIR/debug-signing"
SDK_TOOLCHAIN_DIR="${HOS_SDK_HOME:-/home/yunlang/develop/command-line-tools/sdk/default}/openharmony/toolchains"
HAP_SIGN_TOOL="$SDK_TOOLCHAIN_DIR/lib/hap-sign-tool.jar"

# Debug signing passwords (fixed for debug)
STORE_PWD="123456"
KEY_PWD="123456"

# Subject DNs
ROOT_CA_SUBJECT="C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Root CA"
APP_CA_SUBJECT="C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub App Signing CA"
PROFILE_CA_SUBJECT="C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Profile Signing CA"
APP_CERT_SUBJECT="C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Debug App"
PROFILE_CERT_SUBJECT="C=CN,O=MeowHub,OU=MeowHub Community,CN=MeowHub Debug Profile"

# Key aliases
APP_KEY_ALIAS="meowhub-app-debug"
PROFILE_KEY_ALIAS="meowhub-profile-debug"
ROOT_CA_KEY_ALIAS="meowhub-root-ca"
APP_CA_KEY_ALIAS="meowhub-app-ca"
PROFILE_CA_KEY_ALIAS="meowhub-profile-ca"

P12_FILE="$SIGN_DIR/debug.p12"
APP_CERT_CHAIN="$SIGN_DIR/app-debug-cert.cer"
PROFILE_CERT_CHAIN="$SIGN_DIR/profile-debug-cert.cer"
ROOT_CA_CERT="$SIGN_DIR/root-ca.cer"
APP_CA_CERT="$SIGN_DIR/app-ca.cer"
PROFILE_CA_CERT="$SIGN_DIR/profile-ca.cer"
PROFILE_JSON="$SIGN_DIR/debug-profile.json"
PROFILE_P7B="$SIGN_DIR/debug-profile.p7b"

echo "==> Creating signing directory: $SIGN_DIR"
mkdir -p "$SIGN_DIR"

run_sign_tool() {
    java -jar "$HAP_SIGN_TOOL" "$@"
}

# Step 1: Remove old keystore if exists
if [ -f "$P12_FILE" ]; then
    echo "==> Removing old keystore..."
    rm -f "$P12_FILE"
fi

# Step 2: Generate Root CA (this also generates the keypair)
echo "==> Step 1/9: Generating Root CA..."
run_sign_tool generate-ca \
    -keyAlias "$ROOT_CA_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -keyAlg RSA \
    -keySize 4096 \
    -subject "$ROOT_CA_SUBJECT" \
    -validity 3650 \
    -signAlg SHA384withRSA \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outFile "$ROOT_CA_CERT"

# Step 3: Generate App Signing Service CA
echo "==> Step 2/9: Generating App Signing CA..."
run_sign_tool generate-ca \
    -keyAlias "$APP_CA_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -keyAlg RSA \
    -keySize 2048 \
    -issuer "$ROOT_CA_SUBJECT" \
    -issuerKeyAlias "$ROOT_CA_KEY_ALIAS" \
    -issuerKeyPwd "$KEY_PWD" \
    -subject "$APP_CA_SUBJECT" \
    -validity 3650 \
    -signAlg SHA256withRSA \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outFile "$APP_CA_CERT"

# Step 4: Generate Profile Signing Service CA
echo "==> Step 3/9: Generating Profile Signing CA..."
run_sign_tool generate-ca \
    -keyAlias "$PROFILE_CA_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -keyAlg RSA \
    -keySize 2048 \
    -issuer "$ROOT_CA_SUBJECT" \
    -issuerKeyAlias "$ROOT_CA_KEY_ALIAS" \
    -issuerKeyPwd "$KEY_PWD" \
    -subject "$PROFILE_CA_SUBJECT" \
    -validity 3650 \
    -signAlg SHA256withRSA \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outFile "$PROFILE_CA_CERT"

# Step 5: Generate App Keypair
echo "==> Step 4/9: Generating App Keypair..."
run_sign_tool generate-keypair \
    -keyAlias "$APP_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -keyAlg ECC \
    -keySize NIST-P-256 \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD"

# Step 6: Generate Profile Keypair
echo "==> Step 5/9: Generating Profile Keypair..."
run_sign_tool generate-keypair \
    -keyAlias "$PROFILE_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -keyAlg ECC \
    -keySize NIST-P-256 \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD"

# Step 7: Generate App Debug Certificate (certChain)
echo "==> Step 6/9: Generating App Debug Certificate..."
run_sign_tool generate-app-cert \
    -keyAlias "$APP_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -issuer "$APP_CA_SUBJECT" \
    -issuerKeyAlias "$APP_CA_KEY_ALIAS" \
    -issuerKeyPwd "$KEY_PWD" \
    -subject "$APP_CERT_SUBJECT" \
    -validity 365 \
    -signAlg SHA256withECDSA \
    -rootCaCertFile "$ROOT_CA_CERT" \
    -subCaCertFile "$APP_CA_CERT" \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outForm certChain \
    -outFile "$APP_CERT_CHAIN"

# Step 8: Generate Profile Debug Certificate (certChain)
echo "==> Step 7/9: Generating Profile Debug Certificate..."
run_sign_tool generate-profile-cert \
    -keyAlias "$PROFILE_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -issuer "$PROFILE_CA_SUBJECT" \
    -issuerKeyAlias "$PROFILE_CA_KEY_ALIAS" \
    -issuerKeyPwd "$KEY_PWD" \
    -subject "$PROFILE_CERT_SUBJECT" \
    -validity 365 \
    -signAlg SHA256withECDSA \
    -rootCaCertFile "$ROOT_CA_CERT" \
    -subCaCertFile "$PROFILE_CA_CERT" \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outForm certChain \
    -outFile "$PROFILE_CERT_CHAIN"

# Step 9: Create Provision Profile JSON
echo "==> Step 8/9: Creating Provision Profile..."
cat > "$PROFILE_JSON" << PROFILE_EOF
{
    "version-name": "2.0.0",
    "version-code": 2,
    "app-distribution-type": "os_integration",
    "uuid": "00000000-0000-0000-0000-000000000001",
    "validity": {
        "not-before": $(date -d "1 day ago" +%s),
        "not-after": $(date -d "1 year" +%s)
    },
    "type": "debug",
    "bundle-info": {
        "developer-id": "",
        "development-certificate": "",
        "distribution-certificate": "",
        "bundle-name": "com.meowhub.app",
        "apl": "normal",
        "app-feature": "hos_normal_app"
    },
    "baseapp-info": {},
    "permissions": {},
    "acls": {},
    "issuer": "meowhub-debug"
}
PROFILE_EOF

# Step 10: Sign the Provision Profile
echo "==> Step 9/9: Signing Provision Profile..."
run_sign_tool sign-profile \
    -mode localSign \
    -keyAlias "$PROFILE_KEY_ALIAS" \
    -keyPwd "$KEY_PWD" \
    -profileCertFile "$PROFILE_CERT_CHAIN" \
    -inFile "$PROFILE_JSON" \
    -signAlg SHA256withECDSA \
    -keystoreFile "$P12_FILE" \
    -keystorePwd "$STORE_PWD" \
    -outFile "$PROFILE_P7B"

echo ""
echo "==================== DONE ===================="
echo "All signing materials generated in: $SIGN_DIR"
echo ""
echo "Files:"
echo "  Keystore:      $P12_FILE"
echo "  App Cert:      $APP_CERT_CHAIN"
echo "  Profile:       $PROFILE_P7B"
echo ""
echo "Passwords:"
echo "  Store password: $STORE_PWD"
echo "  Key password:   $KEY_PWD"
echo ""
echo "Now update ohos/build-profile.json5 with signingConfigs"
echo "and rebuild with: flutter build hap --debug"
echo "=============================================="
