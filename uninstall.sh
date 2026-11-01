
#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/hcr-server"
SERVICE="/etc/systemd/system/hcr-server.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta este script como root."

echo "=================================="
echo "       HCR SERVER UNINSTALLER"
echo "=================================="
echo
echo "Se eliminarán:"
echo "- Servicio systemd hcr-server"
echo "- Ejecutable de HCR Server"
echo "- Carpeta $INSTALL_DIR"
echo
echo "También se eliminarán las copias de seguridad"
echo "guardadas dentro de esa carpeta."
echo

read -rp "¿Confirmas la desinstalación? (escribe SI): " CONFIRM

[[ "$CONFIRM" == "SI" ]] || {
    echo "Desinstalación cancelada."
    exit 0
}

if systemctl list-unit-files hcr-server.service --no-legend 2>/dev/null | grep -q hcr-server; then
    systemctl disable --now hcr-server.service || true
    ok "Servicio detenido y deshabilitado."
fi

rm -f "$SERVICE"
systemctl daemon-reload
systemctl reset-failed hcr-server.service 2>/dev/null || true

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf -- "$INSTALL_DIR"
    ok "Carpeta de instalación eliminada."
fi

echo
echo "=================================="
echo "    DESINSTALACIÓN COMPLETADA"
echo "=================================="
echo "HCR Server ha sido eliminado."
