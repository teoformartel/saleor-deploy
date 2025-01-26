# deploy-saleor.sh
# Author:       Aaron K. Nall   http://github.com/thewhiterabbit
#!/bin/sh
set -e

HEADER_TPL="\n\n\n       "
INFO_TPL="\n-->"

# Get the actual user that logged in
USER_NAME="$(who am i | awk '{print $1}')"
if [[ "$USER_NAME" != "root" ]]; then
    USER_DIR="/home/$USER_NAME"
else
    USER_DIR="/root"
fi

SALEOR_DIR="$USER_DIR/saleor"

cd $USER_DIR

# Get the operating system
IN=$(uname -a)
arrIN=(${IN// / })
IN2=${arrIN[3]}
arrIN2=(${IN2//-/ })
OS=${arrIN2[1]}

# Parse options
while [ -n "$1" ]; do # while loop starts
	case "$1" in
        -name)
            DEPLOYED_NAME="$2"
            shift
            ;;

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

        -email)
            EMAIL="$2"
            shift
            ;;

        -email-pw)
            EMAIL_PW="$2"
            shift
            ;;

        -email-host)
            EMAIL_HOST="$2"
            shift
            ;;

        -repo)
            REPO="$2"
            shift
            ;;

        -v)
            vOPT="true"
            VERSION="$2"
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

# Echo the detected operating system
echo "$INFO_TPL OS $OS detected"
sleep 3

# Select/run Operating System specific commands
echo "$INFO_TPL Installing core dependencies..."
sleep 1
case "$OS" in
    Ubuntu)
        sudo apt update
        sudo apt install -y build-essential python3-dev python3-pip python3-cffi python3-venv gcc pipx pip
        sudo apt install -y libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libffi-dev shared-mime-info libhdf5-dev
        sudo apt install -y nodejs npm postgresql postgresql-contrib nginx
        sudo pipx install poetry
        # sudo npm install npm@latest
        sudo pipx ensurepath
        # sudo pip install --upgrade pip
        
        wait
        ;;
    #
    *)
        # Unsupported distribution detected, exit
        echo "Unsupported Linux distribution detected."
        echo "Exiting"
        exit 1
        ;;
esac

echo "$INFO_TPL Finished installing core dependencies"
sleep 2
echo "$INFO_TPL Setting up security feature details..."
sleep 2

# Generate a secret key file
# Does the key file directory exiet?
if [ ! -d "/etc/saleor" ]; then
    sudo mkdir /etc/saleor
else
    # Does the key file exist?
    if [ -f "/etc/saleor/api_sk" ]; then
        # Yes, remove it.
        sudo rm /etc/saleor/api_sk
    fi
fi
# Create randomized 2049 byte key file
sudo echo $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 2048| head -n 1) > /etc/saleor/api_sk

# Set variables for the password, obfuscation string, and user/database names
# Generate an 8 byte obfuscation string for the database name & username 
OBFSTR=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8| head -n 1)
# Append the database name for Saleor with the obfuscation string
PGSQLDBNAME="saleor_db_$OBFSTR"
# Append the database username for Saleor with the obfuscation string
PGSQLUSER="saleor_dbu_$OBFSTR"
# Generate a 128 byte password for the Saleor database user
# TODO: Add special characters once we know which ones won't crash the python script
PGSQLUSERPASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 128 | head -n 1)

echo "$INFO_TPL Finished setting up security feature details"
sleep 2
echo "$INFO_TPL Creating database..."
sleep 2

# Create a superuser for Saleor
# Create the role in the database and assign the generated password
sudo -i -u postgres psql -c "CREATE ROLE $PGSQLUSER PASSWORD '$PGSQLUSERPASS' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN;"
# Create the database for Saleor
sudo -i -u postgres psql -c "CREATE DATABASE $PGSQLDBNAME;"
# TODO - Secure the postgers user account

echo "$INFO_TPL Finished creating database" 
sleep 2

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
sudo -u $USER_NAME git clone https://github.com/saleor/saleor.git
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

