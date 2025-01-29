# deploy-saleor.sh
# Author:       Aaron K. Nall   http://github.com/thewhiterabbit
#!/bin/sh
set -e

INFO_TPL="▉▉▉=>"

# Get the actual user that logged in
USER_NAME="$(who am i | awk '{print $1}')"
if [[ "$USER_NAME" != "root" ]]; then
    USER_DIR="/home/$USER_NAME"
else
    USER_DIR="/root"
fi
SALEOR_DIR="$USER_DIR/saleor"

cd $USER_DIR

# Get the operating system and exit on unsupported distribution (supported Ubuntu only)
IN=$(uname -a)
arrIN=(${IN// / })
IN2=${arrIN[3]}
arrIN2=(${IN2//-/ })
OS=${arrIN2[1]}
if [ ! "$OS" = "Ubuntu"]; then
    echo "$INFO_TPL Unsupported Linux distribution detected."
    echo "$INFO_TPL Exiting"
    exit 1
fi

# Parse options
while [ -n "$1" ]; do # while loop starts
	case "$1" in
        -host)
            HOST="$2"
            shift
            ;;
        -dashboard-uri)
            APP_MOUNT_URI="$2"
            shift
            ;;
        -static-url)
            STATIC_URL="$2"
            shift
            ;;
        -media-url)
            MEDIA_URL="$2"
            shift
            ;;
        -admin-email)
            ADMIN_EMAIL="$2"
            shift
            ;;
        -admin-pw)
            ADMIN_PASS="$2"
            shift
            ;;
        -dbhost)
            PGDBHOST="$2"
            shift
            ;;
        -dbport)
            DBPORT="$2"
            shift
            ;;
        -graphql-port)
            GQL_PORT="$2"
            shift
            ;;
        -graphql-uri)
            APIURI="$2"
            shift
            ;;
        -email-url)
            EMAIL_URL="$2"
            shift
            ;;
        *)
            echo "Option $1 is invalid."
            echo "Exiting"
            exit 1
            ;;
	esac
	shift
done

echo "$INFO_TPL Installing core dependencies..."

sudo apt update
sudo apt install -y curl gnupg
sudo apt install -y build-essential openssl python3-dev python3-pip python3-cffi python3-venv gcc pip
sudo apt install -y libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libffi-dev shared-mime-info libhdf5-dev
sudo apt install -y postgresql postgresql-contrib nginx
sudo apt install -y python3-poetry
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs

echo "$INFO_TPL Finished installing core dependencies"
echo "$INFO_TPL Setting up security feature details..."

# Generate a secret key file, remove before if exists
if [ ! -d "/etc/saleor" ]; then
    sudo mkdir /etc/saleor
else
    if [ -f "/etc/saleor/api_sk" ]; then
        sudo rm /etc/saleor/api_sk
    fi
fi
sudo openssl rand -base64 3072 | tr -dc 'a-zA-Z0-9' | head -c 2049 | sudo tee /etc/saleor/api_sk > /dev/null 
# Set variables for the password, obfuscation string, and user/database names
# Generate an 8 byte obfuscation string for the database name & username 
#OBFSTR=$(openssl rand -base64 6 | tr -dc 'a-z0-9' | head -c 8)
# Append the database name for Saleor with the obfuscation string
#PGSQLDBNAME="saleor_db_$OBFSTR"
# Append the database username for Saleor with the obfuscation string
#PGSQLUSER="saleor_dbu_$OBFSTR"
# Generate a 128 byte password for the Saleor database user
# TODO: Add special characters once we know which ones won't crash the python script
#PGSQLUSERPASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 128 | head -n 1)

echo "$INFO_TPL Finished setting up security feature details"
echo "$INFO_TPL Creating database..."

PGSQLDBNAME="saleor"
PGSQLUSER="saleor"
PGSQLUSERPASS="saleor"
# Create the role in the database if not exists
sudo -i -u postgres psql -c "DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$PGSQLUSER') THEN
      CREATE ROLE $PGSQLUSER PASSWORD '$PGSQLUSERPASS' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN;
   END IF;
END
\$\$;"
# Create the database for Saleor if not exists
sudo -i -u postgres psql -c "SELECT 'CREATE DATABASE $PGSQLDBNAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$PGSQLDBNAME')\gexec"

echo "$INFO_TPL Finished creating database" 

