# Public ACM cert for the game subdomain, DNS-validated via the existing zone.
# The AWS Load Balancer Controller auto-discovers this certificate from the
# Ingress annotation on `alb.ingress.kubernetes.io/certificate-arn` (we output
# its ARN for use in Kustomize).

resource "aws_acm_certificate" "game" {
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "game_validation" {
  for_each = {
    for dvo in aws_acm_certificate.game.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.apex.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "game" {
  certificate_arn         = aws_acm_certificate.game.arn
  validation_record_fqdns = [for r in aws_route53_record.game_validation : r.fqdn]
}
