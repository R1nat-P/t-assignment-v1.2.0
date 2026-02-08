# Architecture Design for "Innovate Inc."

**Cloud Infrastructure Design Document**


---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Cloud Environment Structure](#cloud-environment-structure)
3. [Network Design](#network-design)
4. [Compute Platform](#compute-platform)
5. [Database Architecture](#database-architecture)
6. [Cost Analysis](#cost-analysis)
7. [Security Architecture](#security-architecture)
8. [CI/CD Pipeline](#cicd-pipeline)
9. [Monitoring & Disaster Recovery](#monitoring--disaster-recovery)
10. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

This document outlines a robust, scalable, secure, and cost-effective cloud architecture for Innovate Inc., a startup building a web application with:
- **Backend:** Python/Flask REST API
- **Frontend:** React SPA
- **Database:** PostgreSQL
- **Expected Growth:** From hundreds to potentially millions of users
- **Data Sensitivity:** Handles sensitive user data

### Key Design Principles

- **Start Simple, Scale Smart** - Begin with single AWS account, grow to multi-account structure
- **Cost Optimization First** - Leverage modern AWS technologies for 50% cost savings
- **Security by Design** - Private networks, encrypted data, zero public database access
- **Growth-Ready** - Architecture supports massive scaling without redesign

### Architecture Overview

![Phase 1 Architecture](diagrams/phase1-single-account-architecture.png)

**Phase 1 (Initial Launch):**
- Single AWS account with clear access separation
- Two separate Kubernetes clusters (Development and Production)
- High-availability database with automated backups
- Secure VPN access for administrators
- HashiCorp Vault for secrets management
- ELK Stack for centralized logging  
- Prometheus + Grafana for monitoring
- Velero for Kubernetes backup
- **Cost: $1,175-1,400/month** (depends on ELK choice)

**Phase 2 (Growth):**
- Three AWS accounts (Billing/Management, Development, Production)
- Enhanced security and compliance features
- **Cost: $1,500-1,800/month**

---

## Cloud Environment Structure

### Question 1: Account Strategy & Isolation

#### Phase 1: Single Account with Role Separation

**Structure:**

The architecture starts with a **single AWS account** that provides clear separation between different roles:

**Engineering Team Access:**
- Full access to infrastructure (EKS clusters, databases, networking)
- Can deploy applications, scale resources, debug issues
- **NO access to billing or cost management**
- Access controlled via IAM groups and policies

**Finance/Management Access:**
- Full access to billing, cost reports, and budgets
- Read-only view of infrastructure resources
- Can set budget alerts and analyze spending
- **NO ability to modify infrastructure**

**Environments:**

Two completely separate environments in the same account:

1. **Development Environment**
   - Kubernetes cluster: `innovate-eks-dev`
   - Database: PostgreSQL single-instance (non-critical data)
   - Engineers have full access
   - Cost-optimized configuration
   - Can tolerate downtime for experiments

2. **Production Environment**
   - Kubernetes cluster: `innovate-eks-prod`  
   - Database: PostgreSQL Multi-AZ (automatic failover)
   - Restricted access (senior engineers only)
   - High-availability configuration
   - Zero tolerance for downtime

**Why Separate Clusters?**
- Complete isolation prevents development issues from affecting production
- Independent scaling and resource allocation
- Different security policies per environment
- Clear cost attribution

**Benefits of Single Account (Phase 1):**
- ✅ Simpler to set up and manage
- ✅ Lower administrative overhead
- ✅ Faster for small teams
- ✅ All resources visible in one place
- ✅ No cross-account complexity

**Isolation Mechanisms:**
- IAM policies separate engineering vs finance access
- Separate Kubernetes clusters prevent compute interference
- Security groups control network access per environment
- Cost allocation tags track spending per environment

---

#### Phase 2: Multi-Account Organization (Growth Path)

![Multi-Account Architecture](diagrams/phase2-multi-account-architecture.png)

When the company grows (6-12 months), migrate to **AWS Organizations** with three accounts:

**1. Root/Management Account (Billing Only)**
- **Purpose:** Consolidated billing and organizational management
- **Access:** CFO, Finance team, CTO (emergency only)
- **Engineering Access:** **NONE** - Engineers cannot access this account
- **Resources:** Minimal (just billing and management tools)
- **Cost:** ~$50/month

**2. Production Account**
- **Purpose:** Customer-facing production workloads
- **Access:** Senior DevOps engineers only (with AWS SSO + AssumeRole)
- **Resources:** Production Kubernetes cluster, production database, load balancers
- **Security:** Highest level, all changes require peer review
- **Cost:** ~$600-800/month

**3. Development Account**
- **Purpose:** Development and staging environments
- **Access:** All engineers (full access to experiment)
- **Resources:** Dev/staging clusters, test databases
- **Security:** Standard level, engineers can break things safely
- **Cost:** ~$350-450/month

**Cross-Account Access:**
- Engineers in Dev account can request temporary access to Production
- Requires **AWS SSO (Single Sign-On)** authentication
- Time-limited sessions (8 hours)
- All actions logged for audit

**When to Migrate:**
- Team grows beyond 10 engineers
- Monthly spend exceeds $1,000
- Compliance requirements increase
- Need stricter production isolation

**Migration Time:** 1 week with minimal downtime

---

## Network Design

### VPC Architecture

**CIDR Block:** 10.0.0.0/16 (65,536 IP addresses)

**Three-Tier Subnet Design:**

**1. Public Subnets** (Internet-facing)
- Application Load Balancer (routes traffic to applications)
- NAT Gateways (provide internet access for private resources)
- Bastion host (optional, for emergency access)

**2. Private Subnets** (Application tier)
- Kubernetes worker nodes running applications
- No direct internet access (security benefit)
- Access internet through NAT Gateway for updates

**3. Database Subnets** (Most isolated)
- PostgreSQL databases
- **NO public IP address** - completely private
- Only accessible from application tier or via VPN

![Network Architecture](diagrams/network-detailed.png)

### High Availability

- **3 Availability Zones** - If one datacenter fails, others continue
- **3 NAT Gateways** - One per zone (production)
- **Database Failover** - Automatic switch to standby in 60-120 seconds

### Security Measures

**Network Isolation:**
- Applications isolated from databases
- Development isolated from production (separate clusters)
- All traffic encrypted in transit

**Firewall Rules (Security Groups):**
- Load Balancer: Only accepts HTTPS from internet
- Application tier: Only accepts traffic from load balancer
- Database tier: Only accepts connections from application tier

**Database Access:**
- NO public internet access
- Administrators connect via AWS Client VPN (encrypted tunnel)
- VPN requires **AWS SSO (Single Sign-On)** authentication
- All connections logged and audited

---

## Compute Platform

### Kubernetes (EKS) Configuration

**Two Separate Clusters Strategy:**

**Development Cluster:**
- Testing and experimentation environment
- Cost-optimized (100% Spot instances)
- Engineers have full deployment access
- Downtime acceptable
- Cost: ~$170/month

**Production Cluster:**
- Customer-facing workloads
- Reliability-optimized (80% Spot + 20% On-Demand)
- Restricted deployment access (senior engineers only)
- Zero downtime tolerance
- Cost: ~$525-620/month

### Karpenter Auto-Scaling

Intelligent node provisioning that:
- Monitors application demand in real-time
- Provisions nodes when pods are pending (30-60 seconds)
- Removes underutilized nodes automatically
- Selects cheapest instance type that meets requirements
- Consolidates workloads for maximum efficiency

**Scaling Behavior:**
- Normal load: 3 nodes
- Traffic spike: Auto-provisions 5 additional nodes in ~45 seconds
- Spike ends: Removes excess nodes after 5-minute stabilization window
- Result: Pay only for actual usage

### Cost Optimization

**AWS Graviton Processors (ARM64):**
- 40% cheaper than traditional processors
- Same or better performance
- Used throughout the architecture

**Spot Instances:**
- Up to 90% cheaper than regular pricing
- AWS sells unused capacity at discount
- May be interrupted (with 2-minute warning)
- Perfect for fault-tolerant applications

**Strategy:**
- Development: 100% Spot (maximum cost savings)
- Production: 80% Spot + 20% Regular (balanced cost/reliability)

### Application Deployment

**Containerization:**
- Multi-architecture Docker images (amd64 + arm64)
- Stored in Amazon ECR (Elastic Container Registry)
- Automatic image scanning for vulnerabilities
- Lifecycle policies to delete images older than 30 days

---

## Database Architecture

### PostgreSQL on Amazon RDS

**Database Configuration:**

**Development Database:**
- Instance: db.t4g.small (2 CPU, 4GB RAM)
- Single availability zone (cost-optimized)
- Acceptable for non-critical development data
- **Cost:** $20/month

**Production Database:**
- Instance: db.t4g.medium (2 CPU, 4GB RAM)
- **Multi-AZ:** Automatic failover to standby
- Encrypted storage (AWS KMS)
- 30-day automated backups
- Point-in-time recovery (restore to any second in 30 days)
- **Cost:** $85/month

### High Availability

**Multi-AZ Configuration:**
- Primary database in AZ-1 (active, read/write)
- Standby replica in AZ-2 (synchronous replication)
- Automatic failover on primary failure (60-120 seconds)
- Application reconnects automatically via RDS endpoint

### Backup & Recovery Strategy

**Automated Backups:**
- Daily snapshots taken automatically
- 30-day retention period
- Stored securely in S3
- Zero performance impact

**Point-in-Time Recovery:**
- Can restore database to any second within 30-day window
- Useful for accidental data deletion
- Creates new database (doesn't overwrite existing)

**Manual Snapshots:**
- Before major releases or migrations
- Retained indefinitely until manually deleted
- Can copy to another region for disaster recovery

**Recovery Objectives:**
- **RTO (Recovery Time):** 1 hour
- **RPO (Data Loss):** 5 minutes maximum

### Security

**Private Access Only:**
- Database has **NO public IP address**
- Not accessible from internet
- Applications connect via private network

**Administrator Access:**
- Engineers connect via **AWS Client VPN** (encrypted tunnel)
- Requires company credentials + MFA
- All connections logged and audited
- Alternative: Bastion host ($3/month, simpler but less secure)

**Encryption:**
- Data encrypted at rest (AES-256)
- Data encrypted in transit (TLS 1.2+)
- Encryption keys managed by AWS KMS

**Access Control:**
- Master credentials stored in AWS Secrets Manager (not in code)
- Application has limited database permissions
- Read-only user for analytics/reporting

### Database Scaling Path

**Phase 1 (0-10,000 users):**
- db.t4g.medium (current)
- Single database instance
- Cost: $85/month

**Phase 2 (10,000-100,000 users):**
- db.t4g.large (double the capacity)
- Add read replica for reporting
- Cost: $150-200/month

**Phase 3 (100,000+ users):**
- db.r6g.xlarge (memory-optimized)
- Multiple read replicas
- Cost: $400-500/month

**Phase 4 (Millions of users):**
- Aurora PostgreSQL (serverless)
- Auto-scaling capabilities
- Cost: $800-1,500/month

---

## Cost Analysis

### Monthly Cost Breakdown

#### Phase 1: Single Account (2 Clusters)

**Production Environment:** ~$525-620/month
- Kubernetes cluster control plane: $72
- Worker nodes (compute): $84
- Database (PostgreSQL Multi-AZ): $85
- Network (NAT Gateways, Load Balancer): $120
- VPN (secure admin access): $75-100
- HashiCorp Vault HA + storage: $40
- ELK/OpenSearch (AWS OpenSearch): $400 OR (EC2 ELK): $250
- Prometheus Stack (on EKS): $80
- Velero backups (S3 + replication): $25
- CloudWatch (minimal with ELK): $15
- Storage, other: $20

**Development Environment:** ~$220/month (with AWS OpenSearch) OR ~$255/month (with EC2 ELK)
- Kubernetes cluster control plane: $72
- Worker nodes (smaller, Spot): $15
- Database (single-AZ): $20
- Network (1 NAT Gateway): $35
- Vault (single instance): $5
- ELK/OpenSearch (AWS 1-node): $25 OR (EC2): $60
- Prometheus Stack: $15
- Velero backups: $5
- CloudWatch: $5
- Monitoring: $30

**Total Phase 1 (with AWS OpenSearch):** **$1,290-1,400/month**
**Total Phase 1 (with EC2 ELK - DevOps managed):** **$1,175-1,225/month**

**Cost Decision Factors:**
- AWS OpenSearch: +$115/month, less DevOps overhead (1-2 hours/month)
- EC2 ELK: -$115/month, more DevOps responsibility (5-10 hours/month managing ELK)

#### Phase 2: Multi-Account Organization

- Root/Management account: $50/month
- Production account: $1,070-1,150/month (with AWS OpenSearch) OR $920-970/month (with EC2 ELK)
- Development account: $450-600/month (includes staging needs)

**Total Phase 2 (with AWS OpenSearch):** **$1,570-1,800/month**
**Total Phase 2 (with EC2 ELK - DevOps managed):** **$1,420-1,620/month**

### Cost Optimization Strategies

![Cost Optimization](diagrams/cost-optimization-strategies.png)

**1. AWS Graviton Processors (40% savings)**
- Use ARM64-based processors throughout
- Same performance, much cheaper
- Savings: ~$90/month

**2. Spot Instances (50-70% savings)**
- Use spare AWS capacity at discounted prices
- Development: 100% Spot (maximum savings)
- Production: 80% Spot, 20% regular (balanced)
- Savings: ~$250/month

**3. Savings Plans (30-40% discount)**
- 1-year commitment for predictable workloads
- Applied to always-on resources
- Savings: ~$35/month

**4. VPC Endpoints (eliminate data transfer fees)**
- Direct connection to S3 (no NAT Gateway charges)
- Savings: ~$45/month

**Total Potential Savings:** ~$420/month (35-40% reduction)

**Without optimization:** $1,100-1,200/month  
**With optimization:** $750-850/month  
**Savings:** $350-450/month

### Cost Management

**Budget Alerts:**
- Alert at 80% of monthly budget
- Alert at 100% of monthly budget
- Notifications to finance team and CTO

**Cost Allocation Tags:**
- Track spending by environment (dev vs prod)
- Track spending by team (backend, frontend, data)
- Track spending by cost center

**Monthly Cost Reports:**
- Automated reports showing spend by category
- Trend analysis (compare month-over-month)
- Identify cost optimization opportunities

---

## Security Architecture

![Security Layers](diagrams/security-defense-layers.png)

### Defense-in-Depth (7 Layers)

**Layer 1: Edge Security**
- CloudFront CDN with AWS WAF
- DDoS protection (AWS Shield)
- Geographic restrictions (block high-risk countries)

**Layer 2: Network Perimeter**
- Virtual Private Cloud (VPC) isolation
- Network ACLs (subnet-level firewall)
- VPC Flow Logs (network traffic monitoring)

**Layer 3: Application Firewall**
- AWS WAF on load balancer
- Rate limiting (prevent abuse)
- SQL injection protection
- Cross-site scripting (XSS) prevention

**Layer 4: Compute Isolation**
- Private subnets (no direct internet)
- Security Groups (instance-level firewall)
- Kubernetes network policies (pod-to-pod control)

**Layer 5: Application Security**
- Input validation (all user inputs checked)
- Parameterized SQL queries (prevent injection)
- JWT tokens with expiration
- Container image scanning (detect vulnerabilities)

**Layer 6: Data Encryption**
- **At Rest:** All storage encrypted (EBS, RDS, S3) with AWS KMS
- **In Transit:** TLS 1.2+ everywhere
- Encryption keys managed by AWS KMS
- Secrets managed by HashiCorp Vault (never in code or env vars)

**Layer 7: Identity & Access**
- IAM with least privilege
- **AWS SSO (Single Sign-On)** for centralized authentication
- Role-based access control (RBAC)
- All actions logged to CloudTrail

### Compliance & Auditing

**CloudTrail:**
- All API calls logged (who, what, when, where)
- 90-day retention in CloudWatch Logs
- Long-term archival in S3 (encrypted)

**AWS Config:**
- Configuration change tracking
- Compliance rules enforcement
- Automatic remediation for violations

**VPC Flow Logs:**
- Network traffic capture
- Traffic pattern analysis
- Anomaly detection support

### Security Best Practices

**Data Protection:**
- Sensitive data encrypted everywhere
- No credentials in source code
- Database not publicly accessible
- Regular security updates

**Access Control:**
- Principle of least privilege
- **AWS SSO** for centralized authentication
- Temporary credentials (no long-lived keys)
- Regular access reviews

**Monitoring:**
- Real-time security alerts
- Automated threat detection
- Regular security audits
- Penetration testing (optional)

---

## CI/CD Pipeline

![CI/CD Pipeline](diagrams/cicd-pipeline-flow.png)

### Pipeline Workflow

**1. Code Commit** (GitHub)
- Push triggers GitHub Actions workflow via webhook

**2. Automated Testing** (GitHub Actions)
- Unit tests: pytest (Python), jest (React)
- Linting and code quality checks
- Security vulnerability scanning (Snyk, Trivy)

**3. Multi-Arch Image Build**
- Docker buildx for amd64 + arm64
- Tagged with commit SHA and semantic version
- Cached layers for faster builds

**4. Container Registry** (Amazon ECR)
- Push to ECR with vulnerability scanning
- Lifecycle policy: retain last 10 tagged images

**5. Deployment** (kubectl/ArgoCD)
- **Dev:** Auto-deploy on every commit to `develop` branch
- **Prod:** Manual approval required for `main` branch
- Rolling update strategy (zero downtime)
- HPA adjusts replicas during deployment

**6. Post-Deployment**
- Smoke tests: health and readiness endpoints
- Automated rollback on failure
- Slack notification on completion

**Timeline:** 7-11 minutes (commit to production)

---

## Logging, Monitoring & Secrets Management

### Secrets Management - HashiCorp Vault

**Architecture:**
- **1 Vault server per EKS cluster** (high availability mode)
- Deployed as StatefulSet in dedicated namespace
- Integrated with Kubernetes via Vault Agent Injector
- Secrets fetched at runtime (never stored in container images)

**Vault Configuration per Cluster:**

**Development Cluster:**
- 1 Vault instance (single node, acceptable for dev)
- Storage backend: Kubernetes secrets
- Cost: Included in cluster cost

**Production Cluster:**
- 3 Vault instances (HA with auto-unsealing)
- Storage backend: AWS KMS + DynamoDB
- Automatic backup to S3
- Cost: ~$30-50/month (storage + compute)

**Secret Injection Flow:**
1. Pod starts with Vault Agent Init Container
2. Vault Agent authenticates via Kubernetes ServiceAccount
3. Secrets fetched from Vault and written to shared volume
4. Application reads secrets from volume (not environment variables)
5. Vault Agent sidecar keeps secrets refreshed

**Benefits:**
- Dynamic secrets (generate on-demand)
- Automatic rotation without pod restart
- Centralized audit logging
- Fine-grained access control per namespace/service
- Encryption as a service

---

### Logging - ELK Stack

**Elasticsearch, Logstash, Kibana (ELK) for centralized logging**

**Architecture:**
- **1 ELK stack per account/environment**
- Development: Single ELK stack for dev cluster
- Production: Dedicated ELK stack for prod cluster

**Deployment Options:**

#### Option A: Self-Managed on EC2 (More Control, More Responsibility)

**Infrastructure:**
```
Development ELK:
- 1x t4g.large (Elasticsearch)
- Logstash: Runs on EKS nodes (DaemonSet)
- 1x t4g.small (Kibana)
- Cost: ~$60/month
- Storage: 100GB EBS gp3

Production ELK:
- 3x t4g.xlarge (Elasticsearch cluster for HA)
- Logstash: Runs on EKS nodes (DaemonSet)
- 2x t4g.medium (Kibana HA)
- Cost: ~$250-300/month
- Storage: 500GB EBS gp3 with snapshots
```

**Pros:**
- Full control over configuration
- Can tune performance precisely
- Lower cost for moderate log volumes
- No AWS service limits

**Cons:**
- **DevOps team must manage it** (patches, upgrades, scaling)
- Manual backup/restore procedures
- Requires Elasticsearch expertise
- On-call responsibility for ELK issues
- Time investment: ~5-10 hours/month

---

#### Option B: AWS OpenSearch Service (Managed, Less Responsibility)

**Infrastructure:**
```
Development:
- OpenSearch domain: 1 node (t3.small.search)
- Cost: ~$25/month
- Managed by AWS

Production:
- OpenSearch domain: 3 nodes (r6g.large.search)
- Multi-AZ deployment
- Cost: ~$400/month
- Automatic backups, patches, scaling
```

**Pros:**
- AWS manages infrastructure (patches, backups, HA)
- Automatic scaling
- Built-in monitoring and alerting
- Less DevOps overhead (~1-2 hours/month)
- 99.9% SLA

**Cons:**
- Higher cost (especially at scale)
- Less flexibility in configuration
- Subject to AWS service limits
- Vendor lock-in

---

**Recommendation:**
- **Development:** Self-managed on EC2 (low volume, good for learning)
- **Production:** AWS OpenSearch Service initially, migrate to EC2 if log volume exceeds 500GB/day

**Log Collection:**
- Fluent Bit DaemonSet on all EKS nodes
- Collects logs from all pods
- Enriches with Kubernetes metadata
- Sends to Elasticsearch/OpenSearch
- Log retention: 7 days (dev), 30 days (prod)

---

### Monitoring & Alerting - Prometheus Stack

**Kube-Prometheus-Stack on EKS**

Deployed on each EKS cluster using Helm chart:
- **Prometheus:** Metrics collection and storage
- **Grafana:** Visualization dashboards
- **Alertmanager:** Alert routing and notification
- **Node Exporter:** Host-level metrics
- **Kube-State-Metrics:** Kubernetes object metrics

**Architecture per Cluster:**

**Development Cluster:**
```
Components:
- Prometheus: 1 replica (10GB storage)
- Grafana: 1 replica
- Alertmanager: 1 replica
- Cost: ~$15/month (storage + small nodes)
- Retention: 7 days
```

**Production Cluster:**
```
Components:
- Prometheus: 2 replicas (100GB storage each)
- Grafana: 2 replicas (HA)
- Alertmanager: 3 replicas (HA)
- Cost: ~$80/month (storage + compute)
- Retention: 30 days
```

**Metrics Collected:**
- Infrastructure: CPU, memory, disk, network
- Kubernetes: Pod status, deployments, resource usage
- Application: Custom metrics (request rate, latency, errors)
- Database: RDS metrics via CloudWatch exporter

**Dashboards (Pre-configured):**
- Cluster Overview
- Node Resources
- Pod Resources
- Application Performance (RED metrics: Rate, Errors, Duration)
- Database Performance

**Alerting Rules:**

**Critical (PagerDuty):**
- Cluster nodes down
- Production pods crash looping
- Database connection failures
- Disk space < 10%
- Memory usage > 90%

**Warning (Slack):**
- High CPU usage (> 80% for 10 min)
- High memory usage (> 85% for 10 min)
- Slow response times (> 2s p95)
- Error rate > 1%

**Alert Routing:**
- Critical: PagerDuty → On-call engineer
- Warning: Slack #alerts channel
- Info: Slack #monitoring channel

---

### Cost Comparison

| Component | Self-Managed | AWS Managed | Recommendation |
|-----------|-------------|-------------|----------------|
| **Secrets (Vault)** | Included in EKS | N/A | Self-managed (no AWS alternative) |
| **Logs (Dev)** | $60/mo (EC2 ELK) | $25/mo (OpenSearch) | AWS OpenSearch (simpler) |
| **Logs (Prod)** | $250-300/mo (EC2 ELK) | $400/mo (OpenSearch) | EC2 ELK if > 500GB/day |
| **Monitoring** | Included in EKS | $50-100/mo (CloudWatch) | Prometheus Stack (better) |

**Total Added Cost:**
- Development: ~$100-150/month (OpenSearch + monitoring)
- Production: ~$350-450/month (OpenSearch or ELK + monitoring + Vault HA)

---

**Infrastructure:**
- CPU usage > 80% for 5 minutes
- Memory usage > 85% for 5 minutes
- Database storage < 10GB remaining
- Database connections > 80% of max

**Application:**
- Error rate > 1% for 5 minutes
- Response time > 2 seconds for 5 minutes
- Zero traffic for 5 minutes (possible outage)

**Notifications:**
- Email to engineering team
- SMS for critical production issues
- PagerDuty integration (optional)

### Disaster Recovery

**Recovery Objectives:**
- **RTO (Recovery Time Objective):** 1 hour
- **RPO (Recovery Point Objective):** 5 minutes of data loss max

**Disaster Scenarios:**

**1. Database Failure**
- Multi-AZ automatic failover: 60-120 seconds
- If both fail: Restore from backup in 15-30 minutes
- Point-in-time recovery available

**2. Kubernetes Cluster Failure**

**Velero Backup Strategy:**

Velero backs up Kubernetes resources and persistent volumes to S3:

**Development Cluster:**
```
Backup Schedule:
- Full cluster backup: Daily at 2 AM UTC
- Namespace backups: Every 6 hours
- Retention: 7 days
- Storage: S3 bucket (us-east-1)
- Cost: ~$5/month (S3 storage)
```

**Production Cluster:**
```
Backup Schedule:
- Full cluster backup: Every 6 hours
- Critical namespaces: Every 1 hour
- Retention: 30 days
- Storage: S3 bucket with cross-region replication to us-west-2
- Cost: ~$20-30/month (S3 storage + replication)
```

**What Velero Backs Up:**
- All Kubernetes resources (Deployments, Services, ConfigMaps, Secrets)
- Persistent Volume snapshots (EBS volumes)
- Namespace metadata and RBAC policies
- Custom Resource Definitions (CRDs)
- Vault configuration (if stored in Kubernetes)

**Recovery Procedure:**
1. Provision new EKS cluster (if needed): 15 minutes
2. Install Velero: 2 minutes
3. Restore from latest backup: 5-10 minutes
4. Verify applications: 5 minutes
**Total Recovery Time:** 30-40 minutes

**Velero Configuration per Cluster:**
- Deployed as Deployment in `velero` namespace
- Uses IAM role for S3 access (IRSA)
- Compression enabled (reduces S3 costs)
- Incremental backups (only changed resources)

**3. Regional Outage** (Rare)
- Cross-region S3 backup available
- Velero can restore to different region
- Manual failover to us-west-2
- Recovery time: 1-2 hours (requires manual intervention)

**Backup Strategy Summary:**

| Component | Backup Method | Frequency | Retention | Recovery Time |
|-----------|--------------|-----------|-----------|---------------|
| **RDS Database** | Automated snapshots | Daily + PITR | 30 days | 15-30 min |
| **EKS Resources** | Velero to S3 | Hourly (prod), Daily (dev) | 30 days (prod), 7 days (dev) | 30-40 min |
| **Persistent Volumes** | Velero EBS snapshots | With cluster backup | Same as cluster | 10-20 min |
| **Container Images** | ECR (versioned) | On push | Lifecycle policy | Immediate |
| **Infrastructure** | Terraform in Git | On commit | Unlimited | 20-30 min |
| **Vault Secrets** | S3 backup | Every 6 hours | 30 days | 5-10 min |

### Business Continuity

**Availability Target:** 99.95% uptime
- ~22 minutes of downtime allowed per month
- Multi-AZ design prevents most outages
- Automatic failover for databases
- Self-healing Kubernetes for applications

---

## Implementation Roadmap

### Phase 1: MVP Launch (Weeks 1-4)

**Week 1: Infrastructure Setup**
- Set up AWS account and billing
- Deploy VPC and networking
- Create Kubernetes clusters (dev and prod)
- Deploy databases (dev and prod)
- Estimated time: 5-10 hours with automation

**Week 2: Application Deployment**
- Containerize Flask backend
- Containerize React frontend
- Push containers to registry
- Deploy to development cluster
- Test end-to-end functionality
- Estimated time: 10-15 hours

**Week 3: CI/CD Pipeline**
- Set up GitHub Actions workflows
- Configure automated testing
- Set up automated deployments
- Implement approval process for production
- Estimated time: 8-12 hours

**Week 4: Monitoring & Launch**
- Configure CloudWatch alarms
- Set up Grafana dashboards
- Load testing
- Security review
- **Soft launch to beta users**
- Estimated time: 10-15 hours

**Deliverables:**
- ✅ Working development environment
- ✅ Working production environment
- ✅ Automated deployment pipeline
- ✅ Monitoring and alerts
- ✅ Security hardened

**Cost at Launch:** $750-850/month

---

### Phase 2: Optimize & Scale (Months 2-6)

**Months 2-3: Cost Optimization**
- Enable Savings Plans (commit to 1 year)
- Increase Spot instance usage
- Implement VPC endpoints
- Reduce logging costs
- **Target:** 20-30% cost reduction

**Months 4-5: Performance Tuning**
- Analyze database performance
- Add read replicas if needed
- Optimize slow queries
- Implement caching layer (optional)
- **Target:** Maintain <500ms response time

**Month 6: Enhanced Monitoring**
- Advanced Grafana dashboards
- Custom business metrics
- Cost tracking by feature
- User analytics integration

---

### Phase 3: Multi-Account Migration (Months 6-12)

**Triggers for Migration:**
- Team grows beyond 10 engineers
- Monthly cost exceeds $1,000
- Compliance requirements
- Need stricter production isolation

**Migration Steps:**
1. Create AWS Organization (1 day)
2. Create Development account (2 days)
3. Create Production account (3 days)
4. Migrate production workloads (1 week)
5. Set up cross-account access (2 days)
6. Update CI/CD pipelines (3 days)

**Migration Time:** 2-3 weeks  
**Downtime:** Minimal (few minutes during cutover)

---

### Phase 4: Advanced Features (Year 2+)

**Optional Enhancements:**

**Multi-Region Deployment:**
- Deploy in second AWS region (us-west-2)
- Disaster recovery failover
- Reduced latency for distant users
- Additional cost: $300-400/month

**Enhanced Security:**
- AWS GuardDuty (threat detection)
- AWS Security Hub (compliance dashboard)
- Regular penetration testing
- Additional cost: $50-100/month

**Advanced Monitoring:**
- Distributed tracing
- Anomaly detection (ML-based)
- Predictive scaling
- Additional cost: $50-100/month

---

## Summary & Next Steps

### Architecture Highlights

✅ **Cost-Effective:** $750-850/month (50% savings vs traditional approach)  
✅ **Scalable:** Handles growth from hundreds to millions of users  
✅ **Secure:** 7-layer security, encrypted data, private databases  
✅ **Highly Available:** 99.95%+ uptime with automatic failover  
✅ **Growth-Ready:** Clear path from single account to enterprise setup  
✅ **Well-Documented:** Complete architecture with visual diagrams

### Key Decisions

**Question 1 - Cloud Environment:**
- **Phase 1:** Single AWS account with IAM separation (engineers vs finance)
- **Phase 2:** Three accounts in AWS Organizations (Billing, Dev, Prod)
- **Isolation:** Engineers = infrastructure access, Finance = billing access

**Question 2 - Network Design:**
- VPC with 3-tier architecture (public/private/database)
- Multi-AZ for high availability
- Private database with VPN admin access
- Security groups and network policies

**Question 3 - Compute Platform:**
- Two separate Kubernetes (EKS) clusters (dev and prod)
- Karpenter for intelligent auto-scaling
- Graviton processors + Spot instances for cost savings
- Docker containers with multi-arch support

**Question 4 - Database:**
- Amazon RDS PostgreSQL (fully managed)
- Multi-AZ for production (automatic failover)
- 30-day automated backups + point-in-time recovery
- Private access only (no public endpoint)
- VPN for administrator access

### Next Steps

1. **Review & Approve** this architecture design
2. **Set up AWS account** and billing
3. **Deploy infrastructure** using provided Terraform code (Week 1)
4. **Containerize applications** (Week 2)
5. **Set up CI/CD pipeline** (Week 3)
6. **Deploy & launch** (Week 4)

### Success Metrics

**Cost:**
- ✅ Under $900/month for Phase 1
- ✅ 50% cheaper than traditional approach

**Performance:**
- ✅ Response time < 500ms (95th percentile)
- ✅ Uptime > 99.95% (22 min/month downtime max)

**Security:**
- ✅ Database not publicly accessible
- ✅ All data encrypted
- ✅ MFA required for admin access

**Scalability:**
- ✅ Auto-scales from 3 to 50 servers based on demand
- ✅ Handles 10x traffic spikes gracefully

---

## Appendix: Architecture Diagrams Reference

All detailed architecture diagrams are located in the `diagrams/` folder. Below is a quick reference guide:

### Available Diagrams

**1. Phase 1 - Single Account Architecture** (`phase1-single-account-architecture.png`)
- Shows 2 separate EKS clusters (dev and prod) in single AWS account
- Complete VPC layout with 3 availability zones per environment
- **Observability stacks visible inside each EKS cluster:**
  - HashiCorp Vault for secrets management
  - ELK Stack (Elasticsearch, Logstash, Kibana) for logging
  - Prometheus + Grafana for metrics and monitoring
- Development environment (left): Cost-optimized with 100% Spot
- Production environment (right): HA with Multi-AZ RDS, 3 NAT Gateways
- Velero backup to S3 shown
- Cost: $1,175-1,400/month (depends on EC2 vs AWS OpenSearch for ELK)

**2. Phase 2 - Multi-Account Architecture** (`phase2-multi-account-architecture.png`)
- Shows AWS Organizations with 3 accounts (Root, Dev, Prod)
- Detailed VPC layouts for each account with complete observability stacks

**Root/Management Account (top):**
- AWS Organizations, consolidated billing, CloudTrail, SCPs
- Access: Finance, CFO only via **AWS SSO** - NO Engineers
- Cost: $50/month

**Development Account (middle - detailed VPC 10.1.0.0/16):**
- EKS cluster: innovate-eks-dev across 3 AZs
- **Inside cluster:** Vault (1 pod), Prometheus, Grafana, ELK Stack
- RDS dev: db.t4g.small (single-AZ)
- 1 NAT Gateway (cost-optimized)
- 100% Spot instances
- Access: ALL Engineers (full) via **AWS SSO**
- Cost: $450-600/month

**Production Account (bottom - detailed VPC 10.0.0.0/16):**
- EKS cluster: innovate-eks-prod across 3 AZs
- **Inside cluster:** Vault HA (3 pods), Prometheus HA (2 pods), Grafana HA, ELK Cluster (3-node HA)
- RDS prod: db.t4g.medium (Multi-AZ primary + standby shown)
- 3 NAT Gateways (HA), ALB + AWS WAF
- AWS Client VPN endpoint, Velero backups
- S3 + CloudFront
- 80% Spot + 20% On-Demand
- Access: Senior DevOps via **AWS SSO + AssumeRole**
- Cost: $1,070-1,150/month

**Cross-Account Access:** Dev → Prod via AssumeRole with **AWS SSO**

**Total Cost:** $1,570-1,800/month

**Use this diagram to:** Understand multi-account structure with complete observability and security controls per account, showing Vault, ELK, and Prometheus deployed in each cluster.

**3. Network Architecture** (`network-detailed.png`)
- Three-tier subnet design (Public/Private/Database)
- Security groups and firewall rules
- Traffic flow from internet to database
- High availability across 3 availability zones

**4. CI/CD Pipeline** (`cicd-pipeline-flow.png`)
- Complete deployment automation workflow
- GitHub → Testing → Docker Build → ECR → EKS
- Timeline: 7-11 minutes from commit to production
- Zero-downtime deployment strategy

**5. Cost Optimization** (`cost-optimization-strategies.png`)
- Visual breakdown of 5 cost-saving techniques
- Baseline: $1,000-1,200/month
- Optimized: $450-650/month
- Total savings: $500/month (45-50%)

**6. Security Architecture** (`security-defense-layers.png`)
- 7-layer defense-in-depth model
- From edge security to database encryption
- CloudTrail audit logging and threat detection

### Diagram Quick Reference

| Diagram | Use Case | Key Information |
|---------|----------|-----------------|
| Phase 1 | Initial deployment | Single account with 2 clusters |
| Phase 2 | Growth planning | Multi-account separation |
| Network | Security review | VPC topology and isolation |
| CI/CD | DevOps process | Deployment automation |
| Cost | Budget planning | Savings breakdown |
| Security | Compliance | Defense layers |


