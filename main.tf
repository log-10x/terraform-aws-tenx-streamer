# Local variables for resource naming and configuration
locals {
  # Merge tags with module defaults
  tags = merge(
    var.tags,
    {
      terraform-module         = "tenx-streamer"
      terraform-module-version = "v0.5.2"
      managed-by               = "terraform"
    }
  )

  # Use resource prefix for generated resource names
  resource_prefix = var.resource_prefix

  # Generate S3 bucket names with defaults
  index_source_bucket_name = coalesce(
    var.tenx_streamer_index_source_bucket_name,
    "${local.resource_prefix}-${data.aws_caller_identity.current.account_id}"
  )

  index_results_bucket_name = coalesce(
    var.tenx_streamer_index_results_bucket_name,
    local.index_source_bucket_name # Default to same bucket
  )

  # Generate SQS queue names with defaults
  index_queue_name = coalesce(
    var.tenx_streamer_index_queue_name,
    "${local.resource_prefix}-index-queue"
  )

  query_queue_name = coalesce(
    var.tenx_streamer_query_queue_name,
    "${local.resource_prefix}-query-queue"
  )

  subquery_queue_name = coalesce(
    var.tenx_streamer_subquery_queue_name,
    "${local.resource_prefix}-subquery-queue"
  )

  stream_queue_name = coalesce(
    var.tenx_streamer_stream_queue_name,
    "${local.resource_prefix}-stream-queue"
  )

  # Generate Kubernetes service account name
  service_account_name = coalesce(
    var.service_account_name,
    var.helm_release_name
  )

  # Generate IAM role name
  iam_role_name = coalesce(
    var.iam_role_name,
    "${local.resource_prefix}-irsa"
  )

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  # Passed in from parent module
  oidc_provider     = var.oidc_provider
  oidc_provider_arn = var.oidc_provider_arn
}

###########################################
# Data Sources
###########################################

# Get current AWS region and account information
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

###########################################
# Infrastructure (SQS Queues and S3 Buckets)
###########################################

# Provision infrastructure (SQS queues and S3 buckets)
module "tenx_streamer_infra" {
  source  = "log-10x/tenx-streamer-infra/aws"
  version = ">= 0.3.2"

  # SQS Queue names
  tenx_streamer_index_queue_name    = local.index_queue_name
  tenx_streamer_query_queue_name    = local.query_queue_name
  tenx_streamer_subquery_queue_name = local.subquery_queue_name
  tenx_streamer_stream_queue_name   = local.stream_queue_name

  # SQS Queue configuration
  tenx_streamer_queue_message_retention  = var.tenx_streamer_queue_message_retention
  tenx_streamer_queue_visibility_timeout = var.tenx_streamer_queue_visibility_timeout
  tenx_streamer_queue_max_message_size   = var.tenx_streamer_queue_max_message_size
  tenx_streamer_queue_delay_seconds      = var.tenx_streamer_queue_delay_seconds
  tenx_streamer_queue_receive_wait_time  = var.tenx_streamer_queue_receive_wait_time

  # S3 Bucket configuration
  tenx_streamer_create_index_source_bucket  = var.create_s3_buckets
  tenx_streamer_index_source_bucket_name    = local.index_source_bucket_name
  tenx_streamer_create_index_results_bucket = var.create_s3_buckets
  tenx_streamer_index_results_bucket_name   = local.index_results_bucket_name
  tenx_streamer_index_results_path          = var.tenx_streamer_index_results_path

  # S3 trigger configuration
  tenx_streamer_index_trigger_prefix = var.tenx_streamer_index_trigger_prefix
  tenx_streamer_index_trigger_suffix = var.tenx_streamer_index_trigger_suffix

  tenx_streamer_user_supplied_tags = local.tags
}

###########################################
# Kubernetes Resources
###########################################

# Optionally create the Kubernetes namespace
# Controlled by var.create_namespace (default: false)
resource "kubernetes_namespace_v1" "tenx_streamer" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# Create Kubernetes service account with IRSA annotation
# This service account will be used by streamer pods to assume the IAM role
# The IRSA annotation (eks.amazonaws.com/role-arn) links the service account to the IAM role created in iam.tf
# EKS automatically injects temporary AWS credentials into pods using this service account
resource "kubernetes_service_account_v1" "tenx_streamer" {
  metadata {
    name      = local.service_account_name
    namespace = var.namespace

    # IRSA annotation - this is the critical link between Kubernetes and AWS IAM
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tenx_streamer.arn
    }
  }

  # Ensure the IAM role exists before creating the service account
  depends_on = [aws_iam_role.tenx_streamer]
}

###########################################
# Helm Release
###########################################

# Deploy streamer-10x Helm chart
resource "helm_release" "tenx_streamer" {
  name       = var.helm_release_name
  repository = "https://log-10x.github.io/helm-charts"
  chart      = "streamer-10x"
  namespace  = var.namespace
  version    = var.helm_chart_version

  # Two-layer values merging strategy:
  # 1. User-provided values file (application configuration) - replicas, scaling, resources, etc.
  # 2. Infrastructure overrides (from Terraform) - S3 buckets, SQS queues, service account
  values = concat(
    # Layer 1: User values file with application configuration
    var.helm_values_file != "" ? [file(var.helm_values_file)] : [],

    # Layer 2: Infrastructure overrides (S3, SQS, service account)
    [yamlencode({
      # Use Terraform-created service account instead of Helm-created one
      serviceAccount = {
        create = false
        name   = kubernetes_service_account_v1.tenx_streamer.metadata[0].name
      }

      # S3 bucket configuration (root-level values)
      inputBucket = module.tenx_streamer_infra.index_source_bucket_name
      indexBucket = module.tenx_streamer_infra.index_write_container

      # SQS queue configuration (root-level values)
      indexQueueUrl    = module.tenx_streamer_infra.index_queue_url
      queryQueueUrl    = module.tenx_streamer_infra.query_queue_url
      subQueryQueueUrl = module.tenx_streamer_infra.subquery_queue_url
      streamQueueUrl   = module.tenx_streamer_infra.stream_queue_url
    })]
  )

  # Set sensitive API key separately to avoid showing in Terraform state
  set_sensitive = [{
    name  = "log10xApiKey"
    value = var.tenx_api_key
  }]

  # Ensure infrastructure and service account exist before deploying
  depends_on = [
    module.tenx_streamer_infra,
    kubernetes_service_account_v1.tenx_streamer
  ]
}
