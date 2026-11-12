#!/bin/bash
################################################################################
# Script para instalar Odoo 13 en Ubuntu 20.04 y Ubuntu 18.04
# Basado en el script original de Yenthe Van Ginneken y actualizado para Odoo 13
#
# Requisitos de Odoo 13 (setup.py, requirements.txt y documentación de Odoo 13):
#   - Python 3.6 a 3.8
#   - PostgreSQL 10 o superior
# Probado con este script en servidores limpios: Ubuntu 20.04 y Ubuntu 18.04
# OJO: Ubuntu 20.04 y Ubuntu 18.04 ya no reciben actualizaciones de seguridad estándar de su distribución.
################################################################################

OE_USER="odoo13"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
OE_ADDONS="$OE_HOME/custom/addons"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="13.0"
IS_ENTERPRISE="False"
INSTALL_NGINX="False"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

# Con IS_ENTERPRISE="True": repositorio de Odoo Enterprise (solo partners de Odoo con acceso en GitHub)
OE_ENTERPRISE_URL="https://github.com/odoo/enterprise.git"

# Versiones exigidas por Odoo 13
MIN_PY_VERSION="3.6"
MAX_PY_VERSION="3.8"
MIN_PG_VERSION="10"

# Build oficial de wkhtmltopdf con qt parcheado (cabeceras y pies de pagina en los PDF). Por defecto el de
# Ubuntu 22.04 (jammy): enlaza con libssl3 y se instala en Ubuntu 22.04 y posteriores, sin libssl1.1 (sin soporte).
# Mas abajo se elige el build de cada sistema (Ubuntu 18.04/20.04, Debian 11, Debian 12/13).
WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb

# Redirigir toda la salida a un archivo de log. El log lleva la contrasena maestra del resumen final:
# se crea legible solo por root.
LOG_FILE="odoo_install_logs.txt"
( umask 077; : > "$LOG_FILE" ); chmod 600 "$LOG_FILE"
exec > >(tee -i -a $LOG_FILE)
exec 2>&1

# Detiene la instalacion si falla un paso critico, en lugar de continuar y
# dejar un Odoo que no arranca. El script se puede volver a ejecutar.
abortar() {
  echo -e "\n*** ERROR: $1 ***"
  echo "Revisa el log ($LOG_FILE) y vuelve a ejecutar el script cuando se resuelva."
  exit 1
}

# Reintentos ante cortes de red: apt reintenta descargas y wget tambien los fallos de DNS
# ("Temporary failure in name resolution") cuando su version lo admite. apt no hace preguntas:
# una instalacion desatendida no se queda esperando una respuesta.
APT_GET="sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
WGET="wget --tries=5 --waitretry=10 --retry-connrefused"
wget --help 2>/dev/null | grep -q -- "--retry-on-host-error" && WGET="$WGET --retry-on-host-error"

# Paquetes que existen en unos sistemas y en otros no: se instalan solo los que el sistema tiene
solo_existentes() {
  local p lista=""
  for p in "$@"; do
    # con candidato instalable: «apt-cache show» responde tambien por un paquete que ya no existe pero otro nombra
    # (libatlas-base-dev en Ubuntu 26.04)
    apt-cache policy "$p" 2>/dev/null | grep -q "Candidate: [^(]" && lista="$lista $p"
  done
  echo $lista
}

# Contrasena aleatoria de N letras y cifras (sin tuberias infinitas sobre /dev/urandom)
aleatoria() {
  head -c 4096 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$1"
}

#--------------------------------------------------
# Validar version de Python (Odoo 13 exige 3.6 - 3.8)
#--------------------------------------------------
echo -e "\n---- Validando la version de Python del sistema ----"
PY_VERSION=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)
if ! python3 -c "import sys; v = lambda s: tuple(int(x) for x in s.split('.')); sys.exit(0 if v('$MIN_PY_VERSION') <= sys.version_info[:2] <= v('$MAX_PY_VERSION') else 1)" 2>/dev/null; then
  echo "ERROR: Odoo $OE_VERSION requiere Python entre $MIN_PY_VERSION y $MAX_PY_VERSION. Este sistema tiene Python ${PY_VERSION:-desconocido}."
  echo "Instala Odoo $OE_VERSION sobre Ubuntu 20.04 o Ubuntu 18.04."
  exit 1
fi
echo "Python $PY_VERSION: compatible"

