# Contactanos para Odoo Enterprise y Localización de tu País

Si estás interesado en la versión **Enterprise** de Odoo o necesitas la **localización de tu país**, contáctanos:

- **Correo:** info@adlacademy.com.do  
- **WhatsApp:** +1(809)-418-4467  

### Beneficios de Odoo Enterprise:
- **Módulos Exclusivos:** Acceso a herramientas avanzadas como gestión de suscripciones, planificación avanzada y firmas electrónicas.  
- **Soporte Oficial:** Recibe atención prioritaria directamente del equipo de Odoo.  
- **Actualizaciones Continuas:** Asegura acceso a las últimas mejoras y correcciones de la plataforma.  
- **Cumplimiento Legal:** Adaptación específica para cumplir con regulaciones locales de varios países.

### Beneficios de la Localización:
- **Cumplimiento Normativo:** Configuración para impuestos, facturación y contabilidad conforme a las leyes locales.  
- **Optimización Operativa:** Ahorra tiempo adaptando Odoo a tu mercado específico.  
- **Soporte Técnico:** Asistencia experta para configurar y utilizar las funciones localizadas.  

---

# [Odoo](https://www.odoo.com "Página principal de Odoo") Script de Instalación

## Procedimiento de instalación

##### 1. Descarga el script:
```
sudo wget https://raw.githubusercontent.com/adlacademy/odoo_install/refs/heads/12.0/odoo_install.sh
```

> Esta rama instala **Odoo 12**. Para otra versión, cambia `12.0` en la URL por la rama correspondiente (ver la tabla de compatibilidad).

