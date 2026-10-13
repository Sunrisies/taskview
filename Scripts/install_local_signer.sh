#!/bin/bash
# 在 macOS 终端运行：把固定开发证书和私钥导入登录钥匙串并设置代码签名信任。
# 该证书仅用于本地开发，不是 Apple Developer ID。
set -euo pipefail
cd "$(dirname "$0")/.."
CERT="$PWD/Scripts/signing/dev.crt"
KEY="$PWD/Scripts/signing/dev.key"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
umask 077
SIGNER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/taskview-signer.XXXXXX")"
trap 'rm -rf "$SIGNER_TEMP"; unset TASKVIEW_P12_PASSWORD' EXIT
if [[ ! -f "$CERT" && ! -f "$KEY" ]]; then
    # 新克隆不包含签名材料；各开发者生成自己的证书，现有证书和私钥绝不覆盖。
    mkdir -p "$PWD/Scripts/signing"
    cat > "$SIGNER_TEMP/certificate.cnf" <<'CERT_CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = code_signing
[subject]
CN = TaskView Local Signer
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CERT_CONFIG
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$SIGNER_TEMP/certificate.cnf" \
        -keyout "$SIGNER_TEMP/dev.key" -out "$SIGNER_TEMP/dev.crt"
    cp "$SIGNER_TEMP/dev.key" "$KEY"
    cp "$SIGNER_TEMP/dev.crt" "$CERT"
fi
[[ -f "$CERT" && -f "$KEY" ]] || {
    echo "证书或私钥缺失，请恢复配套文件；不会覆盖现有签名材料。" >&2; exit 1;
}
export TASKVIEW_P12_PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 -export -in "$CERT" -inkey "$KEY" \
    -name "TaskView Local Signer" -out "$SIGNER_TEMP/signer.p12" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:TASKVIEW_P12_PASSWORD
security import "$SIGNER_TEMP/signer.p12" -k "$KEYCHAIN" \
    -P "$TASKVIEW_P12_PASSWORD" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT"
security find-identity -v -p codesigning "$KEYCHAIN"
echo "Local signer installed. Build with: ./Scripts/make_app.sh"
