# Reuses a Route53 public hosted zone you already own. Set `domain_name`
# in terraform.tfvars. The ingress annotates ExternalDNS with the full FQDN;
# ExternalDNS creates the A record pointing at the ALB.
data "aws_route53_zone" "apex" {
  name         = var.domain_name
  private_zone = false
}