# Distribucion: algunos paquetes de desarrollo cambian de nombre entre Ubuntu y Debian
. /etc/os-release
DISTRO_ID="${ID:-ubuntu}"
CODENAME="${VERSION_CODENAME:-}"
echo "Sistema: ${PRETTY_NAME:-$DISTRO_ID}"
case "$CODENAME" in
  bionic|focal)
    echo "ADVERTENCIA: ${PRETTY_NAME:-este sistema} ya no recibe actualizaciones de seguridad estándar. Úsalo solo si necesitas Odoo $OE_VERSION y no puedes usar una versión más reciente del sistema." ;;
esac

# Contrasena maestra: aleatoria salvo que se elija otra en OE_SUPERADMIN con GENERATE_RANDOM_PASSWORD="False".
# Se muestra al final de la instalacion. El usuario de PostgreSQL lleva otra, que solo necesita Odoo.
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
  OE_SUPERADMIN=$(aleatoria 20)
fi
[ -n "$OE_SUPERADMIN" ] || abortar "no se pudo generar la contrasena maestra"
OE_DB_PASSWORD=$(aleatoria 24)
[ -n "$OE_DB_PASSWORD" ] || abortar "no se pudo generar la contrasena de PostgreSQL"

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
$APT_GET install postgresql -y || abortar "no se pudo instalar PostgreSQL"

PG_VERSION=$(ls /etc/postgresql 2>/dev/null | sort -n | tail -1)
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
sudo su - postgres -c "psql -c \"ALTER USER $OE_USER WITH PASSWORD '$OE_DB_PASSWORD';\"" || abortar "no se pudo poner la contrasena del usuario $OE_USER en PostgreSQL"

#--------------------------------------------------
# Validar y Crear Usuario del Sistema
#--------------------------------------------------
echo -e "\n---- Validando usuario del sistema Odoo ----"
if ! id "$OE_USER" &>/dev/null; then
  sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER || abortar "no se pudo crear el usuario del sistema $OE_USER"
fi

#--------------------------------------------------
# Instalar Dependencias
#--------------------------------------------------
echo -e "\n---- Instalando Python 3 y dependencias para Odoo 13 ----"
$APT_GET install git python3 python3-venv python3-wheel build-essential wget python3-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools -y || abortar "no se pudieron instalar Python 3 y las dependencias de compilacion"
$APT_GET install -y python3-pip || abortar "no se pudo instalar python3-pip"

# Dependencias adicionales específicas para Odoo 13
echo -e "\n---- Instalando dependencias adicionales de Odoo 13 ----"
# libjpeg8-dev y libatlas-base-dev solo existen en Ubuntu; en Debian bastan libjpeg-dev y libopenblas-dev.
# Las librerias de imagenes, fuentes y eventos permiten compilar las dependencias de Python que no traen
# paquete precompilado para la version de Python del sistema.
if [ "$DISTRO_ID" = "debian" ]; then
  EXTRA_DEV="libopenblas-dev"
else
  EXTRA_DEV="libjpeg8-dev libatlas-base-dev"
fi
EXTRA_DEV="$EXTRA_DEV libfreetype6-dev libfreetype-dev libwebp-dev libtiff-dev libopenjp2-7-dev libfribidi-dev libharfbuzz-dev libfontconfig1-dev libev-dev"
$APT_GET install node-less libjpeg-dev zlib1g-dev libpq-dev libxml2-dev libffi-dev libssl-dev liblcms2-dev libblas-dev libcairo2-dev pkg-config $(solo_existentes $EXTRA_DEV) -y || abortar "no se pudieron instalar las dependencias adicionales de Odoo"
# npm y rtlcss: hojas de estilo de los idiomas que se escriben de derecha a izquierda (arabe, hebreo...). Van aparte y no
# detienen la instalacion: en Ubuntu 18.04 el npm del sistema choca con libssl-dev (pide libssl1.0-dev).
# Las versiones actuales de rtlcss piden Node.js 12 o posterior; con un Node.js anterior se instala la 2.
if $APT_GET install -y npm; then
  RTLCSS="rtlcss"
  NODE_MAYOR=$(node --version 2>/dev/null | sed 's/^v//; s/\..*//')
  [ -n "$NODE_MAYOR" ] && [ "$NODE_MAYOR" -lt 12 ] 2>/dev/null && RTLCSS="rtlcss@2"
  sudo npm install -g $RTLCSS >/dev/null 2>&1 && echo "rtlcss instalado" || echo "ADVERTENCIA: no se pudo instalar rtlcss (solo hace falta para idiomas de derecha a izquierda)."
else
  echo "ADVERTENCIA: npm no se pudo instalar en este sistema; sin rtlcss (solo hace falta para idiomas de derecha a izquierda)."
