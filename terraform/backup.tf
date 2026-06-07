# ===== AWS Backup (tâche 5 - sauvegardes) =====
resource "aws_backup_vault" "main" {
  name        = "secureaws-backup-vault"
  kms_key_arn = aws_kms_key.main.arn
  tags        = { Name = "secureaws-backup-vault" }
}

resource "aws_backup_plan" "main" {
  name = "secureaws-backup-plan"
  rule {
    rule_name         = "sauvegarde-quotidienne"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)" # tous les jours à 03:00 UTC
    lifecycle {
      delete_after = 30
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "secureaws-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Sauvegarde toutes les ressources taggées Project = secure-multitenant-aws-platform
resource "aws_backup_selection" "main" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "secureaws-selection"
  plan_id      = aws_backup_plan.main.id
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = "secure-multitenant-aws-platform"
  }
}
