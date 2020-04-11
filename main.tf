#----------------------------------------------------------------
# This module creates all resources necessary for OpenVPN in AWS
#----------------------------------------------------------------

# You should define this variable as your remote static ip adress to limit vpn exposure to the public internet

resource "aws_security_group" "openvpn" {
  count       = var.create_vpn ? 1 : 0
  name        = var.name
  vpc_id      = var.vpc_id
  description = "OpenVPN security group"

  tags = {
    Name = var.name
  }

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr, var.vpn_cidr, var.remote_subnet_cidr]

    description = "all incoming traffic from vpc, vpn dhcp, and remote subnet"
  }

  # For OpenVPN Client Web Server & Admin Web UI

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.remote_vpn_ip_cidr]
    description = "ssh"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.remote_vpn_ip_cidr]
    description = "https"
  }

  # see  https://openvpn.net/vpn-server-resources/amazon-web-services-ec2-tiered-appliance-quick-start-guide/
  ingress {
    protocol    = "tcp"
    from_port   = 943
    to_port     = 943
    cidr_blocks = [var.remote_vpn_ip_cidr]
    description = "admin ui"
  }
  ingress {
    protocol    = "udp"
    from_port   = 1194
    to_port     = 1194
    cidr_blocks = [var.remote_vpn_ip_cidr]
  }
  ingress {
    protocol    = "icmp"
    from_port   = 8
    to_port     = 0
    cidr_blocks = [var.remote_vpn_ip_cidr]
    description = "icmp"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.remote_vpn_ip_cidr]
    description = "all outgoing traffic to vpn client remote ip"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr]
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

resource "null_resource" "gateway_dependency" {
  triggers = {
    igw_id = var.igw_id
  }
}

resource "null_resource" "bastion_dependency" {
  triggers = {
    bastion_dependency = var.bastion_dependency
  }
}

resource "aws_instance" "openvpn" {
  count = var.create_vpn ? 1 : 0
  depends_on        = [null_resource.gateway_dependency, null_resource.bastion_dependency]
  ami               = var.ami
  instance_type     = var.instance_type
  key_name          = var.key_name
  subnet_id         = element(var.public_subnet_ids, 0)
  source_dest_check = var.source_dest_check

  vpc_security_group_ids = [local.security_group_id]

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name  = var.name
    route = "public"
  }

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  # Python is required for Ansible to function.
  user_data = <<USERDATA
admin_user=${var.openvpn_admin_user}
admin_pw=${var.openvpn_admin_pw}
USERDATA

}

#wakeup a node after sleep
resource "null_resource" "start-node" {
  count = ( ! var.sleep && var.create_vpn ) ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      aws ec2 start-instances --instance-ids ${aws_instance.openvpn[count.index].id} 
      ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn-service.yaml -v --extra-vars "state=restarted"
EOT
  }
}

resource "null_resource" "shutdownvpn" {
  count = var.sleep && var.create_vpn ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      aws ec2 stop-instances --instance-ids ${aws_instance.openvpn[count.index].id} 
      ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn-service.yaml -v --extra-vars "state=stopped"
EOT
  }
}

#configuration of the vpn instance must occur after the eip is assigned.  normally a provisioner would want to reside in the aws_instance resource, but in this case,
#it must reside in the aws_eip resource to be able to establish a connection

resource "aws_eip" "openvpnip" {
  count = var.create_vpn ? 1 : 0
  vpc      = true
  instance = aws_instance.openvpn[count.index].id

  tags = {
    role = "vpn"
  }
}

locals {
  private_ip = "${element(concat(aws_instance.openvpn.*.private_ip, list("")), 0)}"
  public_ip = "${element(concat(aws_eip.openvpnip.*.public_ip, list("")), 0)}"
  id = "${element(concat(aws_instance.openvpn.*.id, list("")), 0)}"
  security_group_id = "${element(concat(aws_security_group.openvpn.*.id, list("")), 0)}"
  vpn_address = var.route_public_domain_name ? "vpn.${var.public_domain_name}":"${local.public_ip}"
  private_route_table_id         = "${element(concat(var.private_route_table_ids, list("")), 0)}"
  public_route_table_id         = "${element(concat(var.public_route_table_ids, list("")), 0)}"
}

variable "route_public_domain_name" {
}

