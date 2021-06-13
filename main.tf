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
  subnet_id            = var.public_subnet_id
  source_dest_check    = var.source_dest_check

  vpc_security_group_ids = var.security_group_attachments

  root_block_device {
    delete_on_termination = true
  }

  tags = merge(tomap( {"Name" : var.name} ), var.common_tags, local.extra_tags)

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  # Python is required for Ansible to function.
  #   user_data = <<USERDATA
  # admin_user=${var.openvpn_admin_user}
  # admin_pw=${var.openvpn_admin_pw}
  # USERDATA

  user_data = data.template_file.user_data_auth_client.rendered

}

locals {
  resourcetier = var.resourcetier
  client_cert_file_path = "/usr/local/openvpn_as/scripts/seperate/client.ovpn"
  client_cert_vault_path = "${local.resourcetier}/vpn/client_cert_files${local.client_cert_file_path}"
}
data "template_file" "user_data_auth_client" {
  template = format(
    "%s%s%s",
    file("${path.module}/user-data-iam-auth-vpn.sh"),
    file("${path.module}/user-data-vault-store-file.sh"),
    file("${path.module}/user-data-register-consul-service.sh")
  )

  vars = {
    consul_cluster_tag_key     = var.consul_cluster_tag_key
    consul_cluster_tag_value   = var.consul_cluster_name
    example_role_name          = var.example_role_name
    openvpn_admin_user         = var.openvpn_admin_user
    openvpn_user               = var.openvpn_user
    resourcetier               = local.resourcetier
    client_network             = element(split("/", var.vpn_cidr), 0)
    client_netmask_bits        = element(split("/", var.vpn_cidr), 1)
    combined_vpcs_cidr         = var.combined_vpcs_cidr
    aws_internal_domain        = ".consul"
    onsite_private_subnet_cidr = var.onsite_private_subnet_cidr

    consul_service = "vpn"

    client_cert_file_path  = local.client_cert_file_path
    client_cert_vault_path = local.client_cert_vault_path
  }
}

#configuration of the vpn instance must occur after the eip is assigned.  normally a provisioner would want to reside in the aws_instance resource, but in this case,
#it must reside in the aws_eip resource to be able to establish a connection

resource "aws_eip" "openvpnip" {
  count      = var.create_vpn && var.use_eip ? 1 : 0
  vpc        = true
  instance   = aws_instance.openvpn[count.index].id
  depends_on = [aws_instance.openvpn]

  tags = merge(tomap( {"Name" : var.name} ), var.common_tags, local.extra_tags)

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
  private_ip = length( aws_instance.openvpn ) > 0 ? aws_instance.openvpn[0].private_ip : null
  public_ip  = var.use_eip ? length( aws_eip.openvpnip ) > 0 ? aws_eip.openvpnip[0].public_ip : null : length( aws_instance.openvpn ) > 0 ? aws_instance.openvpn[0].public_ip : null
  id         = length( aws_instance.openvpn ) > 0 ? aws_instance.openvpn[0].id : null
  vpn_address = var.route_public_domain_name ? "vpn.${var.public_domain_name}" : local.public_ip
}

resource "aws_route53_record" "openvpn_record" {
  count   = var.route_public_domain_name && var.create_vpn ? 1 : 0
  zone_id = try(var.route_zone_id, null)
  name    = try("vpn.${var.public_domain_name}", null)
  type    = "A"
  ttl     = 300
  records = [local.public_ip]
}
resource "null_resource" "firehawk_init_dependency" { # ensure that the firehawk gateway has finished being prrovisioned because the next process may interupt its network connection
  triggers = {
    firehawk_init_dependency = var.firehawk_init_dependency
  }
}

# route tables to send traffic to the remote subnet are configured once the vpn is provisioned.
resource "aws_route" "private_openvpn_remote_subnet_gateway" {
  count      = var.create_vpn ? length(var.private_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(var.private_route_table_ids, count.index)
  destination_cidr_block = var.onsite_private_subnet_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_gateway" {
  count      = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(var.public_route_table_ids, count.index)
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

  route_table_id         = element(var.private_route_table_ids, count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_openvpn_remote_subnet_vpndhcp_gateway" {
  count      = var.create_vpn ? length(var.public_route_table_ids) : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  route_table_id         = element(var.public_route_table_ids, count.index)
  destination_cidr_block = var.vpn_cidr
  instance_id            = local.id

  timeouts {
    create = "5m"
  }
}

resource "null_resource" "sqs_notify" {
  count      = ( var.create_vpn && (var.sqs_remote_in_vpn != null) ) ? 1 : 0
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      printf "\n...Waiting for consul vpn service before attempting SQS notify.\n\n"
      until consul catalog services | grep -m 1 "vpn"; do sleep 10 ; done

      # This might need to run after ssh auth generation instead.
      scripts/sqs_notify.sh "${local.resourcetier}" "${var.sqs_remote_in_vpn}" "${var.host1}" "${var.host2}"
EOT
  }
}