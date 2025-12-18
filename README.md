# terraform-aws-tenx-streamer

Terraform module that deploys the Log10x streamer application to an existing EKS cluster with complete AWS integration.

## Overview

This module provides a complete deployment of the Log10x streamer to AWS EKS, including:

- **Infrastructure Provisioning**: Automatically creates SQS queues and S3 buckets using the `terraform-aws-tenx-streamer-infra` module
- **IRSA Configuration**: Sets up IAM Roles for Service Accounts for secure, credential-free AWS access
- **Kubernetes Resources**: Creates namespaces and service accounts with proper annotations
- **Helm Deployment**: Deploys the `streamer-10x` Helm chart with all necessary configuration

## Architecture

```
EKS Cluster (existing)
    │
    ├─> OIDC Provider (auto-discovered)
    │       │
    │       └─> IAM Role (IRSA)
    │               │
    │               └─> IAM Policy (S3 + SQS permissions)
    │
    ├─> Kubernetes Namespace
    │       │
    │       └─> Service Account (with IRSA annotation)
    │               │
    │               └─> Streamer Pods
    │                       │
    │                       ├─> S3 Buckets (source + index)
    │                       └─> SQS Queues (index + query + pipeline)
```

## Prerequisites

1. **Existing EKS Cluster** with:
   - OIDC provider configured (standard for EKS clusters)
   - Kubernetes version 1.21+
   - Sufficient capacity for streamer pods

2. **AWS CLI** configured with appropriate credentials

3. **Terraform** version 1.0 or higher

4. **Required Providers**:
   - AWS provider >= 5.0
   - Kubernetes provider >= 2.20
   - Helm provider >= 2.9

## Quick Start

### Basic Usage

```hcl
module "tenx_streamer" {
  source  = "log-10x/tenx-streamer/aws"
  version = "~> 0.1"

  eks_cluster_name = "my-eks-cluster"
  tenx_api_key     = var.tenx_api_key
}
```

This will create all infrastructure (SQS queues and S3 buckets) and deploy the streamer to the `default` namespace with default settings.

### Production Usage with Custom Configuration

```hcl
module "tenx_streamer" {
  source  = "log-10x/tenx-streamer/aws"
  version = "~> 0.1"

  # Required
  eks_cluster_name = "production-eks-cluster"
  tenx_api_key     = var.tenx_api_key

  # Kubernetes configuration
  namespace        = "log10x-streamer"
  create_namespace = true

  # Infrastructure naming
  tenx_streamer_index_source_bucket_name  = "my-logs-bucket"
  tenx_streamer_index_results_bucket_name = "my-index-bucket"
  tenx_streamer_index_queue_name          = "prod-index-queue"
  tenx_streamer_query_queue_name          = "prod-query-queue"
  tenx_streamer_pipeline_queue_name       = "prod-pipeline-queue"

  # Application configuration
  enable_autoscaling               = true
  autoscaling_min_replicas         = 2
  autoscaling_max_replicas         = 10
  autoscaling_target_cpu_percentage = 70
  max_parallel_requests            = 20
  max_queued_requests              = 2000
  readiness_threshold_percent      = 85

  # Helm configuration
  helm_chart_version = "0.1.10"
  helm_values_file   = "streamer-values.yaml"
  helm_values = {
    clusters = [{
      name = "all-in-one"
      resources = {
        requests = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        limits = {
          memory = "4Gi"
        }
      }
    }]
  }

  # Tagging
  tags = {
    Environment = "production"
    Project     = "log10x"
    ManagedBy   = "terraform"
  }
}
```

## IRSA (IAM Roles for Service Accounts)

This module automatically sets up IRSA, which provides secure, credential-free AWS access to Kubernetes pods:

1. **OIDC Auto-Discovery**: Automatically discovers the EKS cluster's OIDC provider
2. **IAM Role Creation**: Creates an IAM role with a trust policy that allows the Kubernetes service account to assume it
3. **Service Account Annotation**: Annotates the Kubernetes service account with the IAM role ARN
4. **Automatic Credential Injection**: EKS automatically injects temporary AWS credentials into pods using this service account

### IAM Permissions

The module creates an IAM role with least-privilege permissions based on actual application requirements:

**S3 Input Bucket (Read-Only)**:
- `s3:GetObject` - Read source log files

**S3 Index Bucket (Full Access)**:
- `s3:ListBucket` - List index files
- `s3:GetObject` - Read existing index files
- `s3:PutObject` - Write new index files
- `s3:PutObjectTagging` - Tag objects with metadata
- `s3:DeleteObject` - Remove obsolete index files

**SQS Queues (All Three Queues)**:
- `sqs:ReceiveMessage` - Poll for messages
- `sqs:DeleteMessage` - Remove processed messages
- `sqs:SendMessage` - Send messages (for pipeline invocation)
- `sqs:GetQueueAttributes` - Get queue metadata

