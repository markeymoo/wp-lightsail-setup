#!/bin/bash -e
clear


# Provide user with the pre-requisites for running this script
function prerequisites {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "-----------------------------------------"
    echo "----------- PRE-REQUISITES --------------"
    echo "-----------------------------------------"
    echo " Installed MariaDB"
    echo " --- Follow These Instructions: https://www.digitalocean.com/community/tutorials/how-to-install-mariadb-on-ubuntu-20-04"
    echo " Granted All Permissions to your MariaDB admin user (not root)"
    echo " --- e.g.  if admin user is myadmin and password is mypassword"
    echo "  GRANT ALL ON *.* TO 'myadmin'@'localhost' IDENTIFIED BY 'mypassword' WITH GRANT OPTION;"
    read -p "Press enter to continue"
    return "$NEXT_VALUE"
}

function update_apps {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "--------------------------------"
    echo "----- Updating App Library -----"
    echo "--------------------------------"
    sudo apt update
    return "$NEXT_VALUE"
}

function apache2_install {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "------------------------------------------"
    echo "-----  Apache Installation and Setup -----"
    if [ $(dpkg-query -s -f='$(Status)' apache2 2>/dev/null | grep -c "ok installed") -eq 0 ];
    then
        echo "Installing"
        sudo apt -y install apache2
        ufw allow in "Apache"
    else
        echo -e "${GREEN}Already installed!${NC}"
    fi

    return "$NEXT_VALUE"
}


# If state.mc file does not exist create and load with initial value of 0
STATE_FILE="/home/ubuntu/state.mc"
ENTRY_STATE="0"
if [ ! -f $STATE_FILE ];
then
    echo " Initialising state file : $STATE_FILE"
    touch $STATE_FILE 
    echo $ENTRY_STATE > $STATE_FILE
else 
    ENTRY_STATE=`cat $STATE_FILE`
fi
echo " State File Content: $ENTRY_STATE"


# Run the state machine, exit if the state entry is equal to existing state
# or 99 which represents completion.
EXIT_FLAG="0"
until [ $EXIT_FLAG = 1 ]; do
    echo "EXIT_FLAG: $EXIT_FLAG"
    if [ $EXIT_FLAG = 0 ];
    then
        echo "----- STATE RUN -----"
        echo "ENTRY_STATE: $ENTRY_STATE"
        NEW_STATE="$ENTRY_STATE"
        case $ENTRY_STATE in
            "0")
                prerequisites "0" "1"
                NEW_STATE=$?
                ;;
            "1")
                update_apps "1" "2"
                NEW_STATE=$?
                ;;
            "2")
                apache2_install "2" "3"
                NEW_STATE=$?
                ;;
            *)
                NEW_STATE="99"
                ;;
        esac

        echo "NEW_STATE: $NEW_STATE"
        if [ "$NEW_STATE" = "$ENTRY_STATE" ] || [ "$NEW_STATE" = 99 ]
        then
            echo $NEW_STATE > $STATE_FILE
            echo "EXITING LOOP - NEW_STATE eq ENTRY_STATE"
            EXIT_FLAG="1"
        else
            ENTRY_STATE=$NEW_STATE
            echo $ENTRY_STATE > $STATE_FILE
            echo "ENTRY_STATE: $ENTRY_STATE"
        fi
    fi

done

exit





