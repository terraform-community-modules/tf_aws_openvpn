#----------------------------------------------------------------
# This module creates all resources necessary for OpenVPN in AWS
#----------------------------------------------------------------

# You should define this variable as your remote static ip adress to limit vpn exposure to the public internet



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
  count      = var.create_vpn ? 1 : 0
  depends_on = [null_resource.gateway_dependency, null_resource.bastion_dependency]
  ami        = var.ami
  # ami               = local.ami
  # needs VPNServerRole_${var.conflictkey}
  # iam_instance_profile = "VPNServerProfile_${var.conflictkey}"
  # iam_instance_profile = data.terraform_remote_state.openvpn_profile.instance_profile_name
  iam_instance_profile = var.iam_instance_profile_name
  instance_type        = var.instance_type
  key_name             = var.aws_key_name
  subnet_id            = concat(sort(var.public_subnet_ids), list(""))[0]
  source_dest_check    = var.source_dest_check

  vpc_security_group_ids = var.security_group_attachments

  root_block_device {
    delete_on_termination = true
  }

  tags = merge(map("Name", var.name), var.common_tags, local.extra_tags)

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  # Python is required for Ansible to function.
  #   user_data = <<USERDATA
  # admin_user=${var.openvpn_admin_user}
  # admin_pw=${var.openvpn_admin_pw}
  # USERDATA

  user_data = data.template_file.user_data_auth_client.rendered

}

# data "vault_aws_access_credentials" "creds" {
#   # dynamically generated AWS key.
#   backend = "aws"
#   role    = "vpn-server-vault-iam-creds-role"
# }

# resource "vault_token" "vpn_admin" {
#   # dynamically generate a token with constrained permisions for the vpn role.
#   role_name = "vpn-server-vault-token-creds-role"
#   policies = ["vpn_server","ssh_host"]
#   renewable        = false
#   explicit_max_ttl = "600s"
# }

data "template_file" "user_data_auth_client" {
  template = file("${path.module}/user-data-auth-client-vault-token.sh")

  vars = {
    consul_cluster_tag_key     = var.consul_cluster_tag_key
    consul_cluster_tag_value   = var.consul_cluster_name
    example_role_name          = var.example_role_name
    openvpn_admin_user         = var.openvpn_admin_user
    openvpn_user               = var.openvpn_user
    resourcetier               = var.resourcetier
    client_network             = element(split("/", var.vpn_cidr), 0)
    client_netmask_bits        = element(split("/", var.vpn_cidr), 1)
    private_subnet1            = element(var.private_subnets, 0)
    public_subnet1             = element(var.public_subnets, 0)
    aws_internal_domain        = ".consul"
    onsite_private_subnet_cidr = var.onsite_private_subnet_cidr
    vault_token                = "" # disabled since using IAM auth method
    # vault_token              = vault_token.vpn_admin.client_token
    # openvpn_admin_pw         = var.openvpn_admin_pw
    # openvpn_user_pw          = var.openvpn_user_pw
  }
}

#configuration of the vpn instance must occur after the eip is assigned.  normally a provisioner would want to reside in the aws_instance resource, but in this case,
#it must reside in the aws_eip resource to be able to establish a connection

resource "aws_eip" "openvpnip" {
  count      = var.create_vpn && var.use_eip ? 1 : 0
  vpc        = true
  instance   = aws_instance.openvpn[count.index].id
  depends_on = [aws_instance.openvpn]

  tags = merge(map("Name", var.name), var.common_tags, local.extra_tags)

}

#wakeup a node after sleep

locals {
  startup = (!var.sleep && var.create_vpn) ? 1 : 0
  extra_tags = {
    role  = "vpn"
    route = "public"
  }
}
output "startup" {
  value = local.startup
}
resource "null_resource" "start-node" {
  count = local.startup

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      # . /vagrant/scripts/exit_test.sh
      aws ec2 start-instances --instance-ids ${aws_instance.openvpn[count.index].id}
      # ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn-service.yaml -v --extra-vars "state=restarted"; exit_test
EOT
  }
}

locals {
  shutdown = var.sleep && var.create_vpn ? 1 : 0
}
output "shutdown" {
  value = local.shutdown
}
resource "null_resource" "shutdownvpn" {
  count = local.shutdown

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      # . /vagrant/scripts/exit_test.sh
      aws ec2 stop-instances --instance-ids ${aws_instance.openvpn[count.index].id}
      # ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn-service.yaml -v --extra-vars "state=stopped"; exit_test
EOT
  }
}