resource "aws_route53_record" "openvpn_record" {
  count   = var.route_public_domain_name && var.create_vpn ? 1 : 0
  zone_id = element(concat(list(var.route_zone_id), list("")), 0)
  name    = element(concat(list("vpn.${var.public_domain_name}"), list("")), 0)
  type    = "A"
  ttl     = 300
  records = [local.public_ip]
}

resource "null_resource" "provision_vpn" {
  count = var.create_vpn ? 1 : 0
  depends_on = [aws_eip.openvpnip, aws_route53_record.openvpn_record]

  triggers = {
    instanceid = local.id
    # If the address changes, the vpn must be provisioned again.
    vpn_address = local.vpn_address
  }

### START this segment is termporary to deal with a cloud init bug
  provisioner "remote-exec" {
    connection {
      user = var.openvpn_admin_user
      host = local.public_ip
      private_key = var.private_key
      type    = "ssh"
      timeout = "10m"
    }
    # this resolves update issue https://unix.stackexchange.com/questions/315502/how-to-disable-apt-daily-service-on-ubuntu-cloud-vm-image
    inline = [
      "set -x",
      "echo 'instance up'",
      "lsb_release -a",
      "ps aux | grep [a]pt",
      "sudo systemd-run --property='After=apt-daily.service apt-daily-upgrade.service' --wait /bin/true",
      "sudo apt-get -y update",
      "sudo apt-get -y install python2.7-minimal python2.7",
      # "sudo systemctl disable apt-daily.timer",
      # "sudo systemctl disable apt-daily-upgrade.timer", # the timers may start the daily update, they need to be disabled, but it wont apply until after reboot. stop will also not resolve this.
    ]
  }
  provisioner "local-exec" {
    command = <<EOT
      . /vagrant/scripts/exit_test.sh
      set -x
      cd /deployuser
      aws ec2 reboot-instances --instance-ids ${aws_instance.openvpn[count.index].id} && sleep 60
EOT
  }
### END this segment is termporary to deal with a cloud init bug

  provisioner "remote-exec" {
    connection {
      user = var.openvpn_admin_user
      host = local.public_ip
      private_key = var.private_key
      type    = "ssh"
      timeout = "10m"
    }
    #inline = ["set -x && sleep 60 && sudo apt-get -y install python"]
    inline = [
      "sudo systemctl stop apt-daily.service",
      "sudo systemctl kill --kill-who=all apt-daily.service",
      "while ! (sudo systemctl list-units --all apt-daily.service | egrep -q '(dead|failed)'); do sleep 1; done", # wait until `apt-get updated` has been killed
      "ps aux | grep [a]pt",
      # "systemctl status apt-daily.service",
      # "sudo systemctl stop apt.systemd.daily",
      # "sudo systemctl kill --kill-who=all apt.systemd.daily",
      # "while ! (sudo systemctl list-units --all apt.systemd.daily | egrep -q '(dead|failed)'); do sleep 1; done", # wait until `apt.systemd.daily` has been killed
      "sudo apt-get -y update",
      "sleep 10",
      "ps aux | grep [a]pt",
      "sudo apt-get -y install python2.7-minimal python2.7",
      "which python2.7",
      "ls /usr/bin",
      "sudo fuser -v /var/cache/debconf/config.dat", # get info if anything else has a lock on this file
      "test=$(which python2.7); if [[ \"$test\" != '/usr/bin/python2.7' ]]; then echo 'failed to use /usr/bin/python2.7'; fi",
      # "sudo systemctl enable apt-daily.timer", # enable again to allow updates
      # "sudo systemctl enable apt-daily-upgrade.timer",
      "echo '...Finished bootstrapping'",
    ]
  }

  provisioner "local-exec" {
    command = <<EOT
      . /vagrant/scripts/exit_test.sh
      set -x
      cd /deployuser
      aws ec2 reboot-instances --instance-ids ${aws_instance.openvpn[count.index].id} && sleep 60
EOT
  }

  provisioner "remote-exec" {
    connection {
      user = var.openvpn_admin_user
      host = local.public_ip
      private_key = var.private_key
      type    = "ssh"
      timeout = "10m"
    }
    #inline = ["set -x && sleep 60 && sudo apt-get -y install python"]
    inline = [
      "echo 'instance up'",
    ]
  }



  provisioner "local-exec" {
    command = <<EOT
      . /vagrant/scripts/exit_test.sh
      set -x
      cd /deployuser
      ansible-playbook -i "$TF_VAR_inventory" ansible/ssh-add-public-host.yaml -v --extra-vars "public_ip=${local.public_ip} public_address=${local.vpn_address} bastion_address=${var.bastion_ip} vpn_address=${local.vpn_address} set_vpn=true"; exit_test
      ansible-playbook -i "$TF_VAR_inventory" ansible/inventory-add.yaml -v --extra-vars "host_name=openvpnip host_ip=${local.public_ip} insert_ssh_key_string=ansible_ssh_private_key_file=$TF_VAR_local_key_path"; exit_test
      ansible-playbook -i "$TF_VAR_inventory" ansible/ssh-add-private-host.yaml -v --extra-vars "private_ip=${local.private_ip} bastion_ip=${var.bastion_ip}"; exit_test
      ansible-playbook -i "$TF_VAR_inventory" ansible/inventory-add.yaml -v --extra-vars "host_name=openvpnip_private host_ip=${local.private_ip} insert_ssh_key_string=ansible_ssh_private_key_file=$TF_VAR_local_key_path"; exit_test
      aws ec2 reboot-instances --instance-ids ${aws_instance.openvpn[count.index].id} && sleep 30
EOT
  }
  provisioner "remote-exec" {
    connection {
      user        = var.openvpn_admin_user
      host        = local.public_ip
      private_key = var.private_key
      type        = "ssh"
      timeout     = "10m"
    }
    inline = [
      "set -x",
      "echo 'instance up'",
      # "until [[ -f /var/lib/cloud/instance/boot-finished ]]; do sleep 1; done"
      # "sudo apt-get -y install python",
    ]
  }
  provisioner "local-exec" {
    command = <<EOT
      . /vagrant/scripts/exit_test.sh
      set -x
      echo "environment vars in this case seem to need to be pushed via the shell"
      echo "TF_VAR_remote_subnet_cidr: $TF_VAR_remote_subnet_cidr"
      echo "remote_subnet_cidr: ${var.remote_subnet_cidr}"
      echo "private_subnet1: ${element(var.private_subnets, 0)}"
      echo "public_subnet1: ${element(var.public_subnets, 0)}"
      ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn.yaml -v --extra-vars "variable_host=openvpnip vpn_address=${local.vpn_address} private_subnet1=${element(var.private_subnets, 0)} public_subnet1=${element(var.public_subnets, 0)} remote_subnet_cidr=${var.remote_subnet_cidr} client_network=${element(split("/", var.vpn_cidr), 0)} client_netmask_bits=${element(split("/", var.vpn_cidr), 1)}"; exit_test
      sleep 30; /vagrant/scripts/tests/test-openvpn.sh --ip "${local.private_ip}"; exit_test
EOT
  }
}