echo "-----  PHP Installation and Setup -----"
if [ $(dpkg-query -s -f='$(Status)' php 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
    echo "Installing php + mods"
    sudo apt -y install php libapache2-mod-php php-mysql
else
    echo -e "${GREEN}php is installed!${NC}"
fi



echo "----- Get Site Information -----"
read -p "Domain Name (without www.): " domainname

echo "----- Create Apache2 vhost if needed and set permissions -----"
if [ ! -d "/var/www/$domainname" ];
then
    echo "Apache dir for vhost does not exist... creating it"
    sudo mkdir /var/www/$domainname
fi

echo " Set vhost directory permissions"
sudo chown -R $USER:$USER /var/www/$domainname

echo "----- Create a new vhost config file, replacing the domains existing one if it exists -----"
if [ -f /etc/apache2/sites-available/$domainname.conf ];
then
    echo "Removing file /etc/apache2/sites-available/$domainname.conf"
    sudo rm -f /etc/apache2/sites-available/$domainname.conf
fi

echo "----- Create vhost file for the new domain -----"
sudo sh -c "cat >/etc/apache2/sites-available/$domainname.conf <<EOF
<VirtualHost *:80>
    ServerName $domainname
    ServerAlias www.$domainname
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/$domainname
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    <Directory /var/www/$domainname >
        AllowOverride All
    </Directory>
</VirtualHost>
EOF"

echo "----- Apache Enable vhost Site -----"
sudo a2ensite $domainname

echo "----- Disable the default apache site -----"
sudo a2dissite 000-default

echo "----- Enable the apache mod_rewrite mod to allow wordpress permalink -----"
sudo a2enmod rewrite

echo "----- Verify that the vhost configuration is good -----"
sudo apache2ctl configtest

echo "----- Reload the revised apache configurations -----"
sudo systemctl reload apache2
echo "----- APACHE2 VHOST SETUP END ------------"
echo "------------------------------------------"

read -p "Continue " dummy

echo "---------------------------------------------------------------------"
echo "------- DOWNLOAD, READY LATEST WORDPRESS DISTRIBUTION - START -------"
echo "        -----------------------------------------------------"
cd /tmp
curl -O https://wordpress.org/latest.tar.gz

echo "----- Delete /tmp/wordpress if already exists"
if [ -d "/tmp/wordpress" ];
then
    echo "Deleting /tmp/wordpress"
    sudo rm -rf /tmp/wordpress
fi

echo "----- Unzip latest.tar.gz -----"
tar xzvf latest.tar.gz
touch /tmp/wordpress/.htaccess
cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
mkdir /tmp/wordpress/wp-content/upgrade

echo "----- Copy wordpress files into the vhost directory -----"
sudo cp -a /tmp/wordpress/. /var/www/$domainname

echo "----- Change wordpress vhost document directory permissions -----"
sudo chown -R www-data:www-data /var/www/$domainname
sudo find /var/www/$domainname/ -type d -exec chmod 750 {} \;
sudo find /var/www/$domainname/ -type f -exec chmod 640 {} \;

echo "----- Obtain new secret values needed by Wordpress to be more secure -----"
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

echo "----- Write salts into vhost wp-config.php -----"
STRING='put your unique phrase here'
sudo printf '%s\n' "g/$STRING/d" a "$SALT" . w | ed -s wp-config.php

echo "------- DOWNLOAD, READY LATEST WORDPRESS DISTRIBUTION - END -------"
echo "-------------------------------------------------------------------"


echo "----------------------------------------------------------"
echo "------- Configure MariaDB and Wordpress Connection -------"
echo "        ------------------------------------------"
echo "Get information for new database (assume it to be on localhost)"
read -p "Database Name: " dbname
read -p "Database User: " dbuser
read -p "Database Password: " dbpass
echo
echo "Your inputs were;"
echo "Database Name = " $dbname
echo "Databse User = " $dbuser
echo "Database Password = " $dbpass
read -p "Are These Correct, y/n : " dbconfirm
if [ $dbconfirm != y ]
then
    echo "exiting"
    exit
fi

echo "Creating user, database within MariaDB and setting permissions"
sudo mysql -u root -p <<EOF
CREATE USER '$dbuser'@'localhost' IDENTIFIED BY '$dbpass';
CREATE DATABASE $dbname DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;;
GRANT ALL PRIVILEGES ON $dbname.* TO '$dbuser'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Modify wp-admin.php to include correct database settings"


echo
