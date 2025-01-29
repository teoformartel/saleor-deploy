echo "$INFO_TPL Creating production deployment packages for Saleor Dashboard..."

echo "$INFO_TPL Please provide details for your Saleor Dashboard installation..."
# Get the APP Mount (Dashboard) URI
while [ "$APP_MOUNT_URI" = "" ]
do
    echo -n "Enter the APP Mount (Dashboard) URI:"
    read APP_MOUNT_URI
done

if [ -d "$USER_DIR/saleor-dashboard" ]; then
    sudo rm -R $USER_DIR/saleor-dashboard
fi

cd $USER_DIR

DASHBOARD_DIR=$USER_DIR/saleor-dashboard
API_URL="https://$HOST/$APIURI/"
DASHBOARD_LOCATION=$(<$USER_DIR/saleor-deploy/res/saleor-dashboard/location)

echo "$INFO_TPL Clonning the Saleor Dashboard Git repository..."
sudo -u $USER_NAME git clone https://github.com/saleor/saleor-dashboard.git
wait
cd $DASHBOARD_DIR
sudo -u $USER_NAME git checkout main

# Install dependancies
sudo -u $USER_NAME npm i
wait
sudo -u $USER_NAME npm run build
wait

# Write the production .env file from template.env
sudo sed "s|{api_url}|$API_URL|
    s|{app_mount_uri}|$APP_MOUNT_URI|
    s|{app_host}|$HOST/$APP_MOUNT_URI|" $USER_DIR/saleor-deploy/res/saleor-dashboard/.env > $USER_DIR/saleor-dashboard/.env
wait


echo "Moving static files for the Dashboard..."
# Move static files for the Dashboard
sudo mv $USER_DIR/saleor-dashboard/build/$APP_MOUNT_URI /var/www/$HOST/


# Modify the new server block
sudo sed -i "s#{dl}#$DASHBOARD_LOCATION#" /etc/nginx/sites-available/saleor
sudo sed -i "s|{USER_DIR}|$USER_DIR|g
    s|{app_mount_uri}|$APP_MOUNT_URI|g
    s|{host}|$HOST|g" /etc/nginx/sites-available/saleor
wait

echo "Enabling server block and Restarting nginx..."
if [ ! -f "/etc/nginx/sites-enabled/saleor" ]; then
    sudo ln -s /etc/nginx/sites-available/saleor /etc/nginx/sites-enabled/
fi
sudo systemctl restart nginx