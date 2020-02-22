#!/bin/bash

# HstWB Installer Install
# -----------------------
# Author: Henrik Noerfjand Stengaard
# Date: 2020-02-23
#
# A bash script to install HstWB Installer launcher for Amibian.

# disable exit on eror and check if dialog is installed
#set +e
dpkg -s dialog >/dev/null 2>&1

# ask to install dialog, if dialog is not installed
if [ $? -ne 0 ]; then
	echo "Dialog is not installed and is required by HstWB Installer"
	echo ""
	while true; do
    		read -p "Do you want to install Dialog [Y/n]? " confirm
    		case $confirm in
			[Yy]* ) sudo apt-get install dialog; break;;
			[Nn]* ) exit;;
		esac
	done
fi

# fail, if dialog is not installed
dpkg -s dialog >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "ERROR: Dialog is not installed"
	exit 1
fi

# detect amibian version 
if [ -d ~/Amiga/conf/ ]; then
 	AMIBIAN_VERSION=1.5
	AMIGA_HDD_PATH=/home/amibian/Amiga/Hard-drives_HDF
	AMIGA_KICKSTARTS_PATH=/home/amibian/Amiga/kickstarts
elif [ -d ~/amibian/amiberry/conf/ -o -d ~/amibian/chips_uae4arm/conf/ ]; then
	AMIBIAN_VERSION=1.4.1001
	AMIGA_HDD_PATH=/root/amibian/amiga_files/hdd
	AMIGA_KICKSTARTS_PATH=/root/amibian/amiga_files/kickstarts
else
	echo "ERROR: Unsupported Amibian version!"
	exit 1
fi

# show install dialog
dialog --clear --stdout \
--title "Detected Amibian v$AMIBIAN_VERSION" \
--yesno "Is it correct you're using Amibian v$AMIBIAN_VERSION?" 0 0

# exit, if detected amibian version is not correct
if [ $? -ne 0 ]; then
        echo "ERROR: Unsupported Amibian version!"
	exit 1
fi

# show install dialog
dialog --clear --stdout \
--title "Install HstWB Installer" \
--yesno "Do you want to install HstWB Installer launcher?" 0 0

# exit, if no is selected
if [ $? -ne 0 ]; then
  exit
fi

# enable exit on error
set -e

# create backup of profile, if it doesn't exist
if [ -f ~/.profile -a ! -f ~/.profile_backup ]; then
	cp ~/.profile ~/.profile_backup
fi


# create hstwb installer profile, if it doesn't exist
if [ ! -d ~/.hstwb-installer ]; then
	mkdir ~/.hstwb-installer
fi

# get root directories
INSTALL_ROOT="$(dirname "$(readlink -fm "$0")")"
HSTWB_INSTALLER_ROOT="$(dirname "$(dirname "$INSTALL_ROOT")")"

# update or create hstwb installer config.sh
if [ -f ~/.hstwb-installer/config.sh ]; then
	sed -e "s/^\(export HSTWB_INSTALLER_ROOT=\).*/\1\"$(echo "$HSTWB_INSTALLER_ROOT" | sed -e "s/\//\\\\\//g")\"/g" ~/.hstwb-installer/config.sh >~/.hstwb-installer/_config.sh
	mv -f ~/.hstwb-installer/_config.sh ~/.hstwb-installer/config.sh
else
	echo "#!/bin/bash -e" >~/.hstwb-installer/config.sh
	echo "export HSTWB_INSTALLER_ROOT=\"$HSTWB_INSTALLER_ROOT\"" >>~/.hstwb-installer/config.sh
	echo "export HSTWB_INSTALLER_BOOT=\"emulator\"" >>~/.hstwb-installer/config.sh
	echo "export AMIGA_HDD_PATH=\"$AMIGA_HDD_PATH\"" >>~/.hstwb-installer/config.sh
	echo "export AMIGA_KICKSTARTS_PATH=\"$AMIGA_KICKSTARTS_PATH\"" >>~/.hstwb-installer/config.sh
	echo "export AMIBIAN_VERSION=\"$AMIBIAN_VERSION\"" >>~/.hstwb-installer/config.sh
fi
chmod +x ~/.hstwb-installer/config.sh

# create first time use trigger
touch ~/.hstwb-installer/.first-time-use

# install hstwb bin
cp -f "$INSTALL_ROOT/hstwb.sh" "/usr/local/bin/hstwb"
chmod +x "/usr/local/bin/hstwb"

# copy hstwb installer profile
cp "$INSTALL_ROOT/install/boot/.profile.$AMIBIAN_VERSION" ~/.profile

# copy hstwb installer menu files
cp -r "$INSTALL_ROOT/install/menu_files" ~/.hstwb-installer

# install for amibian version
case $AMIBIAN_VERSION in
	1.5)
		# add hstwb to amibian menu
		if [ "$(grep -i "hstwb" ~/.amibian_scripts/cli_menu/menu.txt)" == "" ]; then
			cat ~/.hstwb-installer/menu_files/hstwb >>~/.amibian_scripts/cli_menu/menu.txt
		fi

		# copy amiberry configs
		cp -R "$HSTWB_INSTALLER_ROOT/emulators/amiberry/configs/." ~/Amiga/conf/
		;;
	1.4.1001)
		# add hstwb to amibian menu
		if [ "$(grep -i "cat ~/.hstwb-installer/menu_files/hstwb" /usr/local/bin/menu)" == "" ]; then
			echo "cat ~/.hstwb-installer/menu_files/hstwb" >>/usr/local/bin/menu
		fi

		# copy amiberry configs
		cp -R "$HSTWB_INSTALLER_ROOT/emulators/amiberry/configs/." ~/amibian/amiberry/conf/

		# copy chips uae4arm configs
		cp -R "$HSTWB_INSTALLER_ROOT/emulators/chips_uae4arm/configs/." ~/amibian/chips_uae4arm/conf/
		;;
esac

# disable exit on eror
set +e

# show install dialog
dialog --clear --stdout \
--title "Success" \
--yesno "Successfully installed HstWB Installer. For first time use Amibian, should be rebooted. Do you want to reboot now?" 0 0

# reboot, if yes is selected
if [ $? -eq 0 ]; then
 	reboot
fi