##### 2. (Opcional) Revisa los parámetros
Están al principio del script (ver [Parámetros](#parámetros)). Con los valores por defecto instala Odoo 12 Community, accesible en el puerto 8069, con una contraseña maestra aleatoria.

##### 3. Haz el script ejecutable:
```
sudo chmod +x odoo_install.sh
```

##### 4. Ejecuta el script:
```
sudo ./odoo_install.sh
```

Tarda unos minutos. Toda la salida queda también en `odoo_install_logs.txt` (legible solo por root, porque lleva la contraseña maestra).

## Qué hace el script
1. Comprueba que la versión de Python del sistema es compatible con Odoo 12 (3.5 a 3.8).
2. Actualiza el sistema e instala PostgreSQL; comprueba que su versión es la 10 o superior.
3. Crea el usuario de PostgreSQL y el usuario del sistema `odoo12`, que ejecuta el servicio (nunca root).
4. Instala las librerías que necesita Odoo, `node-less` y `rtlcss`.
5. Descarga Odoo 12 desde su repositorio oficial en GitHub (solo la última versión de la rama) y, si se pide, Odoo Enterprise.
6. Crea un entorno virtual de Python e instala ahí las dependencias del `requirements.txt` del propio código de Odoo.
7. Instala wkhtmltopdf 0.12.6 con qt parcheado (cabeceras y pies de página en los PDF), el build oficial de cada sistema.
8. Escribe `/etc/odoo12-server.conf`, la rotación del log y el servicio `odoo12-server`; lo arranca y **comprueba que Odoo responde**. Si algo falla, se detiene y dice qué.
9. Opcional: Nginx delante de Odoo y HTTPS con Let's Encrypt.

## Contraseña maestra
Con `GENERATE_RANDOM_PASSWORD="True"` (el valor por defecto) el script genera una contraseña maestra aleatoria y la muestra al final de la instalación. Guárdala en un lugar seguro: Odoo la pide para crear, copiar, respaldar y restaurar bases de datos. El usuario de PostgreSQL lleva otra contraseña aleatoria distinta, que solo usa Odoo. El archivo de configuración (`/etc/odoo12-server.conf`) queda legible solo por root y por el usuario de Odoo.

## Parámetros
- `OE_USER`: usuario del sistema y de PostgreSQL (`odoo12`). Odoo queda en `/odoo12/odoo12-server` y los módulos propios en `/odoo12/custom/addons`.
- `GENERATE_RANDOM_PASSWORD`: `True` genera la contraseña maestra; con `False` se usa la de `OE_SUPERADMIN` (cámbiala: si se queda en `admin`, el script lo avisa).
- `INSTALL_WKHTMLTOPDF`: `False` si no quieres instalar wkhtmltopdf.
- `OE_PORT`: puerto de Odoo (8069).
- `OE_VERSION`: no lo cambies: cada rama del repositorio instala su versión.
- `IS_ENTERPRISE`: `True` descarga también Odoo Enterprise desde `OE_ENTERPRISE_URL` (`https://github.com/odoo/enterprise.git`). Solo funciona con una cuenta de GitHub con acceso a ese repositorio (partners de Odoo): git pide el usuario y, como contraseña, un token de acceso personal.
- `INSTALL_NGINX`: `True` instala Nginx delante de Odoo (puerto 80) con `proxy_mode` activado; Odoo pasa a escuchar solo en local.
- `WEBSITE_NAME`: dominio del sitio para Nginx (`_` = cualquier nombre).
- `ENABLE_SSL` y `ADMIN_EMAIL`: con `INSTALL_NGINX="True"`, un dominio en `WEBSITE_NAME` que apunte al servidor y un correo válido en `ADMIN_EMAIL`, el script pide un certificado gratuito de Let's Encrypt con certbot y redirige http a https. _Al habilitar HTTPS con Let's Encrypt aceptas sus [condiciones](https://letsencrypt.org/repository/)._
- `LONGPOLLING_PORT`: puerto de /longpolling cuando Odoo trabaja con *workers* (longpolling_port).

### Nginx y *workers*
El script deja Odoo en modo de un solo proceso, que atiende también /longpolling en el puerto 8069, y Nginx envía todo ahí. Si activas *workers* en el `.conf` (recomendado en producción, ver la [guía de despliegue de Odoo](https://www.odoo.com/documentation/12.0/administration/deployment/deploy.html)), cambia en `/etc/nginx/sites-available/odoo12` el `proxy_pass` de `location /longpolling` al puerto `LONGPOLLING_PORT` (8072).

## Cambios del 12 de noviembre de 2026
- Ya no desactiva la verificación TLS de git para root (`http.sslVerify false`) ni descarga con `--no-check-certificate`.
- Ya no añade el repositorio de Ubuntu 16.04 (xenial) a apt ni mete al usuario `odoo12` en el grupo `sudo`.
- Ya no borra el Node.js del sistema (con él se iba `node-less`) para instalar NodeSource.
- wkhtmltopdf 0.12.6 con qt parcheado del build de cada Ubuntu (antes, 0.12.5 de Ubuntu 18.04 para todos).
- Instala setuptools anterior a la 81 en el entorno virtual: Odoo 12 usa pkg_resources, que las versiones nuevas quitaron.

Todas las ramas comparten ya el mismo script, con los requisitos de su versión de Odoo: contraseña maestra aleatoria y otra distinta para PostgreSQL, `.conf` y log de instalación legibles solo por quien debe, wkhtmltopdf con qt parcheado del build oficial de cada sistema, dependencias de Python del `requirements.txt` del propio código de Odoo en un entorno virtual, servicio con reinicio automático y rotación del log, Nginx/HTTPS y Enterprise opcionales, y una comprobación final de que Odoo responde: si un paso crítico falla, el script se detiene y lo dice.

## Requisitos mínimos del servidor
Aunque técnicamente puedes ejecutar una instancia de Odoo con 1GB (1024MB) de RAM, no es recomendable. Una instancia de Linux normalmente usa entre 300MB y 500MB, y el resto debe distribuirse entre Odoo, PostgreSQL y otros servicios. Si instalas Odoo, asegúrate de usar al menos 2GB de RAM. Este script podría fallar si los recursos son insuficientes.  
Se han reportado problemas conocidos en DigitalOcean, por ejemplo, donde la instalación falla en máquinas con 1GB de RAM.

---

## Compatibilidad de versiones de Odoo y del sistema
Cada rama comprueba la versión de Python y de PostgreSQL antes de instalar. Los sistemas de la tabla se probaron con el script en servidores limpios (instalación, base de datos creada y PDF generado desde Odoo) el 12 y el 13 de noviembre de 2026.

| Rama | Python | PostgreSQL | Sistemas probados |
|---|---|---|---|
| **12.0** | 3.5 a 3.8 | 10 o superior | Ubuntu 20.04¹ y Ubuntu 18.04¹ |
| 13.0 | 3.6 a 3.8 | 10 o superior | Ubuntu 20.04¹ y Ubuntu 18.04¹ |
| 14.0 | 3.7 a 3.10 | 12 o superior | Ubuntu 22.04 y Ubuntu 20.04¹ |
| 15.0 | 3.7 a 3.12 | 12 o superior | Ubuntu 22.04, Ubuntu 24.04 y Ubuntu 20.04¹ |
| 16.0 | 3.7 a 3.12 | 12 o superior | Ubuntu 22.04, Ubuntu 24.04, Debian 12 y Ubuntu 20.04¹ |
| 17.0 | 3.10 a 3.14 | 12 o superior | Ubuntu 24.04, Debian 13, Ubuntu 22.04, Debian 12 y Ubuntu 26.04 |
| 18.0 | 3.10 a 3.14 | 12 o superior | Ubuntu 24.04, Debian 13, Ubuntu 22.04, Debian 12 y Ubuntu 26.04 |
| 19.0 | 3.10 a 3.14 | 13 o superior | Ubuntu 24.04, Debian 13, Ubuntu 22.04, Debian 12 y Ubuntu 26.04 |
| 20.0 | 3.12 a 3.14 | 16 o superior | Ubuntu 24.04, Debian 13 y Ubuntu 26.04 |

¹ Ubuntu 18.04 y Ubuntu 20.04 ya no reciben actualizaciones de seguridad estándar de su distribución: úsalos solo para versiones de Odoo que no admiten un sistema más reciente.

Es importante usar un sistema compatible para evitar problemas durante la instalación. Si necesitas ayuda con la instalación o configuración, no dudes en contactarnos a través de **info@adlacademy.com.do** o **WhatsApp: +1(809)-418-4467**.