output "id" {
  value = local.id
}

output "private_ip" {
  value = local.private_ip
}

output "public_ip" {
  value = local.public_ip
}

variable "start_vpn" {
  default = true
}

# route tables to send traffic to the remote subnet are configured once the vpn is provisioned.

resource "aws_route" "private_openvpn_remote_subnet_gateway" {
  count = var.create_vpn ? length(var.private_route_table_ids) : 0
  depends_on = [null_resource.provision_vpn]

  route_table_id         = element(concat(var.private_route_table_ids, list("")), count.index)
  destination_cidr_block = var.remote_subnet_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_gateway" {
  count = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [null_resource.provision_vpn]

  route_table_id         = element(concat(var.public_route_table_ids, list("")), count.index)
  destination_cidr_block = var.remote_subnet_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

### routes may be needed for traffic going back to open vpn dhcp adresses
resource "aws_route" "private_openvpn_remote_subnet_vpndhcp_gateway" {
  count = var.create_vpn ? length(var.private_route_table_ids) : 0
  depends_on = [null_resource.provision_vpn]

  route_table_id         = element(concat(var.private_route_table_ids, list("")), count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_vpndhcp_gateway" {
  count = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [null_resource.provision_vpn]

  route_table_id         = element(concat(var.public_route_table_ids, list("")), count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}