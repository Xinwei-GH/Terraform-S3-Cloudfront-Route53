locals {
  name_prefix    = "xinweis3"
  s3_origin_id   = "xinweis3S3Origin"
  cloudfront_oac = "xinweis3OAC"
}

# Create S3 Bucket
resource "aws_s3_bucket" "static_bucket" {
  bucket        = "${local.name_prefix}.sctp-sandbox.com"
  force_destroy = true
}

# Create a new CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "xinweis3_oac" {
  name                              = local.cloudfront_oac
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Bucket Policy to Allow Access from CloudFront OAC
resource "aws_s3_bucket_policy" "static_bucket_policy" {
  bucket = aws_s3_bucket.static_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}

# Fetch Managed Cache Policy
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_acm_certificate" "xinweis3_cert" {
  provider          = aws.us_east_1
  domain_name       = "${local.name_prefix}.sctp-sandbox.com"
  validation_method = "DNS"
  key_algorithm     = "RSA_2048"

  tags = {
    Name = "Xinwei S3 Certificate"
  }
}

# DNS Validation Record for ACM Certificate
data "aws_route53_zone" "sctp_zone" {
  name = "sctp-sandbox.com"
}

resource "aws_route53_record" "xinweis3_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.xinweis3_cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 300
}

# Validate ACM Certificate
resource "aws_acm_certificate_validation" "xinweis3_cert_validation" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.xinweis3_cert.arn
  validation_record_fqdns = []
}

# Create CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.static_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.xinweis3_oac.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Xinwei S3 Static via CloudFront"
  default_root_object = "index.html"

  aliases = ["${local.name_prefix}.sctp-sandbox.com"]

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id         = data.aws_cloudfront_cache_policy.caching_optimized.id


    compress = true
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.xinweis3_cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  http_version = "http2"

  tags = {
    Environment = "production"
  }
}

# Route 53 Record for CloudFront
resource "aws_route53_record" "cloudfront_alias" {
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = local.name_prefix
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}