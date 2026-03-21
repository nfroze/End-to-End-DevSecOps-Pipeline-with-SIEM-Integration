# Security Exceptions and Design Decisions

This document explains security findings from our scanning tools and the rationale for our design decisions.

## Container Image

The application runs on `node:22-alpine` (Node.js 22 LTS) with `apk upgrade` applied at build time to ensure the latest Alpine security patches. Previous vulnerabilities in OpenSSL (`libcrypto3`/`libssl3`) and npm's bundled dependencies (`glob`, `minimatch`, `tar`) were resolved by upgrading from Node.js 18 (EOL April 2025) to Node.js 22 LTS.

## Checkov Findings - Accepted Risks

### IAM User for Splunk Add-on (Medium Risk - Mitigated)
- **CKV_AWS_273 -- SSO vs IAM Users**: The Splunk Add-on for AWS requires IAM access keys to poll AWS services (GuardDuty, Security Hub, CloudWatch Logs, S3/SQS). SSO federation is not supported by the Add-on. The IAM user follows least-privilege with scoped permissions for read-only access to security data sources only. In production, this would use an IAM role with cross-account assume-role via the Add-on's Assume Role feature.

### SQS/SNS Encryption (Low Risk)
- **CKV_AWS_27 -- SQS Queue Encryption**: The SQS queue carries S3 event notifications (object keys and metadata) for CloudTrail log delivery. This is not sensitive data -- the actual log contents are in S3 (encrypted at rest by default). KMS encryption on SQS adds cost and requires key policy management for SNS-to-SQS delivery.
- **CKV_AWS_26 -- SNS Topic Encryption**: Same rationale. The SNS topic carries S3 bucket notifications, not log contents. AWS-managed encryption is sufficient for demo.

### CloudTrail Configuration (Low Risk)
- **CKV_AWS_35 -- No KMS CMK Encryption**: CloudTrail logs in S3 are encrypted at rest using SSE-S3 (AES-256) by default. KMS CMK adds cost and key management overhead for a demo project.
- **CKV_AWS_252 -- No SNS Topic for CloudTrail Notifications**: CloudTrail already delivers to S3 with S3 event notifications routing to SNS/SQS for Splunk ingestion. A separate CloudTrail-level SNS topic would be redundant.
- **CKV_AWS_67 -- Single-Region Trail**: The project operates entirely in eu-west-2. Multi-region trails are recommended for production but unnecessary for a single-region demo.

### S3 Lifecycle Configuration (Low Risk)
- **CKV_AWS_300 -- No Abort Incomplete Multipart Upload Rule**: CloudTrail writes small compressed JSON files, not multipart uploads. This rule is relevant for large file uploads (e.g., video, backups) but not for CloudTrail log delivery.

### EKS Public Endpoint (Medium Risk - Mitigated)
- **CKV_AWS_39 / CKV_AWS_38 -- Public API Endpoint**: GitHub Actions needs to deploy to the cluster. In production, we would:
  - Use a self-hosted runner inside the VPC
  - Or restrict public_access_cidrs to GitHub's IP ranges
  - Or use AWS Systems Manager for access

### KMS Key Rotation (Low Risk)
- **CKV_AWS_7 -- No CMK Rotation Enabled**: The project uses AWS-managed encryption keys where applicable. Customer-managed CMKs with automatic rotation are recommended for production but add operational overhead for a demo environment.

### CloudWatch Logs (Low Risk)
- **30-day Retention**: Sufficient for demo. Production would use 365+ days for compliance.
- **No KMS Encryption**: CloudWatch Logs are encrypted at rest by default. KMS adds cost without significant security benefit for demo logs.

### DynamoDB State Lock Table (Low Risk)
- **No Point-in-Time Recovery**: This table only stores Terraform locks, not application data. Locks are ephemeral.
- **Default Encryption**: Uses AWS-managed keys. Sufficient for lock data.

## Security Strengths Demonstrated

Despite these exceptions, our infrastructure demonstrates strong security:

1. **Network Isolation**: Private subnets for compute, public only for load balancers
2. **IAM Least Privilege**: All roles and the Splunk Add-on IAM user follow principle of least privilege
3. **Encryption in Transit**: TLS everywhere
4. **No Hardcoded Secrets**: All sensitive data in environment variables or Terraform tfvars (gitignored)
5. **Comprehensive Scanning**: SAST, SCA, Container, IaC, and Secret scanning in CI/CD
6. **Threat Detection**: GuardDuty enabled with findings routed to Splunk SIEM
7. **Compliance Monitoring**: Security Hub with AWS Foundational Best Practices standard
8. **Audit Logging**: CloudTrail, VPC Flow Logs, EKS Audit Logs -- all ingested into Splunk
9. **Pull-Based Ingestion**: Splunk Add-on for AWS polls data sources -- no push infrastructure to maintain

## Recommendations for Production

To address the remaining findings in a production environment:

1. Implement KMS CMK encryption for SQS, SNS, CloudTrail, and CloudWatch Logs
2. Replace IAM user with cross-account IAM role for Splunk Add-on
3. Enable multi-region CloudTrail
4. Use PrivateLink endpoints for AWS services
5. Implement AWS WAF on the load balancer
6. Restrict EKS public endpoint to known CIDR ranges
7. Use AWS Secrets Manager instead of environment variables
8. Enable AWS Shield for DDoS protection

These exceptions are documented and understood, demonstrating mature security thinking appropriate for a DevSecOps role.
