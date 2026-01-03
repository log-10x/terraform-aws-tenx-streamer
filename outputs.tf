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

output "subquery_queue_url" {
  description = "URL of the sub-query SQS queue"
  value       = module.tenx_streamer_infra.subquery_queue_url
}

output "stream_queue_url" {
  description = "URL of the stream SQS queue"
  value       = module.tenx_streamer_infra.stream_queue_url
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

