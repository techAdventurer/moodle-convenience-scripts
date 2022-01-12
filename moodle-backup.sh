#!/bin/bash

###################################
##    Moodle backup script       ##
###################################

# Logging should be enabled by redirecting output to a log file.

MOODLE_DOMAIN="lms.example.com"
MOODLE_SOURCE="/var/www/moodle/moodle_source"
MOODLE_DATA="/var/www/moodle/moodle_data"

MOODLE_DB_NAME="moodle"
MOODLE_DB_USER="moodle"
MOODLE_DB_USER_PASSWORD="moodle"

BACKUP_DIRECTORY="$HOME/MDL_BCKP-$(date --rfc-3339='date')"
MOODLE_BACKUP_DROP_OFF="/home/user"

MAINTENANCE_WARNING_TIME="0"  # Minutes

APACHE_CONF_PATH="/etc/apache2/sites-available"
PHP_INI_FILE="/etc/php/7.4/apache2/php.ini"


echo -e "\n$(date --rfc-3339="seconds")\tStarting backup script for \"$MOODLE_DOMAIN\"."

echo -e "$(date --rfc-3339="seconds")\tEnabling maintenance mode in $MAINTENANCE_WARNING_TIME minutes"
sudo -u www-data /usr/bin/php $MOODLE_SOURCE/admin/cli/maintenance.php --enablelater=$MAINTENANCE_WARNING_TIME

echo -e "$(date --rfc-3339="seconds")\tNow waiting for maintenance mode to activate. Waiting $MAINTENANCE_WARNING_TIME + 2 m."
sleep $(echo $MAINTENANCE_WARNING_TIME)m
# sleep 2m
echo -e "$(date --rfc-3339="seconds")\tMaintenance mode should now be active."

if $(test -d $BACKUP_DIRECTORY)
then
	echo -e "$(date --rfc-3339="seconds")\tTemporary backup directory already exists. Deleting its contents to make room for the new files."
	rm -r $BACKUP_DIRECTORY/*
else
	echo -e "$(date --rfc-3339="seconds")\tTemporary backup directory NOT found at $BACKUP_DIRECTORY - Creating it."
	mkdir $BACKUP_DIRECTORY
fi

echo -e "$(date --rfc-3339="seconds")\tCreating manifest file with script settings."
echo -e "
Archive creation date: $(date --rfc-3339="seconds")
Settings:
- MOODLE_DOMAIN: $MOODLE_DOMAIN
- MOODLE_SOURCE: $MOODLE_SOURCE
- MOODLE_DATA: $MOODLE_DATA
- APACHE_CONF_PATH: $APACHE_CONF_PATH
- PHP_INI_FILE: $PHP_INI_FILE
Backup created by an automated script.
" | tee $BACKUP_DIRECTORY/README.md

echo -e "$(date --rfc-3339="seconds")\tDumping $MOODLE_DB_NAME database."
mysqldump -u $MOODLE_DB_USER --password=$MOODLE_DB_USER_PASSWORD -C -Q -e --create-options --single-transaction $MOODLE_DB_NAME > $BACKUP_DIRECTORY/moodle_dump.sql

echo -e "$(date --rfc-3339="seconds")\tCopying $MOODLE_SOURCE/config.php"
cp -r $MOODLE_SOURCE/config.php $BACKUP_DIRECTORY/config.php

echo -e "$(date --rfc-3339="seconds")\tCopying $MOODLE_SOURCE"
cp -r $MOODLE_SOURCE $BACKUP_DIRECTORY/moodle_source

echo -e "$(date --rfc-3339="seconds")\tCopying $MOODLE_DATA"
cp -r $MOODLE_DATA $BACKUP_DIRECTORY/moodle_data

echo -e "$(date --rfc-3339="seconds")\tCopying $APACHE_CONF_PATH"
cp -r $APACHE_CONF_PATH $BACKUP_DIRECTORY/apache_conf

echo -e "$(date --rfc-3339="seconds")\tCopying $PHP_INI_FILE"
cp -r $PHP_INI_FILE $BACKUP_DIRECTORY/php.ini

echo -e "$(date --rfc-3339="seconds")\tArchiving and compressing files."
cd $BACKUP_DIRECTORY/../
tar -cz -f MDL_BCKP-$(date --rfc-3339='date').tar.gz MDL_BCKP-$(date --rfc-3339='date')

echo -e "$(date --rfc-3339="seconds")\tNew archive's hash:"
sha256sum MDL_BCKP-$(date --rfc-3339='date').tar.gz

echo -e "$(date --rfc-3339="seconds")\tMoving the backup file to desired folder for pickup."
mv $BACKUP_DIRECTORY.tar.gz $MOODLE_BACKUP_DROP_OFF/

echo -e "$(date --rfc-3339="seconds")\tRemoving $BACKUP_DIRECTORY"
rm -r $BACKUP_DIRECTORY

echo -e "$(date --rfc-3339="seconds")\tDisabling maintenance mode for $MOODLE_DOMAIN"
sudo -u www-data /usr/bin/php $MOODLE_SOURCE/admin/cli/maintenance.php --disable

echo -e "$(date --rfc-3339="seconds")\tEnd of script."
