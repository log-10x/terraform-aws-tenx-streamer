module "tenx_streamer" {
  source = "../../"

  eks_cluster_name = var.eks_cluster_name
  tenx_api_key     = var.tenx_api_key

  helm_values_file = "${path.module}/values.yaml"

  tags = {
    Environment = "development"
    Project     = "log10x-streamer"
    Example     = "basic"
  }
}
