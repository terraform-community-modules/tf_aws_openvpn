variable "name"               { default = "openvpn" }
variable "vpc_id"             { }
variable "vpc_cidr"           { }
variable "public_subnet_ids"  { type = "list" }
variable "cert_arn"           { }
variable "key_name"           { }
variable "private_key"        { }
variable "ami"                { }
variable "instance_type"      { }
variable "openvpn_user"       { }
variable "openvpn_admin_user" { }
variable "openvpn_admin_pw"   { }
variable "vpn_cidr"           { }
variable "sub_domain"         { }
variable "route_zone_id"      { }
