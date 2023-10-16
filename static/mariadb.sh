#!/bin/bash

# T&M Hansson IT AB © - 2023, https://www.hanssonit.se/

true
SCRIPT_NAME="MariaDB"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

################################ MariaDB ####################################

# Installation of the MariaDB database 10.11
# add the repository for the latest version of MariaDB
# Add repository for MariaDB 10.11
echo "Adding repository for MariaDB 10.11..."
# Import the MariaDB repository key
echo "Importing the MariaDB repository key..."
sudo apt install -y apt-transport-https curl
sudo mkdir -p /etc/apt/keyrings
sudo curl -o /etc/apt/keyrings/mariadb-keyring.pgp 'https://mariadb.org/mariadb_release_signing_key.pgp'
echo "MariaDB repository key imported successfully!"
# Create a sources list file for MariaDB
echo "Creating a sources list file for MariaDB..."
sudo tee /etc/apt/sources.list.d/mariadb.sources << EOL
# MariaDB 10.11 repository list - created $(date -u +"%Y-%m-%d %H:%M UTC")
# https://mariadb.org/download/
X-Repolib-Name: MariaDB
Types: deb
# deb.mariadb.org is a dynamic mirror if your preferred mirror goes offline. See https://mariadb.org/mirrorbits/ for details.
# URIs: https://deb.mariadb.org/10.11/ubuntu
URIs: https://atl.mirrors.knownhost.com/mariadb/repo/10.11/ubuntu
Suites: jammy
Components: main main/debug
Signed-By: /etc/apt/keyrings/mariadb-keyring.pgp
EOL
echo "Sources list file created for MariaDB!"

apt-get update -q4 & spinner_loading
install_if_not mariadb-server

# Create root password in MariaDB safe mode
# Step 1: Stop MariaDB
if sudo systemctl is-active --quiet mariadb; then
    sudo systemctl stop mariadb
    if [ $? -eq 0 ]; then
        echo "MariaDB stopped successfully"
    else
        echo "Error: Failed to stop MariaDB"
        exit 1
    fi
else
    echo "MariaDB is already stopped"
fi

# Step 2: Start MariaDB in Safe Mode
sudo mysqld_safe --skip-grant-tables --skip-networking &
if [ $? -eq 0 ]; then
    echo "MariaDB started in safe mode successfully"
else
    echo "Error: Failed to start MariaDB in safe mode"
    exit 1
fi

# Step 3: Connect to MariaDB
mysql -u root <<END
USE mysql;
UPDATE user SET password = PASSWORD('$MDBROOT_PASS') WHERE User = 'root';
FLUSH PRIVILEGES;
END
if [ $? -eq 0 ]; then
    echo "MariaDB root password updated successfully"
else
    echo "Error: Failed to update MariaDB root password"
    exit 1
fi

# Step 4: Exit MariaDB
if [ "$?" -eq 0 ]; then
    exit
else
    echo "Error: Failed to exit MariaDB"
    exit 1
fi

# Step 5: Stop MariaDB Safe Mode
sudo pkill -f mysqld_safe
if [ $? -eq 0 ]; then
    echo "MariaDB safe mode stopped successfully"
else
    echo "Error: Failed to stop MariaDB safe mode"
    exit 1
fi

# Step 6: Start MariaDB
sudo systemctl start mariadb
if [ $? -eq 0 ]; then
    echo "MariaDB started successfully"
else
    echo "Error: Failed to start MariaDB"
    exit 1
fi

# Create DB
sudo mysql -u root <<END
CREATE USER '$MDB_USER'@'localhost' IDENTIFIED BY '$MDB_PASS';
CREATE DATABASE $MDB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
GRANT ALL PRIVILEGES ON $MDB_NAME.* TO '$MDB_USER'@'localhost';
FLUSH PRIVILEGES;
END

# Check if the database exists
if mysqlshow -u root -p --count $MDB_NAME >/dev/null 2>&1; then
    echo "Database $MDB_NAME exists"
else
    echo "Database $MDB_NAME does not exist"
fi

print_text_in_color "$ICyan" "MariaDB password for user $MDB_USER in database $MDB_NAME: $MDB_PASS"
systemctl restart mariadb.service

# Stop MariaDB service
sudo service mariadb stop

# Create SCRIPTS directory if it doesn't exist
mkdir -p "$SCRIPTS"

# Download the MariaDB configuration file
curl -o "$MDB_FILE_LOCAL" "$MDB_FILE_URL"

# Check if the MariaDB configuration file was downloaded successfully
if [ $? -ne 0 ]; then
    MESSAGE="ERROR: Failed to download MariaDB configuration file from $MDB_FILE_URL."
    msg_box "Error" "$MESSAGE"
    exit 1
fi

# Define the path to the MariaDB configuration file
MDB_FILE="$MDB_FILE_LOCAL"

# Check if the MariaDB configuration file exists
if [ ! -f "$MDB_FILE" ]; then
    MESSAGE="ERROR: MariaDB configuration file $MDB_FILE not found. Please download it from https://example.com/my.cnf.config."
    msg_box "Error" "$MESSAGE"
    sleep 30
else
    # Stop MariaDB service
    sudo service mariadb stop

    # Backup existing my.cnf file
    sudo mv /etc/mysql/my.cnf /etc/mysql/my.cnf.bak

    # Create a new my.cnf file with the provided configuration
    sudo tee /etc/mysql/my.cnf >/dev/null <<EOL
    $(cat "$MDB_FILE")
EOL

    # Check if there were any errors
    if [ $? -eq 0 ]; then
        echo "Configuration added to my.cnf successfully"
    else
        MESSAGE="ERROR WITH MariaDB my.cnf import. Please download the configuration file from https://example.com/my.cnf.config and try again."
        msg_box "Error" "$MESSAGE"
        sleep 30
    fi
fi

########################################## END MariaDB ##########################################