fi

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

ENTERPRISE_ADDONS=""
if [ "$IS_ENTERPRISE" = "True" ]; then
  echo -e "\n---- Descargando Odoo Enterprise ----"
  echo "Hace falta una cuenta de GitHub con acceso a $OE_ENTERPRISE_URL (partners de Odoo)."
  echo "Si git pide credenciales: tu usuario de GitHub y, como contrasena, un token de acceso personal."
  sudo rm -rf $OE_HOME/enterprise
  sudo mkdir -p $OE_HOME/enterprise
  git clone --depth 1 --branch $OE_VERSION "$OE_ENTERPRISE_URL" $OE_HOME/enterprise/addons || abortar "no se pudo descargar Odoo Enterprise. Comprueba que tu cuenta de GitHub tiene acceso a $OE_ENTERPRISE_URL"
  ENTERPRISE_ADDONS="$OE_HOME/enterprise/addons,"
fi

echo "Creando el directorio de addons personalizados en $OE_ADDONS..."
sudo mkdir -p $OE_ADDONS

echo "Estableciendo los permisos para $OE_HOME y $OE_HOME_EXT..."
sudo chown -R $OE_USER:$OE_USER $OE_HOME
sudo chown -R $OE_USER:$OE_USER $OE_HOME_EXT
sudo chown -R $OE_USER:$OE_USER $OE_ADDONS


#--------------------------------------------------
# Validar requirements.txt
#--------------------------------------------------
# Se usa el requirements.txt del propio codigo de Odoo que se acaba de descargar: siempre corresponde a esa
# version del codigo y trae las versiones de cada paquete para cada version de Python.
echo -e "\n---- Validando archivo requirements.txt ----"
[ -s $OE_HOME_EXT/requirements.txt ] || abortar "el codigo de Odoo descargado no trae requirements.txt"


#--------------------------------------------------
# Crear entorno virtual e instalar dependencias
#--------------------------------------------------
echo -e "\n---- Creando el entorno virtual ----"
python3 -m venv $OE_HOME_EXT/venv || abortar "no se pudo crear el entorno virtual"
source $OE_HOME_EXT/venv/bin/activate
$OE_HOME_EXT/venv/bin/pip install --upgrade pip
$OE_HOME_EXT/venv/bin/pip install wheel
REQUISITOS=$OE_HOME_EXT/requirements.txt
# Odoo 13 importa pkg_resources, que viene con setuptools: el entorno virtual de Python 3.12 o posterior ya no trae
# setuptools y sus versiones nuevas quitaron pkg_resources (sin esto, Odoo no arranca: «No module named pkg_resources»).
$OE_HOME_EXT/venv/bin/pip install "setuptools<81" || abortar "no se pudo instalar setuptools en el entorno virtual"
# Para Python 3.10 y 3.11 el requirements.txt de Odoo 13 fija gevent 21.8.0 y greenlet 1.1.2, que no traen paquete
# precompilado y ya no se pueden compilar (gevent pide una alfa de Cython 3.0 que PyPI ya no ofrece). Se instalan gevent
# 22.10.2 y greenlet 2.0.2, la pareja que el propio Odoo 16 fija para Python 3.11; el resto, tal cual.
sed -e "s/^gevent==21\.8\.0/gevent==22.10.2/" -e "s/^greenlet==1\.1\.2/greenlet==2.0.2/" \
    $OE_HOME_EXT/requirements.txt > /tmp/odoo_requirements.txt
REQUISITOS=/tmp/odoo_requirements.txt
$OE_HOME_EXT/venv/bin/pip install -r $REQUISITOS || abortar "fallo la instalacion de las dependencias de Python (pip)"
# Paquetes que Odoo usa si estan instalados y que su requirements.txt no trae: pdfminer.six (indexa el texto de los PDF adjuntos).
# Se instalan sin cambiar nada de lo que fijo el requirements.txt (si no, pdfminer.six subia cryptography y el pyOpenSSL
# antiguo de Odoo dejaba de cargar: «module 'lib' has no attribute 'GEN_EMAIL'»); si no hay version compatible, se omiten.
$OE_HOME_EXT/venv/bin/pip freeze > /tmp/odoo_instalado.txt
$OE_HOME_EXT/venv/bin/pip install -c /tmp/odoo_instalado.txt pdfminer.six || echo "ADVERTENCIA: no se pudieron instalar pdfminer.six (opcionales)."
rm -f /tmp/odoo_instalado.txt /tmp/odoo_requirements.txt
deactivate

