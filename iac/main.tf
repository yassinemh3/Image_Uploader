provider "aws" {
  region = var.region
}

##########################
#  A)  LOCAL BUILD STEP  #
##########################

# 1.  Ensure node_modules are present (idempotent)
resource "null_resource" "npm_install" {
  # rerun if lock-file OR any JS changes
  triggers = {
    package_lock_hash = filesha256("${path.module}/../package-lock.json")
    app_hash          = filesha256("${path.module}/../app.js")
    handler_hash      = filesha256("${path.module}/../handler.js")
  }

  provisioner "local-exec" {
    command     = "npm ci --omit=dev"
    working_dir = "${path.module}/.."
  }
}

# 2.  Zip everything that must land in Lambda
data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.npm_install]                  # wait for npm

  type        = "zip"
  source_dir  = "${path.module}/.."                          # project root
  output_path = "${path.module}/lambda.zip"

  # keep code + views + assets but exclude terraform & virtual-env etc.
  excludes = [
    ".git/*", ".gitignore",
    ".venv/*",
    "iac/*",
    "lambda.zip",
    "*.md"
  ]
}


resource "random_id" "rand" {
  byte_length = 4
}

# S3 Bucket for Images
resource "aws_s3_bucket" "image_storage" {
  bucket        = "fastapi-image-storage-${random_id.rand.hex}"
  force_destroy = true
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "fastapi_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Sid       = ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "lambda-s3-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
      Resource = [
        aws_s3_bucket.image_storage.arn,
        "${aws_s3_bucket.image_storage.arn}/*"
      ]
    }]
  })
}

# Lambda Function
resource "aws_lambda_function" "backend" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "handler.handler"
  runtime       = "nodejs18.x"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256


  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.image_storage.bucket
    }
  }
}

# REST API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "fastapi-rest"
  binary_media_types = ["*/*"]
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}



resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

# Root-Methode
resource "aws_api_gateway_method" "root_any" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = aws_api_gateway_method.root_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.backend.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.backend.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
    depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.root_integration   # ← neu
  ]
}

# Stage (separat)
resource "aws_api_gateway_stage" "stage" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name = "prod"
}
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# WAF IP Restriction
resource "aws_wafv2_ip_set" "allowlist" {
  name               = "whitelist-ip"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist
}

resource "aws_wafv2_web_acl" "web_acl" {
  name        = "ip-allow-web-acl"
  scope       = "REGIONAL"
  description = "Allow only specific IPs"

  default_action {
    block {}
  }

  rule {
    name     = "AllowSpecificIP"
    priority = 0
    action {
      allow {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.allowlist.arn
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowSpecificIP"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "webACL"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "associate_waf" {
  resource_arn = aws_api_gateway_stage.stage.arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.image_storage.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_read" {
  depends_on = [aws_s3_bucket_public_access_block.example]

  bucket = aws_s3_bucket.image_storage.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.image_storage.arn}/*"
      }
    ]
  })
}
