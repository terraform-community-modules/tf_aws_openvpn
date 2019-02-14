#!/bin/bash

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
