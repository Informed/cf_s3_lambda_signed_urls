provider "aws" {
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_cloudfront_origin_access_identity" "OAI" {
}

module "frontend" {
  source = "./modules/frontend"

  OAI_iam_arn = aws_cloudfront_origin_access_identity.OAI.iam_arn
}

resource "aws_s3_bucket" "files_bucket" {
  force_destroy = "true"
}

module "api" {
  source = "./modules/backend"

  files_bucket_arn  = aws_s3_bucket.files_bucket.arn
  files_bucket_path = "files"
}

# lambda@edge

resource "random_id" "id" {
  byte_length = 8
}

data "archive_file" "lambda_edge_zip" {
  type        = "zip"
  output_path = "/tmp/${random_id.id.hex}-lambda_edge.zip"
  source {
    content  = <<EOF
module.exports.handler = async (event) => {
	const request = event.Records[0].cf.request;
	request.uri = request.uri.replace(/^\/[^\/]*/, "");
	return request;
};
EOF
    filename = "main.js"
  }
}

resource "aws_lambda_function" "lambda_edge" {
  function_name = "${random_id.id.hex}-edge-function"

  filename         = data.archive_file.lambda_edge_zip.output_path
  source_code_hash = data.archive_file.lambda_edge_zip.output_base64sha256

  handler = "main.handler"
  runtime = "nodejs12.x"
  role    = aws_iam_role.lambda_edge_exec.arn

  provider = aws.us_east_1
  publish  = true
}

resource "aws_iam_role" "lambda_edge_exec" {
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

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = module.frontend.bucket_regional_domain_name
    origin_id   = "frontend"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.OAI.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = replace(module.api.invoke_url, "/^https?://([^/]*).*/", "$1")
    origin_id   = "api"
    origin_path = replace(module.api.invoke_url, "/^https?://[^/]*(/.*)$/", "$1")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  origin {
    domain_name = aws_s3_bucket.files_bucket.bucket_regional_domain_name
    origin_id   = "files_bucket"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "frontend"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
    viewer_protocol_policy = "https-only"

    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = aws_lambda_function.lambda_edge.qualified_arn
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/files/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "files_bucket"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only"

    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = aws_lambda_function.lambda_edge.qualified_arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "domain_name" {
  value = aws_cloudfront_distribution.distribution.domain_name
}