## Input Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `eks_cluster_name` | Name of the existing EKS cluster to deploy to | `string` |
| `tenx_api_key` | Log10x API key for authentication (sensitive) | `string` |

### Infrastructure Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `tenx_streamer_index_source_bucket_name` | S3 bucket for source files. Auto-generated if empty. | `string` | `""` |
| `tenx_streamer_index_results_bucket_name` | S3 bucket for index results. Uses source bucket if empty. | `string` | `""` |
| `tenx_streamer_index_queue_name` | Index SQS queue name. Auto-generated if empty. | `string` | `""` |
| `tenx_streamer_query_queue_name` | Query SQS queue name. Auto-generated if empty. | `string` | `""` |
| `tenx_streamer_pipeline_queue_name` | Pipeline SQS queue name. Auto-generated if empty. | `string` | `""` |
| `create_s3_buckets` | Whether to create S3 buckets or use existing ones | `bool` | `true` |
| `tenx_streamer_queue_message_retention` | SQS message retention period in seconds | `number` | `345600` (4 days) |
| `tenx_streamer_index_trigger_suffix` | S3 suffix that triggers indexing (e.g., '.log') | `string` | `""` (all objects) |

### Kubernetes Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace to deploy into | `string` | `"default"` |
| `create_namespace` | Whether to create the Kubernetes namespace | `bool` | `false` |
| `service_account_name` | Kubernetes service account name. Defaults to helm_release_name. | `string` | `""` |

### Helm Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `helm_release_name` | Helm release name | `string` | `"tenx-streamer"` |
| `helm_chart_version` | Version of the streamer-10x Helm chart | `string` | `"0.1.10"` |
| `helm_values_file` | Path to custom Helm values YAML file | `string` | `""` |
| `helm_values` | Additional Helm values as a map | `any` | `{}` |

### Application Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `replica_count` | Number of replicas (when autoscaling disabled) | `number` | `1` |
| `enable_autoscaling` | Enable horizontal pod autoscaling | `bool` | `false` |
| `autoscaling_min_replicas` | Minimum replicas for autoscaling | `number` | `1` |
| `autoscaling_max_replicas` | Maximum replicas for autoscaling | `number` | `5` |
| `autoscaling_target_cpu_percentage` | Target CPU utilization for autoscaling | `number` | `80` |
| `max_parallel_requests` | Max parallel pipeline executions per pod | `number` | `10` |
| `max_queued_requests` | Max queued pipeline requests per pod | `number` | `1000` |
| `readiness_threshold_percent` | Readiness threshold percentage (0-100) | `number` | `90` |

### IAM Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `iam_role_name` | IAM role name. Auto-generated if empty. | `string` | `""` |
| `additional_iam_policies` | Additional IAM policy statements | `list(object)` | `[]` |

### Tagging

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `tags` | Tags to apply to AWS resources | `map(string)` | `{}` |

## Outputs

### Infrastructure Outputs

- `index_queue_url` - URL of the index SQS queue
- `query_queue_url` - URL of the query SQS queue
- `pipeline_queue_url` - URL of the pipeline SQS queue
- `index_source_bucket_name` - Name of the source S3 bucket
- `index_results_bucket_name` - Name of the index results S3 bucket
- `index_write_container` - S3 path for writing index results

### IAM Outputs

- `iam_role_arn` - ARN of the IAM role for IRSA
- `iam_role_name` - Name of the IAM role for IRSA

### Kubernetes Outputs

- `namespace` - Kubernetes namespace where streamer is deployed
- `service_account_name` - Name of the Kubernetes service account

### Helm Outputs

- `helm_release_name` - Name of the Helm release
- `helm_release_status` - Status of the Helm release
- `helm_release_version` - Version of the deployed Helm chart

### EKS Outputs

