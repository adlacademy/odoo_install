#!/bin/bash
################################################################################
# Script para instalar Odoo 20 en Ubuntu 24.04 LTS o Debian 13
# Basado en el script original de Yenthe Van Ginneken y actualizado para Odoo 20
#
# Requisitos de Odoo 20 (odoo/release.py):
#   - Python 3.12 a 3.14   (Ubuntu 24.04 trae Python 3.12)
#   - PostgreSQL 16 o superior (Ubuntu 24.04 trae PostgreSQL 16)
# Debian 13 (trixie) trae Python 3.13 y PostgreSQL 17: tambien es compatible.
# Ubuntu 22.04 y Debian 12 NO son compatibles (Python 3.10 / 3.11).
################################################################################

OE_USER="odoo20"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
OE_ADDONS="$OE_HOME/custom/addons"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="20.0"
IS_ENTERPRISE="False"
INSTALL_NGINX="False"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

# Versiones minimas exigidas por Odoo 20
MIN_PY_VERSION="3.12"
MAX_PY_VERSION="3.14"
MIN_PG_VERSION="16"

# Build oficial de wkhtmltopdf para Ubuntu 22.04 (jammy): enlaza con libssl3 y sus
# dependencias se resuelven en Ubuntu 24.04, sin instalar libssl1.1 (sin soporte).
WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb

# Redirigir toda la salida a un archivo de log
LOG_FILE="odoo_install_logs.txt"
exec > >(tee -i $LOG_FILE)
exec 2>&1

# Detiene la instalacion si falla un paso critico, en lugar de continuar y
# dejar un Odoo que no arranca. El script se puede volver a ejecutar.
abortar() {
  echo -e "\n*** ERROR: $1 ***"
  echo "Revisa el log ($LOG_FILE) y vuelve a ejecutar el script cuando se resuelva."
  exit 1
}

# Reintentos ante cortes de red: apt reintenta descargas y wget tambien los
# fallos de DNS ("Temporary failure in name resolution").
APT_GET="sudo apt-get -o Acquire::Retries=5"
WGET="wget --tries=5 --waitretry=10 --retry-connrefused --retry-on-host-error"

#--------------------------------------------------
# Validar version de Python (Odoo 20 exige 3.12 - 3.14)
#--------------------------------------------------
echo -e "\n---- Validando la version de Python del sistema ----"
PY_VERSION=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)
if ! python3 -c "import sys; sys.exit(0 if (3, 12) <= sys.version_info[:2] <= (3, 14) else 1)" 2>/dev/null; then
  echo "ERROR: Odoo $OE_VERSION requiere Python entre $MIN_PY_VERSION y $MAX_PY_VERSION. Este sistema tiene Python ${PY_VERSION:-desconocido}."
  echo "Instala Odoo $OE_VERSION sobre Ubuntu 24.04 LTS o Debian 13."
  exit 1
fi
echo "Python $PY_VERSION: compatible"

# Distribucion: algunos paquetes de desarrollo cambian de nombre entre Ubuntu y Debian
. /etc/os-release
DISTRO_ID="${ID:-ubuntu}"
echo "Sistema: ${PRETTY_NAME:-$DISTRO_ID}"

# Contrasena maestra: aleatoria (GENERATE_RANDOM_PASSWORD estaba declarado pero no se usaba y quedaba «admin»).
# Se usa tambien para el usuario de PostgreSQL y se muestra al final de la instalacion.
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
  OE_SUPERADMIN=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
fi

#--------------------------------------------------
# Actualizar Servidor
#--------------------------------------------------
echo -e "\n---- Actualizando el Servidor ----"
$APT_GET update || abortar "no se pudo actualizar la lista de paquetes (apt-get update)"
$APT_GET upgrade -y || abortar "fallo la actualizacion del sistema (apt-get upgrade)"

#--------------------------------------------------
# Instalar PostgreSQL
#--------------------------------------------------
echo -e "\n---- Instalando PostgreSQL ----"
$APT_GET install postgresql postgresql-server-dev-all -y || abortar "no se pudo instalar PostgreSQL"

PG_VERSION=$(ls /etc/postgresql | sort -n | tail -1)
if [ -z "$PG_VERSION" ] || [ "${PG_VERSION%%.*}" -lt "$MIN_PG_VERSION" ]; then
  echo "ERROR: Odoo $OE_VERSION requiere PostgreSQL $MIN_PG_VERSION o superior. Version instalada: ${PG_VERSION:-ninguna}."
  exit 1
