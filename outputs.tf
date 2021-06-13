output "id" {
  value      = local.id
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
}

output "private_ip" {
  value      = local.private_ip
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
}

output "public_ip" {
  value      = local.public_ip
  depends_on = [local.public_ip, aws_route53_record.openvpn_record]
}