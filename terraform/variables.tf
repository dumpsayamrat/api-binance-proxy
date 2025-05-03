variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-1"  # Singapore - good choice for accessing Binance APIs
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tf_state_bucket" {
  description = "S3 bucket for storing Terraform state"
  type        = string
  default     = "your-terraform-state-bucket"
}