- `eks_cluster_name` - Name of the EKS cluster
- `eks_cluster_endpoint` - Endpoint of the EKS cluster
- `eks_oidc_provider_arn` - ARN of the EKS OIDC provider
- `eks_oidc_provider` - OIDC provider URL (without https:// prefix)

## Advanced Usage

### Using Existing Infrastructure

If you already have SQS queues and S3 buckets:

```hcl
module "tenx_streamer" {
  source  = "log-10x/tenx-streamer/aws"
  version = "~> 0.1"

  eks_cluster_name = "my-eks-cluster"
  tenx_api_key     = var.tenx_api_key

  # Use existing infrastructure
  create_s3_buckets                        = false
  tenx_streamer_index_source_bucket_name   = "existing-logs-bucket"
  tenx_streamer_index_results_bucket_name  = "existing-index-bucket"
  tenx_streamer_index_queue_name           = "existing-index-queue"
  tenx_streamer_query_queue_name           = "existing-query-queue"
  tenx_streamer_pipeline_queue_name        = "existing-pipeline-queue"
}
```

### Adding Custom IAM Policies

If your application needs additional AWS permissions:

```hcl
module "tenx_streamer" {
  source  = "log-10x/tenx-streamer/aws"
  version = "~> 0.1"

  eks_cluster_name = "my-eks-cluster"
  tenx_api_key     = var.tenx_api_key

  additional_iam_policies = [
    {
      sid       = "CloudWatchLogs"
      effect    = "Allow"
      actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      resources = ["arn:aws:logs:*:*:*"]
    }
  ]
}
```

### Custom Helm Values

Merge custom Helm values with generated configuration:

```hcl
module "tenx_streamer" {
  source  = "log-10x/tenx-streamer/aws"
  version = "~> 0.1"

  eks_cluster_name = "my-eks-cluster"
  tenx_api_key     = var.tenx_api_key

  helm_values = {
    clusters = [{
      name = "all-in-one"

      resources = {
        requests = {
          cpu    = "2000m"
          memory = "4Gi"
        }
        limits = {
          cpu    = "4000m"
          memory = "8Gi"
        }
      }

      nodeSelector = {
        workload-type = "log-processing"
      }

      tolerations = [{
        key      = "log-processing"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }]
    }]
  }
}
```

## Troubleshooting

### Pods Cannot Access S3/SQS

**Symptoms**: Pods fail with AWS authentication errors

**Possible Causes**:
1. OIDC provider not configured on EKS cluster
2. Service account annotation missing or incorrect
3. IAM role trust policy doesn't match service account

**Solutions**:
```bash
# Verify OIDC provider exists
aws eks describe-cluster --name <cluster-name> --query "cluster.identity.oidc.issuer"

# Verify service account annotation
kubectl get sa <service-account-name> -n <namespace> -o yaml

# Check pod has correct service account
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# Check AWS credentials are injected
kubectl exec <pod-name> -n <namespace> -- env | grep AWS
```

### Helm Release Fails to Deploy

**Symptoms**: `terraform apply` fails during Helm release creation

**Possible Causes**:
1. Insufficient permissions to create Kubernetes resources
2. Invalid Helm values
3. Chart version doesn't exist

**Solutions**:
```bash
# Verify AWS credentials can access cluster
aws eks update-kubeconfig --name <cluster-name>
kubectl auth can-i create deployments -n <namespace>

# Test Helm chart locally
helm repo add log-10x https://log-10x.github.io/helm-charts
helm repo update
helm search repo log-10x/streamer-10x --versions

# Validate custom values file
helm template test log-10x/streamer-10x -f <your-values-file>
```

### Resource Name Conflicts

**Symptoms**: Terraform fails with "already exists" errors

**Possible Causes**:
1. Resources from previous deployment not cleaned up
2. Multiple modules deploying to same cluster without unique names

**Solutions**:
```hcl
# Use unique resource names per deployment
module "tenx_streamer" {
  source = "..."

  helm_release_name                      = "tenx-streamer-prod"
  iam_role_name                          = "prod-tenx-streamer-irsa"
  service_account_name                   = "tenx-streamer-prod"
  tenx_streamer_index_queue_name         = "prod-index-queue"
  tenx_streamer_query_queue_name         = "prod-query-queue"
  tenx_streamer_pipeline_queue_name      = "prod-pipeline-queue"
}
```

### OIDC Provider ARN Not Found

**Symptoms**: IAM role creation fails with "invalid principal" error

**Possible Causes**:
1. EKS cluster doesn't have OIDC provider configured
2. OIDC provider was deleted

**Solutions**:
```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# Create OIDC provider for cluster
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve
```

## Examples

See the [examples/](examples/) directory for complete working examples:

- [Basic](examples/basic/) - Minimal configuration with defaults
- [Production](examples/production/) - Production-ready configuration with autoscaling

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |
| kubernetes | >= 2.20 |
| helm | >= 2.9 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| kubernetes | >= 2.20 |
| helm | >= 2.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| tenx_streamer_infra | log-10x/tenx-streamer-infra/aws | ~> 0.1 |

## Resources

| Name | Type |
|------|------|
| aws_iam_role.tenx_streamer | resource |
| aws_iam_role_policy.tenx_streamer | resource |
| kubernetes_namespace.tenx_streamer | resource |
| kubernetes_service_account.tenx_streamer | resource |
| helm_release.tenx_streamer | resource |
| aws_region.current | data source |
| aws_caller_identity.current | data source |
| aws_eks_cluster.target | data source |
| aws_eks_cluster_auth.target | data source |

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Support

For issues and questions:
- GitHub Issues: https://github.com/log-10x/terraform-aws-tenx-streamer/issues
- Documentation: https://docs.log10x.com
