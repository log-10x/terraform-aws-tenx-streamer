# IAM Role for Service Account (IRSA)
# This role allows Kubernetes service accounts to assume AWS permissions
resource "aws_iam_role" "tenx_streamer" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# IAM Policy with S3 and SQS permissions
# Permissions are based on actual AWS operations performed by the application
# (analyzed from AWSIndexAccess.java and SqsConsumer.java)
resource "aws_iam_role_policy" "tenx_streamer" {
  role = aws_iam_role.tenx_streamer.id
  name = "tenx-streamer-permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # S3 Input Bucket - Read-only access
      # Used by: AWSIndexAccess.readObject() for reading source log files
      [
        {
          Sid    = "S3InputBucketRead"
          Effect = "Allow"
          Action = [
            "s3:GetObject"
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_streamer_infra.index_source_bucket_name}/*"
          ]
        }
      ],
      # S3 Index Bucket - List bucket access
      # Used by: AWSIndexAccess.iterateIndexObjects() for listing index files
      [
        {
          Sid    = "S3IndexBucketList"
          Effect = "Allow"
          Action = [
            "s3:ListBucket"
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_streamer_infra.index_results_bucket_name}"
          ]
        }
      ],
      # S3 Index Bucket - Object-level access
      # Used by: AWSIndexAccess for reading, writing, and deleting index objects
      [
        {
          Sid    = "S3IndexBucketObjectAccess"
          Effect = "Allow"
          Action = [
            "s3:GetObject",   # Read existing index files
            "s3:PutObject",   # Write new index files
            "s3:DeleteObject" # Remove obsolete index files
          ]
          Resource = [
            "arn:aws:s3:::${module.tenx_streamer_infra.index_results_bucket_name}/*"
          ]
        }
      ],
      # SQS All Queues - Full message access
      # Used by: SqsConsumer for polling and processing messages
      [
        {
          Sid    = "SQSQueueAccess"
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",    # Poll for messages
            "sqs:DeleteMessage",     # Remove processed messages
            "sqs:SendMessage",       # Send messages (for pipeline invocation)
            "sqs:GetQueueAttributes" # Get queue metadata
          ]
          Resource = [
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.index_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.query_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.subquery_queue_name}",
            "arn:aws:sqs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${local.stream_queue_name}"
          ]
        }
      ],
      # Additional custom policies provided by user
      [
        for policy in var.additional_iam_policies : {
          Sid      = try(policy.sid, null)
          Effect   = policy.effect
          Action   = policy.actions
          Resource = policy.resources
        }
      ]
    )
  })
}
