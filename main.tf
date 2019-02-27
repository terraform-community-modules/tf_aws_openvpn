#----------------------------------------------------------------
# This module creates all resources necessary for OpenVPN in AWS
#----------------------------------------------------------------

# You should define this variable as your remote static ip adress to limit vpn exposure to the public internet

resource "aws_security_group" "openvpn" {
  name        = "${var.name}"
  vpc_id      = "${var.vpc_id}"
  description = "OpenVPN security group"

  tags {
    Name = "${var.name}"
  }

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}", "${var.vpn_cidr}", "${var.remote_subnet_cidr}"]
    description = "all incoming traffic from vpc"
  }

  # For OpenVPN Client Web Server & Admin Web UI

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
    description = "ssh"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
    description = "https"
  }
  # see  https://openvpn.net/vpn-server-resources/amazon-web-services-ec2-tiered-appliance-quick-start-guide/
  ingress {
    protocol    = "tcp"
    from_port   = 943
    to_port     = 943
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
    description = "admin ui"
  }
  ingress {
    protocol    = "udp"
    from_port   = 1194
    to_port     = 1194
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
  }
  ingress {
    protocol    = "icmp"
    from_port   = 8
    to_port     = 0
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
    description = "icmp"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.remote_vpn_ip_cidr}"]
    description = "all outgoing traffic to vpn client remote ip"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
    description = "all outgoing traffic to vpc"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "all outgoing traffic to anywhere"
  }
}

variable "source_dest_check" {
  default = true
}

resource "aws_instance" "openvpn" {
  ami               = "${var.ami}"
  instance_type     = "${var.instance_type}"
  key_name          = "${var.key_name}"
  subnet_id         = "${element(var.public_subnet_ids, count.index)}"
  source_dest_check = "${var.source_dest_check}"

  vpc_security_group_ids = ["${aws_security_group.openvpn.id}"]

  tags {
    Name = "${var.name}"
    route = "public"
  }

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  # Python is required for Ansible to function.
  user_data = <<USERDATA
admin_user=${var.openvpn_admin_user}
admin_pw=${var.openvpn_admin_pw}
sudo apt-get install -y python
USERDATA
}

#wakeup a node after sleep
resource "null_resource" "start-node" {
  count = "${var.sleep ? 0 : 1}"

  provisioner "local-exec" {
    command = "aws ec2 start-instances --instance-ids ${aws_instance.openvpn.id}"
  }
}

resource "null_resource" shutdownvpn {
  count = "${var.sleep ? 1 : 0}"

  provisioner "local-exec" {
    command = "aws ec2 stop-instances --instance-ids ${aws_instance.openvpn.id}"
  }
}

#configuration of the vpn instance must occur after the eip is assigned.  normally a provisioner would want to reside in the aws_instance resource, but in this case,
#it must reside in the aws_eip resource to be able to establish a connection

resource "aws_eip" "openvpnip" {

  vpc      = true
  instance = "${aws_instance.openvpn.id}"

  tags {
    role = "vpn"
  }

  provisioner "remote-exec" {
    connection {
      user        = "${var.openvpn_admin_user}"
      host        = "${aws_eip.openvpnip.public_ip}"
      private_key = "${var.private_key}"
      timeout     = "10m"
    }

    inline = [
      #allow echo of input in bash.  Won't display pipes though!
      "set -x",

      # Sleep 60 seconds until AMI is ready
      "sleep 60",

      # Install python for ansible
      "sudo apt-get -y install python",

      # Set VPN network info
      "sudo /usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.network -v ${element(split("/", var.vpn_cidr), 0)} ConfigPut",

      "sudo /usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.netmask_bits -v ${element(split("/", var.vpn_cidr), 1)} ConfigPut",

      # here we enable tls which is required if we are to generate ta.key and client.ovpn files
      "sudo /usr/local/openvpn_as/scripts/sacli --key 'vpn.server.tls_auth' --value ='true' ConfigPut",

      # Do a warm restart so the config is picked up
      "sudo /usr/local/openvpn_as/scripts/sacli start",
    ]
  }

  provisioner "remote-exec" {
    connection {
      user        = "${var.openvpn_admin_user}"
      host        = "${aws_eip.openvpnip.public_ip}"
      private_key = "${var.private_key}"
      timeout     = "10m"
    }

    inline = [
      "cd /usr/local/openvpn_as/scripts/",

      # todo : need to add a user that is different to the admin user.  currently they must be identical.
      "echo ${var.openvpn_admin_pw} | sudo -S mkdir seperate",

      "set -x",

      # this enables auto login: todo : check if theres a problem with not having this above the start command
      "sudo ./sacli --user ${var.openvpn_user} --key 'prop_autologin' --value 'true' UserPropPut",

      "sudo ./sacli --user ${var.openvpn_user} AutoGenerateOnBehalfOf",
      "sudo ./sacli -o ./seperate --cn ${var.openvpn_user} get5",
      "sudo chown ${var.openvpn_user} seperate/*",
      "ls -la seperate",
    ]
  }

  
  # After a remote exec, its possible to use local exec to add the ssh keys to the known hosts file.  this is done only once.
  provisioner "local-exec" {
    command = <<EOT
      set -x
      ssh-keyscan -H ${aws_eip.openvpnip.public_ip} >> ~/.ssh/known_hosts
  EOT
  }
}

output "id" {
  value = "${aws_instance.openvpn.id}"
}

output "private_ip" {
  value = "${aws_instance.openvpn.private_ip}"
}

output "public_ip" {
  value = "${aws_eip.openvpnip.public_ip}"
}

variable "start_vpn" {
  default = true
}

# resource "null_resource" "start_vpn" {
#   depends_on = ["aws_eip.openvpnip"]

#   triggers {
#     instanceid = "${ aws_eip.openvpnip.id }"
#   }

#   count = "${var.start_vpn}"

#   provisioner "local-exec" {
#     command = <<EOT
#       ${path.module}/startvpn.sh
#       sleep 10
#       ping -c15 '${aws_instance.openvpn.private_ip}'
#   EOT
#   }
# }

# resource "aws_elb" "openvpn" {
#   name                        = "openvpn-elb"
#   subnets                     = ["${var.public_subnet_ids}"]
#   internal                    = false
#   idle_timeout                = 30
#   connection_draining         = true
#   connection_draining_timeout = 30
#   instances                   = ["${aws_instance.openvpn.id}"]
#   security_groups             = ["${aws_security_group.openvpn.id}"]

#   listener {
#     instance_port      = 443
#     instance_protocol  = "https"
#     lb_port            = 443
#     lb_protocol        = "https"
#     ssl_certificate_id = "${var.cert_arn}"
#   }

#   health_check {
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 5
#     target              = "TCP:443"
#     interval            = 20
#   }

#   tags {
#     Name = "openvpn-elb"
#   }
# }

# resource "aws_route53_record" "openvpn-web" {
#   zone_id = "${var.route_zone_id}"
#   name    = "vpn-web.${var.domain_name}"
#   type    = "A"

#   alias {
#     name                   = "${aws_elb.openvpn.dns_name}"
#     zone_id                = "${aws_elb.openvpn.zone_id}"
#     evaluate_target_health = false
#   }
# }

resource "aws_route53_record" "openvpn_record" {
  zone_id = "${var.route_zone_id}"
  name    = "vpn.${var.public_domain_name}"
  type    = "A"
  ttl     = 300
  records = ["${aws_eip.openvpnip.public_ip}"]
}
