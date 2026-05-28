# aws-iam-security-audit

AWS IAM security audit project — deliberately misconfigured, detected with AWS native tools, and remediated using least privilege principles. Deployed through Terraform.

---

## The Problem This Project Solves

IAM misconfiguration is the biggest cause of cloud security breaches in the world right now. Over 70% of cloud breaches stem from compromised or misconfigured identities.

In 2019 a former AWS employee exploited a misconfigured IAM role at Capital One. The role had far more S3 permissions than it needed. The attacker used those excess permissions to access 106 million customer records. AWS's infrastructure was never breached — Capital One's own misconfiguration was the problem.

This project simulates exactly that scenario — creating realistic IAM misconfigurations, detecting them with AWS Config and IAM Access Analyzer, remediating them by applying least privilege, and documenting the entire workflow as evidence.

---

## What I Built

Two deliberately misconfigured IAM identities:

**dev-user** — An IAM user with a wildcard policy granting full access to everything in the AWS account
**dev-role** — An IAM role with overly broad S3 permissions across all buckets including delete access

Detection tools deployed:
- AWS Config with two compliance rules detecting wildcard policies and missing MFA
- IAM Access Analyzer scanning for external access risks
- IAM Unused Access Analyzer scanning for permission creep

---

## The Misconfigurations

### Misconfiguration 1 — Wildcard Policy on dev-user

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

This policy grants every possible AWS action on every resource. A compromised dev-user could create admin accounts, delete databases, exfiltrate all data, or destroy the entire AWS environment.

### Misconfiguration 2 — Broad S3 Role

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:ListAllMyBuckets"],
  "Resource": "*"
}
```

Three problems — delete permission granted, all buckets visible, wildcard resource scope. A compromised EC2 using this role could access every S3 bucket in the account.

---

## Detection — AWS Config Findings

AWS Config immediately flagged both misconfigurations:

| Rule | Resource | Status |
|---|---|---|
| iam-policy-no-statements-with-admin-access | wildcard-everything-policy | ⚠️ Noncompliant |
| iam-user-mfa-enabled | dev-user | ⚠️ Noncompliant |

---

## Remediation — Least Privilege Applied

### Fix 1 — dev-user

Detached wildcard policy. Attached least privilege policy:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": "arn:aws:s3:::specific-bucket-only/*"
}
```

### Fix 2 — dev-role

Detached overly broad S3 policy. Attached scoped policy:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": "arn:aws:s3:::specific-bucket-only/*"
}
```

Changes applied and verified via AWS CLI:

```bash
aws iam list-attached-user-policies --user-name dev-user
aws iam list-attached-role-policies --role-name dev-role
```

---

## Before vs After

| | Before | After |
|---|---|---|
| dev-user permissions | Everything in AWS | Read one bucket + CloudWatch logs |
| dev-role permissions | All S3 buckets, including delete | Read one specific bucket only |
| Delete permission | Yes | No |
| Resource scope | * (all resources) | Specific ARN only |
| Config compliance | Noncompliant | Policies fixed, wildcard quarantined |

---

## Evidence Screenshots

### IAM Access Analyzer — Active and Scanning
![Access Analyzer](./evidence/Image%2028-05-2026%20at%2017.30.jpeg)

### AWS Config — Policy Compliance Table
![Compliance Table](./evidence/Image%2028-05-2026%20at%2017.37.jpeg)

### AWS Config — All Policies Compliance Status
![Policy Status](./evidence/Image%2028-05-2026%20at%2017.40.jpeg)

### Terminal — Full Remediation Verified
![Terminal Evidence](./evidence/Image%2028-05-2026%20at%2017.58.jpeg)
---

## Key Concepts Demonstrated

**Shared Responsibility Model** — AWS secures the infrastructure. You secure identity, configuration, and data. 99% of cloud security failures are the customer's fault.

**Principle of Least Privilege** — Every user and role should have only the minimum permissions needed for their specific job. Nothing more.

**Defence in Depth** — Multiple detection layers used — Config for compliance, Access Analyzer for external exposure, Unused Access Analyzer for permission creep.

**Infrastructure as Code** — All resources deployed through Terraform. Every change version controlled and auditable in GitHub.

---

## Terraform Structure

## How to Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## How to Destroy

```bash
terraform destroy
```

---

## What I Learned

- How IAM policies are structured and what makes them dangerous
- The difference between AWS Config and IAM Access Analyzer — they detect different types of problems
- How to apply least privilege in practice — not just in theory
- Why the Capital One breach happened and how proper IAM hygiene prevents it
- How to use the AWS CLI to verify IAM changes directly
- Why dangerous policies should be deleted not just detached

---

## Tools Used
Terraform · AWS IAM · AWS Config · IAM Access Analyzer · AWS CLI · Git · GitHub
