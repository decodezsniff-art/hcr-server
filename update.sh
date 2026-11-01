
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

command -v curl >/dev/null || fail "Instala curl."
command -v file >/dev/null || fail "Instala file."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        EXPECTED="x86-64"
        ;;
    aarch64|arm64)
        fail "Todavía no hay un binario ARM64 publicado."
        ;;
    *)
        fail "Arquitectura no compatible: $ARCH"
        ;;
esac

mkdir -p "$INSTALL_DIR"

TMP="$(mktemp "${INSTALL_DIR}/hcr-update.XXXXXX")"
BACKUP="${INSTALL_DIR}/hcr-server.backup.$(date +%Y%m%d-%H%M%S)"
OLD_VERSION="$("$BINARY" -version 2>&1 || true)"

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT

echo "Versión instalada: $OLD_VERSION"
echo "Descargando nueva versión..."

curl -fLsS --retry 3 "$URL" -o "$TMP" \
    || fail "No se pudo descargar el binario."

[[ -s "$TMP" ]] || fail "El archivo descargado está vacío."

FILE_INFO="$(file "$TMP")"
echo "$FILE_INFO"

[[ "$FILE_INFO" == *"ELF 64-bit"* && "$FILE_INFO" == *"$EXPECTED"* ]] \
    || fail "El binario no corresponde a la arquitectura de esta VPS."

chmod 755 "$TMP"

NEW_VERSION="$("$TMP" -version 2>&1)" \
    || fail "El binario descargado no puede ejecutarse."

echo "Nueva versión: $NEW_VERSION"

if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
    echo "La versión descargada es igual a la instalada."
    read -rp "¿Deseas reinstalarla igualmente? (s/N): " CONFIRM
    [[ "${CONFIRM,,}" == "s" ]] || exit 0
fi

cp -a "$BINARY" "$BACKUP"
ok "Copia de seguridad: $BACKUP"

echo "Deteniendo HCR Server..."
systemctl stop "$SERVICE"

if ! mv -f "$TMP" "$BINARY"; then
    systemctl start "$SERVICE" || true
    fail "No se pudo reemplazar el binario."
fi

echo "Iniciando nueva versión..."

if ! systemctl start "$SERVICE"; then
    echo "ERROR: restaurando versión anterior..."
    cp -a "$BACKUP" "$BINARY"
    systemctl restart "$SERVICE" || true
    fail "Actualización revertida."
fi

sleep 3

if ! systemctl is-active --quiet "$SERVICE"; then
    echo "ERROR: el servicio no está activo."
    echo "Restaurando versión anterior..."

    systemctl stop "$SERVICE" || true
    cp -a "$BACKUP" "$BINARY"
    systemctl restart "$SERVICE" || true

    fail "Actualización revertida."
fi

ok "HCR Server actualizado correctamente."

echo "Versión actual: $("$BINARY" -version)"
echo "Servicio: $(systemctl is-active "$SERVICE")"
echo "Copia anterior: $BACKUP"
