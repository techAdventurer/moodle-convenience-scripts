#!/bin/bash

# Install, upgrade or restore moodle on a VPS

set -e

MOODLE_DOMAIN="lms.example.com"
MOODLE_SOURCE="/var/www/moodle/moodle_source"
MOODLE_DATA="/var/www/moodle/moodle_data"
MOODLE_GIT_VERSION="311"

MOODLE_DB_NAME="moodle"
MOODLE_DB_USER="moodle"
MOODLE_DB_USER_PASSWORD="moodle"

TEMPORARY_DIRECTORY="$HOME/MDL-SCRIPT-TMP"
TEMPORARY_RESTORE_DIRECTORY="$HOME/MDL_TO_RESTORE"

SCRIPT_ACTION=$1
if [ $SCRIPT_ACTION == "install" ]; then
    IS_INSTALL="1"
    IS_UPGRADE="0"
    IS_RESTORE="0"
elif [ $SCRIPT_ACTION == "upgrade" ]; then
    IS_INSTALL="0"
    IS_UPGRADE="1"
    IS_RESTORE="0"
elif [ $SCRIPT_ACTION == "restore" ]; then
    IS_INSTALL="0"
    IS_UPGRADE="0"
    IS_RESTORE="1"

    if $(test -f $2 ) && $(test "$2" != ""); then
        echo "File $2 found!"
        mkdir $TEMPORARY_RESTORE_DIRECTORY
        tar -xf $2 -C $TEMPORARY_RESTORE_DIRECTORY --strip-components 1  # cd into MDL_TO_RESTORE then untars files into it
    else
        echo "Could not find the backup file '$2'"
        exit 1
    fi
else
    echo "
    Action is missing or incorrect.
    Please enter the action next to the script name (e.g. ./moodle-script upgrade).
    Authorized actions:
        - install : Install moodle from scratch (you'll have to manually execute certbot --apache)
        - upgrade : Upgrade moodle on a pre-configured system
        - restore : Restore moodle from a backup file (add the path to the backup file as next argument)
    "
    exit 1
fi

sudo apt-get update
sudo apt-get upgrade --yes

if [ $IS_INSTALL == "1" ] || [ $IS_RESTORE == "1" ]; then

    sudo apt-get install --yes \
        git

    sudo apt-get install --yes \
        apache2

    sudo apt-get install --yes \
        php \
        php-curl \
        php-mbstring \
        php-tokenizer \
        php-xmlrpc \
        php-soap \
        php-zip \
        php-gd \
        php-xml \
        php-intl \
        php-json \
        php-mysql

    sudo apt-get install --yes \
        mariadb-server

    sudo apt-get install --yes \
        snapd

    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot

    # Deactivating the default apache website
    sudo a2dissite 000-default.conf

    # Stopping the apache2 service
    sudo systemctl stop apache2

    # Creating a config file and activating the corresponding website
    echo "
        <VirtualHost *:80>
            ServerAdmin webmaster@$MOODLE_DOMAIN
            ServerName $MOODLE_DOMAIN
            DocumentRoot $MOODLE_SOURCE
            ErrorLog \${APACHE_LOG_DIR}/error.log
            CustomLog \${APACHE_LOG_DIR}/access.log combined
        </VirtualHost>
    " | sudo tee /etc/apache2/sites-available/$MOODLE_DOMAIN.conf > /dev/null
    
    sudo a2ensite $MOODLE_DOMAIN.conf

    # Creating a new database and a new user with appropriate permissions
    sudo mysql -e "CREATE DATABASE $MOODLE_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON $MOODLE_DB_NAME.* 
                    TO '$MOODLE_DB_USER'@'localhost' IDENTIFIED BY '$MOODLE_DB_USER_PASSWORD';"

    # Creating directories and transfer ownership to www-data
    sudo mkdir --parents $MOODLE_SOURCE $MOODLE_DATA
    sudo chown -R www-data:www-data $MOODLE_SOURCE
    sudo chown -R www-data:www-data $MOODLE_DATA
fi

# If restoring a previous moodle install from a backup, restore the moodle database from the backup dump
if [ $IS_RESTORE == "1" ]; then
    echo "Restoring database $MOODLE_DB_NAME from the backup file. This might take a little while..."
    sudo mysql --database=$MOODLE_DB_NAME < $TEMPORARY_RESTORE_DIRECTORY/moodle_dump.sql
fi

# Create a temporary directory to hold source code
mkdir $TEMPORARY_DIRECTORY
cd $TEMPORARY_DIRECTORY

# Downloading moodle source
git clone --depth 1 --branch MOODLE_$MOODLE_GIT_VERSION\_STABLE git://git.moodle.org/moodle.git moodle

# Downloading trema theme source
git clone --depth 1 --branch master git://github.com/trema-tech/moodle-theme_trema.git trema

# Downloading webanalytics plugin source
git clone --depth 1 --branch master git://github.com/catalyst/moodle-tool_webanalytics.git webanalytics


# Save useful config.php file and removing all previous source files
if [ $IS_UPGRADE == "1" ]; then
    sudo cp $MOODLE_SOURCE/config.php $TEMPORARY_DIRECTORY/config.php
    sudo rm -r $MOODLE_SOURCE/*
fi

# Stopping apache2 while moving files (in case it wasn't stopped already)
sudo systemctl stop apache2

# Moving source files in appropriate directories
if [ $IS_UPGRADE == "1" ] || [ $IS_INSTALL == "1" ]; then
    sudo mv $TEMPORARY_DIRECTORY/moodle/* $MOODLE_SOURCE/
    sudo chown -R www-data:www-data $MOODLE_SOURCE

    sudo mv $TEMPORARY_DIRECTORY/trema $MOODLE_SOURCE/theme/trema
    sudo chown -R www-data:www-data $MOODLE_SOURCE/theme/trema

    sudo mv $TEMPORARY_DIRECTORY/webanalytics $MOODLE_SOURCE/admin/tool/webanalytics
    sudo chown -R www-data:www-data $MOODLE_SOURCE/admin/tool/webanalytics
elif [ $IS_RESTORE ]; then
    sudo mv $TEMPORARY_RESTORE_DIRECTORY/moodle_source/* $MOODLE_SOURCE/
    sudo chown -R www-data:www-data $MOODLE_SOURCE
fi

# Replace or add config.php config file
if [ $IS_UPGRADE == "1" ]; then
    sudo mv $TEMPORARY_DIRECTORY/config.php $MOODLE_SOURCE/config.php
    sudo chown www-data:www-data $MOODLE_SOURCE/config.php
elif [ $IS_RESTORE == "1" ]; then
    sudo mv $TEMPORARY_RESTORE_DIRECTORY/config.php $MOODLE_SOURCE/config.php
    sudo chown www-data:www-data $MOODLE_SOURCE/config.php
fi

# Remove temporary directory
sudo rm -r $TEMPORARY_DIRECTORY

# If restore, remove MDL_TO_RESTORE temporary directory
if [ $IS_RESTORE == "1" ]; then
    rm -rf $TEMPORARY_RESTORE_DIRECTORY
fi

# Restart apache2
sudo systemctl restart apache2

# Things left to do
echo "
======= This is not over ! =======
- Configure www-data cron ( * * * * * /usr/bin/php  $MOODLE_SOURCE/admin/cli/cron.php)
- Change php.ini values (i.e. max_upload_size)
- Run certbot --apache if this is a new installation
- Configure backups
- Secure Moodle (Firewall, Password policies, ...)4
"

# End
echo "Script end."
