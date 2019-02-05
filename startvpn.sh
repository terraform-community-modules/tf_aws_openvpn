#!/bin/bash

#IMPORTANT: you will need to have the permissions locked down tight in this file for this to be secure.
#Make the file owned by root and group root:

#sudo chown root:root <my script>

#Now set the SetUID bit, make it executable for all and writable only by root:

#sudo chmod 4755 <my script>
#sudo chmod +s <my script>


#edit the sudoers file to conatin this line, which will allow these vpn autologin files to be copied to /etc without a password.

# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/ca.crt /etc/openvpn/.
# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/client.crt /etc/openvpn/.
# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/client.key /etc/openvpn/.
# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/openvpn.conf /etc/openvpn/.
# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/ta.key /etc/openvpn/.
# deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/yourserver.txt /etc/openvpn/.

# /home/deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload
# /home/deadlineuser ALL=(ALL:ALL) NOPASSWD:/usr/sbin/service openvpn restart


#instead, you may want to allow a group of users to be able to do this.  EDIT THIS DIDN'T WORK BECAUSE WE CANT USE RELATIVE PATHS

# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/ca.crt /etc/openvpn/.
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/client.crt /etc/openvpn/.
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/client.key /etc/openvpn/.
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/openvpn.conf /etc/openvpn/.
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/ta.key /etc/openvpn/.
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/yourserver.txt /etc/openvpn/.

# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload
# %deadlineanduser ALL=(ALL:ALL) NOPASSWD:/usr/sbin/service openvpn restart

#Keep in mind if this script will allow any input or editing of files, this will also be done as root.
#https://bbs.archlinux.org/viewtopic.php?id=126126
#https://askubuntu.com/questions/229800/how-to-auto-start-openvpn-client-on-ubuntu-cli
#https://serverfault.com/questions/480909/how-can-i-run-openvpn-as-daemon-sending-a-config-file

#echo openvpnas | sudo /usr/local/sbin/openvpn --config ./client.ovpn

set -x
mkdir -p /home/deadlineuser/openvpn_config/
cd /home/deadlineuser/openvpn_config/

echo '--- copying openvpn config files ---'
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/ca.crt /etc/openvpn/.
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/client.crt /etc/openvpn/.
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/client.key /etc/openvpn/.
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/openvpn.conf /etc/openvpn/.
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/ta.key /etc/openvpn/.
sudo /bin/cp -rfa /home/deadlineuser/openvpn_config/yourserver.txt /etc/openvpn/.

echo 'finished copy.' 
echo 'restarting service'
sudo systemctl daemon-reload
sudo /usr/sbin/service openvpn restart
echo '--- openvpn restarted ---'
