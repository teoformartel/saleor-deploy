# deploy-saleor.sh
# Author:       Aaron K. Nall   http://github.com/thewhiterabbit
#!/bin/sh
set -e

# Define helper's constants
INFO_TPL="▉▉▉=>"

# Get the actual user that logged in
USER_NAME="$(who am i | awk '{print $1}')"
USER_DIR="/root"
if [[ "$USER_NAME" != "root" ]]; then
    USER_DIR="/home/$USER_NAME"
fi
SALEOR_DIR="$USER_DIR/saleor"

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

# Define defaults
PGDBHOST="localhost"
DBPORT="5432"
GQL_PORT="9000"
API_PORT="8000"
APIURI="graphql" 
VERSION="main"
STATIC_URL="/static/" 
MEDIA_URL="/media/" 

# Parse options
while [ -n "$1" ]; do
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
            echo "Option $1 is invalid. Exiting..."
            exit 1
            ;;
	esac
	shift
done

# Exit if required options are missing
if [[ "$HOST" == "" || "$ADMIN_EMAIL" == "" || "$ADMIN_PASS" == "" ]]; then
   echo "$file"
fi

echo "$INFO_TPL Removing existing configurations and data..."
if [ -f "/etc/systemd/system/saleor.service" ]; then
    sudo rm /etc/systemd/system/saleor.service
fi
if [ -f "/etc/nginx/sites-available/saleor" ]; then
	sudo rm /etc/nginx/sites-available/saleor
fi
if [ -d "/var/www/$HOST" ]; then
    sudo rm -R /var/www/$HOST
fi
if [ -f "$USER_DIR/run/saleor.sock" ]; then
    sudo rm $USER_DIR/run/saleor.sock
fi
if [ -f "/etc/saleor/api_sk" ]; then
    sudo rm /etc/saleor/api_sk
fi
if [ -d "$SALEOR_DIR" ]; then
    sudo rm -R $SALEOR_DIR
fi
if [ -d "/etc/uwsgi/vassals" ]; then
	sudo bash -c "rm -R /etc/uwsgi/vassals"
fi

echo "$INFO_TPL Making important folders than not exist"
if [ ! -d "/etc/uwsgi" ]; then
	sudo bash -c "mkdir /etc/uwsgi"
fi
if [ ! -d "/etc/saleor" ]; then
	sudo mkdir /etc/saleor
fi
if [ ! -d "$USER_DIR/run" ]; then
	sudo -u $USER_NAME mkdir $USER_DIR/run
fi
if [ ! -d "/etc/uwsgi/vassals" ]; then
	sudo bash -c "mkdir /etc/uwsgi/vassals"
fi




echo "$INFO_TPL Installing core dependencies..."
sudo apt update
sudo apt install -y curl gnupg
sudo apt install -y build-essential openssl python3-dev python3-pip python3-cffi python3-venv gcc pip
sudo apt install -y libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libffi-dev shared-mime-info libhdf5-dev
sudo apt install -y postgresql postgresql-contrib nginx
sudo apt install -y python3-poetry
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs

echo "$INFO_TPL Setting up security feature details..."
sudo openssl rand -base64 3072 | tr -dc 'a-zA-Z0-9' | head -c 2049 | sudo tee /etc/saleor/api_sk > /dev/null # Generate a secret key file

echo "$INFO_TPL Creating database and role if not exist..."
PGSQLDBNAME="saleor"
PGSQLUSER="saleor"
PGSQLUSERPASS="saleor"
sudo -i -u postgres psql -c "DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$PGSQLUSER') THEN
      CREATE ROLE $PGSQLUSER PASSWORD '$PGSQLUSERPASS' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN;
   END IF;
END
\$\$;"
sudo -i -u postgres psql -c "SELECT 'CREATE DATABASE $PGSQLDBNAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$PGSQLDBNAME')\gexec"

# Clone the Saleor Git repository
echo "$INFO_TPL Cloning Saleor from github..."
cd $USER_DIR
sudo -u $USER_NAME git clone --depth 10 https://github.com/saleor/saleor.git
cd $SALEOR_DIR
sudo -u $USER_NAME git checkout $VERSION

echo "$INFO_TPL Creating production deployment packages..."
poetry install
wait
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

PYTHON_ENV_PATH=$(poetry env info --path)
# Setup the environment variables for Saleor API
DB_URL="postgres://$PGSQLUSER:$PGSQLUSERPASS@$PGDBHOST:$DBPORT/$PGSQLDBNAME"
API_HOST=$(hostname -i);
C_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
A_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
QL_ORIGINS="$HOST,$API_HOST,localhost,127.0.0.1"
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
          s/{gqlorigins}/$QL_ORIGINS/g\" $USER_DIR/saleor-deploy/res/saleor/.env > $USER_DIR/saleor/.env"
sudo bash -c "printf \"RSA_PRIVATE_KEY=\\"%s\\"\n\" \"$RSA_PRIVATE_KEY\" >> $USER_DIR/saleor/.env"
wait

# Create the production uwsgi initialization file and copy uwsgi_params file to saleor dir
sudo bash -c "sed \"s|{USER_DIR}|$USER_DIR|g; s/{USER_NAME}/$USER_NAME/g; s|{PYTHON_ENV_PATH}|$PYTHON_ENV_PATH|g\" $USER_DIR/saleor-deploy/res/saleor/uwsgi.ini > $SALEOR_DIR/saleor/wsgi/prod.ini"
sudo cp $USER_DIR/saleor-deploy/res/saleor/uwsgi_params $SALEOR_DIR/uwsgi_params
sudo bash -c "ln -s $SALEOR_DIR/saleor/wsgi/prod.ini /etc/uwsgi/vassals" 
# Create the saleor service file
sudo bash -c "sed \"s|{USER_NAME}|$USER_NAME|g; s|{PYTHON_ENV_PATH}|$PYTHON_ENV_PATH|g; s|{USER_DIR}|$USER_DIR|g\" $USER_DIR/saleor-deploy/res/saleor/service > /etc/systemd/system/saleor.service"
# Create the nginx server block
sudo bash -c "sed \"s|{USER_DIR}|$USER_DIR|g; s|{HOST}|$HOST|g; s|{STATIC_URL}|$STATIC_URL|g; s|{MEDIA_URL}|$MEDIA_URL|g\" $USER_DIR/saleor-deploy/res/saleor/nginx > /etc/nginx/sites-available/saleor"
# Create the host directory in /var/www/
sudo mkdir /var/www/$HOST
# Create the media directory
sudo mkdir /var/www/$HOST$MEDIA_URL

# Move static files
sudo bash -c "mv $USER_DIR/saleor/static /var/www/${HOST}${STATIC_URL}"

# Set ownerships
sudo bash -c "chown -R $USER_NAME:www-data $USER_DIR/saleor"
sudo bash -c "chown -R www-data:www-data /var/www/$HOST"
wait

# Open the selected ports for the API and APP
sudo ufw allow $GQL_PORT
sudo ufw allow $API_PORT

echo "$INFO_TPL Finished creating production deployment packages for Saleor API & GraphQL"

source $USER_DIR/saleor-deploy/deploy-dashboard.sh

# Enable service
sudo bash -c "systemctl enable saleor.service"
sudo bash -c "systemctl daemon-reload"
sudo bash -c "systemctl start saleor.service"

# Finishing
echo "$INFO_TPL I think we're done here."
echo "$INFO_TPL Test the installation."