echo "$INFO_TPL Github cloning complete"
sleep 2

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

# Create the saleor service file
sudo sed "s/{USER_NAME}/$USER_NAME/ s|{USER_DIR}|$USER_DIR|g" $USER_DIR/saleor-deploy/resources/saleor/template.service > /etc/systemd/system/saleor.service
wait
# Create the saleor server block
sudo sed "s|{USER_DIR}|$USER_DIR|g /{host}/$HOST/g s|{static}|$STATIC_URL|g s|{media}|$MEDIA_URL|g" $USER_DIR/saleor-deploy/resources/saleor/server_block > /etc/nginx/sites-available/saleor
wait
# Create the production uwsgi initialization file
sudo sed "s|{USER_DIR}|$USER_DIR|g s/{USER_NAME}/$USER_NAME/" $USER_DIR/saleor-deploy/resources/saleor/template.uwsgi > $SALEOR_DIR/saleor/wsgi/prod.ini
# Create the host directory in /var/www/
sudo mkdir /var/www/$HOST
wait
# Create the media directory
sudo mkdir /var/www/$HOST$MEDIA_URL
wait
# Static directory will be moved into /var/www/$HOST/ after collectstatic is performed

echo "$INFO_TPL Creating production deployment packages for Saleor API & GraphQL..."

# Setup the environment variables for Saleor API
# Build the database URL
DB_URL="postgres://$PGSQLUSER:$PGSQLUSERPASS@$PGDBHOST:$DBPORT/$PGSQLDBNAME"
EMAIL_URL="smtp://$EMAIL:$EMAIL_PW@$EMAIL_HOST:/?ssl=True"
API_HOST=$(hostname -i);
# Build the chosts and ahosts lists
C_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
A_HOSTS="$HOST,$API_HOST,localhost,127.0.0.1"
QL_ORIGINS="$HOST,$API_HOST,localhost,127.0.0.1"
# Write the production .env file from template.env
sudo sed "s|{dburl}|$DB_URL|
          s|{emailurl}|$EMAIL_URL|
          s/{chosts}/$C_HOSTS/
          s/{ahosts}/$A_HOSTS/
          s/{host}/$HOST/g
          s|{static}|$STATIC_URL|g
          s|{media}|$MEDIA_URL|g
          s/{adminemail}/$ADMIN_EMAIL/
          s/{gqlorigins}/$QL_ORIGINS/" $USER_DIR/saleor-deploy/resources/saleor/template.env > $USER_DIR/saleor/.env
wait

# Copy the uwsgi_params file to /saleor/uwsgi_params
sudo cp $USER_DIR/saleor-deploy/resources/saleor/uwsgi_params $USER_DIR/saleor/uwsgi_params

pip install setuptools wheel

poetry install
# Activate the virtual environment
source $(poetry env info --path)/bin/activate
wait
# Install uwsgi
pip3 install uwsgi
wait
# Set any secret Environment Variables
export ADMIN_PASS="$ADMIN_PASS"
# Install the project
npm install
wait
# Run an audit to fix any vulnerabilities
sudo -u $USER_NAME npm audit fix
wait
# Establish the database
python3 manage.py migrate
wait
python3 manage.py createsuperuser
wait
python3 manage.py collectstatic
wait
# Build the schema
npm run build-schema
wait
# Build the emails
npm run build-emails
wait
# Exit the virtual environment
deactivate
# Set ownership of the app directory to $USER_NAME:www-data
sudo chown -R $USER_NAME:www-data $USER_DIR/saleor
wait
sudo mv $USER_DIR/saleor/static /var/www/${HOST}${STATIC_URL}
sudo chown -R www-data:www-data /var/www/$HOST

echo "$INFO_TPL Finished creating production deployment packages for Saleor API & GraphQL"

# Enable the Saleor service
sudo systemctl enable saleor.service
sudo systemctl daemon-reload
sudo systemctl start saleor.service

echo "$INFO_TPL I think we're done here."
echo "$INFO_TPL Test the installation."