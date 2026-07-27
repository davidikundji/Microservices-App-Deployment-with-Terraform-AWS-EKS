# Techpathway BothCamp — Multi-Service Architecture

What started as a single Flask app is now three independently deployable
services, each with its own codebase and its own Dockerfile. They only talk
to each other over HTTP — no shared filesystem, no shared database.

This repo covers the services and their images only. The Kubernetes cluster,
manifests, secrets management, ingress, and monitoring are all owned by the
DevOps team's infrastructure repo — not here. What DevOps needs from this
repo is three container images and the contract described below.

```
                          ┌─────────────────────┐
                          │   main-app (:5111)   │
                          │  storefront + admin  │
                          │  MySQL/RDS or SQLite │
                          └─────────┬─────┬──────┘
                     order placed → auto-confirmed
                                    │     │
                                    ▼     ▼
                ┌────────────────────┐ ┌──────────────────────────┐
                │ action-messages     │ │ techpathway-warehouse     │
                │ (:5001)             │ │ (:5002)                   │
                │ emails the customer │ │ inventory + fulfillment   │
                │ + CC's a fixed addr │ │ own SQLite DB             │
                │ own SQLite log      │ │                           │
                └────────────────────┘ └──────────────────────────┘
```

## The 3 services

**`weekly-call/`** — main-app (storefront brand: "Techpathway BothCamp"). The existing Flask admin dashboard +
storefront. Orders are **auto-confirmed on placement** — both the storefront
checkout and the admin "New Order" form set status to `confirmed`
immediately and call out to the other two services right away. No manual
status change is needed to trigger the warehouse hand-off or the
confirmation email; the admin order-detail page can still move a confirmed
order through `processing → shipped → delivered` afterward.

**`action-messages/`** (formerly `notification-service`) — one job:
`POST /notify/order-confirmed` generates a tracking number, then sends (or,
without SMTP configured, logs) a short "congratulations, you built the
Techpathway Kubernetes project!" email to the customer, **always CC'd to
`ALWAYS_CC_EMAIL`** (default `m.olujobi1@gmail.com`) unless the customer's
own address happens to match it. Signed from **The Techpathway Team, Weekly
Class**. Has its own dashboard at `/` showing every message sent, its
tracking number, and who it was CC'd to. Own SQLite audit log.

**`techpathway-warehouse/`** (formerly `warehouse-service`) — receives every
new order via `POST /warehouse/orders`, decrements its own inventory, and
tracks each order through `received → picking → packed → shipped` on a
small kanban board at `/`. Own SQLite DB, seeded with the same 8 SKUs as the
storefront.

## The contract DevOps needs

Whoever writes the Deployment/Service manifests for these three images
needs to know:

| Service | Image built from | Port | Health check | Required env vars |
|---|---|---|---|---|
| main-app | `weekly-call/` | 5111 | `GET /health` | `SECRET_KEY`, `NOTIFICATION_SERVICE_URL`, `WAREHOUSE_SERVICE_URL`, `NOTIFICATION_PUBLIC_URL`, `WAREHOUSE_PUBLIC_URL`. Optional: `MYSQL_*` / `S3_*` / `AWS_*` (falls back to local SQLite + local images if unset) |
| action-messages | `action-messages/` | 5001 | `GET /health` | `FROM_EMAIL`, `FROM_NAME`, `ALWAYS_CC_EMAIL`. Optional: `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`/`SMTP_PASSWORD` (blank `SMTP_HOST` = demo mode, logs instead of sending) |
| techpathway-warehouse | `techpathway-warehouse/` | 5002 | `GET /health` | none required |

`NOTIFICATION_SERVICE_URL` and `WAREHOUSE_SERVICE_URL` are how main-app
reaches the other two — whatever DNS name/Service name they get in the
cluster needs to go in those two vars. `NOTIFICATION_PUBLIC_URL` /
`WAREHOUSE_PUBLIC_URL` are separate on purpose: they're browser-facing links
shown in the admin sidebar, so they need to be real externally reachable
hostnames, not internal Service DNS.

`action-messages` and `techpathway-warehouse` each use a local SQLite file
as their datastore — if DevOps runs more than 1 replica of either, they'll
need a persistent volume per pod (or a real shared database) since SQLite
doesn't support concurrent writers across pods. `main-app` is stateless
per-request and safe to run at 2+ replicas out of the box (assuming
MySQL/RDS is configured — multiple replicas each with their own local
SQLite file would see different data).

All calls between services are "best effort": if a sibling pod is down or
slow, the admin action that triggered the call (placing an order) still
succeeds — the failure is logged, not raised.

## Secrets: AWS Secrets Manager (optional)

