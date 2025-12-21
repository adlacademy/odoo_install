#!/bin/bash
################################################################################
# Script para instalar Odoo 12 en Ubuntu 18.04/20.04 LTS
# Basado en el script original de Yenthe Van Ginneken y actualizado para Odoo 12
################################################################################

OE_USER="odoo12"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="12.0"
IS_ENTERPRISE="False"
INSTALL_NGINX="False"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

WKHTMLTOX_X64=https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.trusty_amd64.deb
WKHTMLTOX_X32=https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.trusty_i386.deb

# Redirigir toda la salida a un archivo de log
LOG_FILE="odoo_install_logs.txt"
exec > >(tee -i $LOG_FILE)
exec 2>&1

#--------------------------------------------------
# Actualizar Servidor
#--------------------------------------------------
echo -e "\n---- Actualizando el Servidor ----"
# universe package is for Ubuntu 18.x
sudo add-apt-repository universe -y
# libpng12-0 dependency for wkhtmltopdf
sudo add-apt-repository "deb http://mirrors.kernel.org/ubuntu/ xenial main" -y
sudo apt-get update
sudo apt-get upgrade -y

#--------------------------------------------------
# Instalar PostgreSQL
#--------------------------------------------------
echo -e "\n---- Instalando PostgreSQL ----"
sudo apt-get install postgresql postgresql-server-dev-all -y
sudo su - postgres -c "createuser -s $OE_USER" 2>/dev/null || true

echo -e "\n---- Configurando PostgreSQL para Odoo ----"
PG_HBA_FILE="/etc/postgresql/$(ls /etc/postgresql)/main/pg_hba.conf"
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
  sudo adduser $OE_USER sudo
fi

#--------------------------------------------------
# Instalar Dependencias
#--------------------------------------------------
echo -e "\n---- Instalando Python 3 y dependencias para Odoo 12 ----"
sudo apt-get install git python3 python3-pip python3-venv python3-wheel build-essential wget python3-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libjpeg-dev gdebi -y

echo -e "\n---- Instalando nodeJS NPM y rtlcss para soporte LTR ----"
sudo apt-get install nodejs npm -y
sudo npm install -g rtlcss

#--------------------------------------------------
# Instalar Wkhtmltopdf si es necesario
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Instalando wkhtml para ODOO 12 ----"
  if [ "`getconf LONG_BIT`" == "64" ];then
      _url=$WKHTMLTOX_X64
  else
      _url=$WKHTMLTOX_X32
  fi
  sudo wget $_url -P /tmp/
  sudo gdebi --n /tmp/`basename $_url`
  sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin 2>/dev/null || true
  sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin 2>/dev/null || true
else
  echo "Wkhtmltopdf no se instala por eleccion del usuario!"
fi

#--------------------------------------------------
# Crear directorio de logs
#--------------------------------------------------
echo -e "\n---- Creando directorio de logs ----"
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Descargar y Configurar Odoo
#--------------------------------------------------
if [ -d "$OE_HOME_EXT" ]; then
  echo "El directorio $OE_HOME_EXT ya existe. Eliminandolo para una instalacion limpia."
  sudo rm -rf $OE_HOME_EXT
fi

echo "Creando el directorio del servidor Odoo..."
sudo mkdir -p $OE_HOME_EXT

echo "Clonando el repositorio de Odoo en $OE_HOME_EXT..."
git clone --depth 1 --branch $OE_VERSION https://github.com/odoo/odoo.git $OE_HOME_EXT || {
  echo "Error al clonar el repositorio de Odoo. Verifica la conectividad y la URL."; exit 1;
}

if [ $IS_ENTERPRISE = "True" ]; then
    echo -e "\n--- Creando symlink para node"
    sudo ln -s /usr/bin/nodejs /usr/bin/node 2>/dev/null || true
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an offical Odoo partner and you need access to\nhttp://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done

    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
fi

echo -e "\n---- Creando directorio de modulos personalizados en /odoo12/custom/addons ----"
sudo mkdir -p /odoo12/custom/addons

echo -e "\n---- Estableciendo permisos para $OE_HOME y $OE_HOME_EXT ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME
sudo chown -R $OE_USER:$OE_USER $OE_HOME_EXT
sudo chown -R $OE_USER:$OE_USER /odoo12/custom/addons

#--------------------------------------------------
# Validar y Descargar requirements.txt
#--------------------------------------------------
echo -e "\n---- Validando archivo requirements.txt ----"
wget https://raw.githubusercontent.com/odoo/odoo/${OE_VERSION}/requirements.txt -O $OE_HOME_EXT/requirements.txt

#--------------------------------------------------
# Crear entorno virtual e instalar dependencias
#--------------------------------------------------
echo -e "\n---- Creando el entorno virtual ----"
python3 -m venv $OE_HOME_EXT/venv
source $OE_HOME_EXT/venv/bin/activate
$OE_HOME_EXT/venv/bin/pip install --upgrade pip
$OE_HOME_EXT/venv/bin/pip install wheel
$OE_HOME_EXT/venv/bin/pip install -r $OE_HOME_EXT/requirements.txt

