# Enterprise AWS Blue-Green Deployment Architecture

[![AWS](https://img.shields.io/badge/AWS-ap--south--1-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform_v1.17+-blue?logo=terraform)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Config-Ansible_v2.21+-red?logo=ansible)](https://www.ansible.com/)
[![Docker](https://img.shields.io/badge/Containers-Docker_Multi--Stage-2496ED?logo=docker)](https://www.docker.com/)
[![Jenkins](https://img.shields.io/badge/CI%2FCD-14--Stage_Jenkinsfile-D24939?logo=jenkins)](https://www.jenkins.io/)

A complete, production-grade Infrastructure as Code (IaC) and CI/CD project implementing zero-downtime **Blue-Green Deployments** on Amazon Web Services (AWS) for a 3-tier microservices application (React, Java 17 Spring Boot, and MySQL 8.0).

---

## 1. Executive Summary & Architecture

In mission-critical production environments, traditional in-place deployments cause downtime, user-facing 502 errors, and risky rollbacks. 

This project implements an **automated, zero-downtime Blue-Green deployment architecture**:
- **Blue Environment**: Active production serving 100% of live traffic (running Version 1.0.0).
- **Green Environment**: Staging environment where candidate releases (Version 2.0.0) are deployed, containerized, and smoke-tested in complete isolation.
- **Application Load Balancer (ALB)**: Shifts 100% of live traffic from Blue to Green in milliseconds via listener target group re-pointing.
- **Sub-Second Rollback**: If health checks or metrics degrade post-deployment, the ALB listener rule is reverted back to Blue in **less than 1 second** with zero redeployment delay.

### End-to-End Architecture Flowchart

```text
                                  PUBLIC INTERNET
                                         |
                                         v
                              [ AWS Internet Gateway ]
                                         |
                 +-----------------------+-----------------------+
                 |                                               |
     [ Public Subnet A: ap-south-1a ]                [ Public Subnet B: ap-south-1b ]
     CIDR: 10.0.1.0/24                               CIDR: 10.0.2.0/24
                 |                                               |
                 +-----------------------+-----------------------+
                                         |
                        [ Application Load Balancer (ALB) ]
                        Port 80 (Public Security Group: 0.0.0.0/0)
                                         |
                 +-----------------------+-----------------------+
                 | (Active Production Traffic)                   | (Staging / Testing Traffic)
                 v                                               v
        [ Blue Target Group ]                           [ Green Target Group ]
        Health Check: /api/health                       Health Check: /api/health
                 |                                               |
                 v                                               v
     +-----------------------+                       +-----------------------+
     |  EC2 Instance: BLUE   |                       |  EC2 Instance: GREEN  |
     |  (t3.small, Ubuntu)   |                       |  (t3.small, Ubuntu)   |
     |                       |                       |                       |
     |  [Frontend (Nginx)]   |                       |  [Frontend (Nginx)]   |
     |  [Backend (Spring)]   |                       |  [Backend (Spring)]   |
     |  [MySQL 8.0 (Shared)] |                       |  [MySQL 8.0 (Shared)] |
     +-----------+-----------+                       +-----------+-----------+
                 |                                               |
                 +-----------------------+-----------------------+
                                         |
                           [ Amazon ECR Registry ]
                           - bluegreen-backend:v1.0.0 / v2.0.0
                           - bluegreen-frontend:v1.0.0 / v2.0.0
```

---

## 2. Key Engineering & Cost-Control Decisions

| Component | Engineering Decision | Production Justification |
| :--- | :--- | :--- |
| **Network Architecture** | **Zero NAT Gateways** | Saved **~₹3,500/month ($41/mo)** by avoiding expensive NAT Gateways. EC2 instances reside in public subnets with direct IGW routing, secured by Zero-Trust Security Groups. |
| **Security Groups** | **Zero-Trust Lockdown** | EC2 ports 80 and 8080 **never accept direct public internet traffic**; they accept traffic *strictly* originating from the ALB Security Group ID. Port 3306 (MySQL) has zero public exposure. |
| **Containerization** | **Multi-Stage Builds** | Backend image size reduced from **800MB to 180MB** by separating Maven compilation from the Alpine JRE runtime. Enforced non-root user execution (`appuser`) and container memory awareness (`-XX:MaxRAMPercentage=75.0`). |
| **Database Strategy** | **Shared DB & Expand-Contract** | Independent databases cause data drift and lost customer transactions. Blue and Green share a common database using the Expand-Contract (Parallel-Run) schema migration pattern. |
| **Traffic Steering** | **ALB Listener Re-Pointing** | Avoids DNS TTL caching delays. Shifting traffic at the load balancer level ensures global cutover in milliseconds. |

---

## 3. Repository Directory Structure

```text
├── Jenkinsfile                 # 14-stage declarative CI/CD pipeline with automated rollback
├── docker-compose.prod.yml      # Multi-container production compose specification
├── .gitignore                  # Enforces security: ignores .tfstate, .pem keys, and build files
├── README.md                   # Complete architectural and operational documentation
├── backend/
│   ├── Dockerfile              # Multi-stage Maven 3.9 + Temurin JDK 17 -> JRE 17 Alpine
│   ├── pom.xml                 # Spring Boot Web, Data JPA, Actuator, MySQL Driver
│   └── src/                    # Java REST API (/api/health, /api/info, /api/tasks)
├── frontend/
│   ├── Dockerfile              # Multi-stage Node 18 build -> Nginx Alpine runtime
│   ├── nginx.conf              # Reverse proxy routing / to React and /api/ to Spring Boot
│   └── src/                    # React UI displaying dynamic Blue/Green environment theme
├── database/
│   └── init.sql                # MySQL schema definition and initial data seed
├── terraform/
│   ├── providers.tf            # AWS Provider (ap-south-1), TLS, and Local providers
│   ├── variables.tf            # Configurable CIDRs, instance types, and region definitions
│   ├── vpc.tf                  # Custom VPC, 2 Multi-AZ Subnets, IGW, and Route Tables
│   ├── security_groups.tf      # ALB public ingress and EC2 zero-trust ingress rules
│   ├── alb.tf                  # ALB, Blue/Green Target Groups, and Port 80 Listener
│   ├── ec2.tf                  # Ubuntu 22.04 LTS AMIs, IAM Instance Profiles, SSH Key Pairs
│   ├── ecr.tf                  # Private registries with automated CVE scanning & lifecycle rules
│   └── outputs.tf              # ALB DNS, public IPs, and Target Group ARNs
└── ansible/
    ├── ansible.cfg             # Automation defaults (host_key_checking = False)
    ├── inventory.ini           # Inventory defining [blue], [green], and [app_servers]
    ├── setup_docker.yml        # Host provisioning: Docker Engine, Compose plugin, AWS CLI
    └── deploy.yml              # Deployment playbook: ECR pull, container launch, health check
```

---

## 4. The 14-Stage Jenkins CI/CD Pipeline

The `Jenkinsfile` orchestrates an automated, enterprise release process:

```text
[Stage 1: Checkout] ➔ Clones source code from GitHub main branch
         |
[Stage 2: Code Validation] ➔ Syntax checking and static analysis
         |
[Stage 3: Build Application] ➔ Compiles Java backend and packages React static bundle
         |
[Stage 4: Unit Testing] ➔ Executes test suites to prevent regression bugs
         |
[Stage 5: Docker Image Build] ➔ Multi-stage builds for linux/amd64 architecture
         |
[Stage 6: Security Scan] ➔ Audits Docker layers and packages for CVE vulnerabilities
         |
[Stage 7: Push Image to ECR] ➔ Pushes versioned images (v1.0.0, v2.0.0) to AWS ECR
         |
[Stage 8: Deploy to Inactive] ➔ Queries ALB, detects idle environment, deploys new version
         |
[Stage 9: Health Check Gate] ➔ Polls /api/health until HTTP 200 OK (fails if container crashed)
         |
[Stage 10: Smoke Testing] ➔ Executes end-to-end API integration and database write tests
         |
[Stage 11: Production Approval] ➔ Release manager manual sign-off gate in Jenkins UI
         |
[Stage 12: ALB Traffic Shift] ➔ Calls AWS ELBv2 API to shift traffic to new target group
         |
[Stage 13: Post-Verification] ➔ Validates live public ALB traffic
         |
[Stage 14: Automated Rollback] ➔ Reverts ALB listener rule instantly if any stage fails
```

---

## 5. Operational Runbooks

### 1. Triggering a Zero-Downtime Deployment
To deploy Version 2.0.0 to the inactive environment and shift traffic:

```bash
# 1. Deploy Version 2 containers to Green
cd ansible && ansible-playbook deploy.yml -e "target_env=green image_tag=v2.0.0 app_env=GREEN"

# 2. Shift 100% of public traffic to Green at the Load Balancer
aws elbv2 modify-listener \
  --listener-arn <ALB_LISTENER_ARN> \
  --default-actions Type=forward,TargetGroupArn=<GREEN_TARGET_GROUP_ARN>
```

### 2. Executing an Emergency Rollback (< 1 second)
If an unhandled exception or memory leak occurs post-deployment:

```bash
# Revert traffic back to the proven, healthy Blue environment
aws elbv2 modify-listener \
  --listener-arn <ALB_LISTENER_ARN> \
  --default-actions Type=forward,TargetGroupArn=<BLUE_TARGET_GROUP_ARN>
```

---

## 6. Failure Simulation & Chaos Testing Verification

During chaos engineering testing, we simulated 4 real-world production failure modes:

1. **Container Crash Simulation**: Killed the Spring Boot backend (`docker stop app-backend`).
   - *Result*: The automated deployment gate detected `Connection refused` and aborted the release. Production traffic on Blue remained 100% unaffected.
2. **Target Group Health Transition**: Observed targets moving between `healthy` and `unused`.
   - *Finding*: AWS ALB marks inactive target groups as `unused` when not bound to an active listener rule, conserving AWS compute resources.
3. **Architecture Mismatch Prevention**: Handled cross-compilation from Apple Silicon (ARM64) to AWS EC2 (x86_64) using `--platform linux/amd64`.
   - *Result*: Prevented fatal `exec format error` container crashes on EC2.
4. **Log Exhaustion Protection**: Implemented global Docker log rotation (`max-size: 10m`, `max-file: 3`), ensuring containers cannot exhaust the 10GB EBS root storage.

---

## 7. High-Yield Interview Q&A

### Q1: Why Blue-Green over Rolling or Canary deployments?
**Answer:** Rolling deployments update instances in batches. If a bug is discovered halfway, rollback requires redeploying the old version sequentially across all instances (taking 15–30 minutes). In Blue-Green deployments, the previous environment remains running in the background; rollback is a single load-balancer listener shift taking **less than 1 second**.

### Q2: How do you prevent data loss with databases in Blue-Green?
**Answer:** We never deploy independent databases for Blue and Green. Both environments share a single database to prevent data drift. Schema changes follow the **Expand-Contract (Parallel-Run)** pattern:
- **Expand**: Add non-breaking nullable columns or tables supporting both versions.
- **Switch**: Shift traffic to the new version.
- **Contract**: Remove deprecated columns only after the release has been proven stable in production.

### Q3: Why combine Terraform and Ansible instead of using just one?
**Answer:** We enforce the principle of separation of concerns:
- **Terraform** provisions immutable cloud infrastructure (VPC, Subnets, ALB, Target Groups, EC2, IAM, ECR).
- **Ansible** provisions software configuration inside the instances (installing Docker, configuring systemd services, managing user permissions, and deploying containers).

---

## 8. Resume-Ready Experience Summary

- **Architected and deployed a production-grade Zero-Downtime Blue-Green Deployment pipeline** on AWS for a 3-tier microservices application (React, Java 17 Spring Boot, MySQL 8.0).
- **Automated cloud infrastructure provisioning using Terraform (IaC)**, implementing a multi-AZ VPC, Application Load Balancers, dynamic Target Groups, IAM instance profiles, and private Amazon ECR registries.
- **Engineered idempotent Ansible playbooks** to configure Docker host daemons, enforce container log rotation policies, and manage multi-container lifecycle deployments across environments.
- **Authored a 14-stage declarative Jenkins CI/CD pipeline** featuring multi-stage Docker builds, automated health check verification gates, zero-downtime ALB traffic switching, and sub-second automated rollback handlers.
- **Optimized cloud architecture costs saving ~₹3,500/month** by eliminating NAT Gateways in favor of public subnets secured with Zero-Trust Security Groups restricting application ports strictly to ALB origin traffic.