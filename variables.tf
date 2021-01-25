variable "example_role_name" {
  description = "The name of the vault role"
  type        = string
  default     = "example-role"
}
variable "consul_cluster_name" {
  description = "What to name the Consul server cluster and all of its associated resources"
  type        = string
  default     = "consul-example"
}

variable "consul_cluster_tag_key" {
  description = "The tag the Consul EC2 Instances will look for to automatically discover each other and form a cluster."
  type        = string
  default     = "consul-servers"
}
variable "name" {
  default = "openvpn"
}

variable "create_vpn" {}

variable "vpc_id" {
}

variable "vpc_cidr" {
}

variable "remote_vpn_ip_cidr" {
  default = "0.0.0.0/0"
}

variable "remote_ssh_ip_cidr" {
  description = "The IP used to ssh to the access server for admin."
}

variable "remote_subnet_cidr" {
}

variable "public_subnet_ids" {
  default = []
}

# variable "cert_arn" {
# }

variable "aws_key_name" {
}

variable "use_bastion" {
  description = "If enabled, will open ssh ports to a bastion host for provisioning.  This shouldn't be required if provisioning via private subnet."
  type = bool
  default = false
}

variable "bastion_ip" {
  description = "The IP address of the bastion for access"
  type = string
  default = "none"
}

# variable "private_key" {
# }

# variable "aws_private_key_path" {
# }

variable "instance_type" {
}

variable "openvpn_user" {
}

variable "openvpn_user_pw" {
  description = "The user password used to login to Open VPN Access Server."
  type = string
  validation {
    condition = (
      length(var.openvpn_user_pw) >= 8
    )
    error_message = "The openvpn_user_pw configured in vault must be at least 8 characters in length."
  }
}

variable "openvpn_admin_user" {
  description = "The admin user name used to configure OpenVPN Access Server"
  default = "openvpnas"
}

variable "openvpn_admin_pw" {
  description = "The admin password used to login to Open VPN Access Server."
  type = string
  validation {
    condition = (
      length(var.openvpn_admin_pw) >= 8
    )
    error_message = "The openvpn_admin_pw configured in vault must be at least 8 characters in length."
  }
}

variable "vpn_cidr" {
}

variable "public_domain_name" {
}

variable "route_zone_id" {
}

variable "sleep" {
  default = false
}

variable "igw_id" {
}

variable "private_subnets" {
  default = []
}

variable "public_subnets" {
  default = []
}

variable "bastion_dependency" {
  default = "None"
}

variable "firehawk_init_dependency" {
  default = "None"
}

variable "private_route_table_ids" {}
variable "public_route_table_ids" {}

variable "private_domain_name" {}

variable "ami" {}