if [ $IS_ENTERPRISE = "True" ]; then
    echo -e "\n---- Instalando librerias especificas de Enterprise ----"
    $OE_HOME_EXT/venv/bin/pip install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

deactivate

#--------------------------------------------------
# Configurar Archivo de Configuracion
#--------------------------------------------------
echo -e "\n---- Generando password de admin ----"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi

if [ $IS_ENTERPRISE = "True" ]; then
    ADDONS_PATH="${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons,/odoo12/custom/addons"
else
    ADDONS_PATH="${OE_HOME_EXT}/addons,/odoo12/custom/addons"
fi

sudo bash -c "cat > /etc/${OE_CONFIG}.conf" <<EOL
[options]
admin_passwd = $OE_SUPERADMIN
db_host = localhost
db_port = 5432
db_user = $OE_USER
db_password = $OE_SUPERADMIN
http_port = $OE_PORT
addons_path=$ADDONS_PATH
logfile=/var/log/$OE_USER/odoo.log
logrotate=true
EOL

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

#--------------------------------------------------
# Crear Servicio de Sistema (systemd)
#--------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/$OE_CONFIG.service" <<EOF
[Unit]
Description=Odoo12
Documentation=http://www.odoo.com
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$OE_USER
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME_EXT/venv/bin/python3 $OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
StandardOutput=journal+console
WorkingDirectory=$OE_HOME_EXT

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $OE_CONFIG
sudo systemctl start $OE_CONFIG

#--------------------------------------------------
# Instalar Nginx si es necesario
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  echo -e "\n---- Instalando y configurando Nginx ----"
  sudo apt install nginx -y
  cat <<EOF > ~/odoo
server {
  listen 80;

  server_name $WEBSITE_NAME;

  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  proxy_set_header X-Client-IP \$remote_addr;
  proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log   /var/log/nginx/$OE_USER-error.log;

  proxy_buffers 16 64k;
  proxy_buffer_size 128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

  types {
    text/less less;
    text/scss scss;
  }

  gzip on;
  gzip_min_length 1100;
  gzip_buffers 4 32k;
  gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
    proxy_pass http://127.0.0.1:$OE_PORT;
    proxy_redirect off;
  }

  location /longpolling {
    proxy_pass http://127.0.0.1:$LONGPOLLING_PORT;
  }

  location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
    expires 2d;
    proxy_pass http://127.0.0.1:$OE_PORT;
    add_header Cache-Control "public, no-transform";
  }

  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404 1m;
    proxy_buffering on;
    expires 864000;
    proxy_pass http://127.0.0.1:$OE_PORT;
  }
}
EOF

  sudo mv ~/odoo /etc/nginx/sites-available/
  sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
  sudo rm /etc/nginx/sites-enabled/default 2>/dev/null || true
  sudo service nginx reload
  sudo bash -c "echo 'proxy_mode = True' >> /etc/${OE_CONFIG}.conf"
  echo "Done! Nginx configurado en /etc/nginx/sites-available/odoo"
else
  echo "Nginx no se instala por eleccion del usuario!"
fi

#--------------------------------------------------
# Habilitar SSL con certbot
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ] && [ $WEBSITE_NAME != "_" ]; then
  sudo add-apt-repository ppa:certbot/certbot -y && sudo apt-get update -y
  sudo apt-get install python-certbot-nginx -y
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo "SSL/HTTPS habilitado!"
else
  echo "SSL/HTTPS no habilitado por eleccion del usuario o configuracion incompleta!"
fi

echo -e "\n---- Verificando estado del servicio ----"
sudo systemctl status $OE_CONFIG

#--------------------------------------------------
# Informacion de Configuracion Final
#--------------------------------------------------
echo -e "-----------------------------------------------------------"
echo "Instalacion de Odoo 12 completada!"
echo "Acceso: http://localhost:$OE_PORT o http://<tu-ip-servidor>:$OE_PORT"
echo "Usuario del sistema: $OE_USER"
echo "Directorio de instalacion: $OE_HOME_EXT"
echo "Archivo de configuracion: /etc/${OE_CONFIG}.conf"
echo "Archivo de log: /var/log/$OE_USER/odoo.log"
echo "Servicio systemd: $OE_CONFIG.service"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo -e "-----------------------------------------------------------"
echo "Comandos utiles:"
echo "  - Ver logs: sudo journalctl -u $OE_CONFIG -f"
echo "  - Reiniciar servicio: sudo systemctl restart $OE_CONFIG"
echo "  - Parar servicio: sudo systemctl stop $OE_CONFIG"
echo "  - Iniciar servicio: sudo systemctl start $OE_CONFIG"
if [ $INSTALL_NGINX = "True" ]; then
  echo "  - Nginx config: /etc/nginx/sites-available/odoo"
fi
echo -e "-----------------------------------------------------------"
