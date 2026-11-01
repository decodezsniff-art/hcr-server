
# HCR Server

Servidor HCR para Linux, con instalador y herramientas de administración.

## Características

- Instalación automatizada.
- Configuración de puerto personalizado.
- Transportes Plain, TLS y Auto.
- Configuración del destino SSH.
- Servicio administrado por systemd.
- Actualización desde GitHub.
- Desinstalación automatizada.
- Compatible actualmente con Linux AMD64.

## Requisitos

- Ubuntu 22.04 o superior.
- Acceso root.
- systemd.
- curl, file e iproute2.

## Instalación

Ejecuta:

```bash
curl -fsSL https://raw.githubusercontent.com/decodezsniff-art/hcr-server/main/install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
```

## Actualización

```bash
curl -fsSL https://raw.githubusercontent.com/decodezsniff-art/hcr-server/main/update.sh -o update.sh
chmod +x update.sh
sudo bash update.sh
```

## Desinstalación

```bash
curl -fsSL https://raw.githubusercontent.com/decodezsniff-art/hcr-server/main/uninstall.sh -o uninstall.sh
chmod +x uninstall.sh
sudo bash uninstall.sh
```

## Administración

Consultar estado:

```bash
systemctl status hcr-server
```

Ver registros:

```bash
journalctl -u hcr-server -f
```

Reiniciar:

```bash
systemctl restart hcr-server
```

## Arquitectura

Actualmente se publica el binario Linux AMD64.

## Licencia

Pendiente de definir.
