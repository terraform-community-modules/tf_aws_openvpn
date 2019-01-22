# tf_aws_openvpn

Terraform module which creates OpenVPN on AWS

## This module is creating the following resources:

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
  key_name           = "${var.key_name}"
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

## Additional Notes for Routing

You can check /var/log/syslog to confirm vpn connection.
check autoload is set to all or openvpn in /etc/default
ensure startvpn.sh is in ~/openvpn_config.  openvpn.conf auto login files are constructed here and placed in /etc/openvpn before execution.

read more here to learn about setting up routes
https://openvpn.net/vpn-server-resources/site-to-site-routing-explained-in-detail/
https://askubuntu.com/questions/612840/adding-route-on-client-using-openvpn

You will need ip forwarding on client and server if routing both sides.
https://community.openvpn.net/openvpn/wiki/265-how-do-i-enable-ip-forwarding
These are the manual steps I'm doing to get both private subnets to connect, and I'd love to figure out the equivalent commands that I can drop in when I'm provisioning the access server to automate them, but for now these are manual steps.

[b]1.0 Should VPN clients have access to private subnets
(non-public networks on the server side)?[/b]
Yes, enable routing

[b]2.0 Specify the private subnets to which all clients should be given access (one per line):[/b]
10.0.101.0/24
10.0.1.0/24
(these subnets are in aws, the open vpn access server resides in the 10.0.101.0/24 subnet)

[b]3.0 Allow access from these private subnets to all VPN client IP addresses and subnets[/b] : on

[b]4.0 in user permissions / user
configure vpn gateway:
[/b]yes

[b]5.0 Allow client to act as VPN gateway
for these client-side subnets:[/b]
192.168.0.0/24

if you intend to provide access to other systems on your local network, promiscuous mode must enabled on host ethernet adapters.  for example, if openvpn client is in ubuntu vm, and we are running the vm with bridged ethernet in a linux host, then enabling promiscuous mode, and setting up a static route is needed in the host.
https://askubuntu.com/questions/430355/configure-a-network-interface-into-promiscuous-mode
for example, if you use a rhel host run this in the host to provide static route to the adaptor inside the vm (should be on the same subnet)
```
sudo ip route add 10.0.0.0/16 via [ip adress of the bridged ethernet adaptor in the vm]
```
check routes with:
   sudo route -n
  ifconfig eth1 up
  ifconfig eth1 promisc

In the ubuntu vm where where terraform is running, ip forwarding must be on.  You must be using a bridged adaptor.
http://www.networkinghowtos.com/howto/enable-ip-forwarding-on-ubuntu-13-04/
  sudo sysctl net.ipv4.ip_forward=1


## Authors

Created and maintained by [Quentin Rousseau](https://github.com/kwent) (contact@quent.in).
Autostart and Routing Abilities in this fork by Andrew Graham (https://github.com/queglay/) (queglay@gmail.com)

## License

Apache 2 Licensed. See LICENSE for full details.
