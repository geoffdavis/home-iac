# GitHub Actions OIDC federation for CI-driven OpenTofu runs (Digger).
#
# Lets .github/workflows/digger_workflow.yml assume an AWS role via
# short-lived, per-run credentials instead of long-lived static keys
# stored as repo secrets.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # thumbprint_list is required by the resource schema but unused for
  # verification: AWS has validated GitHub's OIDC endpoint against its
  # trusted CA bundle (not this thumbprint) since July 2023.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
  ]

  tags = merge(local.common_tags, { Purpose = "github-actions-oidc" })
}

resource "aws_iam_role" "github_actions_digger" {
  name        = "github-actions-home-iac-digger"
  description = "Assumed by digger_workflow.yml via GitHub OIDC to run OpenTofu against this repo's AWS resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Any ref/PR/workflow within this repo may assume the role.
          # Tighten to e.g. "repo:geoffdavis/home-iac:ref:refs/heads/main"
          # (plus a separate plan-only role for PR branches) if you want
          # apply and plan to carry different blast radii.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:geoffdavis/home-iac:*"
          }
        }
      }
    ]
  })

  max_session_duration = 3600

  tags = merge(local.common_tags, { Purpose = "github-actions-oidc" })
}

# Scoped to exactly the resources this environment currently manages.
# Extend the resource lists here as new aws_s3_bucket / aws_iam_user /
# aws_iam_policy resources are added under environments/home.
resource "aws_iam_role_policy" "github_actions_digger" {
  name = "home-iac-terraform-management"
  role = aws_iam_role.github_actions_digger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*",
        ]
      },
      {
        Sid      = "TerraformStateLockTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      {
        Sid    = "ManagedS3Buckets"
        Effect = "Allow"
        Action = "s3:*"
        Resource = concat(
          values(module.s3_buckets.bucket_arns),
          [for arn in values(module.s3_buckets.bucket_arns) : "${arn}/*"],
        )
      },
      {
        Sid    = "ManagedIamUserAndPolicy"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:ListUserTags",
          "iam:ListAttachedUserPolicies",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:DeletePolicy",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = [
          aws_iam_user.home_assistant_backup.arn,
          aws_iam_policy.home_assistant_backup_s3_access.arn,
          # Orphaned resources (tracked in state, no longer declared in
          # config anywhere) -- confirmed safe to destroy 2026-08-27.
          # Remove this pair of ARNs once the destroy has landed and
          # they're gone from state.
          "arn:aws:iam::078129923125:user/longhorn-backup-user",
          "arn:aws:iam::078129923125:policy/longhorn-backup-s3-access",
        ]
      },
      {
        # Self-management: this role reads/updates its own role, inline
        # policy, and the OIDC provider it trusts. Missed in the initial
        # policy -- every `tofu plan` refreshes these along with
        # everything else this environment manages.
        Sid    = "ManagedOwnRoleAndOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags",
        ]
        Resource = [
          aws_iam_role.github_actions_digger.arn,
          aws_iam_openid_connect_provider.github_actions.arn,
        ]
      },
      {
        # Same orphaned-bucket cleanup as above, for the S3 side.
        Sid    = "OrphanedLonghornBucket"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::longhorn-backups-home-ops",
          "arn:aws:s3:::longhorn-backups-home-ops/*",
        ]
      },
    ]
  })
}

output "github_actions_digger_role_arn" {
  description = "Role ARN for digger_workflow.yml's aws-role-to-assume input (set as a repo Actions VARIABLE, not a secret — it isn't sensitive)"
  value       = aws_iam_role.github_actions_digger.arn
}
