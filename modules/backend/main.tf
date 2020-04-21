resource "random_id" "id" {
  byte_length = 8
}

data "aws_arn" "files_bucket" {
  arn = var.files_bucket_arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${random_id.id.hex}-lambda.zip"
  source {
    content  = file("${path.module}/backend.js")
    filename = "backend.js"
  }
}

resource "aws_lambda_function" "signer_lambda" {
  function_name = "signer-${random_id.id.hex}-function"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "backend.handler"
  runtime = "nodejs12.x"
  role    = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      BUCKET    = data.aws_arn.files_bucket.resource
      PATH_PART = var.files_bucket_path
    }
  }
}

data "aws_iam_policy_document" "lambda_exec_role_policy" {
  statement {
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${var.files_bucket_arn}/*",
    ]
  }
  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${var.files_bucket_arn}/*",
    ]
  }
  statement {
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      var.files_bucket_arn,
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.signer_lambda.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "lambda_exec_role" {
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_exec_role_policy.json
}

resource "aws_iam_role" "lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
	  "Action": "sts:AssumeRole",
	  "Principal": {
			"Service": "lambda.amazonaws.com"
	  },
	  "Effect": "Allow"
	}
  ]
}
EOF
}

module "apigw" {
  source = "./modules/apigw"

  lambda_function = aws_lambda_function.signer_lambda
}