fi
echo "PostgreSQL $PG_VERSION: compatible"

sudo su - postgres -c "createuser -s $OE_USER" 2>/dev/null || true

echo -e "\n---- Configurando PostgreSQL para Odoo ----"
PG_HBA_FILE="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
if [ -f "$PG_HBA_FILE" ]; then
  sudo sed -i "s/local   all             all                                     peer/local   all             all                                     md5/" $PG_HBA_FILE
  sudo systemctl restart postgresql
fi
sudo su - postgres -c "psql -c \"ALTER USER $OE_USER WITH PASSWORD '$OE_SUPERADMIN';\""

#--------------------------------------------------
# Validar y Crear Usuario del Sistema
#--------------------------------------------------
echo -e "\n---- Validando usuario del sistema Odoo ----"
if ! id "$OE_USER" &>/dev/null; then
  sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
fi

#--------------------------------------------------
# Instalar Dependencias
#--------------------------------------------------
echo -e "\n---- Instalando Python 3 y dependencias para Odoo 20 ----"
$APT_GET install git python3 python3-venv python3-wheel build-essential wget python3-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools -y || abortar "no se pudieron instalar Python 3 y las dependencias de compilacion"
$APT_GET install -y python3-pip || abortar "no se pudo instalar python3-pip"

# Dependencias adicionales específicas para Odoo 20
echo -e "\n---- Instalando dependencias adicionales de Odoo 20 ----"
# libjpeg8-dev y libatlas-base-dev solo existen en Ubuntu; en Debian bastan libjpeg-dev y libopenblas-dev
if [ "$DISTRO_ID" = "debian" ]; then
  EXTRA_DEV="libopenblas-dev"
else
  EXTRA_DEV="libjpeg8-dev libatlas-base-dev"
fi
$APT_GET install npm node-less libjpeg-dev zlib1g-dev libpq-dev libxml2-dev libffi-dev libssl-dev liblcms2-dev libblas-dev libcairo2-dev pkg-config $EXTRA_DEV -y || abortar "no se pudieron instalar las dependencias adicionales de Odoo"

#--------------------------------------------------
# Descargar y Configurar Odoo
#--------------------------------------------------
if [ -d "$OE_HOME_EXT" ]; then
  echo "El directorio $OE_HOME_EXT ya existe. Eliminándolo para una instalación limpia."
  sudo rm -rf $OE_HOME_EXT
fi

echo "Creando el directorio del servidor Odoo..."
sudo mkdir -p $OE_HOME_EXT

echo "Clonando el repositorio de Odoo en $OE_HOME_EXT..."
CLONADO="False"
for INTENTO in 1 2 3; do
  git clone --depth 1 --branch $OE_VERSION https://github.com/odoo/odoo.git $OE_HOME_EXT && { CLONADO="True"; break; }
  echo "Fallo al clonar (intento $INTENTO de 3). Reintentando en 15 segundos..."
  sudo rm -rf $OE_HOME_EXT
  sleep 15
done
[ "$CLONADO" = "True" ] || abortar "no se pudo clonar el repositorio de Odoo. Verifica la conectividad y la URL."

echo "Creando el directorio de addons personalizados en $OE_ADDONS..."
sudo mkdir -p $OE_ADDONS

echo "Estableciendo los permisos para $OE_HOME y $OE_HOME_EXT..."
sudo chown -R $OE_USER:$OE_USER $OE_HOME
sudo chown -R $OE_USER:$OE_USER $OE_HOME_EXT
sudo chown -R $OE_USER:$OE_USER $OE_ADDONS


#--------------------------------------------------
# Validar y Descargar requirements.txt
#--------------------------------------------------
echo -e "\n---- Validando archivo requirements.txt ----"
$WGET https://raw.githubusercontent.com/adlacademy/odoo_install/refs/heads/20.0/requirements.txt -O $OE_HOME_EXT/requirements.txt || abortar "no se pudo descargar requirements.txt"
# wget -O deja un archivo vacio si la descarga falla a medias
[ -s $OE_HOME_EXT/requirements.txt ] || abortar "requirements.txt esta vacio"


#--------------------------------------------------
# Crear entorno virtual e instalar dependencias
#--------------------------------------------------
echo -e "\n---- Creando el entorno virtual ----"
python3 -m venv $OE_HOME_EXT/venv || abortar "no se pudo crear el entorno virtual"
source $OE_HOME_EXT/venv/bin/activate
$OE_HOME_EXT/venv/bin/pip install --upgrade pip
$OE_HOME_EXT/venv/bin/pip install wheel
$OE_HOME_EXT/venv/bin/pip install -r $OE_HOME_EXT/requirements.txt || abortar "fallo la instalacion de las dependencias de Python (pip)"
deactivate