locals {
  private_ip        = element(concat(aws_instance.openvpn.*.private_ip, list("")), 0)
  public_ip         = element(concat(var.use_eip ? aws_eip.openvpnip.*.public_ip : aws_instance.openvpn.*.public_ip, list("")), 0)
  id                = element(concat(aws_instance.openvpn.*.id, list("")), 0)
  # security_group_id = element(concat(aws_security_group.openvpn.*.id, list("")), 0)
  vpn_address       = var.route_public_domain_name ? "vpn.${var.public_domain_name}" : local.public_ip
  # private_route_table_id         = element(concat(var.private_route_table_ids, list("")), 0)
  # public_route_table_id         = element(concat(var.public_route_table_ids, list("")), 0)
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
resource "null_resource" "firehawk_init_dependency" { # ensure that the firehawk gateway has finished being prrovisioned because the next process may interupt its network connection
  triggers = {
    firehawk_init_dependency = var.firehawk_init_dependency
  }
}

# resource "null_resource" "provision_vpn" {
#   count = var.create_vpn ? 1 : 0
#   depends_on = [local.public_ip, aws_route53_record.openvpn_record, null_resource.firehawk_init_dependency]

# #   triggers = {
# #     instanceid = local.id
# #     # If the address changes, the vpn must be provisioned again.
# #     vpn_address = local.vpn_address
# #   }

#   provisioner "local-exec" {
#     interpreter = ["/bin/bash", "-c"]
#     command = <<EOT
#       # . /vagrant/scripts/exit_test.sh
#       export SHOWCOMMANDS=true; set -x
#       cd /deployuser
#       # sleep 60 # local wait until instance can be logged into
# EOT
#   }

# provisioner "remote-exec" {
#   connection {
#     user = var.openvpn_admin_user
#     host = local.public_ip
#     private_key = var.private_key
#     type    = "ssh"
#     timeout = "10m"
#   }
#   inline = [
#     "echo 'instance up'", # test connection
#   ]
# }

#   ### START this segment is termporary to deal with a cloud init bug
#   provisioner "remote-exec" {
#     connection {
#       user = var.openvpn_admin_user
#       host = local.public_ip
#       private_key = var.private_key
#       type    = "ssh"
#       timeout = "10m"
#     }
#     # this resolves update issue https://unix.stackexchange.com/questions/315502/how-to-disable-apt-daily-service-on-ubuntu-cloud-vm-image
#     inline = [
#       "export SHOWCOMMANDS=true; set -x",
#       "lsb_release -a",
#       "ps aux | grep [a]pt",
#       "sudo cat /etc/systemd/system.conf",
#       "sudo systemd-run --property='After=apt-daily.service apt-daily-upgrade.service' --wait /bin/true",
#       "sudo apt-get -y update",
#       "sudo apt-get -y install python3",
#       "sudo apt-get -y install python-apt",
#       "sudo fuser -v /var/cache/debconf/config.dat", # get info if anything else has a lock on this file
#       "sudo chown openvpnas:openvpnas /home/openvpnas", # This must be a bug with 2.8.5 open vpn ami.
#       "echo '...Finished bootstrapping'",
#     ]
#   }

#   provisioner "local-exec" {
#     interpreter = ["/bin/bash", "-c"]
#     command = <<EOT
#       . /vagrant/scripts/exit_test.sh
#       export SHOWCOMMANDS=true; set -x
#       cd /deployuser
#       aws ec2 reboot-instances --instance-ids ${aws_instance.openvpn[count.index].id} && sleep 60
# EOT
#   }

#   provisioner "remote-exec" {
#     connection {
#       user = var.openvpn_admin_user
#       host = local.public_ip
#       private_key = var.private_key
#       type    = "ssh"
#       timeout = "10m"
#     }
#     inline = [
#       "echo 'instance up'",
#     ]
#   }

#   provisioner "local-exec" {
#     interpreter = ["/bin/bash", "-c"]
#     command = <<EOT
#       . /vagrant/scripts/exit_test.sh
#       cd /deployuser
#       ansible-playbook -i "$TF_VAR_inventory" ansible/ssh-add-public-host.yaml -v --extra-vars "public_ip=${local.public_ip} public_address=${local.vpn_address} bastion_address=${var.bastion_ip} vpn_address=${local.vpn_address} set_vpn=true"; exit_test
#       # ansible-playbook -i "$TF_VAR_inventory" ansible/inventory-add.yaml -v --extra-vars "host_name=openvpnip host_ip=${local.public_ip} insert_ssh_key_string=ansible_ssh_private_key_file=$TF_VAR_aws_private_key_path"; exit_test
#       ansible-playbook -i "$TF_VAR_inventory" ansible/ssh-add-private-host.yaml -v --extra-vars "private_ip=${local.private_ip} bastion_ip=${var.bastion_ip}"; exit_test
#       ansible-playbook -i "$TF_VAR_inventory" ansible/inventory-add.yaml -v --extra-vars "host_name=openvpnip_private group_name=role_openvpn_access_server host_ip=${local.private_ip} insert_ssh_key_string=ansible_ssh_private_key_file=$TF_VAR_aws_private_key_path"; exit_test
#       aws ec2 reboot-instances --instance-ids ${aws_instance.openvpn[count.index].id} && sleep 30
# EOT
#   }
#   provisioner "remote-exec" {
#     connection {
#       user        = var.openvpn_admin_user
#       host        = local.public_ip
#       private_key = var.private_key
#       type        = "ssh"
#       timeout     = "10m"
#     }
#     inline = [
#       "echo 'instance up'",
#       "sudo apt-get -y clean && sudo apt-get -y autoclean",
#     ]
#   }
#   provisioner "local-exec" {
#     interpreter = ["/bin/bash", "-c"]
#     command = <<EOT
#       . /vagrant/scripts/exit_test.sh
#       echo "environment vars in this case seem to need to be pushed via the shell"
#       echo "TF_VAR_onsite_private_subnet_cidr: $TF_VAR_onsite_private_subnet_cidr"
#       echo "onsite_private_subnet_cidr: ${var.onsite_private_subnet_cidr}"
#       echo "private_subnet1: ${element(var.private_subnets, 0)}"
#       echo "public_subnet1: ${element(var.public_subnets, 0)}"
#       set -x
#       ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn.yaml -v --extra-vars "vpn_address=${local.vpn_address} private_domain_name=${var.private_domain_name} private_ip=${local.private_ip} private_subnet1=${element(var.private_subnets, 0)} public_subnet1=${element(var.public_subnets, 0)} onsite_private_subnet_cidr=${var.onsite_private_subnet_cidr} client_network=${element(split("/", var.vpn_cidr), 0)} client_netmask_bits=${element(split("/", var.vpn_cidr), 1)}"; exit_test
#       ansible-playbook -i "$TF_VAR_inventory" ansible/node-centos-routes.yaml -v --extra-vars "variable_host=ansible_control variable_user=deployuser hostname=ansible_control ethernet_interface=eth1" # configure routes for ansible control to the gateway to test the connection

#       if [[ "$TF_VAR_set_routes_on_workstation" = "true" ]]; then # Intended for a dev envoronment only where multiple parralel deployments may occur, we cant provision a router for each subnet
#         ansible-playbook -i "$TF_VAR_inventory" ansible/node-centos-routes.yaml -v -v --extra-vars "variable_host=workstation1 variable_user=deployuser hostname=workstation1 ansible_ssh_private_key_file=$TF_VAR_onsite_workstation_private_ssh_key ethernet_interface=$TF_VAR_workstation_ethernet_interface"; exit_test
#       fi

#       sleep 30

#       ansible-playbook -i "$TF_VAR_inventory" ansible/openvpn-restart-client.yaml

#       sleep 30

#       /vagrant/scripts/tests/test-openvpn.sh --ip "${local.private_ip}"; exit_test
# EOT
#   }
# }

variable "start_vpn" {
  default = true
}

# route tables to send traffic to the remote subnet are configured once the vpn is provisioned.

resource "aws_route" "private_openvpn_remote_subnet_gateway" {
  count      = var.create_vpn ? length(var.private_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(concat(var.private_route_table_ids, list("")), count.index)
  destination_cidr_block = var.onsite_private_subnet_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_gateway" {
  count      = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(concat(var.public_route_table_ids, list("")), count.index)
  destination_cidr_block = var.onsite_private_subnet_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

### routes may be needed for traffic going back to open vpn dhcp adresses
resource "aws_route" "private_openvpn_remote_subnet_vpndhcp_gateway" {
  count      = var.create_vpn ? length(var.private_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(concat(var.private_route_table_ids, list("")), count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_vpndhcp_gateway" {
  count      = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(concat(var.public_route_table_ids, list("")), count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

output "id" {
  value      = local.id
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
  # depends_on = [ # don't allow other nodes to attempt to use this information until the routes are configured
  #   aws_route.public_openvpn_remote_subnet_vpndhcp_gateway, 
  #   aws_route.private_openvpn_remote_subnet_vpndhcp_gateway , 
  #   aws_route.public_openvpn_remote_subnet_gateway, 
  #   aws_route.private_openvpn_remote_subnet_gateway
  # ]
}

output "private_ip" {
  value      = local.private_ip
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
  # depends_on = [ # don't allow other nodes to attempt to use this information until the routes are configured
  #   aws_route.public_openvpn_remote_subnet_vpndhcp_gateway, 
  #   aws_route.private_openvpn_remote_subnet_vpndhcp_gateway , 
  #   aws_route.public_openvpn_remote_subnet_gateway, 
  #   aws_route.private_openvpn_remote_subnet_gateway
  # ]
}

output "public_ip" {
  value      = local.public_ip
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
  # depends_on = [ # don't allow other nodes to attempt to use this information until the routes are configured
  #   aws_route.public_openvpn_remote_subnet_vpndhcp_gateway, 
  #   aws_route.private_openvpn_remote_subnet_vpndhcp_gateway , 
  #   aws_route.public_openvpn_remote_subnet_gateway, 
  #   aws_route.private_openvpn_remote_subnet_gateway
  # ]
}