# Collect input from the user to assign required installation parameters
echo "$INFO_TPL Please provide details for your Saleor API instillation..."
# Get the API host domain
while [ "$HOST" = "" ]
do
    echo -n "Enter the API host domain:"
    read HOST
done
# Get an optional custom Static URL
if [ "$STATIC_URL" = "" ]; then
    echo -n "Enter a custom Static Files URI (optional):"
    read STATIC_URL
    if [ "$STATIC_URL" != "" ]; then
        STATIC_URL="/$STATIC_URL/"
    fi
else
    STATIC_URL="/$STATIC_URL/"
fi
# Get an optional custom media URL
if [ "$MEDIA_URL" = "" ]; then
        echo -n "Enter a custom Media Files URI (optional):"
        read MEDIA_URL
        if [ "$MEDIA_URL" != "" ]; then
                MEDIA_URL="/$MEDIA_URL/"
        fi
else
        MEDIA_URL="/$MEDIA_URL/"
fi
# Get the Admin's email address
while [ "$ADMIN_EMAIL" = "" ]
do
        echo ""
        echo -n "Enter the Dashboard admin's email:"
        read ADMIN_EMAIL
done
# Get the Admin's desired password
while [ "$ADMIN_PASS" = "" ]
do
        echo ""
        echo -n "Enter the Dashboard admin's desired password:"
        read -s ADMIN_PASS
done

# Set default and optional parameters
if [ "$PGDBHOST" = "" ]; then
    PGDBHOST="localhost"
fi
#
if [ "$DBPORT" = "" ]; then
    DBPORT="5432"
fi
#
if [[ "$GQL_PORT" = "" ]]; then
    GQL_PORT="9000"
fi
#
if [[ "$API_PORT" = "" ]]; then
    API_PORT="8000"
fi
#
if [ "$APIURI" = "" ]; then
    APIURI="graphql" 
fi
#
if [ "$vOPT" = "true" ]; then
    if [ "$VERSION" = "" ]; then
        VERSION="main"
    fi
else
    VERSION="main"
fi
#
if [ "$STATIC_URL" = "" ]; then
    STATIC_URL="/static/" 
fi
#
if [ "$MEDIA_URL" = "" ]; then
    MEDIA_URL="/media/" 
fi

# Open the selected ports for the API and APP
# Open GraphQL port
sudo ufw allow $GQL_PORT
# Open API port
sudo ufw allow $API_PORT

# Clone the Saleor Git repository
cd $USER_DIR
# Remove existing Saleor
if [ -d "$SALEOR_DIR" ]; then
    sudo rm -R $SALEOR_DIR
    wait
    echo "$INFO_TPL Existing Saleor removed"
fi
#
echo "$INFO_TPL Cloning Saleor from github..."
sudo -u $USER_NAME git clone --depth 10 https://github.com/saleor/saleor.git
wait
# Make sure we're in the project root directory for Saleor
cd $SALEOR_DIR
wait
# Was the -v (version) option used?
if [ "vOPT" = "true" ] || [ "$VERSION" != "" ]; then
    # Checkout the specified version
    sudo -u $USER_NAME git checkout main
    wait
fi
#
if [ ! -d "$USER_DIR/run" ]; then
    sudo -u $USER_NAME mkdir $USER_DIR/run
else
    if [ -f "$USER_DIR/run/saleor.sock" ]; then
        sudo rm $USER_DIR/run/saleor.sock
    fi
fi

echo "$INFO_TPL Github cloning complete" || sleep 2

# Remove existing service file
if [ -f "/etc/systemd/system/saleor.service" ]; then
    sudo rm /etc/systemd/system/saleor.service
fi
# Remove existing server block
if [ -f "/etc/nginx/sites-available/saleor" ]; then
	sudo rm /etc/nginx/sites-available/saleor
fi
# Remove existing www folder
if [ -d "/var/www/$HOST" ]; then
    sudo rm -R /var/www/$HOST
    wait
fi
echo "sed \"s|{USER_NAME}|$USER_NAME|g; s|{PYTHON_ENV_PATH}|$PYTHON_ENV_PATH|g\" $USER_DIR/saleor-deploy/resources/saleor/template.service > /etc/systemd/system/saleor.service"
# Create the saleor service file
sudo bash -c "sed \"s|{USER_NAME}|$USER_NAME|g; s|{USER_DIR}|$USER_DIR|g\" $USER_DIR/saleor-deploy/resources/saleor/template.service > /etc/systemd/system/saleor.service"

