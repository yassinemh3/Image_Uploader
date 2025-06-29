variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "fastapi-backend"
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function"
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function"
  type        = number
  default     = 512
}


variable "frontend_index_document" {
  description = "Index document for S3 website"
  type        = string
  default     = "index.html"
}

variable "ip_allowlist" {
  description = "List of allowed IPv4 addresses"
  type        = list(string)
}