Both `main-app` and `action-messages` support pulling real credentials from
AWS Secrets Manager instead of a plaintext `.env` file — useful once this
goes past local demo/bootcamp use, since it means SMTP passwords, the RDS
password, and AWS keys never have to sit in a file (or get pasted anywhere).

How it works: set `SECRETS_MANAGER_SECRET_NAME` (and optionally `AWS_REGION`,
defaults to `us-east-1`) to the name/ARN of a secret holding a JSON object of
env-var keys and values, e.g.:

```bash
aws secretsmanager create-secret \
  --name techpathway/action-messages \
  --secret-string '{"SMTP_HOST":"smtp.gmail.com","SMTP_PORT":"587","SMTP_USER":"you@gmail.com","SMTP_PASSWORD":"your-app-password","ALWAYS_CC_EMAIL":"m.olujobi1@gmail.com"}'
```

At startup, each app fetches that secret and merges its keys into its own
environment, overriding anything set locally. If `SECRETS_MANAGER_SECRET_NAME`
is left blank (the default), this is skipped entirely and everything works
exactly as before — plain env vars / `.env` / demo mode. If the fetch fails
for any reason (missing IAM permission, wrong secret name, wrong region), the
app logs a warning and falls back to its local env vars rather than crashing
— a broken secret should never take down the service.

Whichever role/user the container runs as in production needs
`secretsmanager:GetSecretValue` permission on the relevant secret(s) — that's
an IAM policy DevOps would attach to the ECS task role / EKS pod's IAM role
(via IRSA), not something baked into the image.

## Run everything locally (docker-compose)

```bash
docker compose up --build
```

| Service | URL |
|---|---|
| Storefront/admin | http://localhost:5111 |
| Action messages | http://localhost:5001 |
| Warehouse board | http://localhost:5002 |

Try it end to end: place an order from `/store` (or `/orders/new` in the
admin) — it's confirmed automatically, so within a couple seconds it should
show up on the warehouse board at `:5002` and a message should appear on
`:5001` with a tracking number.

No Docker yet? `bash run-local.sh` does the same thing with plain Python
venvs instead of containers.

## Build and push to Amazon ECR

Replace `<account-id>` and `<region>` with yours (find your account ID with
`aws sts get-caller-identity`):

```bash
export AWS_ACCOUNT_ID=<account-id>
export AWS_REGION=<region>
export ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 1. Create a repo per service (one-time)
aws ecr create-repository --repository-name main-app                 --region $AWS_REGION
aws ecr create-repository --repository-name action-messages          --region $AWS_REGION
aws ecr create-repository --repository-name techpathway-warehouse    --region $AWS_REGION

# 2. Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

# 3. Build, tag, and push each image
docker build -t main-app ./weekly-call
docker tag main-app:latest $ECR_REGISTRY/main-app:latest
docker push $ECR_REGISTRY/main-app:latest

docker build -t action-messages ./action-messages
docker tag action-messages:latest $ECR_REGISTRY/action-messages:latest
docker push $ECR_REGISTRY/action-messages:latest

docker build -t techpathway-warehouse ./techpathway-warehouse
docker tag techpathway-warehouse:latest $ECR_REGISTRY/techpathway-warehouse:latest
docker push $ECR_REGISTRY/techpathway-warehouse:latest
```

A copy of this as a runnable script is in `push-to-ecr.sh` at the repo
root — edit the `AWS_ACCOUNT_ID`/`AWS_REGION` values at the top and run
`bash push-to-ecr.sh`. Requires the AWS CLI installed and configured
(`aws configure`) with permissions for ECR.

Once pushed, hand DevOps the three image URIs
(`$ECR_REGISTRY/main-app:latest`, etc.) plus the contract table above —
that's everything they need to write the Kubernetes manifests.

## Why replica counts would differ (for DevOps' reference)

`main-app` is stateless per-request (data lives in MySQL/RDS), so it's safe
to run at 2+ replicas behind a load balancer. `action-messages` and
`techpathway-warehouse` each use local SQLite as their datastore for
simplicity, and SQLite doesn't support multiple concurrent writers — running
either at more than 1 replica would need a persistent volume per pod at
minimum, or swapping SQLite for a real database first (the same step
`main-app` already took when it moved from local SQLite to RDS).

## What's not in this repo (by design)

- No Kubernetes manifests, no cluster, no ingress — that's the DevOps
  team's infrastructure repo.
- No monitoring — same reason.
- No shared auth between services — anyone who can reach a service can
  call its API. Fine inside a private network; add mTLS or an API key if
  this goes further.
- No message queue — `main-app` calls the other two services synchronously
  over HTTP with a 3s timeout. A production version of this would likely
  put SQS/RabbitMQ between them so an order isn't lost if
  techpathway-warehouse is mid-restart.
- No CI/CD — the ECR push above is manual.
