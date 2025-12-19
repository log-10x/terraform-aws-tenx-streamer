module "tenx_streamer" {
  source = "../../"

  eks_cluster_name = var.eks_cluster_name
  tenx_api_key     = var.tenx_api_key
  namespace        = var.namespace

  helm_values_file = "${path.module}/values.yaml"

  # Use existing S3 buckets
  create_s3_buckets                     = false
  tenx_streamer_index_source_bucket_name = var.source_bucket_name
  tenx_streamer_index_results_bucket_name = var.results_bucket_name

  tags = {
    Environment = "production"
    Project     = "log10x-streamer"
    Example     = "production"
    ManagedBy   = "terraform"
  }
}
