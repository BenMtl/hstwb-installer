# ~/.profile: executed by Bourne-compatible login shells.
setfont Topazc.psf.gz
setterm -background blue -foreground white --bold on --store
# clear the screen
clear
export PS1="\W \$"

# expand filesystem
if [ -f ~/expand_filesystem.sh -a -f ~/.expand_filesystem ]; then
  rm -f ~/.expand_filesystem
  ~/expand_filesystem.sh
fi

# repair usb medias
if [ -f ~/repair_usb_medias.sh -a -f ~/.repair_usb_medias ]; then
  rm -f ~/.repair_usb_medias
  ~/repair_usb_medias.sh
fi

# find hstwb self install
if [ -f ~/find_hstwb_self_install.sh -a -f ~/.find_hstwb_self_install ]; then
  rm -f ~/.find_hstwb_self_install
	~/find_hstwb_self_install.sh
fi

# install kickstart
if [ -f ~/install_kickstart.sh ]; then
	~/install_kickstart.sh -i -id=/media/hstwb-self-install/kickstart -kd=/root/amibian/amiga_files/kickstarts
fi

# select emulator
if [ -f ~/select_emulator.sh -a -f ~/.select_emulator ]; then
  rm -f ~/.select_emulator
	~/select_emulator.sh
fi

# build install entries
if [ -f ~/build_install_entries.sh -a -f ~/.build_install_entries ]; then
  rm -f ~/.build_install_entries
	~/build_install_entries.sh
fi

# start emulator, if not logged in via ssh
mytty=`tty`
if [ "$mytty" == "/dev/tty1" ]; then
  bootstartingemulator
fi

# clear the screen
clear

# show the menu
menu

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n
