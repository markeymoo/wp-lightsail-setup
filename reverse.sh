#!/bin/bash -e
echo "!!!!! THIS SCRIPT REMOVES ALL ACTIONS PERFORMED BY wp-setup.sh !!!!!"
read -p "Domain: " domainname
echo "---------------------------------"
echo "------- Remove MariaDB  -------"
read -p "Database Host: " dbhost
read -p "Database Admin Username: " dbadmin
read -p "Database Admin Password: " dbadminpw
read -p "Database Name: " dbname
read -p "Database User: " dbuser
echo
echo "Your inputs were;"
echo "Database Host = " $dbhost
echo "Database Admin Username: " $dbadmin
echo "Database Admin Password: " $dbadminpw
echo "Database Name = " $dbname
echo "Database User = " $dbuser
read -p "Are These Correct, y/n : " dbconfirm
    
sudo mariadb -u $dbadmin -p$dbadminpw <<EOF
DROP USER '$dbuser'@'$dbhost';
DROP DATABASE $dbname;
EOF

echo "----------------------------------"
echo "------- Remove WordPress  ------"
sudo rm -r /var/www/$domainname
sudo apt remove apache2 php libapache2-mod-php php-mysql php7.4-fpm certbot python3-certbot
sudo rm /home/ubuntu/state.mc