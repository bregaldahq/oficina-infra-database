# ---------------------------------------------------------------------------
# Private connectivity to Secrets Manager.
#
# ADR-010 removed the NAT gateway to save ~US$33/month. The consequence, which
# only surfaced at runtime: the private subnets have no route out of the VPC at
# all. The auth Lambda runs in them and reaches RDS fine (it is internal), but
# Secrets Manager is a PUBLIC AWS endpoint — the call left the ENI, found no
# route and hung until the 15s Lambda timeout, with no error to show for it.
#
# An interface endpoint puts Secrets Manager inside the VPC. It costs about
# US$7.20/month per AZ — still far cheaper than a NAT gateway, and it exposes
# exactly one service instead of the whole internet.
#
# Set vpc_endpoint_single_az = true to halve the cost in non-critical
# environments, at the price of losing AZ redundancy for the endpoint.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "Interface VPC endpoints. Accepts 443 only from db clients."
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-vpce-sg" }
}

# Same "badge" pattern used for the database: whoever carries the db_client SG
# is allowed in. The Lambda already carries it.
resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = aws_security_group.db_client.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS from workloads carrying the db-client SG"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = var.vpc_endpoint_single_az ? [aws_subnet.private[0].id] : aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = { Name = "${local.name_prefix}-secretsmanager-vpce" }
}
