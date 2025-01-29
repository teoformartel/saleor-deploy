#########################################################################################
echo ""
echo "Creating production deployment packages for Saleor Dashboard..."
echo ""
#########################################################################################



#########################################################################################
# Collect input from the user to assign required installation parameters
#########################################################################################
echo "Please provide details for your Saleor Dashboard installation..."
echo ""
# Get the Dashboard & GraphQL host domain
while [ "$SAME_HOST" = "" ]
do
        echo -n "Are you hosting the Dashboard on the same host domain as the API (yes|no)?"
        read SAME_HOST
done
# Get the API host IP or domain
if [ "$SAME_HOST" = "no" ]; then
        while [ "$APP_HOST" = "" ]
        do
                echo ""
                echo -n "Enter the Dashboard host domain:"
                read APP_HOST
        done
fi
# Get the APP Mount (Dashboard) URI
while [ "$APP_MOUNT_URI" = "" ]
do
        echo ""
        echo -n "Enter the APP Mount (Dashboard) URI:"
        read APP_MOUNT_URI
done
#########################################################################################



#########################################################################################
# Clone the git and setup the environment variables for Saleor API & Dashboard install
#########################################################################################
# Make sure we're in the user's home directory
cd $USER_DIR
# Clone the Saleor Dashboard Git repository
if [ -d "$USER_DIR/saleor-dashboard" ]; then
    sudo rm -R $USER_DIR/saleor-dashboard
fi
sudo -u $USER_NAME git clone https://github.com/saleor/saleor-dashboard.git
wait
# Build the API URL
API_URL="https://$HOST/$APIURI/"
# Write the production .env file from template.env
if [ "$SAME_HOST" = "no" ]; then
        sudo sed "s|{api_url}|$API_URL|
                s|{app_mount_uri}|$APP_MOUNT_URI|
                s|{app_host}|$APP_HOST/$APP_MOUNT_URI|" $USER_DIR/saleor-deploy/resources/saleor-dashboard/template.env > $USER_DIR/saleor-dashboard/.env
        wait
else
        sudo sed "s|{api_url}|$API_URL|
                s|{app_mount_uri}|$APP_MOUNT_URI|
                s|{app_host}|$HOST/$APP_MOUNT_URI|" $USER_DIR/saleor-deploy/resources/saleor-dashboard/template.env > $USER_DIR/saleor-dashboard/.env
        wait
fi
#########################################################################################



#########################################################################################
# Build Saleor Dashboard for production
#########################################################################################
# Make sure we're in the project root directory
cd saleor-dashboard
sudo -u $USER_NAME git checkout main
# Install dependancies
sudo -u $USER_NAME npm i
wait
sudo -u $USER_NAME npm run build
wait
#########################################################################################


#########################################################################################
# Setup the nginx block and move the static build files
#########################################################################################
echo "Moving static files for the Dashboard..."
echo ""
if [ "$SAME_HOST" = "no" ]; then
        # Move static files for the Dashboard
        sudo mv $USER_DIR/saleor-dashboard/build/$APP_MOUNT_URI /var/www/$APP_HOST/
        # Make an empry variable
        DASHBOARD_LOCATION=""
        # Clean the saleor server block
        sudo sed -i "s#{dl}#$DASHBOARD_LOCATION#" /etc/nginx/sites-available/saleor
        # Create the saleor-dashboard server block
        sudo sed "s|{USER_DIR}|$USER_DIR|g
                  s/{app_mount_uri}/$APP_MOUNT_URI/g
                  s/{host}/$APP_HOST/g" $USER_DIR/saleor-deploy/resources/saleor-dashboard/server_block > /etc/nginx/sites-available/saleor-dashboard
        wait
        sudo chown -R www-data /var/www/$APP_HOST
        echo "Enabling server block and Restarting nginx..."
        sudo ln -s /etc/nginx/sites-available/saleor-dashboard /etc/nginx/sites-enabled/
else
        # Move static files for the Dashboard
        sudo mv $USER_DIR/saleor-dashboard/build/$APP_MOUNT_URI /var/www/$HOST/
        # Populate the DASHBOARD_LOCATION variable
        DASHBOARD_LOCATION=$(<$USER_DIR/saleor-deploy/resources/saleor-dashboard/dashboard-location)
        # Modify the new server block
        sudo sed -i "s#{dl}#$DASHBOARD_LOCATION#" /etc/nginx/sites-available/saleor
        wait
        # Modify the new server block again
        sudo sed -i "s|{USER_DIR}|$USER_DIR|g
                     s|{app_mount_uri}|$APP_MOUNT_URI|g
                     s|{host}|$HOST|g" /etc/nginx/sites-available/saleor
        wait
        echo "Enabling server block and Restarting nginx..."
        if [ ! -f "/etc/nginx/sites-enabled/saleor" ]; then
                sudo ln -s /etc/nginx/sites-available/saleor /etc/nginx/sites-enabled/
        fi
fi
sudo systemctl restart nginx
#########################################################################################
