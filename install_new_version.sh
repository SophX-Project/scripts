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

# Set up database
DB_PASS="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)"
mysql -u root --execute="DROP DATABASE bookstack;"
mysql -u root --execute="DROP USER 'bookstack'@'localhost';"
mysql -u root --execute="CREATE DATABASE bookstack;"
mysql -u root --execute="CREATE USER 'bookstack'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASS';"
mysql -u root --execute="GRANT ALL ON bookstack.* TO 'bookstack'@'localhost';FLUSH PRIVILEGES;"

# Download BookStack
git clone https://github.com/SophX-Project/php.git
cd php || exit

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

# install bookstack to /var/www
rm -r /var/www/bookstack || rm /var/www/bookstack
BOOKSTACK_DIR=/var/www/bookstack
cd .. && mv php $BOOKSTACK_DIR
chown $USER:$USER -R $BOOKSTACK_DIR && chmod -R 775 $BOOKSTACK_DIR

# Set file and folder permissions
chown www-data:www-data -R $BOOKSTACK_DIR/bootstrap/cache $BOOKSTACK_DIR/public/uploads $BOOKSTACK_DIR/storage && chmod -R 755 $BOOKSTACK_DIR/bootstrap/cache $BOOKSTACK_DIR/public/uploads $BOOKSTACK_DIR/storage

# Restart apache to load new config
service apache2 stop
nginx -t
systemctl restart nginx

echo ""
echo "Setup Finished, Your BookStack instance should now be installed."
echo "You can login with the email 'admin@admin.com' and password of 'password'"
echo "MySQL was installed without a root password, It is recommended that you set a root MySQL password."
echo ""
echo "You can access ubuntu apache html at: http://$DOMAIN"
echo "You can access your BookStack instance at: http://$DOMAIN/bookstack/login"
