# Define provider
provider "aws" {
  region = "eu-west-1"
}

#s3 acl
resource "aws_s3_bucket_public_access_block" "bucket" {
  for_each = var.markets
  bucket   = aws_s3_bucket.bucket[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#s3 policy
resource "aws_s3_bucket_policy" "bucket" {
  for_each   = var.markets
  depends_on = [aws_s3_bucket_public_access_block.bucket]
  bucket     = aws_s3_bucket.bucket[each.key].id
  policy     = data.aws_iam_policy_document.s3_policy[each.key].json
}

#iam policy
data "aws_iam_policy_document" "s3_policy" {
  for_each = var.markets
  statement {
    actions   = ["s3:GetObject"]
    effect    = "Allow"
    resources = ["${aws_s3_bucket.bucket[each.key].arn}/*"]
    principals {
      #TODO: update to AWS with iam_arn
      type        = "CanonicalUser"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity[each.key].s3_canonical_user_id]
    }
  }
}

resource "aws_iam_role" "lambda_edge_exec" {
  for_each           = var.markets
  name               = "lambda-execution-role-${var.env}-${each.value.domain_prefix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

#cloudfront identity
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  for_each = var.markets
  comment  = "${each.value.domain_prefix}.${var.domain}.s3.amazonaws.com"
}

#DNS A
resource "aws_route53_record" "A_record" {
  for_each = var.markets
  zone_id  = var.hosted_zone_id
  name     = "${each.value.domain_prefix}.${var.domain}"
  type     = "A"
  alias {
    name                   = aws_cloudfront_distribution.iqos-connect-web[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.iqos-connect-web[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

#DNS AAAA
resource "aws_route53_record" "AAAA_record" {
  for_each = var.markets
  zone_id  = var.hosted_zone_id
  name     = "${each.value.domain_prefix}.${var.domain}"
  type     = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.iqos-connect-web[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.iqos-connect-web[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

#certificate region
data "aws_acm_certificate" "domain" {
  for_each = var.markets
  domain   = var.is_wildcard_certificate ? "*.${var.domain}" : "${each.value.domain_prefix}.${var.domain}"
  statuses = ["ISSUED"]
  provider = aws.virginia
}

#certificate
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

#24.06.2022. to remove in next version of deploy. Cant't be removed before prod deploy. Error will be given
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

#lambda zip
data "archive_file" "hsts_lambda_zip" {
  for_each    = var.markets
  type        = "zip"
  source_dir  = "./../../../../lambdas/hsts-header"
  output_path = "lambda-archives/hsts-lambda-${each.value.domain_prefix}.zip"
}

data "archive_file" "auth_lambda_zip" {
  for_each    = var.markets
  type        = "zip"
  source_dir  = "./../../../../lambdas/auth-check"
  output_path = "lambda-archives/auth-lambda-${each.value.domain_prefix}.zip"
}

#lambda origin-response
resource "aws_lambda_function" "hsts-lambda" {
  for_each         = var.markets
  function_name    = "iqweb-headers-${var.env}-${each.value.domain_prefix}"
  role             = aws_iam_role.lambda_edge_exec[each.key].arn
  handler          = "origin-response.handler"
  filename         = data.archive_file.hsts_lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.hsts_lambda_zip[each.key].output_base64sha256
  runtime          = "nodejs14.x"
  publish          = "true"
  provider         = aws.virginia
}

#lambda auth
resource "aws_lambda_function" "auth_lambda" {
  for_each         = local.web_markets
  function_name    = "iqweb-auth-${var.env}-${each.value.domain_prefix}"
  role             = aws_iam_role.lambda_edge_exec[each.key].arn
  handler          = "auth.handler"
  filename         = data.archive_file.auth_lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.auth_lambda_zip[each.key].output_base64sha256
  runtime          = "nodejs14.x"
  publish          = "true"
  provider         = aws.virginia
}

#cloudfront
resource "aws_cloudfront_distribution" "iqos-connect-web" {
  for_each            = var.markets
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"
  default_root_object = each.value.is_ref == false ? "index.html" : null

  origin {
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity[each.key].cloudfront_access_identity_path
    }

    domain_name = "${each.value.domain_prefix}.${var.domain}.s3.amazonaws.com"
    origin_id   = "S3-${each.value.domain_prefix}.${var.domain}"
  }

  aliases = ["${each.value.domain_prefix}.${var.domain}"]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    default_ttl            = 86400
    max_ttl                = 31536000
    min_ttl                = 0
    target_origin_id       = "S3-${each.value.domain_prefix}.${var.domain}"
    trusted_signers        = []
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      headers                 = []
      query_string            = false
      query_string_cache_keys = []

      cookies {
        forward           = "none"
        whitelisted_names = []
      }
    }

    //lambda_function_association can't be deleted with terraform. Only with aws console.
    lambda_function_association {
      event_type   = "origin-response"
      include_body = false
      lambda_arn   = aws_lambda_function.hsts-lambda[each.key].qualified_arn
    }

    //lambda_function_association can't be deleted with terraform. Only with aws console.
    dynamic "lambda_function_association" {
      for_each = each.value.is_ref == false ? [0] : []
      content {
        event_type   = "viewer-request"
        include_body = false
        lambda_arn   = aws_lambda_function.auth_lambda[each.key].qualified_arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  dynamic "custom_error_response" {
    for_each = each.value.is_ref == false ? [0] : []
    content {
      error_caching_min_ttl = 300
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
    }
  }

  dynamic "custom_error_response" {
    for_each = each.value.is_ref == false ? [0] : []
    content {
      error_caching_min_ttl = 300
      error_code            = 504
      response_code         = 200
      response_page_path    = "/index.html"
    }

  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.domain[each.key].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
}

#bucket
resource "aws_s3_bucket" "bucket" {
  for_each      = var.markets
  bucket        = "${each.value.domain_prefix}.${var.domain}"
  acl           = "private"
  force_destroy = true

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["Content-Disposition", "Content-Type"]
    max_age_seconds = 3000
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  website {
    error_document = each.value.is_ref == false ? "index.html" : null
    index_document = "index.html"
  }
}
