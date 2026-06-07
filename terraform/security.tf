# ===== Sécurité de la plateforme (tâche 5) =====
data "aws_caller_identity" "current" {}

# --- KMS : clé de chiffrement gérée ---
resource "aws_kms_key" "main" {
  description             = "SecureAws - cle de chiffrement (S3, donnees clients)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags = { Name = "secureaws-kms" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/secureaws"
  target_key_id = aws_kms_key.main.key_id
}

# --- CloudTrail : journalisation de toutes les actions API ---
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "secureaws-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = { Name = "secureaws-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "secureaws-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.cloudtrail]
}

output "kms_key_arn" { value = aws_kms_key.main.arn }
