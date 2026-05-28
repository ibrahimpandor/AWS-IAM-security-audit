# ============================================
# MISCONFIGURED IAM USER
# This is deliberately insecure — do not use
# in a real environment
# ============================================

resource "aws_iam_user" "dev_user" {
  name = "dev-user"

  tags = {
    Name        = "dev-user"
    Project     = var.project_name
    Security    = "misconfigured"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_policy" "wildcard_policy" {
  name        = "wildcard-everything-policy"
  description = "INTENTIONALLY MISCONFIGURED - wildcard permissions for audit demonstration"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DangerousWildcardAccess"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "dev_user_fixed" {
  user       = aws_iam_user.dev_user.name
  policy_arn = aws_iam_policy.wildcard_policy.arn
}

# ============================================
# MISCONFIGURED IAM ROLE
# Overly broad S3 access — should only access
# one specific bucket, not all S3 resources
# ============================================

resource "aws_iam_role" "dev_role" {
  name        = "dev-role"
  description = "INTENTIONALLY MISCONFIGURED - overly broad permissions for audit demonstration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2ToAssume"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "dev-role"
    Project   = var.project_name
    Security  = "misconfigured"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_policy" "overly_broad_s3" {
  name        = "overly-broad-s3-policy"
  description = "INTENTIONALLY MISCONFIGURED - grants access to all S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OverlyBroadS3Access"
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dev_role_fixed" {
  role       = aws_iam_role.dev_role.name
  policy_arn = aws_iam_policy.overly_broad_s3.arn
}

# ============================================
# IAM ACCESS ANALYZER
# Scans your account and detects resources
# accessible from outside your trust zone
# ============================================

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.project_name}-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name      = "${var.project_name}-analyzer"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ============================================
# AWS CONFIG
# Continuously monitors and records resource
# configurations and evaluates compliance
# ============================================

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_iam_role" "config_role" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "aws-config-role"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_s3_bucket" "config_bucket" {
  bucket = "${var.project_name}-config-logs-${var.account_id}"

  tags = {
    Name      = "config-logs"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigBucketAcl"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}"
      },
      {
        Sid    = "AllowConfigDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}/AWSLogs/${var.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.config_bucket]
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

# Config rule — detects IAM users without MFA
resource "aws_config_config_rule" "mfa_enabled" {
  name = "iam-user-mfa-enabled"

  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Config rule — detects wildcard IAM policies
resource "aws_config_config_rule" "no_wildcards" {
  name = "iam-policy-no-statements-with-admin-access"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# ============================================
# FIXED POLICIES — LEAST PRIVILEGE
# These are the corrected versions of the
# misconfigured policies above
# You will apply these after running the audit
# ============================================

resource "aws_iam_policy" "least_privilege_dev" {
  name        = "least-privilege-dev-policy"
  description = "FIXED - least privilege policy replacing wildcard"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ReadOnlySpecificBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}",
          "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}/*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:*"
      }
    ]
  })
}

resource "aws_iam_policy" "least_privilege_s3_role" {
  name        = "least-privilege-s3-role-policy"
  description = "FIXED - scoped S3 access replacing overly broad policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadOnlySpecificBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}",
          "arn:aws:s3:::${var.project_name}-config-logs-${var.account_id}/*"
        ]
      }
    ]
  })
}

# ============================================
# OUTPUTS
# Prints key information after terraform apply
# ============================================

output "dev_user_arn" {
  description = "ARN of the misconfigured dev user"
  value       = aws_iam_user.dev_user.arn
}

output "dev_role_arn" {
  description = "ARN of the misconfigured dev role"
  value       = aws_iam_role.dev_role.arn
}

output "wildcard_policy_arn" {
  description = "ARN of the wildcard policy - the misconfiguration"
  value       = aws_iam_policy.wildcard_policy.arn
}

output "access_analyzer_arn" {
  description = "ARN of the Access Analyzer"
  value       = aws_accessanalyzer_analyzer.main.arn
}

output "config_bucket" {
  description = "S3 bucket storing Config logs"
  value       = aws_s3_bucket.config_bucket.id
}

output "least_privilege_dev_arn" {
  description = "ARN of the fixed least privilege policy for dev user"
  value       = aws_iam_policy.least_privilege_dev.arn
}

output "least_privilege_role_arn" {
  description = "ARN of the fixed least privilege policy for dev role"
  value       = aws_iam_policy.least_privilege_s3_role.arn
}