#--------------------------------------------------
# Instalar Wkhtmltopdf y dependencias
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Instalando Wkhtmltopdf ----"
  $APT_GET install -y xfonts-75dpi xfonts-base fontconfig libxrender1 libxext6
  # El build de Ubuntu 22.04 depende de libjpeg-turbo8, que Debian no tiene: en Debian, el build oficial de
  # Debian 12 (bookworm), que se instala y funciona en Debian 13 (probado)
  if [ "$DISTRO_ID" = "debian" ]; then
    WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
  fi
  $WGET $WKHTMLTOX_X64 -O /tmp/wkhtmltox.deb
  # apt (y no dpkg -i) resuelve las dependencias del paquete automaticamente
  $APT_GET install -y /tmp/wkhtmltox.deb
  wkhtmltopdf --version || echo "ADVERTENCIA: wkhtmltopdf no quedo instalado; los informes PDF no funcionaran."
fi

#--------------------------------------------------
# Configurar Archivo de Configuración
#--------------------------------------------------
sudo bash -c "cat > /etc/${OE_CONFIG}.conf" <<EOL
[options]
admin_passwd = $OE_SUPERADMIN
db_host = localhost
db_port = 5432
db_user = $OE_USER
db_password = $OE_SUPERADMIN
addons_path=${OE_HOME_EXT}/addons,${OE_ADDONS}
logfile=/var/log/$OE_USER/odoo.log
http_interface=0.0.0.0
http_port = $OE_PORT
gevent_port = $LONGPOLLING_PORT
EOL

# El archivo lleva la contrasena maestra: solo lo leen root y el usuario de Odoo
sudo chown root:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

sudo mkdir -p /var/log/$OE_USER
sudo touch /var/log/$OE_USER/odoo.log
sudo chown -R $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Crear Servicio de Sistema
#--------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/$OE_CONFIG.service" <<EOF
[Unit]
Description=Odoo20
Documentation=http://www.odoo.com
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$OE_USER
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME_EXT/venv/bin/python3 $OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
StandardOutput=journal+console
WorkingDirectory=$OE_HOME_EXT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $OE_CONFIG
# restart (y no start) para que al reejecutar el script se cargue la nueva instalacion
sudo systemctl restart $OE_CONFIG

echo -e "\n---- Verificando que Odoo responde en el puerto $OE_PORT ----"
ODOO_OK="False"
for i in $(seq 1 30); do
  if wget -q --tries=1 --timeout=10 -O /dev/null "http://127.0.0.1:$OE_PORT/web/login"; then ODOO_OK="True"; break; fi
  sleep 2
done
sudo systemctl status $OE_CONFIG --no-pager
if [ "$ODOO_OK" != "True" ]; then
  sudo tail -n 30 /var/log/$OE_USER/odoo.log
  abortar "Odoo no responde en el puerto $OE_PORT tras 60 segundos. Revisa /var/log/$OE_USER/odoo.log"
fi
echo "Odoo responde correctamente en el puerto $OE_PORT"

#--------------------------------------------------
# Información de Configuración Final
#--------------------------------------------------
echo -e "-----------------------------------------------------------"
echo "¡Instalación de Odoo 20 completada!"
echo "Acceso: http://localhost:$OE_PORT o http://<tu-ip-servidor>:$OE_PORT"
echo "Usuario del sistema: $OE_USER"
echo "Directorio de instalación: $OE_HOME_EXT"
echo "Addons personalizados: $OE_ADDONS"
echo "Archivo de configuración: /etc/${OE_CONFIG}.conf"
echo "Contraseña maestra (gestor de bases de datos): $OE_SUPERADMIN"
echo "  Guárdala en un lugar seguro: la pide Odoo para crear, copiar, respaldar y restaurar bases de datos."
echo "Archivo de log: /var/log/$OE_USER/odoo.log"
echo "Servicio systemd: $OE_CONFIG.service"
echo -e "-----------------------------------------------------------"
echo "Comandos útiles:"
echo "  - Ver logs: sudo journalctl -u $OE_CONFIG -f"
echo "  - Reiniciar servicio: sudo systemctl restart $OE_CONFIG"
echo "  - Parar servicio: sudo systemctl stop $OE_CONFIG"
echo -e "-----------------------------------------------------------"
