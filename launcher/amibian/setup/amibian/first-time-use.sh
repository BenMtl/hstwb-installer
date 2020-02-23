#!/bin/bash

# First Time Use
# --------------
# Author: Henrik Noerfjand Stengaard
# Date: 2020-02-23
#
# Bash script for first time use of Amibian.

function delete_triggers()
{
	if [ -f ~/.hstwb-installer/.first-time-use-dialog ]; then
		rm ~/.hstwb-installer/.first-time-use-dialog
	fi
	if [ -f ~/.hstwb-installer/.first-time-use ]; then
		rm ~/.hstwb-installer/.first-time-use
	fi
	if [ -f ~/.hstwb-installer/.expand-filesystem ]; then
		rm ~/.hstwb-installer/.expand-filesystem
	fi
}

# show first time use dialog, if its trigger doesnt exist
if [ ! -f ~/.hstwb-installer/.first-time-use-dialog ]; then
	# show first time use dialog
	dialog --clear --stdout \
	--title "First time use" \
	--yesno "First time use will go through initial steps to get Amibian, emulators and HstWB Installer up and running. Do you want to go through first time use steps?" 0 0

	# exit, if no is selected
	if [ $? -ne 0 ]; then
		delete_triggers
		exit
	fi

	# create first time use dialog trigger
	touch ~/.hstwb-installer/.first-time-use-dialog

fi

# enable exit on error
#set -e

# expand filesystem, if its trigger exists
if [ ! -f ~/.hstwb-installer/.expand-filesystem ]; then
	touch ~/.hstwb-installer/.expand-filesystem
	$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/amibian/expand-filesystem.sh
fi

# find hstwb self install
$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/hstwb-installer/find-hstwb-self-install.sh

# install kickstart rom
$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/emulators/install-kickstart-rom.sh

# change emulator
$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/emulators/change-emulator.sh

# change wifi configuration
$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/amibian/change-wifi-configuration.sh

# install hstwb installer image
$HSTWB_INSTALLER_ROOT/launcher/amibian/setup/hstwb-installer/install-hstwb-installer-image.sh

# delete triggers
delete_triggers
