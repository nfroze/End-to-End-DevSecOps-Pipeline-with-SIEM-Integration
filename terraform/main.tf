terraform {
  backend "s3" {
    bucket = "project5-terraform-state"
    key    = "terraform.tfstate"
    region = "eu-west-2"
  }

  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Splunk HEC credentials (used by OTel Collector in cd.yml, not by Terraform modules)
variable "splunk_hec_url" {
  description = "Splunk HEC URL"
  type        = string
}

variable "splunk_hec_token" {
  description = "Splunk HEC Token"
  type        = string
  sensitive   = true
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
}

# IAM Module
module "iam" {
  source = "./modules/iam"
}

# EKS Module
module "eks" {
  source             = "./modules/eks"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  cluster_role_arn   = module.iam.eks_cluster_role_arn
  node_role_arn      = module.iam.eks_node_role_arn
}

# Security Module (Splunk Add-on for AWS pull model)
# Sources: GuardDuty, Security Hub, CloudTrail (S3/SQS), VPC Flow Logs, EKS Audit Logs
# Kubernetes container logs handled by Splunk OTel Collector (Helm) -- see /splunk/values.yaml
module "security" {
  source = "./modules/security"

  eks_cluster_name = module.eks.cluster_name

  depends_on = [module.eks]
}

# ---------- Outputs for Splunk Add-on configuration ----------

output "splunk_addon_access_key_id" {
  description = "IAM access key ID -- configure in Splunk Add-on for AWS"
  value       = module.security.splunk_addon_access_key_id
}

output "splunk_addon_secret_access_key" {
  description = "IAM secret access key -- configure in Splunk Add-on for AWS"
  value       = module.security.splunk_addon_secret_access_key
  sensitive   = true
}

output "cloudtrail_sqs_queue_url" {
  description = "SQS queue URL -- configure in Splunk Add-on CloudTrail input"
  value       = module.security.cloudtrail_sqs_queue_url
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket -- configure in Splunk Add-on CloudTrail input"
  value       = module.security.cloudtrail_s3_bucket
}
