# Local Testing with Real AWS
# Deploys Cloud Streamer to minikube using real AWS S3/SQS.
# Requires AWS credentials with permissions for S3 and SQS.
#
# Prerequisites:
#   - minikube running
#   - AWS credentials configured (env vars or profile)
#
# Usage:
#   terraform init
#   terraform apply \
#     -var="tenx_api_key=YOUR_API_KEY" \
#     -var="aws_access_key_id=$AWS_ACCESS_KEY_ID" \
#     -var="aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

# Configure AWS provider - uses your credentials (env vars, profile, or instance role)
provider "aws" {
  region = var.aws_region
}

# Kubernetes provider - uses current kubectl context
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Helm provider
provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

###########################################
# Variables
###########################################

variable "tenx_api_key" {
  description = "Log10x API key (get at console.log10x.com)"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID (passed to pods in minikube)"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (passed to pods in minikube)"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for streamer"
  type        = string
  default     = "log10x-streamer"
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "streamer"
}

###########################################
# Infrastructure (S3/SQS via real AWS)
###########################################

module "streamer_infra" {
  source = "log-10x/tenx-streamer-infra/aws"

  tenx_streamer_index_queue_name    = "${var.resource_prefix}-index-queue"
  tenx_streamer_query_queue_name    = "${var.resource_prefix}-query-queue"
  tenx_streamer_subquery_queue_name = "${var.resource_prefix}-subquery-queue"
  tenx_streamer_stream_queue_name   = "${var.resource_prefix}-stream-queue"

  tenx_streamer_create_index_source_bucket  = true
  tenx_streamer_index_source_bucket_name    = "${var.resource_prefix}-logs"
  tenx_streamer_create_index_results_bucket = true
  tenx_streamer_index_results_bucket_name   = "${var.resource_prefix}-index"
  tenx_streamer_index_results_path          = "indexed/"

  tenx_streamer_index_trigger_prefix = ""
  tenx_streamer_index_trigger_suffix = ".log"
}

###########################################
# Kubernetes Resources
###########################################

resource "kubernetes_namespace_v1" "streamer" {
  metadata {
    name = var.namespace
  }
}

###########################################
# Helm Release
###########################################

resource "helm_release" "streamer" {
  name       = "streamer"
  repository = "https://log-10x.github.io/helm-charts"
  chart      = "streamer-10x"
  namespace  = kubernetes_namespace_v1.streamer.metadata[0].name

  wait    = true
  timeout = 300

  values = [yamlencode({
    log10xApiKey = var.tenx_api_key

    inputBucket = module.streamer_infra.index_source_bucket_name
    indexBucket = module.streamer_infra.index_write_container

    indexQueueUrl    = module.streamer_infra.index_queue_url
    queryQueueUrl    = module.streamer_infra.query_queue_url
    subQueryQueueUrl = module.streamer_infra.subquery_queue_url
    streamQueueUrl   = module.streamer_infra.stream_queue_url

    clusters = [{
      name                = "all-in-one"
      roles               = ["index", "query", "stream"]
      replicaCount        = 1
      maxParallelRequests = 5
      maxQueuedRequests   = 100

      # AWS credentials for pods running in minikube
      extraEnv = [
        { name = "AWS_ACCESS_KEY_ID", value = var.aws_access_key_id },
        { name = "AWS_SECRET_ACCESS_KEY", value = var.aws_secret_access_key },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      resources = {
        requests = { cpu = "500m", memory = "1Gi" }
        limits   = { cpu = "1000m", memory = "2Gi" }
      }
    }]

    fluentBit = {
      output = { type = "stdout" }
    }

    scheduledQueries = { enabled = false }
    defaultIngress   = { enabled = false }
  })]

  depends_on = [module.streamer_infra]
}

###########################################
# Outputs
###########################################

output "namespace" {
  value = kubernetes_namespace_v1.streamer.metadata[0].name
}

output "input_bucket" {
  value = module.streamer_infra.index_source_bucket_name
}

output "index_bucket" {
  value = module.streamer_infra.index_write_container
}

output "port_forward_command" {
  value = "kubectl port-forward -n ${var.namespace} svc/streamer-streamer-10x-all-in-one 8080:80"
}
