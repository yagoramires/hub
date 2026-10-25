#!/bin/zsh
# Cria (uma vez) um certificado local de assinatura de código no Chaveiro de login.
#
# Com assinatura ad-hoc, cada build tem uma identidade diferente e o macOS deixa de
# reconhecer a permissão de Acessibilidade já concedida. Assinando sempre com o mesmo
# certificado, a permissão sobrevive às recompilações.
#
# Para desfazer: Acesso às Chaves → login → apagar "Aero Local Signing".
set -euo pipefail

NAME="Aero Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ certificado \"$NAME\" já existe"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/id.p12" -passout pass:aero

# -T libera o uso da chave pelo codesign sem pedir senha a cada build.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P aero -T /usr/bin/codesign >/dev/null
echo "✓ certificado \"$NAME\" criado no Chaveiro de login"
