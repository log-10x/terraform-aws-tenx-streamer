###########################################
# Required Variables
###########################################

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to deploy to"
  type        = string
}

variable "tenx_api_key" {
  description = "Log10x API key for authentication"
  type        = string
  sensitive   = true
}

###########################################
# Infrastructure Configuration
###########################################

variable "tenx_streamer_index_source_bucket_name" {
  description = "Name of S3 bucket for source files to be indexed. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_streamer_index_results_bucket_name" {
  description = "Name of S3 bucket for indexing results. If empty, uses same as source bucket."
  type        = string
  default     = ""
}

variable "tenx_streamer_index_queue_name" {
  description = "Name of the index SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_streamer_query_queue_name" {
  description = "Name of the query SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "tenx_streamer_pipeline_queue_name" {
  description = "Name of the pipeline SQS queue. If empty, module will generate a name."
  type        = string
  default     = ""
}

variable "create_s3_buckets" {
  description = "Whether to create S3 buckets (true) or use existing ones (false)"
  type        = bool
  default     = true
}

variable "tenx_streamer_queue_message_retention" {
  description = "Message retention period in seconds for SQS queues (default: 4 days)"
  type        = number
  default     = 345600
}

variable "tenx_streamer_index_trigger_suffix" {
  description = "S3 object suffix that triggers indexing (e.g., '.log'). If empty, all objects trigger indexing."
  type        = string
  default     = ""
}

###########################################
# Kubernetes Configuration
###########################################

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = false
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account (defaults to helm_release_name if empty)"
  type        = string
  default     = ""
}

###########################################
# Helm Chart Configuration
###########################################

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = "tenx-streamer"
}

variable "helm_chart_version" {
  description = "Version of the streamer-10x Helm chart"
  type        = string
  default     = "0.2.2"
}

variable "helm_values_file" {
  description = "Path to custom Helm values YAML file for application configuration (replicas, scaling, resources, etc.)"
  type        = string
  default     = ""
}

###########################################
# IAM Configuration
###########################################

variable "iam_role_name" {
  description = "Name of the IAM role for IRSA (defaults to '{cluster}-tenx-streamer-irsa' if empty)"
  type        = string
  default     = ""
}

variable "additional_iam_policies" {
  description = "Additional IAM policy statements to attach to the IRSA role"
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

###########################################
# Tagging
###########################################

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
