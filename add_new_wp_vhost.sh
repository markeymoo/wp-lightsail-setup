#!/bin/bash -e
clear

echo "----- Obtain Parameters -----"
read -p "Domain: " domainname
read -p "DB Host: " dbhost
read -p "DB Admin User: " dbadmin
read -p "DB Admin User Password: " dbadminpw
read -p "New DB Name: " dbname
read -p "New DB User: " dbuser
read -p "New DB User Password: " dbpass

echo "These Are The Values Provided"
echo "Domain: " $domainname
echo "DB Host: " $dbhost
echo "DB Admin User: " $dbadmin
echo "DB Admin User Password: " $dbadminpw
echo "New DB Name: " $dbname
echo "New DB User: " $dbuser
echo "New DB User Password: " $dbpass

read -p "Are These Correct, y/n : " dbconfirm

if [ $dbconfirm != y ]
then
    echo "exiting"
    exit
fi



update_apps() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "--------------------------------"
    echo "----- Updating App Library -----"
    echo "--------------------------------"
    sudo apt update
    FUNCTION_RESULT=$NEXT_VALUE
}

apache2_install() {
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

    FUNCTION_RESULT=$NEXT_VALUE
}

php_install() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "-----  PHP Installation and Setup -----"
    
    if [ $(dpkg-query -s -f='$(Status)' php 2>/dev/null | grep -c "ok installed") -eq 0 ];
    then
        echo "Installing php + mods"
        sudo apt -y install php libapache2-mod-php php-mysql
    else
        echo -e "${GREEN}php is installed!${NC}"
    fi

    FUNCTION_RESULT=$NEXT_VALUE
}

configure_apache_vhost() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"

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
    sudo cat >/etc/apache2/sites-available/$domainname.conf <<EOF
    <VirtualHost *:80>
        ServerName $domainname
        ServerAlias www.$domainname
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/$domainname
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
        <Directory /var/www/$domainname>
            AllowOverride All
        </Directory>
        Protocols h2 http/1.1
    </VirtualHost>
EOF

    echo "----- Apache Enable vhost Site -----"
    sudo a2ensite $domainname

    echo "----- Disable the default apache site -----"
    sudo a2dissite 000-default

    echo "----- Enable the apache mod_rewrite mod to allow wordpress permalink -----"
    sudo a2enmod rewrite

    echo "----- Enable the apache https mod to allow http/2 serving -----"
    sudo a2enmod http2

    echo "----- Disable php7.4 and mpm_prefork apache mod -----"
    sudo a2dismod php7.4
    sudo a2dismod mpm_prefork
    sudo a2enmod mpm_event proxy_fcgi setenvif

    echo "----- Install php-fpm -----"
    if [ $(dpkg-query -s -f='$(Status)' php7.4-fpm 2>/dev/null | grep -c "ok installed") -eq 0 ];
    then
        echo "Installing"
        sudo apt -y install php7.4-fpm
        sudo systemctl start php7.4-fpm
        sudo systemctl enable php7.4-fpm
        sudo a2enconf php7.4-fpm
    else
        echo -e "${GREEN}Already installed!${NC}"
    fi

    echo "----- Verify that the vhost configuration is good -----"
    sudo apache2ctl configtest

    echo "----- Reload the revised apache configurations -----"
    sudo systemctl reload apache2
    echo "----- APACHE2 VHOST SETUP END ------------"
    echo "------------------------------------------"

    FUNCTION_RESULT=$NEXT_VALUE
}

install_latest_wordpress() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
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
    sudo chown www-data:www-data /var/www/$domainname
    sudo find /var/www/$domainname/ -type d -exec chmod 755 {} \;
    sudo find /var/www/$domainname/ -type f -exec chmod 644 {} \;

    echo "----- Obtain new secret values needed by Wordpress to be more secure -----"
    SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

    echo "----- Write salts into vhost wp-config.php -----"
    STRING='put your unique phrase here'
    sudo printf '%s\n' "g/$STRING/d" a "$SALT" . w | ed -s /var/www/$domainname/wp-config.php

    echo "------- DOWNLOAD, READY LATEST WORDPRESS DISTRIBUTION - END -------"
    echo "-------------------------------------------------------------------"
    FUNCTION_RESULT=$NEXT_VALUE
}

