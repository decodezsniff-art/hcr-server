
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="decodezsniff-art/hcr-server"
BRANCH="main"
INSTALL_DIR="/opt/hcr-server"
BINARY="$INSTALL_DIR/hcr-server"
SERVICE="/etc/systemd/system/hcr-server.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta como root."

for cmd in systemctl ss curl file install; do
    command -v "$cmd" >/dev/null || fail "Falta el comando: $cmd"
done

systemctl is-system-running >/dev/null 2>&1 ||
    fail "systemd no está disponible o no está funcionando."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) fail "Todavía no existe un binario ARM64 publicado." ;;
    *) fail "Arquitectura no compatible: $ARCH" ;;
esac

echo "=================================="
echo "       HCR SERVER INSTALLER"
echo "=================================="
echo "Arquitectura: $ARCH"
echo

read -rp "Puerto HCR [8880]: " PORT
PORT="${PORT:-8880}"

[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || fail "Puerto inválido."
(( PORT >= 1 && PORT <= 65535 )) || fail "Puerto fuera de rango."

if ss -H -ltn | awk -v p=":$PORT" '$4 ~ (p "$") {found=1} END {exit !found}'; then
    fail "El puerto TCP $PORT está ocupado."
fi

read -rp "Transporte (plain/tls/auto) [tls]: " TRANSPORT
TRANSPORT="${TRANSPORT:-tls}"
TRANSPORT="${TRANSPORT,,}"

case "$TRANSPORT" in
    plain|tls|auto) ;;
    *) fail "Transporte inválido." ;;
esac

read -rp "Destino SSH [127.0.0.1:22]: " TARGET
TARGET="${TARGET:-127.0.0.1:22}"

[[ "$TARGET" =~ ^[a-zA-Z0-9_.:\[\]-]+$ ]] ||
    fail "Destino SSH inválido."

TLS_CERT=""
TLS_KEY=""

if [[ "$TRANSPORT" != "plain" ]]; then
    read -rp "Ruta del certificado TLS: " TLS_CERT
    read -rp "Ruta de la clave privada TLS: " TLS_KEY

    [[ "$TLS_CERT" =~ ^[a-zA-Z0-9_./-]+$ ]] ||
        fail "Ruta del certificado no válida."

    [[ "$TLS_KEY" =~ ^[a-zA-Z0-9_./-]+$ ]] ||
        fail "Ruta de la clave no válida."

    [[ -f "$TLS_CERT" && -r "$TLS_CERT" ]] ||
        fail "No existe o no se puede leer el certificado."

    [[ -f "$TLS_KEY" && -r "$TLS_KEY" ]] ||
        fail "No existe o no se puede leer la clave privada."
fi

echo
echo "Puerto: $PORT"
echo "Transporte: $TRANSPORT"
echo "Destino SSH: $TARGET"
echo

read -rp "¿Continuar? (s/N): " CONFIRM
[[ "${CONFIRM,,}" == "s" ]] || exit 0

mkdir -p "$INSTALL_DIR"

TMP="$(mktemp)"
OLD_BINARY=""
OLD_SERVICE=""
HAD_BINARY=0
HAD_SERVICE=0
CHANGED=0
SUCCESS=0

cleanup() {
    rm -f "$TMP"

    if [[ "$CHANGED" -eq 1 && "$SUCCESS" -eq 0 ]]; then
        echo "Restaurando instalación anterior..."

        systemctl stop hcr-server.service 2>/dev/null || true

        if [[ "$HAD_BINARY" -eq 1 ]]; then
            cp -a "$OLD_BINARY" "$BINARY"
        else
            rm -f "$BINARY"
        fi

        if [[ "$HAD_SERVICE" -eq 1 ]]; then
            cp -a "$OLD_SERVICE" "$SERVICE"
            systemctl daemon-reload
            systemctl restart hcr-server.service || true
        else
            rm -f "$SERVICE"
            systemctl daemon-reload
            systemctl reset-failed hcr-server.service || true
        fi
    fi
}

trap cleanup EXIT

URL="https://raw.githubusercontent.com/$REPO/$BRANCH/hcr-server"

echo "Descargando HCR Server..."
curl -fLsS --retry 3 "$URL" -o "$TMP" ||
    fail "Error de descarga."

[[ -s "$TMP" ]] || fail "El binario está vacío."

FILE_INFO="$(file "$TMP")"
echo "$FILE_INFO"

[[ "$FILE_INFO" == *"ELF 64-bit"* && "$FILE_INFO" == *"x86-64"* ]] ||
    fail "El binario no corresponde a Linux AMD64."

chmod 755 "$TMP"

VERSION="$("$TMP" -version 2>&1)" ||
    fail "El binario descargado no puede ejecutarse."

echo "Versión descargada: $VERSION"

if [[ -f "$BINARY" ]]; then
    OLD_BINARY="$INSTALL_DIR/hcr-server.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$BINARY" "$OLD_BINARY"
    HAD_BINARY=1
    ok "Copia anterior: $OLD_BINARY"
fi

if [[ -f "$SERVICE" ]]; then
    OLD_SERVICE="$INSTALL_DIR/hcr-server.service.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$SERVICE" "$OLD_SERVICE"
    HAD_SERVICE=1
fi

if [[ "$TRANSPORT" == "plain" ]]; then
    EXEC_ARGS="-listen :$PORT -target $TARGET -transport $TRANSPORT"
else
    EXEC_ARGS="-listen :$PORT -target $TARGET -transport $TRANSPORT -tls-cert $TLS_CERT -tls-key $TLS_KEY"
fi

CHANGED=1

install -m 755 "$TMP" "$BINARY"

cat > "$SERVICE" <<EOF
[Unit]
Description=HCR Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BINARY $EXEC_ARGS
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hcr-server.service

systemctl restart hcr-server.service ||
    fail "No se pudo iniciar HCR."

sleep 3

if ! systemctl is-active --quiet hcr-server.service; then
    systemctl status hcr-server.service --no-pager || true
    fail "HCR no quedó activo."
fi

SUCCESS=1

ok "HCR Server instalado correctamente."
echo "Versión: $VERSION"
echo "Puerto: $PORT"
echo "Transporte: $TRANSPORT"
echo "Destino SSH: $TARGET"
echo
echo "Estado: systemctl status hcr-server"
echo "Registros: journalctl -u hcr-server -f"
