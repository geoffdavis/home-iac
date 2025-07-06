# IAM Policy Requirements for OpenTofu State Locking with DynamoDB

Your current IAM user `arn:aws:iam::078129923125:user/geoff-s3-admin` needs additional permissions to use DynamoDB for state locking.

## Required DynamoDB Permissions

Add the following permissions to your IAM user or create a new policy:

### Option 1: Minimal DynamoDB Permissions (Recommended)

This policy grants only the permissions needed for OpenTofu state locking:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "OpenTofuStateLocking",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DescribeTable",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:TagResource",
                "dynamodb:ListTagsOfResource"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-west-2:078129923125:table/opentofu-state-locks-home-iac"
            ]
        }
    ]
}
```

### Option 2: Broader DynamoDB Permissions

If you plan to manage multiple state files or environments:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "OpenTofuStateLockingBroad",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DescribeTable",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:ListTables",
                "dynamodb:TagResource",
                "dynamodb:ListTagsOfResource"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-west-2:078129923125:table/opentofu-state-locks-*",
                "arn:aws:dynamodb:us-west-2:078129923125:table/terraform-state-locks-*"
            ]
        }
    ]
}
```

## How to Apply These Permissions

### Via AWS Console:
1. Log into AWS Console with an admin account
2. Navigate to IAM → Users → geoff-s3-admin
3. Click "Add permissions" → "Create inline policy"
4. Choose JSON editor and paste one of the policies above
5. Name it something like "OpenTofuStateLocking"

### Via AWS CLI (requires admin credentials):
```bash
# Save the policy to a file
cat > dynamodb-state-lock-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "OpenTofuStateLocking",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DescribeTable",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:TagResource",
                "dynamodb:ListTagsOfResource"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-west-2:078129923125:table/opentofu-state-locks-home-iac"
            ]
        }
    ]
}
EOF

# Attach the policy to your user
aws iam put-user-policy \
  --user-name geoff-s3-admin \
  --policy-name OpenTofuStateLocking \
  --policy-document file://dynamodb-state-lock-policy.json
```

## After Adding Permissions

Once the permissions are added:

1. Uncomment the DynamoDB configuration in `environments/dev/state-backend.tf`
2. Uncomment the `dynamodb_table` line in `environments/dev/backend.tf`
3. Run `tofu apply` to create the DynamoDB table
4. Run `tofu init -reconfigure` to update the backend configuration

## Benefits of State Locking

- **Prevents concurrent modifications**: Only one person/process can modify state at a time
- **Automatic lock release**: Locks are automatically released when operations complete
- **Force unlock capability**: Can manually unlock if a process fails
- **Team collaboration**: Essential for teams working on the same infrastructure

## Current S3 Permissions

Your current IAM user already has the necessary S3 permissions for state storage. The complete set of permissions for OpenTofu state management includes:

### S3 Permissions (you already have these):
- `s3:ListBucket` on the state bucket
- `s3:GetObject` on the state file
- `s3:PutObject` on the state file

### DynamoDB Permissions (you need to add these):
- Listed in the policies above