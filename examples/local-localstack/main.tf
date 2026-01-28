# Local Testing with LocalStack
# Deploys Cloud Streamer to minikube using LocalStack for S3/SQS emulation.
# No AWS account required.
#
# Prerequisites:
#   - minikube running
#   - LocalStack deployed in minikube (see doc.log10x.com/apps/cloud/streamer/test)
#   - LocalStack port-forward: kubectl port-forward -n localstack svc/localstack 4566:4566
#
# Usage:
#   terraform init
#   terraform apply -var="tenx_api_key=test-key"

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

# Configure AWS provider to use LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sqs = "http://localhost:4566"
  }

  s3_use_path_style = true
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
  description = "Log10x API key (use any placeholder for local testing)"
  type        = string
  sensitive   = true
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

locals {
  localstack_external = "http://localhost:4566"
  localstack_internal = "http://localstack.localstack.svc.cluster.local:4566"
}

###########################################
# Infrastructure (S3/SQS via LocalStack)
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

    indexQueueUrl    = replace(module.streamer_infra.index_queue_url, local.localstack_external, local.localstack_internal)
    queryQueueUrl    = replace(module.streamer_infra.query_queue_url, local.localstack_external, local.localstack_internal)
    subQueryQueueUrl = replace(module.streamer_infra.subquery_queue_url, local.localstack_external, local.localstack_internal)
    streamQueueUrl   = replace(module.streamer_infra.stream_queue_url, local.localstack_external, local.localstack_internal)

    clusters = [{
      name                = "all-in-one"
      roles               = ["index", "query", "stream"]
      replicaCount        = 1
      maxParallelRequests = 5
      maxQueuedRequests   = 100

      extraEnv = [
        { name = "AWS_ENDPOINT_URL", value = local.localstack_internal },
        { name = "AWS_ACCESS_KEY_ID", value = "test" },
        { name = "AWS_SECRET_ACCESS_KEY", value = "test" },
        { name = "AWS_REGION", value = "us-east-1" },
        { name = "TENX_S3_PATH_STYLE", value = "true" },
        { name = "TENX_INVOKE_PIPELINE_SCAN_ENDPOINT", value = replace(module.streamer_infra.subquery_queue_url, local.localstack_external, local.localstack_internal) },
        { name = "TENX_INVOKE_PIPELINE_STREAM_ENDPOINT", value = replace(module.streamer_infra.stream_queue_url, local.localstack_external, local.localstack_internal) },
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
