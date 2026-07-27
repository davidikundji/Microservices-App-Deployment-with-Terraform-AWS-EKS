# Techpathway BothCamp

Fashion e-commerce platform — Flask + MySQL RDS + S3

> This is one of 3 services in the full system (main-app, action-messages,
> techpathway-warehouse). See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for
> how they fit together, what DevOps needs from each one, and how to push
> images to ECR.

---

## Open in VS Code

```bash
code weekly-call/
```

---

## Run locally

```bash
bash start.sh
```

- **http://localhost:5111/store** — Customer storefront
- **http://localhost:5111/** — Admin backend

---

## Project structure

```
weekly-call/
├── app.py                  ← Main Flask app
├── db_init.py              ← Creates DB with 8 real products
├── start.sh                ← One-command local start
├── .env.example            ← Fill in RDS + S3 credentials
│
├── TC_images/              ← Your original product images
├── static/images/          ← Same images served by Flask locally
├── static/css/             ← Admin + store styles
├── static/js/              ← Cart + admin JS
│
├── templates/
│   ├── store/              ← Customer storefront pages
│   └── errors/             ← 404, 500, 429 pages
│
└── scripts/
    ├── deploy_ec2.sh       ← EC2 deploy (DevOps runs this)
    └── setup_rds.sh        ← Load DB into RDS
```

---

## Your 8 Products

| SKU | Product | Price |
|-----|---------|-------|
| TC-001 | Classic Slim Blazer | $189.99 |
| TC-002 | Luxury Oil Wax Tote Bag | $249.99 |
| TC-003 | Minimalist White Sneakers | $119.99 |
| TC-004 | Knit Polo — Sage Blue | $89.99 |
| TC-005 | Cashmere Zip Set — Oat | $299.99 |
| TC-006 | Canadian Club Jersey | $74.99 |
| TC-007 | Wide-Leg Dress Pants — Navy | $129.99 |
| TC-008 | Brogue Oxford Dress Shoes | $349.99 |

---

## Connect AWS (when ready)

Edit `.env` with your RDS endpoint, password, S3 bucket and IAM keys.
Restart — app switches from SQLite to RDS + S3 automatically.
