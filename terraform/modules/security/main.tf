# modules/security/main.tf
# Security module: Splunk Add-on for AWS (pull model).
# Event sources: GuardDuty, Security Hub, CloudTrail (S3/SQS), VPC Flow Logs, EKS Audit.
# Kubernetes container logs are handled by Splunk OTel Collector (Helm) -- see /splunk/values.yaml.

# ---------- Variables ----------

variable "eks_cluster_name" {
  description = "EKS cluster name (used to derive CloudWatch log group)"
  type        = string
}

# ---------- Outputs ----------

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "splunk_addon_access_key_id" {
  description = "IAM access key ID for the Splunk Add-on for AWS"
  value       = aws_iam_access_key.splunk_addon.id
}

output "splunk_addon_secret_access_key" {
  description = "IAM secret access key for the Splunk Add-on for AWS"
  value       = aws_iam_access_key.splunk_addon.secret
  sensitive   = true
}

output "cloudtrail_sqs_queue_url" {
  description = "SQS queue URL for CloudTrail S3 notifications"
  value       = aws_sqs_queue.cloudtrail_notifications.url
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name containing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "guardduty_log_group" {
  description = "CloudWatch log group for GuardDuty findings (polled by Splunk)"
  value       = aws_cloudwatch_log_group.guardduty.name
}

output "securityhub_log_group" {
  description = "CloudWatch log group for Security Hub findings (polled by Splunk)"
  value       = aws_cloudwatch_log_group.securityhub.name
}

output "vpc_flow_log_group" {
  description = "CloudWatch log group for VPC flow logs (polled by Splunk)"
  value       = "/aws/vpc/project5"
}

output "eks_audit_log_group" {
  description = "CloudWatch log group for EKS audit logs (polled by Splunk)"
  value       = "/aws/eks/${var.eks_cluster_name}/cluster"
}