#--------------------------------------------------
# Instalar Wkhtmltopdf y dependencias
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Instalando Wkhtmltopdf ----"
  $APT_GET install -y xfonts-75dpi xfonts-base fontconfig libxrender1 libxext6
  # El build de Ubuntu 22.04 depende de libjpeg-turbo8, que Debian no tiene: cada sistema usa el build oficial
  # que le corresponde (Debian 12 sirve tambien en Debian 13, probado). Ubuntu 18.04 y 20.04 traen libssl1.1
  # de serie y usan el build de su version.
  case "$CODENAME" in
    bionic) WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.bionic_amd64.deb ;;
    focal) WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.focal_amd64.deb ;;
    bullseye) WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bullseye_amd64.deb ;;
    *)
      if [ "$DISTRO_ID" = "debian" ]; then
        WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
      fi
      ;;
  esac
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    $WGET $WKHTMLTOX_X64 -O /tmp/wkhtmltox.deb
    # apt (y no dpkg -i) resuelve las dependencias del paquete automaticamente
    $APT_GET install -y /tmp/wkhtmltox.deb
  else
    echo "ADVERTENCIA: no hay build oficial de wkhtmltopdf con qt parcheado para $(dpkg --print-architecture): se instala el del sistema (los PDF saldran sin cabecera ni pie)."
    $APT_GET install -y wkhtmltopdf
  fi
  wkhtmltopdf --version || echo "ADVERTENCIA: wkhtmltopdf no quedo instalado; los informes PDF no funcionaran."
fi

#--------------------------------------------------
# Configurar Archivo de Configuración
#--------------------------------------------------
# Con Nginx delante, Odoo solo escucha en local y confia en las cabeceras del proxy (proxy_mode)
if [ "$INSTALL_NGINX" = "True" ]; then
  HTTP_INTERFACE="127.0.0.1"
else
  HTTP_INTERFACE="0.0.0.0"
fi

sudo bash -c "cat > /etc/${OE_CONFIG}.conf" <<EOL
[options]
admin_passwd = $OE_SUPERADMIN
db_host = localhost
db_port = 5432
db_user = $OE_USER
db_password = $OE_DB_PASSWORD
addons_path=${ENTERPRISE_ADDONS}${OE_HOME_EXT}/addons,${OE_ADDONS}
logfile=/var/log/$OE_USER/odoo.log
data_dir = $OE_HOME/.local/share/Odoo
http_interface=$HTTP_INTERFACE
http_port = $OE_PORT
longpolling_port = $LONGPOLLING_PORT
EOL
if [ "$INSTALL_NGINX" = "True" ]; then
  echo "proxy_mode = True" | sudo tee -a /etc/${OE_CONFIG}.conf >/dev/null
fi

# data_dir fijo (el mismo que usa el servicio): un «sudo -u odoo<N> odoo-bin ...» lanzado a mano en un sistema cuyo sudo conserva
# el HOME de quien lo lanza (Ubuntu 18.04 y 20.04) dejaba el filestore en el home de esa persona, o fallaba sin permiso.
# El archivo lleva la contrasena maestra: solo lo leen root y el usuario de Odoo
sudo chown root:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

sudo mkdir -p /var/log/$OE_USER
sudo touch /var/log/$OE_USER/odoo.log
sudo chown -R $OE_USER:$OE_USER /var/log/$OE_USER

# Rotacion semanal del log (sin ella crece sin limite)
sudo bash -c "cat > /etc/logrotate.d/$OE_USER" <<EOF
/var/log/$OE_USER/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

#--------------------------------------------------
# Crear Servicio de Sistema
#--------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/$OE_CONFIG.service" <<EOF
[Unit]
Description=Odoo13
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
for i in $(seq 1 45); do
  if wget -q --tries=1 --timeout=10 -O /dev/null "http://127.0.0.1:$OE_PORT/web/login"; then ODOO_OK="True"; break; fi
  sleep 2
done
sudo systemctl status $OE_CONFIG --no-pager
if [ "$ODOO_OK" != "True" ]; then
  sudo tail -n 30 /var/log/$OE_USER/odoo.log
  abortar "Odoo no responde en el puerto $OE_PORT tras 90 segundos. Revisa /var/log/$OE_USER/odoo.log"
fi
echo "Odoo responde correctamente en el puerto $OE_PORT"

