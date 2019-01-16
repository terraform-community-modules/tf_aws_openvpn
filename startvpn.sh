#!/bin/bash

#IMPORTANT: you will need to have the permissions locked down tight in this file for this to be secure.

#Create the folder ~/openvpn_config
#Copy startvpn.sh to this path.

#Make the file owned by root and group root:
#sudo chown root.root <my script>

#Now set the SetUID bit, make it executable for all and writable only by root:

#sudo chmod 4755 <my script>

#edit the sudoers file to conatin these line, which will allow the command to be run without a password.
#user ALL=(ALL:ALL) NOPASSWD:cp -rfa * /etc/openvpn/.
#user ALL=(ALL:ALL) NOPASSWD:service openvpn restart

#Keep in mind if this script will allow any input or editing of files, this will also be done as root.

#https://bbs.archlinux.org/viewtopic.php?id=126126
#https://askubuntu.com/questions/229800/how-to-auto-start-openvpn-client-on-ubuntu-cli
#https://serverfault.com/questions/480909/how-can-i-run-openvpn-as-daemon-sending-a-config-file


cd ~/openvpn_config/
sudo /bin/cp -rfa * /etc/openvpn/.
sudo /usr/sbin/service openvpn restart
