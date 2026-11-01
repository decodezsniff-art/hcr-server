
#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/hcr-server"
SERVICE="/etc/systemd/system/hcr-server.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Ejecuta este script como root."

command -v systemctl >/dev/null ||
    fail "systemd no está disponible."

echo "=================================="
echo "       HCR SERVER UNINSTALLER"
echo "=================================="
echo
echo "Se eliminarán exclusivamente:"
echo "- Servicio: hcr-server.service"
echo "- Ejecutable y archivos de:"
echo "  $INSTALL_DIR"
echo
echo "ATENCIÓN:"
echo "- También se eliminarán las copias de seguridad."
echo "- Los certificados externos a esa carpeta se conservarán."
echo "- No se eliminarán otros servicios ni programas."
echo

read -rp "Para confirmar, escribe SI: " CONFIRM

[[ "$CONFIRM" == "SI" ]] || {
    echo "Desinstalación cancelada."
    exit 0
}

echo
echo "Deteniendo servicio..."

if systemctl cat hcr-server.service >/dev/null 2>&1; then
    systemctl disable --now hcr-server.service ||
        fail "No se pudo detener o deshabilitar HCR."
    ok "Servicio detenido y deshabilitado."
else
    echo "El servicio HCR no está registrado."
fi

if [[ -f "$SERVICE" ]]; then
    rm -f -- "$SERVICE"
    ok "Archivo de servicio eliminado."
fi

systemctl daemon-reload
systemctl reset-failed hcr-server.service 2>/dev/null || true

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf -- "$INSTALL_DIR"
    ok "Carpeta de instalación eliminada."
else
    echo "La carpeta de instalación no existe."
fi

echo
echo "=================================="
echo "    DESINSTALACIÓN COMPLETADA"
echo "=================================="
echo "HCR Server ha sido eliminado."
