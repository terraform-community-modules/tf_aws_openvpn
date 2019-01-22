#!/bin/bash

#IMPORTANT: you will need to have the permissions locked down tight in this file for this to be secure.
#Make the file owned by root and group root:

#sudo chown root.root <my script>

#Now set the SetUID bit, make it executable for all and writable only by root:

#sudo chmod 4755 <my script>
#sudo chmod +s <my script>


#edit the sudoers file to conatin this line, which will allow the command to be run without a password.
#user ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa * /etc/openvpn/.
#user ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload
#user ALL=(ALL:ALL) NOPASSWD:/usr/sbin/service openvpn restart


#Keep in mind if this script will allow any input or editing of files, this will also be done as root.

#https://bbs.archlinux.org/viewtopic.php?id=126126

#https://askubuntu.com/questions/229800/how-to-auto-start-openvpn-client-on-ubuntu-cli

#https://serverfault.com/questions/480909/how-can-i-run-openvpn-as-daemon-sending-a-config-file

#echo openvpnas | sudo /usr/local/sbin/openvpn --config ./client.ovpn

cd ~/openvpn_config/

echo '--- copying openvpn config files ---'
sudo /bin/cp -rfa * /etc/openvpn/.

echo 'finished copy.' 
echo 'restarting service'
sudo systemctl daemon-reload
sudo /usr/sbin/service openvpn restart
echo '--- openvpn restarted ---'
