###########################################
# Infrastructure Outputs
###########################################

output "index_queue_url" {
  description = "URL of the index SQS queue"
  value       = module.tenx_streamer_infra.index_queue_url
}

output "query_queue_url" {
  description = "URL of the query SQS queue"
  value       = module.tenx_streamer_infra.query_queue_url
}

output "pipeline_queue_url" {
  description = "URL of the pipeline SQS queue"
  value       = module.tenx_streamer_infra.pipeline_queue_url
}

output "index_source_bucket_name" {
  description = "Name of the S3 bucket for source files to be indexed"
  value       = module.tenx_streamer_infra.index_source_bucket_name
}

output "index_results_bucket_name" {
  description = "Name of the S3 bucket for indexing results"
  value       = module.tenx_streamer_infra.index_results_bucket_name
}

output "index_write_container" {
  description = "S3 path for writing index results (bucket or bucket/prefix)"
  value       = module.tenx_streamer_infra.index_write_container
}

###########################################
# IAM Outputs
###########################################

output "iam_role_arn" {
  description = "ARN of the IAM role for IRSA"
  value       = aws_iam_role.tenx_streamer.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for IRSA"
  value       = aws_iam_role.tenx_streamer.name
}

###########################################
# Kubernetes Outputs
###########################################

output "namespace" {
  description = "Kubernetes namespace where streamer is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account_v1.tenx_streamer.metadata[0].name
}

###########################################
# Helm Outputs
###########################################

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.tenx_streamer.name
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = helm_release.tenx_streamer.status
}

output "helm_release_version" {
  description = "Version of the deployed Helm chart"
  value       = helm_release.tenx_streamer.version
}

###########################################
# EKS Cluster Outputs
###########################################

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = data.aws_eks_cluster.target.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = data.aws_eks_cluster.target.endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  value       = local.oidc_provider_arn
}

output "eks_oidc_provider" {
  description = "OIDC provider URL (without https:// prefix)"
  value       = local.oidc_provider
}
