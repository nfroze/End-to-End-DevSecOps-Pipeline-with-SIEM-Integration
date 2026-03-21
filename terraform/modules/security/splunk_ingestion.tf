# =============================================================================
# modules/security/splunk_ingestion.tf
# Splunk Add-on for AWS (pull model): Splunk polls CloudWatch Logs and S3/SQS.
# No Firehose, no Lambda.
#
# Data flow:
#   GuardDuty       -> EventBridge -> CloudWatch Logs <- Splunk polls
#   Security Hub    -> EventBridge -> CloudWatch Logs <- Splunk polls
#   CloudTrail      -> S3 -> SNS -> SQS <- Splunk polls
#   VPC Flow Logs   -> CloudWatch Logs <- Splunk polls (log group from VPC module)
#   EKS Audit Logs  -> CloudWatch Logs <- Splunk polls (log group from EKS module)
#   K8s Containers  -> OTel Collector -> Splunk HEC (unchanged, managed by Helm)
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# 1. GUARDDUTY -> EventBridge -> CloudWatch Logs <- Splunk polls
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = { Name = "project5-guardduty" }
}

resource "aws_cloudwatch_log_group" "guardduty" {
  name              = "/aws/events/project5-guardduty"
  retention_in_days = 30
  tags              = { Name = "project5-guardduty-logs" }
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  name        = "project5-guardduty-to-cwl"
  description = "Route GuardDuty findings to CloudWatch Logs for Splunk"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  rule = aws_cloudwatch_event_rule.guardduty.name
  arn  = aws_cloudwatch_log_group.guardduty.arn
}

resource "aws_cloudwatch_log_resource_policy" "guardduty" {
  policy_name     = "project5-guardduty-eventbridge"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeWrite"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.guardduty.arn}:*"
    }]
  })
}

# =============================================================================
# 2. SECURITY HUB -> EventBridge -> CloudWatch Logs <- Splunk polls
# =============================================================================

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_cloudwatch_log_group" "securityhub" {
  name              = "/aws/events/project5-securityhub"
  retention_in_days = 30
  tags              = { Name = "project5-securityhub-logs" }
}

resource "aws_cloudwatch_event_rule" "securityhub" {
  name        = "project5-securityhub-to-cwl"
  description = "Route Security Hub findings to CloudWatch Logs for Splunk"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "securityhub" {
  rule = aws_cloudwatch_event_rule.securityhub.name
  arn  = aws_cloudwatch_log_group.securityhub.arn
}

resource "aws_cloudwatch_log_resource_policy" "securityhub" {
  policy_name     = "project5-securityhub-eventbridge"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeWrite"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.securityhub.arn}:*"
    }]
  })
}

# =============================================================================
# 3. CLOUDTRAIL -> S3 -> SNS -> SQS <- Splunk Add-on polls
# =============================================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "project5-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "project5-cloudtrail" }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "project5-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags       = { Name = "project5-cloudtrail" }
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# SNS topic for S3 event notifications
resource "aws_sns_topic" "cloudtrail_notifications" {
  name = "project5-cloudtrail-s3-notifications"
  tags = { Name = "project5-cloudtrail-notifications" }
}

resource "aws_sns_topic_policy" "cloudtrail_notifications" {
  arn = aws_sns_topic.cloudtrail_notifications.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3Publish"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.cloudtrail_notifications.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.cloudtrail.arn
        }
      }
    }]
  })
}

# SQS dead letter queue for failed messages
resource "aws_sqs_queue" "cloudtrail_dlq" {
  name                      = "project5-cloudtrail-s3-notifications-dlq"
  message_retention_seconds = 1209600
  tags                      = { Name = "project5-cloudtrail-sqs-dlq" }
}

# SQS queue - Splunk Add-on polls this for new CloudTrail objects
resource "aws_sqs_queue" "cloudtrail_notifications" {
  name                       = "project5-cloudtrail-s3-notifications"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  tags                       = { Name = "project5-cloudtrail-sqs" }

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.cloudtrail_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "cloudtrail_notifications" {
  queue_url = aws_sqs_queue.cloudtrail_notifications.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSNSMessages"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.cloudtrail_notifications.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.cloudtrail_notifications.arn
        }
      }
    }]
  })
}

# SNS -> SQS subscription
resource "aws_sns_topic_subscription" "cloudtrail_sqs" {
  topic_arn = aws_sns_topic.cloudtrail_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.cloudtrail_notifications.arn
}

# S3 -> SNS notification on new CloudTrail objects
resource "aws_s3_bucket_notification" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  topic {
    topic_arn = aws_sns_topic.cloudtrail_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.cloudtrail_notifications]
}

# =============================================================================
# 4. VPC FLOW LOGS - Already in CloudWatch (/aws/vpc/project5)
#    Splunk Add-on polls via CloudWatch Logs API. No extra infra needed.
# =============================================================================

# (VPC flow log group is created by the VPC module)

# =============================================================================
# 5. EKS AUDIT LOGS - Already in CloudWatch (/aws/eks/<cluster>/cluster)
#    Splunk Add-on polls via CloudWatch Logs API. No extra infra needed.
# =============================================================================

# (EKS audit log group is created by the EKS module)

# =============================================================================
# IAM USER FOR SPLUNK ADD-ON FOR AWS
# Least-privilege access to poll all five data sources.
# =============================================================================

resource "aws_iam_user" "splunk_addon" {
  name = "project5-splunk-addon"
  tags = { Name = "project5-splunk-addon" }
}

resource "aws_iam_access_key" "splunk_addon" {
  user = aws_iam_user.splunk_addon.name
}

resource "aws_iam_user_policy" "splunk_addon" {
  name = "project5-splunk-addon-policy"
  user = aws_iam_user.splunk_addon.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # GuardDuty - list and get findings
      {
        Sid    = "GuardDutyRead"
        Effect = "Allow"
        Action = [
          "guardduty:GetDetector",
          "guardduty:ListDetectors",
          "guardduty:GetFindings",
          "guardduty:ListFindings"
        ]
        Resource = "*"
      },
      # Security Hub - get findings
      {
        Sid    = "SecurityHubRead"
        Effect = "Allow"
        Action = [
          "securityhub:GetFindings",
          "securityhub:BatchGetSecurityControls",
          "securityhub:DescribeHub"
        ]
        Resource = "*"
      },
      # SQS - list queues (requires account-level resource)
      {
        Sid      = "SQSList"
        Effect   = "Allow"
        Action   = ["sqs:ListQueues"]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      # SQS - poll CloudTrail notifications
      {
        Sid    = "SQSRead"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.cloudtrail_notifications.arn
      },
      # S3 - read CloudTrail log objects
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
      },
      # CloudWatch Logs - poll VPC Flow Logs and EKS Audit Logs
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}
