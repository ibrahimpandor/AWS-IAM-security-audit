variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "The name of this project"
  type        = string
  default     = "aws-iam-security-audit"
}

variable "account_id" {
  description = "Your AWS account ID"
  type        = string
  default     = "532025488915"
}