wait
# Create the saleor server block
sudo bash -c "sed \"s|{USER_DIR}|$USER_DIR|g; s|{host}|$HOST|g; s|{static}|$STATIC_URL|g; s|{media}|$MEDIA_URL|g\" $USER_DIR/saleor-deploy/resources/saleor/server_block > /etc/nginx/sites-available/saleor"
wait
# Create the host directory in /var/www/
sudo mkdir /var/www/$HOST
wait
# Create the media directory
sudo mkdir /var/www/$HOST$MEDIA_URL
wait
# Static directory will be moved into /var/www/$HOST/ after collectstatic is performed

echo "$INFO_TPL Creating production deployment packages for Saleor API & GraphQL..."

# Setup the environment variables for Saleor API
DB_URL="postgres://$PGSQLUSER:$PGSQLUSERPASS@$PGDBHOST:$DBPORT/$PGSQLDBNAME"
API_HOST=$(hostname -i);
C_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
A_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
QL_ORIGINS="$HOST,$API_HOST,localhost,127.0.0.1"

poetry install
wait
PYTHON_ENV_PATH=$(poetry env info --path)

# Activate the virtual environment
source $PYTHON_ENV_PATH/bin/activate
wait

# Setup enviroment
poetry run npm install
wait
poetry run pip install setuptools wheel uwsgi
wait
poetry run python manage.py migrate
wait
poetry run python manage.py createsuperuser
wait
poetry run python manage.py collectstatic
wait
poetry run python manage.py get_graphql_schema > saleor/graphql/schema.graphql
wait

SECRET_KEY=$(poetry run python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
RSA_PRIVATE_KEY=$(openssl genrsa 3072)
sudo bash -c "sed \"s|{DB_URL}|$DB_URL|g;
          s|{EMAIL_URL}|$EMAIL_URL|g;
          s/{C_HOSTS}/$C_HOSTS/g;
          s/{A_HOSTS}/$A_HOSTS/g;
          s/{HOST}/$HOST/g;
          s|{STATIC_URL}|$STATIC_URL|g;
          s|{MEDIA_URL}|$MEDIA_URL|g;
          s/{ADMIN_EMAIL}/$ADMIN_EMAIL/g;
          s|{SECRET_KEY}|$SECRET_KEY|g;
          s/{gqlorigins}/$QL_ORIGINS/g\" $USER_DIR/saleor-deploy/resources/saleor/template.env > $USER_DIR/saleor/.env"
sudo bash -c "printf \"RSA_PRIVATE_KEY=\\"%s\\"\n\" \"$RSA_PRIVATE_KEY\" >> $USER_DIR/saleor/.env"
wait
# Create the production uwsgi initialization file
sudo bash -c "sed \"s|{USER_DIR}|$USER_DIR|g; s/{USER_NAME}/$USER_NAME/g; s|{PYTHON_ENV_PATH}|$PYTHON_ENV_PATH|g\" $USER_DIR/saleor-deploy/resources/saleor/template.uwsgi > $SALEOR_DIR/saleor/wsgi/prod.ini"
# Copy the uwsgi_params file to /saleor/uwsgi_params
sudo cp $USER_DIR/saleor-deploy/resources/saleor/uwsgi_params $SALEOR_DIR/uwsgi_params
if [ ! -d "/etc/uwsgi" ]; then
	sudo bash -c "mkdir /etc/uwsgi"
fi
if [ -d "/etc/uwsgi/vassals" ]; then
	sudo bash -c "rm -R /etc/uwsgi/vassals"
fi
sudo bash -c "mkdir /etc/uwsgi/vassals"
sudo bash -c "ln -s $SALEOR_DIR/saleor/wsgi/prod.ini /etc/uwsgi/vassals" 

deactivate

# Move static files
sudo bash -c "mv $USER_DIR/saleor/static /var/www/${HOST}${STATIC_URL}"

# Set ownership
sudo bash -c "chown -R $USER_NAME:www-data $USER_DIR/saleor"
sudo bash -c "chown -R www-data:www-data /var/www/$HOST"
wait

echo "$INFO_TPL Finished creating production deployment packages for Saleor API & GraphQL"

# Enable service
sudo bash -c "systemctl enable saleor.service"
sudo bash -c "systemctl daemon-reload"
sudo bash -c "systemctl start saleor.service"


# Finishing
echo "$INFO_TPL I think we're done here."
echo "$INFO_TPL Test the installation."