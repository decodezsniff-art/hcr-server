
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
command -v systemctl >/dev/null || fail "systemd no disponible."
command -v ss >/dev/null || fail "Instala iproute2."
command -v curl >/dev/null || fail "Instala curl."
command -v file >/dev/null || fail "Instala file."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        fail "Todavía no existe un binario ARM64 publicado."
        ;;
    *)
        fail "Arquitectura no compatible: $ARCH"
        ;;
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

[[ "$TARGET" =~ ^[a-zA-Z0-9_.:\[\]-]+$ ]] || fail "Destino SSH inválido."

TLS_CERT=""
TLS_KEY=""

if [[ "$TRANSPORT" != "plain" ]]; then
    read -rp "Ruta del certificado TLS: " TLS_CERT
    read -rp "Ruta de la clave privada TLS: " TLS_KEY

    [[ -f "$TLS_CERT" ]] || fail "No existe el certificado."
    [[ -f "$TLS_KEY" ]] || fail "No existe la clave privada."

    [[ "$TLS_CERT" =~ ^[a-zA-Z0-9_./-]+$ ]] || fail "Ruta del certificado no válida o contiene espacios."
    [[ "$TLS_KEY" =~ ^[a-zA-Z0-9_./-]+$ ]] || fail "Ruta de la clave no válida o contiene espacios."

    [[ -r "$TLS_CERT" && -r "$TLS_KEY" ]] || fail "No se pueden leer los archivos TLS."
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
BACKUP=""

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT

URL="https://raw.githubusercontent.com/$REPO/$BRANCH/hcr-server"

echo "Descargando HCR Server..."
curl -fL --retry 3 "$URL" -o "$TMP" || fail "Error de descarga."

[[ -s "$TMP" ]] || fail "El binario está vacío."

FILE_INFO="$(file "$TMP")"
echo "$FILE_INFO"

[[ "$FILE_INFO" == *"ELF 64-bit"* && "$FILE_INFO" == *"x86-64"* ]] \
    || fail "El binario no corresponde a Linux AMD64."

chmod 755 "$TMP"

if [[ -f "$BINARY" ]]; then
    BACKUP="$INSTALL_DIR/hcr-server.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$BINARY" "$BACKUP"
    ok "Copia anterior guardada: $BACKUP"
fi

install -m 755 "$TMP" "$BINARY"

if [[ "$TRANSPORT" == "plain" ]]; then
    EXEC_ARGS="-listen :$PORT -target $TARGET -transport $TRANSPORT"
else
    EXEC_ARGS="-listen :$PORT -target $TARGET -transport $TRANSPORT -tls-cert $TLS_CERT -tls-key $TLS_KEY"
fi

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
systemctl enable hcr-server

if ! systemctl restart hcr-server; then
    echo "Error al iniciar. Restaurando binario anterior..."

    if [[ -n "$BACKUP" ]]; then
        cp -a "$BACKUP" "$BINARY"
    else
        rm -f "$BINARY" "$SERVICE"
        systemctl daemon-reload
        systemctl reset-failed hcr-server || true
        fail "Instalación revertida."
    fi

    systemctl daemon-reload
    systemctl restart hcr-server || true
    fail "No se pudo iniciar HCR. Se restauró el binario anterior."
fi

sleep 2

if ! systemctl is-active --quiet hcr-server; then
    systemctl status hcr-server --no-pager || true
    fail "HCR no quedó activo. Revisa los registros."
fi

ok "HCR Server instalado correctamente."
echo "Versión: $("$BINARY" -version)"
echo "Puerto: $PORT"
echo "Transporte: $TRANSPORT"
echo "Destino SSH: $TARGET"
echo
echo "Estado: systemctl status hcr-server"
echo "Registros: journalctl -u hcr-server -f"
