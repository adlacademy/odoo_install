#!/bin/bash
################################################################################
# Script para instalar Odoo 17 en Ubuntu 22.04 LTS
# Basado en el script original de Yenthe Van Ginneken y actualizado para Odoo 17
################################################################################

OE_USER="odoo17"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="17.0"
IS_ENTERPRISE="False"
INSTALL_NGINX="False"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.focal_amd64.deb
LIBSSL_URL=http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb

#--------------------------------------------------
# Redirigir toda la salida a un archivo de log
#--------------------------------------------------
LOG_FILE="odoo_install_logs.txt"
exec > >(tee -i $LOG_FILE)
exec 2>&1

#--------------------------------------------------
# Actualizar Servidor
#--------------------------------------------------
echo -e "\n---- Actualizando el Servidor ----"
sudo apt-get update
sudo apt-get upgrade -y

#--------------------------------------------------
# Instalar PostgreSQL
#--------------------------------------------------
echo -e "\n---- Instalando PostgreSQL ----"
sudo apt-get install postgresql postgresql-server-dev-all -y
sudo su - postgres -c "createuser -s $OE_USER" 2>/dev/null || true

PG_HBA_FILE="/etc/postgresql/$(ls /etc/postgresql)/main/pg_hba.conf"
if [ -f "$PG_HBA_FILE" ]; then
  echo -e "\n---- Configurando PostgreSQL para Odoo ----"
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
echo -e "\n---- Instalando Python 3 y configurando entorno virtual ----"
sudo apt-get install git python3 python3-venv python3-wheel build-essential wget python3-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools -y
sudo apt-get install -y python3-pip

#--------------------------------------------------
# Descargar y Configurar Odoo
#--------------------------------------------------
if [ -d "$OE_HOME_EXT" ]; then
  echo "El directorio $OE_HOME_EXT ya existe. Eliminándolo para una instalación limpia."
  sudo rm -rf $OE_HOME_EXT
fi

sudo mkdir -p $OE_HOME_EXT
sudo mkdir -p /odoo17/custom/addons

echo "Clonando el repositorio de Odoo en $OE_HOME_EXT..."
git clone --depth 1 --branch $OE_VERSION https://github.com/odoo/odoo.git $OE_HOME_EXT || {
  echo "Error al clonar el repositorio de Odoo. Verifica la conectividad y la URL."; exit 1;
}

sudo chown -R $OE_USER:$OE_USER $OE_HOME
sudo chown -R $OE_USER:$OE_USER $OE_HOME_EXT
sudo chown -R $OE_USER:$OE_USER /odoo17/custom/addons

#--------------------------------------------------
# Validar y Descargar requirements.txt
#--------------------------------------------------
echo -e "\n---- Validando archivo requirements.txt ----"
if [ ! -f "$OE_HOME_EXT/requirements.txt" ]; then
  wget https://github.com/odoo/odoo/raw/17.0/requirements.txt -O $OE_HOME_EXT/requirements.txt
fi

#--------------------------------------------------
# Crear entorno virtual e instalar dependencias
#--------------------------------------------------
echo -e "\n---- Creando el entorno virtual ----"
python3 -m venv $OE_HOME_EXT/venv
source $OE_HOME_EXT/venv/bin/activate
$OE_HOME_EXT/venv/bin/pip install --upgrade pip
$OE_HOME_EXT/venv/bin/pip install -r $OE_HOME_EXT/requirements.txt
deactivate

#--------------------------------------------------
# Reinstalar Wkhtmltopdf y dependencias
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Reinstalando Wkhtmltopdf ----"
  wget $LIBSSL_URL -P /tmp/
  sudo dpkg -i /tmp/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
  sudo apt-get install -y xfonts-75dpi xfonts-base fontconfig libxrender1 libxext6
  wget $WKHTMLTOX_X64 -P /tmp/
  sudo dpkg -i /tmp/wkhtmltox_0.12.6-1.focal_amd64.deb
  sudo apt-get install -f -y
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
addons_path=${OE_HOME_EXT}/addons,/odoo17/custom/addons
logfile=/var/log/$OE_USER/odoo.log
logrotate=true
EOL

sudo mkdir -p /var/log/$OE_USER
sudo touch /var/log/$OE_USER/odoo.log
sudo chown -R $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Crear Servicio de Sistema
#--------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/$OE_CONFIG.service" <<EOF
[Unit]
Description=odoo17
Documentation=http://www.odoo.com

[Service]
Type=simple
User=$OE_USER
ExecStart=$OE_HOME_EXT/venv/bin/python3 $OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
WorkingDirectory=$OE_HOME_EXT

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $OE_CONFIG
sudo systemctl start $OE_CONFIG

#--------------------------------------------------
# Información de Configuración Final
#--------------------------------------------------
echo -e "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running."
echo "Port: $OE_PORT"
echo "Configuration file: /etc/${OE_CONFIG}.conf"
echo "Log file: /var/log/$OE_USER/odoo.log"
echo "-----------------------------------------------------------"
