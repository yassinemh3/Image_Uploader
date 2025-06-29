
output "api_gateway_url" {
  description = "Invoke URL of the REST API"
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/prod"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.image_storage.bucket
  description = "Name of the S3 bucket for image storage"
}