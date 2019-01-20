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
    cidr_blocks = ["${var.vpc_cidr}"]
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
  }

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  user_data = <<USERDATA
admin_user=${var.openvpn_admin_user}
admin_pw=${var.openvpn_admin_pw}
USERDATA
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

  provisioner "remote-exec" {
    connection {
      user        = "${var.openvpn_user}"
      host        = "${aws_eip.openvpnip.public_ip}"
      private_key = "${var.private_key}"
      timeout     = "10m"
    }

    inline = [
      #allow echo of input in bash.  Won't display pipes though!
      "set -x",

      # Sleep 60 seconds until AMI is ready
      "sleep 60",

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
      user        = "${var.openvpn_user}"
      host        = "${aws_eip.openvpnip.public_ip}"
      private_key = "${var.private_key}"
      timeout     = "10m"
    }

    inline = [
      "cd /usr/local/openvpn_as/scripts/",

      # todo : need to correct this test user to be dynamic based on user input.
      "echo ${var.openvpn_admin_pw} | sudo -S mkdir seperate",

      "set -x",

      # this enables auto login: todo : check if theres a problem with not having this above the start command
      "sudo ./sacli --user openvpnas --key 'prop_autologin' --value 'true' UserPropPut",

      "sudo ./sacli --user openvpnas AutoGenerateOnBehalfOf",
      "sudo ./sacli -o ./seperate --cn openvpnas get5",
      "sudo chown openvpnas seperate/*",
      "ls -la seperate",
    ]
  }

  #we download the connection config files, and alter the client.ovpn file to use a password file.
  ### note user must follow instructions on startvpn.sh to function
  ### todo : would be better to avoid all file movement in local exec.  startvpn should only start the service and nothing else.
  provisioner "local-exec" {
    command = <<EOT
      set -x
      mkdir ~/openvpn_config
      cd ~/openvpn_config
      rm -f ta.key
      rm -f client.ovpn
      rm -f client.conf
      rm -f client.key
      rm -f client.crt
      rm -f ca.crt
      rm -f yourserver.txt
      rm -f client_route.conf
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r -i '${var.local_key_path}' openvpnas@${aws_eip.openvpnip.public_ip}:/usr/local/openvpn_as/scripts/seperate/* ~/openvpn_config/
      ls -la
      echo 'openvpnas' >> yourserver.txt
      echo 'SecurityThroughObscurity99' >> yourserver.txt
      sed -i 's/auth-user-pass/auth-user-pass yourserver.txt/g' client.ovpn
      sed -i '/# OVPN_ACCESS_SERVER_PROFILE=/c\# OVPN_ACCESS_SERVER_PROFILE=openvpnas@${aws_eip.openvpnip.public_ip}/AUTOLOGIN\n# OVPN_ACCESS_SERVER_AUTOLOGIN=1' client.ovpn
      mv client.ovpn openvpn.conf
  EOT
  }

  # You can check /var/log/syslog to confirm connection
  # check autoload is set to all or openvpn in /etc/default 
  # todo : need to document for users how to create start vpn script and add to sudoers.  script should exist in /etc/openvpn.
  # the visudo permissions should be more specific, dont * copy to folder in this script.

  #read more here to learn about setting up routes
  # https://askubuntu.com/questions/612840/adding-route-on-client-using-openvpn
}

variable "start_vpn" {
  default = true
}

resource "null_resource" "start_vpn" {
  depends_on = ["aws_eip.openvpnip"]
  count      = "${var.start_vpn}"

  provisioner "local-exec" {
    command = <<EOT
      ~/openvpn_config/startvpn.sh
      sleep 10
      ping -c15 '${aws_instance.openvpn.private_ip}'
  EOT
  }
}

resource "aws_elb" "openvpn" {
  name                        = "openvpn-elb"
  subnets                     = ["${var.public_subnet_ids}"]
  internal                    = false
  idle_timeout                = 30
  connection_draining         = true
  connection_draining_timeout = 30
  instances                   = ["${aws_instance.openvpn.id}"]
  security_groups             = ["${aws_security_group.openvpn.id}"]

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${var.cert_arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "TCP:443"
    interval            = 20
  }

  tags {
    Name = "openvpn-elb"
  }
}

resource "aws_route53_record" "openvpn-web" {
  zone_id = "${var.route_zone_id}"
  name    = "vpn-web.${var.domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.openvpn.dns_name}"
    zone_id                = "${aws_elb.openvpn.zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "openvpn" {
  zone_id = "${var.route_zone_id}"
  name    = "vpn.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = ["${aws_eip.openvpnip.public_ip}"]
}
