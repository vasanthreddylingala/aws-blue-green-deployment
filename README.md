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
