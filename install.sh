
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="decodezsniff-art/hcr-server"
BRANCH="main"
BINARY_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/hcr-server"

INSTALL_DIR="/opt/hcr-server"
BINARY="${INSTALL_DIR}/hcr-server"
SERVICE="/etc/systemd/system/hcr-server.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta este instalador como root."

command -v systemctl >/dev/null || fail "systemd no está disponible."
command -v ss >/dev/null || fail "Instala iproute2 para comprobar puertos."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        fail "Todavía no hay un binario ARM64 publicado."
        ;;
    *)
        fail "Arquitectura no compatible: $ARCH"
        ;;
esac

echo "=================================="
echo "       HCR SERVER INSTALLER"
echo "=================================="
echo "Arquitectura detectada: $ARCH"
echo

read -rp "Puerto HCR [8880]: " PORT
PORT="${PORT:-8880}"

[[ "$PORT" =~ ^[0-9]+$ ]] || fail "Puerto inválido."
(( PORT >= 1 && PORT <= 65535 )) || fail "Puerto fuera de rango."

if ss -H -ltn | awk -v p=":$PORT" '$4 ~ (p "$") {found=1} END {exit !found}'; then
    fail "El puerto TCP $PORT ya está ocupado."
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

[[ "$TARGET" =~ ^[a-zA-Z0-9._:-]+$ ]] || fail "Destino SSH inválido."

TLS_ARGS=""

if [[ "$TRANSPORT" != "plain" ]]; then
    read -rp "Ruta del certificado TLS: " TLS_CERT
    read -rp "Ruta de la clave privada TLS: " TLS_KEY

    [[ -f "$TLS_CERT" ]] || fail "No existe el certificado."
    [[ -f "$TLS_KEY" ]] || fail "No existe la clave privada."
    [[ "$TLS_CERT" != *" "* && "$TLS_KEY" != *" "* ]] || fail "Las rutas no pueden contener espacios."

    TLS_ARGS="-tls-cert $TLS_CERT -tls-key $TLS_KEY"
fi

echo
echo "===== CONFIGURACIÓN ====="
echo "Puerto:       $PORT"
echo "Transporte:   $TRANSPORT"
echo "Destino SSH:  $TARGET"
echo "Arquitectura: $ARCH"
echo

read -rp "¿Continuar con la instalación? (s/N): " CONFIRM
[[ "${CONFIRM,,}" == "s" ]] || exit 0

command -v curl >/dev/null || fail "Instala curl antes de continuar."

mkdir -p "$INSTALL_DIR"

if [[ -f "$BINARY" ]]; then
    BACKUP="${INSTALL_DIR}/hcr-server.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$BINARY" "$BACKUP"
    ok "Copia de seguridad: $BACKUP"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Descargando HCR Server..."
curl -fL --retry 3 "$BINARY_URL" -o "$TMP" || fail "No se pudo descargar el binario."

[[ -s "$TMP" ]] || fail "El archivo descargado está vacío."

if command -v file >/dev/null; then
    file "$TMP" | grep -q "ELF 64-bit.*x86-64" || fail "El binario no parece ser ELF AMD64."
fi

install -m 755 "$TMP" "$BINARY"
ok "Binario instalado."

cat > "$SERVICE" <<EOF
[Unit]
Description=HCR Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BINARY -listen :$PORT -target $TARGET -transport $TRANSPORT $TLS_ARGS
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hcr-server
systemctl restart hcr-server

sleep 2

if systemctl is-active --quiet hcr-server; then
    ok "HCR Server está funcionando."
else
    systemctl status hcr-server --no-pager || true
    fail "El servicio no pudo iniciar. Revisa los registros."
fi

echo
echo "=================================="
echo "       INSTALACIÓN COMPLETA"
echo "=================================="
echo "Versión: $("$BINARY" -version)"
echo "Puerto: $PORT"
echo "Transporte: $TRANSPORT"
echo "Destino SSH: $TARGET"
echo
echo "Estado: systemctl status hcr-server"
echo "Registros: journalctl -u hcr-server -f"
