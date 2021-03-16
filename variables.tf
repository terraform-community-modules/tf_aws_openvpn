variable "resourcetier" {
    description = "The resource tier speicifies a unique name for a resource based on the environment.  eg:  dev, green, blue, main."
    type = string
}

variable "pipelineid" {
    description = "The pipelineid variable can be used to uniquely specify and identify resource names for a given deployment.  The pipeline ID could be set to a job ID in CI software for example.  The default of 0 is fine if no more than one concurrent deployment run will occur."
    type = string
    default = "0"
}

variable "conflictkey" {
    description = "The conflictkey is a unique name for each deployement usuallly consisting of the resourcetier and the pipeid."
    type = string
}
variable "example_role_name" {
  description = "The name of the vault role. (Note: This is not the AWS role name.)"
  type        = string
  default     = "example-role"
}
variable "consul_cluster_name" {
  description = "What to name the Consul server cluster and all of its associated resources"
  type        = string
  # default     = "consul-example"
}

variable "consul_cluster_tag_key" {
  description = "The tag the Consul EC2 Instances will look for to automatically discover each other and form a cluster."
  type        = string
  default     = "consul-servers"
}
variable "name" {
  default = "openvpn"
  type = string
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

# variable "openvpn_user_pw" {
#   description = "The user password used to login to Open VPN Access Server."
#   type = string
#   validation {
#     condition = (
#       length(var.openvpn_user_pw) >= 8
#     )
#     error_message = "The openvpn_user_pw configured in vault must be at least 8 characters in length."
#   }
# }

variable "openvpn_admin_user" {
  description = "The admin user name used to configure OpenVPN Access Server"
  default = "openvpnas"
}

# variable "openvpn_admin_pw" {
#   description = "The admin password used to login to Open VPN Access Server."
#   type = string
#   validation {
#     condition = (
#       length(var.openvpn_admin_pw) >= 8
#     )
#     error_message = "The openvpn_admin_pw configured in vault must be at least 8 characters in length."
#   }
# }

variable "use_eip" {
  description = "Allows the provisioning of an elsatice IP"
  type = bool
  default = false
}

variable "vpn_cidr" {
  description = "The CIDR range that the vpn will assign using DHCP.  These are virtual addresses for routing traffic."
  type        = string
}

variable "onsite_private_subnet_cidr" {
  description = "The subnet CIDR Range of your onsite private subnet. This is also the subnet where your VPN client resides in. eg: 192.168.1.0/24"
  type        = string
}

variable "public_domain_name" {
  description = "(Optional) The public domain if required for DNS names of hosts eg: vpn.example.com"
  type        = string
  default     = null
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

variable "iam_instance_profile_name" {
  description = "The name of the instance profile to attach to the VPN"
  type = string
}
# variable "bucket_extension_vault" {
#     description = "The bucket extension where the terraform remote state resides"
#     type = string
# }
# variable "resourcetier_vault" {
#     description = "The resourcetier the desired vault vpc resides in"
#     type = string
# }
# variable "vpcname_vault" {
#     description = "A namespace component defining the location of the terraform remote state"
#     type = string
# }