configure_wordpress_database() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"

    echo "Creating user, database within MariaDB and setting permissions"

    sudo mysql -u $dbadmin -p'$dbadminpw' -h $dbhost <<EOF
    CREATE USER '$dbuser'@'$dbhost' IDENTIFIED BY '$dbpass';
    CREATE DATABASE $dbname DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
    GRANT ALL PRIVILEGES ON $dbname.* TO '$dbuser'@'$dbhost';
    FLUSH PRIVILEGES;
EOF

    echo "Modify wp-admin.php to include correct database settings : wp-config.php"
    STRING='database_name_here'
    sudo sed -i -e "s/$STRING/$dbname/g" /var/www/$domainname/wp-config.php
    STRING='username_here'
    sudo sed -i -e "s/$STRING/$dbuser/g" /var/www/$domainname/wp-config.php
    STRING='password_here'
    sudo sed -i -e "s/$STRING/$dbpass/g" /var/www/$domainname/wp-config.php
    STRING='localhost'
    sudo sed -i -e "s/$STRING/$dbhost/g" /var/www/$domainname/wp-config.php

    if ! grep -Fxq "define( 'FS_METHOD', 'direct' );" /var/www/$domainname/wp-config.php
    then
        sudo echo "define( 'FS_METHOD', 'direct' );" >> /var/www/$domainname/wp-config.php
    fi
    
    FUNCTION_RESULT=$NEXT_VALUE
}

install_certbot() {
    local ENTRY_VALUE="$1"
    local NEXT_VALUE="$2"
    echo "-----  Install Certbot -----"
    read -p "Enter webmaster email: " webmaster
    
    if [ $(dpkg-query -s -f='$(Status)' certbot 2>/dev/null | grep -c "ok installed") -eq 0 ];
    then
        echo "Installing php + mods"
        sudo apt -y install certbot python3-certbot-apache
    else
        echo -e "${GREEN}certbot is installed!${NC}"
    fi

    certbot --apache --non-interactive --agree-tos --redirect -m $webmaster -d $domainname -d www.$domainname

    FUNCTION_RESULT=$NEXT_VALUE
}

# If state.mc file does not exist create and load with initial value of 0
STATE_FILE="/home/ubuntu/state.mc"
ENTRY_STATE=1
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
EXIT_FLAG=0
until [ $EXIT_FLAG = 1 ]; do
    echo "EXIT_FLAG: $EXIT_FLAG"
    if [ $EXIT_FLAG = 0 ];
    then
        echo "----- STATE RUN -----"
        echo "ENTRY_STATE: $ENTRY_STATE"
        NEW_STATE="$ENTRY_STATE"
        case $ENTRY_STATE in
            1)
                NEW_STATE=2
                ;;
            2)
                update_apps 2 3
                NEW_STATE=$FUNCTION_RESULT
                ;;
            3)
                apache2_install 3 4
                NEW_STATE=$FUNCTION_RESULT
                ;;
            4)
                php_install 4 5
                NEW_STATE=$FUNCTION_RESULT
                ;;
            5)
                configure_apache_vhost 5 6
                NEW_STATE=$FUNCTION_RESULT
                ;;
            6)
                install_latest_wordpress 6 7
                NEW_STATE=$FUNCTION_RESULT
                ;;
            7)
                configure_wordpress_database 7 8
                NEW_STATE=$FUNCTION_RESULT
                ;;
            8)
                install_certbot 8 9
                NEW_STATE=$FUNCTION_RESULT
                ;;
            *)
                NEW_STATE=99
                ;;
        esac

        echo "NEW_STATE: $NEW_STATE"
        read -p "Press enter to continue" dummy

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