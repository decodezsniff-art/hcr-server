
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="decodezsniff-art/hcr-server"
BRANCH="main"
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/hcr-server"

INSTALL_DIR="/opt/hcr-server"
BINARY="${INSTALL_DIR}/hcr-server"
SERVICE="hcr-server"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta como root."
[[ -x "$BINARY" ]] || fail "HCR Server no está instalado."
systemctl cat "$SERVICE" >/dev/null 2>&1 || fail "No existe el servicio."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64) EXPECTED="x86-64" ;;
    aarch64|arm64) EXPECTED="ARM aarch64" ;;
    *) fail "Arquitectura no compatible: $ARCH" ;;
esac

command -v curl >/dev/null || fail "Necesitas curl."
command -v file >/dev/null || fail "Necesitas file."

TMP="$(mktemp)"
BACKUP="${INSTALL_DIR}/hcr-server.backup.$(date +%Y%m%d-%H%M%S)"

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT

echo "Descargando nueva versión..."
curl -fL --retry 3 "$URL" -o "$TMP" || fail "Falló la descarga."

[[ -s "$TMP" ]] || fail "El archivo está vacío."

FILE_INFO="$(file "$TMP")"
echo "$FILE_INFO"

case "$EXPECTED" in
    x86-64)
        [[ "$FILE_INFO" == *"x86-64"* ]] || fail "Arquitectura incorrecta."
        ;;
    "ARM aarch64")
        [[ "$FILE_INFO" == *"ARM aarch64"* ]] || fail "Arquitectura incorrecta."
        ;;
esac

chmod 755 "$TMP"

echo "Nueva versión:"
"$TMP" -version

cp -a "$BINARY" "$BACKUP"
ok "Copia de seguridad creada: $BACKUP"

systemctl stop "$SERVICE"

if ! install -m 755 "$TMP" "$BINARY"; then
    cp -a "$BACKUP" "$BINARY"
    systemctl start "$SERVICE"
    fail "No se pudo instalar. Binario anterior restaurado."
fi

if ! systemctl start "$SERVICE"; then
    echo "Falló el inicio. Restaurando versión anterior..."
    cp -a "$BACKUP" "$BINARY"
    systemctl start "$SERVICE" || true
    fail "Actualización revertida."
fi

sleep 2

if systemctl is-active --quiet "$SERVICE"; then
    ok "HCR Server actualizado correctamente."
    "$BINARY" -version
else
    cp -a "$BACKUP" "$BINARY"
    systemctl restart "$SERVICE" || true
    fail "El servicio no quedó activo. Versión anterior restaurada."
fi
