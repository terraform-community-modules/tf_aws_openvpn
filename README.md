## Terraform OpenVPN module for AWS

### This module is creating the following resources:

1. Two Route53 Records
  a. vpn-web.domain.com
  b. vpn.domain.com
2. One EC2 Load Balancer (ELB) using Amazon Certificate Manager (ACM)
3. One EC2 Security Group
4. One EC2 Instance

### Architecture

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

### Usage

```hcl
module "openvpn" {
  source             = "github.com/kwent/terraform-openvpn-aws"
  name               = "openVPN"
  vpc_id             = "${var.vpc_id}"
  vpc_cidr           = "${var.vpc_cidr}"
  public_subnet_ids  = "${var.public_subnet_ids}"
  cert_arn           = "${var.cert_arn}"
  key_name           = "${var.key_name}"
  private_key        = "${var.private_key}"
  ami                = "${var.ami}"
  instance_type      = "${var.instance_type}"
  openvpn_user       = "${var.openvpn_user}"
  openvpn_admin_user = "${var.openvpn_admin_user}"
  openvpn_admin_pw   = "${var.openvpn_admin_pw}"
  vpn_cidr           = "${var.vpn_cidr}"
  sub_domain         = "${var.public_domain_name}"
  route_zone_id      = "${var.route_zone_id}"
}
```