#--------------------------------------------------
# Nginx (opcional) y HTTPS con Let's Encrypt (opcional)
#--------------------------------------------------
URL_ACCESO="http://localhost:$OE_PORT o http://<tu-ip-servidor>:$OE_PORT"
if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n---- Instalando y configurando Nginx ----"
  $APT_GET install -y nginx || abortar "no se pudo instalar Nginx"
  # Sin workers, Odoo atiende /longpolling en el mismo puerto ($OE_PORT). Si activas workers en el .conf,
  # cambia el proxy_pass de /longpolling al puerto $LONGPOLLING_PORT.
  sudo bash -c "cat > /etc/nginx/sites-available/$OE_USER" <<EOF
map \$http_upgrade \$conexion_${OE_USER} {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  server_name $WEBSITE_NAME;

  access_log /var/log/nginx/$OE_USER-access.log;
  error_log  /var/log/nginx/$OE_USER-error.log;

  client_max_body_size 200m;
  proxy_read_timeout 720s;
  proxy_connect_timeout 720s;
  proxy_send_timeout 720s;

  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;

  location /longpolling {
    proxy_pass http://127.0.0.1:$OE_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$conexion_${OE_USER};
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  location / {
    proxy_pass http://127.0.0.1:$OE_PORT;
    proxy_redirect off;
  }

  gzip on;
  gzip_types text/css text/plain text/xml application/xml application/json application/javascript;
}
EOF
  sudo ln -sf /etc/nginx/sites-available/$OE_USER /etc/nginx/sites-enabled/$OE_USER
  # Con WEBSITE_NAME="_" este sitio atiende cualquier nombre: se quita el sitio de bienvenida de Nginx
  if [ "$WEBSITE_NAME" = "_" ]; then
    sudo rm -f /etc/nginx/sites-enabled/default
  fi
  sudo nginx -t || abortar "la configuracion de Nginx no es valida (/etc/nginx/sites-available/$OE_USER)"
  sudo systemctl reload nginx || sudo systemctl restart nginx
  URL_ACCESO="http://$( [ "$WEBSITE_NAME" = "_" ] && echo '<tu-ip-servidor>' || echo "$WEBSITE_NAME" )"

  if [ "$ENABLE_SSL" = "True" ] && [ "$WEBSITE_NAME" != "_" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ]; then
    echo -e "\n---- Activando HTTPS con Let's Encrypt (certbot) ----"
    $APT_GET install -y certbot python3-certbot-nginx || abortar "no se pudo instalar certbot"
    if sudo certbot --nginx -d $WEBSITE_NAME --non-interactive --agree-tos -m $ADMIN_EMAIL --redirect; then
      URL_ACCESO="https://$WEBSITE_NAME"
    else
      echo "ADVERTENCIA: certbot no pudo obtener el certificado. Comprueba que $WEBSITE_NAME apunta a este servidor y que el puerto 80 esta abierto; Odoo sigue disponible por http."
    fi
  elif [ "$ENABLE_SSL" = "True" ]; then
    echo "HTTPS no activado: para activarlo pon tu dominio en WEBSITE_NAME y tu correo en ADMIN_EMAIL."
  fi
fi

#--------------------------------------------------
# Información de Configuración Final
#--------------------------------------------------
echo -e "-----------------------------------------------------------"
echo "¡Instalación de Odoo 13 completada!"
echo "Acceso: $URL_ACCESO"
echo "Usuario del sistema: $OE_USER"
echo "Directorio de instalación: $OE_HOME_EXT"
echo "Addons personalizados: $OE_ADDONS"
echo "  (mientras esa carpeta este vacia, Odoo la omite y lo avisa en el log: \"invalid addons directory\". Es normal.)"
echo "Archivo de configuración: /etc/${OE_CONFIG}.conf"
echo "Contraseña maestra (gestor de bases de datos): $OE_SUPERADMIN"
echo "  Guárdala en un lugar seguro: la pide Odoo para crear, copiar, respaldar y restaurar bases de datos."
if [ "$OE_SUPERADMIN" = "admin" ]; then
  echo "  ADVERTENCIA: la contraseña maestra es «admin». Cámbiala en /etc/${OE_CONFIG}.conf (admin_passwd) y reinicia el servicio."
fi
echo "Archivo de log: /var/log/$OE_USER/odoo.log"
echo "Servicio systemd: $OE_CONFIG.service"
echo -e "-----------------------------------------------------------"
echo "Comandos útiles:"
echo "  - Ver logs: sudo journalctl -u $OE_CONFIG -f"
echo "  - Reiniciar servicio: sudo systemctl restart $OE_CONFIG"
echo "  - Parar servicio: sudo systemctl stop $OE_CONFIG"
echo -e "-----------------------------------------------------------"
