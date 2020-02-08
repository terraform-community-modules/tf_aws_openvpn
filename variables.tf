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

variable "remote_subnet_cidr" {
}

variable "public_subnet_ids" {
  default = []
}

variable "cert_arn" {
}

variable "key_name" {
}

variable "bastion_ip" {
}

variable "private_key" {
}

variable "local_key_path" {
}

variable "ami" {
}

variable "instance_type" {
}

variable "openvpn_user" {
}

variable "openvpn_user_pw" {
}

variable "openvpn_admin_user" {
}

variable "openvpn_admin_pw" {
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

variable "bastion_dependency" {}

variable "private_route_table_ids" {}
variable "public_route_table_ids" {}