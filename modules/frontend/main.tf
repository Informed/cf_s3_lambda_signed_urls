resource "aws_s3_bucket" "frontend_bucket" {
  force_destroy = "true"
}

locals {
  mime_type_mappings = {
    html = "text/html",
    js   = "text/javacript",
    css  = "text/css"
  }
}

resource "aws_s3_bucket_object" "frontend_object" {
  for_each = fileset("${path.module}/static_files", "*")

  key          = each.value
  source       = "${path.module}/static_files/${each.value}"
  bucket       = aws_s3_bucket.frontend_bucket.bucket
  etag         = filemd5("${path.module}/static_files/${each.value}")
  content_type = local.mime_type_mappings[concat(regexall("\\.([^\\.]*)$", each.value), [[""]])[0][0]]
}

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.frontend_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [var.OAI_iam_arn]
    }
  }
}

