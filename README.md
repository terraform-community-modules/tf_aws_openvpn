# tf_aws_openvpn

Terraform module which creates OpenVPN on AWS

# Important steps for permissions and startvpn.sh

*IMPORTANT: you will need to have the permissions locked down tight in on startvpn.sh for this to be secure.
Make the file owned by root and group root:*

    sudo chown root:root startvpn.sh

Now set the SetUID bit, make it executable for all and writable only by root:

    sudo chmod 4755 startvpn.sh
    sudo chmod +s startvpn.sh


edit the sudoers file to conatin this line, which will allow these vpn autologin files to be copied to /etc without a password.

```
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/ca.crt /etc/openvpn/.
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/client.crt /etc/openvpn/.
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/client.key /etc/openvpn/.
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/openvpn.conf /etc/openvpn/.
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/ta.key /etc/openvpn/.
deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa /home/deadlineuser/openvpn_config/yourserver.txt /etc/openvpn/.

/home/deadlineuser ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload
/home/deadlineuser ALL=(ALL:ALL) NOPASSWD:/usr/sbin/service openvpn restart
```

instead, you may want to allow a group of users to be able to do this.  

Edit: THIS DIDN'T ACTUALLY WORK BECAUSE WE CANT USE RELATIVE PATHS IN SUDOERS.
the right way to do it if needed would be to have a non home dir path temp location, with appropraite permissions to read and write by the group on within that path.

```
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/ca.crt /etc/openvpn/.
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/client.crt /etc/openvpn/.
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/client.key /etc/openvpn/.
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/openvpn.conf /etc/openvpn/.
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/ta.key /etc/openvpn/.
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/cp -rfa ~/openvpn_config/yourserver.txt /etc/openvpn/.

%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload
%deadlineanduser ALL=(ALL:ALL) NOPASSWD:/usr/sbin/service openvpn restart
```

Keep in mind if this script will allow any input or editing of files, this will also be done as root.  some more references on related subjects:
https://bbs.archlinux.org/viewtopic.php?id=126126
https://askubuntu.com/questions/229800/how-to-auto-start-openvpn-client-on-ubuntu-cli
https://serverfault.com/questions/480909/how-can-i-run-openvpn-as-daemon-sending-a-config-file

startvpn.sh is currently how open vpn configuration is handled locally.  the files retrieved from remote access server
are needed for auto login to work.

It would be better to replace this with an Ansible playbook instead.


## the tf_aws_openvpn module is creating the following resources:

1. Two Route53 Records
  a. vpn-web.domain.com
  b. vpn.domain.com
2. One EC2 Load Balancer (ELB) using Amazon Certificate Manager (ACM)
3. One EC2 Security Group
4. One EC2 Instance

## Architecture

```plain

For Web only:

             +-[1/a]-+     +--[2]--+     +--[3]--+     +--[4]--+
             |       |     |       |     |       |     |       |
Internet --> |  DNS  | --> |  ELB  | --> |  SG   | --> |  EC2  |
             |       |     |       |     |       |     |       |
             +-------+     +-------+     +-------+     +-------+
    vpn-web.domain.com  -->  TCP:443  -->  TCP:443  -->  TCP:443 OK

For VPN connection: (ELB does not support custom port 1194)

             +-[1/b]-+     +--[2]--+     +--[3]--+
             |       |     |       |     |       |
Internet --> |  DNS  | --> |  SG   | --> |  EC2  |
             |       |     |       |     |       |
             +-------+     +-------+     +-------+
        vpn.domain.com -->  TCP:1194 -->  TCP:1194 OK
```

## Usage

```hcl
module "openvpn" {
  source             = "github.com/terraform-community-modules/tf_aws_openvpn"
  name               = "openVPN"
  # VPC Inputs
  vpc_id             = "${var.vpc_id}"
  vpc_cidr           = "${var.vpc_cidr}"
  public_subnet_ids  = "${var.public_subnet_ids}"
  # EC2 Inputs
  key_name           = "${var.aws_key_name}"
  private_key        = "${var.private_key}"
  ami                = "${var.ami}"
  instance_type      = "${var.instance_type}"
  # ELB Inputs
  cert_arn           = "${var.cert_arn}"
  # DNS Inputs
  domain_name        = "${var.public_domain_name}"
  route_zone_id      = "${var.route_zone_id}"
  # OpenVPN Inputs
  openvpn_user       = "${var.openvpn_user}"
  openvpn_admin_user = "${var.openvpn_admin_user}" # Note: Don't choose "admin" username. Looks like it's already reserved.
  openvpn_admin_pw   = "${var.openvpn_admin_pw}"
}
```

## Important Notes for Routing:

You can check /var/log/syslog to confirm vpn connection.
check autoload is set to all or openvpn in /etc/default
ensure startvpn.sh is in ~/openvpn_config.  openvpn.conf auto login files are constructed here and placed in /etc/openvpn before execution.  
  
read more here to learn about setting up routes  
https://openvpn.net/vpn-server-resources/site-to-site-routing-explained-in-detail/  
https://askubuntu.com/questions/612840/adding-route-on-client-using-openvpn  

You will need ip forwarding on client and server if routing both sides.  
https://community.openvpn.net/openvpn/wiki/265-how-do-i-enable-ip-forwarding  

**These are the manual steps required to get both private subnets to connect, and we'd love to figure out the equivalent commands drop in when I'm provisioning the access server to automate them, but for now these are manual steps.**
  
- Should VPN clients have access to private subnets  
(non-public networks on the server side)?  
Yes, enable routing  
  
- Specify the private subnets to which all clients should be given access (one per line):  
10.0.101.0/24
10.0.1.0/24
(these subnets are in aws, the open vpn access server resides in the 10.0.101.0/24 subnet)  

- Allow access from these private subnets to all VPN client IP addresses and subnets : on  
  
- in user permissions / user  
configure vpn gateway:  
yes  
  
- Allow client to act as VPN gateway (enter the cidr block for your onsite network)
for these client-side subnets:  
192.168.92.0/24

At this point, your client side vpn client should be able to ping any private ip, and if you ssh into one of those ips, it whould be able to ping your client side ip with its private ip address.

If not you will have to trouble shoot before you can continue further because this functionality is required.
  
if you intend to provide access to other systems on your local network, promiscuous mode must enabled on host ethernet adapters.  for example, if openvpn client is in ubuntu vm, and we are running the vm with bridged ethernet in a linux host, then enabling promiscuous mode, and setting up a static route is needed in the host.  
https://askubuntu.com/questions/430355/configure-a-network-interface-into-promiscuous-mode  
for example, if you use a rhel host run this in the host to provide static route to the adaptor inside the vm (should be on the same subnet)
```
sudo ip route add 10.0.0.0/16 via [ip adress of the bridged ethernet adaptor in the vm]
```
check routes with:
```
sudo route -n
ifconfig eth1 up
ifconfig eth1 promisc
```

In the ubuntu vm where where terraform is running, ip forwarding must be on.  You must be using a bridged adaptor.
http://www.networkinghowtos.com/howto/enable-ip-forwarding-on-ubuntu-13-04/

```
sudo sysctl net.ipv4.ip_forward=1
```


## Authors

Created and maintained by [Quentin Rousseau](https://github.com/kwent) (contact@quent.in).
Autostart and Routing Abilities in this fork by Andrew Graham (https://github.com/queglay/) (queglay@gmail.com)

## License

Apache 2 Licensed. See LICENSE for full details.
