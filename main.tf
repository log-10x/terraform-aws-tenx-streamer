# Local variables for resource naming and configuration
locals {
  # Merge tags with module defaults
  tags = merge(
    var.tags,
    {
      terraform-module         = "tenx-streamer"
      terraform-module-version = "v0.2.0"
      managed-by               = "terraform"
      eks-cluster              = var.eks_cluster_name
    }
  )

  # Use cluster name as prefix for generated resource names
  cluster_prefix = var.eks_cluster_name

  # Generate S3 bucket names with defaults
  index_source_bucket_name = coalesce(
    var.tenx_streamer_index_source_bucket_name,
    "tenx-streamer-${local.cluster_prefix}-${data.aws_caller_identity.current.account_id}"
  )

  index_results_bucket_name = coalesce(
    var.tenx_streamer_index_results_bucket_name,
    local.index_source_bucket_name # Default to same bucket
  )

  # Generate SQS queue names with defaults
  index_queue_name = coalesce(
    var.tenx_streamer_index_queue_name,
    "${local.cluster_prefix}-tenx-index-queue"
  )

  query_queue_name = coalesce(
    var.tenx_streamer_query_queue_name,
    "${local.cluster_prefix}-tenx-query-queue"
  )

  pipeline_queue_name = coalesce(
    var.tenx_streamer_pipeline_queue_name,
    "${local.cluster_prefix}-tenx-pipeline-queue"
  )

  # Generate Kubernetes service account name
  service_account_name = coalesce(
    var.service_account_name,
    var.helm_release_name
  )

  # Generate IAM role name
  iam_role_name = coalesce(
    var.iam_role_name,
    "${local.cluster_prefix}-tenx-streamer-irsa"
  )

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  # Extract from EKS cluster and construct ARN for IAM trust policy
  # Format: oidc.eks.{region}.amazonaws.com/id/{CLUSTER_ID} (without https://)
  oidc_provider_url = data.aws_eks_cluster.target.identity[0].oidc[0].issuer
  oidc_provider     = replace(local.oidc_provider_url, "https://", "")
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
}

###########################################
# Data Sources
###########################################

# Get current AWS region and account information
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# Lookup existing EKS cluster
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

# Lookup EKS cluster authentication
data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}

###########################################
# Infrastructure (SQS Queues and S3 Buckets)
###########################################

# Provision infrastructure (SQS queues and S3 buckets)
module "tenx_streamer_infra" {
  source  = "log-10x/tenx-streamer-infra/aws"
  version = "~> 0.2"

  tenx_streamer_index_queue_name    = local.index_queue_name
  tenx_streamer_query_queue_name    = local.query_queue_name
  tenx_streamer_pipeline_queue_name = local.pipeline_queue_name

  tenx_streamer_create_index_source_bucket  = var.create_s3_buckets
  tenx_streamer_index_source_bucket_name    = local.index_source_bucket_name
  tenx_streamer_create_index_results_bucket = var.create_s3_buckets
  tenx_streamer_index_results_bucket_name   = local.index_results_bucket_name

  tenx_streamer_queue_message_retention = var.tenx_streamer_queue_message_retention
  tenx_streamer_index_trigger_suffix    = var.tenx_streamer_index_trigger_suffix

  tenx_streamer_user_supplied_tags = local.tags
}

###########################################
# Kubernetes Provider
###########################################

# Configure Kubernetes provider using AWS CLI for EKS authentication
provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

  # Use AWS CLI exec plugin for dynamic token authentication
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.eks_cluster_name,
      "--region",
      data.aws_region.current.id
    ]
  }
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
# Helm Provider
###########################################

# Configure Helm provider using AWS CLI for EKS authentication
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.target.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

    # Use AWS CLI exec plugin for dynamic token authentication
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.eks_cluster_name,
        "--region",
        data.aws_region.current.id
      ]
    }
  }
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
      pipelineQueueUrl = module.tenx_streamer_infra.pipeline_queue_url
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
