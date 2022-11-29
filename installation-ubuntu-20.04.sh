#!/bin/sh
# This script will install a new BookStack instance on a fresh Ubuntu 20.04 server.
# This script is experimental and does not ensure any security.

# Fetch domain to use from first provided parameter,
# Otherwise request the user to input their domain
DOMAIN=$1
if [ -z "$1" ]
then
echo ""
printf "Enter the domain you want to host BookStack and press [ENTER]\nExamples: 106.14.179.121 or docs.my-site.com\n"
read -r DOMAIN
fi

# Ensure a domain was provided otherwise display
# an error message and stop the script
if [ -z "$DOMAIN" ]
then
  >&2 echo 'ERROR: A domain must be provided to run this script'
  exit 1
fi

# Get the current machine IP address
CURRENT_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

# Install core system packages
export DEBIAN_FRONTEND=noninteractive
add-apt-repository universe
apt update
apt install -y git unzip apache2 php7.4 curl php7.4-fpm php7.4-curl php7.4-mbstring php7.4-ldap \
php7.4-tidy php7.4-xml php7.4-zip php7.4-gd php7.4-mysql mysql-server-8.0 libapache2-mod-php7.4 nginx

# Set up database
DB_PASS="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)"
mysql -u root --execute="DROP DATABASE bookstack;"
mysql -u root --execute="DROP USER 'bookstack'@'localhost';"
mysql -u root --execute="CREATE DATABASE bookstack;"
mysql -u root --execute="CREATE USER 'bookstack'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASS';"
mysql -u root --execute="GRANT ALL ON bookstack.* TO 'bookstack'@'localhost';FLUSH PRIVILEGES;"

# Download BookStack
cd /var/www || exit
git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch bookstack
BOOKSTACK_DIR="/var/www/bookstack"
cd $BOOKSTACK_DIR || exit

# Install composer
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo 'ERROR: Invalid composer installer checksum'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --quiet
rm composer-setup.php

# Move composer to global installation
mv composer.phar /usr/local/bin/composer

# Install BookStack composer dependencies
export COMPOSER_ALLOW_SUPERUSER=1
php /usr/local/bin/composer install --no-dev --no-plugins

# Copy and update BookStack environment variables
cp .env.example .env
sed -i.bak "s@APP_URL=.*\$@APP_URL=http://$DOMAIN/bookstack@" .env
sed -i.bak 's/DB_DATABASE=.*$/DB_DATABASE=bookstack/' .env
sed -i.bak 's/DB_USERNAME=.*$/DB_USERNAME=bookstack/' .env
sed -i.bak "s/DB_PASSWORD=.*\$/DB_PASSWORD=$DB_PASS/" .env

# Generate the application key
php artisan key:generate --no-interaction --force
# Migrate the databases
php artisan migrate --no-interaction --force

# Set file and folder permissions
chown www-data:www-data -R bootstrap/cache public/uploads storage && chmod -R 755 bootstrap/cache public/uploads storage

# Set up nginx
rm /etc/nginx/sites-available/default
cat >/etc/nginx/sites-available/default <<EOL
server {
  listen 80;
  listen [::]:80;

  root /var/www/html;
  index index.html index.htm index.nginx-debian.html;
  server_name _;

  location / {
    try_files $uri $uri/ =404;
  }

  location /bookstack/ {
    proxy_pass http://localhost:8083/;
    proxy_redirect off;
  }

}
EOL

cat >/etc/nginx/sites-available/bookstack <<EOL
server {
  listen 8083;
  listen [::]:8083;

  server_name localhost;

  root /var/www/bookstack/public;
  index index.php index.html;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php7.4-fpm.sock;
  }
}
EOL

ln -s /etc/nginx/sites-available/bookstack /etc/nginx/sites-enabled/

# Restart apache to load new config
nginx -t
systemctl restart nginx
systemctl status nginx

echo ""
echo "Setup Finished, Your BookStack instance should now be installed."
echo "You can login with the email 'admin@admin.com' and password of 'password'"
echo "MySQL was installed without a root password, It is recommended that you set a root MySQL password."
echo ""
echo "You can access ubuntu apache html at: http://$DOMAIN"
echo "You can access your BookStack instance at: http://$DOMAIN/bookstack"
