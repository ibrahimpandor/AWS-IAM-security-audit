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

### AWS Config — All Policies Compliance Status
![Compliance Table](./evidence/Image%2028-05-2026%20at%2017.37.jpeg)

### AWS Config — Policy Compliance Table
![Policy Status](./evidence/Image%2028-05-2026%20at%2017.40.jpeg)

### Terminal — Full Remediation Verified
![Terminal Evidence](./evidence/Image%2028-05-2026%20at%2017.58.jpeg)
---

## Key Concepts Demonstrated

**Shared Responsibility Model** — AWS secures the infrastructure. secure identity, configuration, and data. 99% of cloud security failures are the customer's fault.

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

## What problems did i face 

1. AWS Config couldn't write to my S3 bucket
The first time I ran terraform apply it failed with an error I hadn't seen before — Config was refusing to deliver logs to my S3 bucket. After some digging I realised the bucket had no policy allowing the Config service to actually write to it. Even though Config and the bucket were in the same AWS account, Config still needed explicit permission. I added a bucket policy granting Config the s3:GetBucketAcl and s3:PutObject actions and it worked immediately. It taught me that in AWS, nothing gets access to anything without being explicitly told it can.

2. Terraform said it was fixed but AWS disagreed
This one frustrated me for a while. I changed the policy attachments in my Terraform code — renamed the resource from dev_user_wildcard to dev_user_fixed — and ran terraform apply. Terraform said the changes were applied and no differences existed. But when I checked AWS directly using the CLI, the wildcard policy was still attached to dev-user.
What happened was Terraform treated the renamed resource as a brand new one rather than an update to the existing one, so it never actually detached the old policy. I had to go into the AWS CLI manually and detach the wildcard policy myself, then attach the correct one. It was a good lesson — Terraform's state file doesn't always match what's actually in AWS, and the CLI is the ground truth.

3. Access Analyzer found nothing — and that confused me
I expected IAM Access Analyzer to immediately flag my wildcard policy as dangerous. It found nothing. I thought something was broken.
It turned out I misunderstood what Access Analyzer actually does. It only looks for resources accessible from outside your AWS account — public S3 buckets, roles that external accounts can assume, that kind of thing. My wildcard policy was dangerous but entirely internal. For internal compliance violations like wildcard policies, AWS Config is the right tool. Once I understood the difference it actually made the project stronger because now I can explain exactly why you need both tools and what each one catches.

4. Config kept saying noncompliant even after I fixed the policies
After I detached the wildcard policy from dev-user and dev-role, I went back to AWS Config expecting to see everything turn green. It still showed noncompliant. I kept refreshing thinking it just needed time to update.
Eventually I understood why — Config was evaluating the policy itself, not just whether it was attached to anyone. The wildcard-everything-policy still existed in IAM with Action: * written in it. As far as Config was concerned, that policy was dangerous regardless of whether anyone was using it. The correct final fix would be to delete the policy entirely. I chose to leave it as a documented finding because in real companies that kind of change goes through a proper approval process before deletion — you don't just delete things. I documented it in my README instead.

5. GitHub rejected my push because of a massive file
Same problem I hit in Project 1 — the .terraform provider folder was 782MB and GitHub has a 100MB limit. This time I knew what was coming. I created a .gitignore before pushing, but the file had already been committed to Git history so GitHub still rejected it. I used git filter-branch to scrub it from the entire commit history, then force pushed. Fixed. The lesson from Project 1 saved me time on Project 2.

6. Git refused to merge because of conflicting histories
When I tried to push my code, Git rejected it because my local repo and the GitHub repo had been created separately and had no shared history. They didn't know about each other. I fixed it with git pull origin main --allow-unrelated-histories which forced Git to merge the two timelines together, then pushed normally. A bit messy but straightforward once you understand what's happening.

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
