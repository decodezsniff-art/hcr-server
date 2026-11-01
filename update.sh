
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="decodezsniff-art/hcr-server"
BRANCH="main"
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/hcr-server"

INSTALL_DIR="/opt/hcr-server"
BINARY="${INSTALL_DIR}/hcr-server"
SERVICE="hcr-server.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta como root."

for cmd in systemctl curl file; do
    command -v "$cmd" >/dev/null ||
        fail "Falta el comando: $cmd"
done

[[ -x "$BINARY" ]] ||
    fail "HCR Server no está instalado."

systemctl cat "$SERVICE" >/dev/null 2>&1 ||
    fail "No existe el servicio HCR."

systemctl is-active --quiet "$SERVICE" ||
    fail "El servicio HCR no está activo. Revisa su estado antes de actualizar."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64) EXPECTED="x86-64" ;;
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
CHANGED=0
SUCCESS=0

cleanup() {
    rm -f "$TMP"

    if [[ "$CHANGED" -eq 1 && "$SUCCESS" -eq 0 ]]; then
        echo "Restaurando versión anterior..."

        systemctl stop "$SERVICE" 2>/dev/null || true

        if [[ -f "$BACKUP" ]]; then
            cp -a "$BACKUP" "$BINARY"
            systemctl restart "$SERVICE" || true
        fi
    fi
}

trap cleanup EXIT

echo "=================================="
echo "         HCR SERVER UPDATE"
echo "=================================="
echo "Versión instalada: $OLD_VERSION"
echo

echo "Descargando nueva versión..."

curl -fLsS --retry 3 "$URL" -o "$TMP" ||
    fail "No se pudo descargar el binario."

[[ -s "$TMP" ]] ||
    fail "El archivo descargado está vacío."

FILE_INFO="$(file "$TMP")"
echo "$FILE_INFO"

[[ "$FILE_INFO" == *"ELF 64-bit"* &&
   "$FILE_INFO" == *"$EXPECTED"* ]] ||
    fail "El binario no corresponde a esta arquitectura."

chmod 755 "$TMP"

NEW_VERSION="$("$TMP" -version 2>&1)" ||
    fail "El binario descargado no puede ejecutarse."

echo "Versión nueva: $NEW_VERSION"

if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
    echo "La versión descargada es igual a la instalada."
    read -rp "¿Deseas reinstalarla igualmente? (s/N): " CONFIRM
    [[ "${CONFIRM,,}" == "s" ]] || exit 0
fi

cp -a "$BINARY" "$BACKUP"
ok "Copia de seguridad guardada: $BACKUP"

echo "Deteniendo HCR Server..."

systemctl stop "$SERVICE" ||
    fail "No se pudo detener HCR."

CHANGED=1

mv -f "$TMP" "$BINARY"

echo "Iniciando nueva versión..."

if ! systemctl start "$SERVICE"; then
    fail "No se pudo iniciar la nueva versión."
fi

sleep 3

if ! systemctl is-active --quiet "$SERVICE"; then
    systemctl status "$SERVICE" --no-pager || true
    fail "La nueva versión no quedó activa."
fi

SUCCESS=1

ok "HCR Server actualizado correctamente."

echo "Versión actual: $("$BINARY" -version)"
echo "Servicio: $(systemctl is-active "$SERVICE")"
echo "Copia anterior: $BACKUP"
