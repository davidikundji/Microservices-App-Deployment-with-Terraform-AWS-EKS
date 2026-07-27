"""
action-messages — app.py
(formerly notification-service — renamed for containerization/ECR)

Standalone microservice for Techpathway BothCamp. It owns exactly one job:
when the main app confirms an order, generate a tracking number and email
the customer a congratulations note (always CC'ing ALWAYS_CC_EMAIL). It runs
in its own pod, has its own tiny SQLite datastore (an audit log of messages
sent), and is only reachable by the main app over its internal Service URL —
nothing here talks back to the main app's database directly.
"""

import os, sqlite3, smtplib, logging, random, string
from email.mime.text import MIMEText
from datetime import datetime, timezone

from flask import Flask, request, jsonify, render_template
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger("action-messages")
logging.basicConfig(level=logging.INFO)


def _load_secrets_manager_env():
    """Optional: if SECRETS_MANAGER_SECRET_NAME is set, pull that secret from
    AWS Secrets Manager (a JSON object, e.g. {"SMTP_HOST": "smtp.gmail.com",
    "SMTP_USER": "...", "SMTP_PASSWORD": "...", "ALWAYS_CC_EMAIL": "..."})
    and merge it into the process environment — secret values override
    anything already set locally. This is how real SMTP credentials should
    reach this service in production, instead of a plaintext .env file. If
    the env var isn't set, or the fetch fails for any reason, this silently
    no-ops and falls back to whatever plain env vars were already there —
    demo mode still works if nothing is configured at all."""
    secret_name = os.getenv("SECRETS_MANAGER_SECRET_NAME", "").strip()
    if not secret_name:
        return
    try:
        import boto3, json
        client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
        secret = json.loads(client.get_secret_value(SecretId=secret_name)["SecretString"])
        for k, v in secret.items():
            os.environ[k] = str(v)
        log.info("Loaded %d values from Secrets Manager secret '%s'", len(secret), secret_name)
    except Exception as e:
        log.warning("Could not load Secrets Manager secret '%s': %s — falling back to local env vars",
                    secret_name, e)


_load_secrets_manager_env()

app = Flask(__name__)

DB_PATH = os.path.join(os.path.dirname(__file__), "notifications.db")

SMTP_HOST = os.getenv("SMTP_HOST", "").strip()
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "").strip()
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
FROM_EMAIL = os.getenv("FROM_EMAIL", "orders@techpathway-bothcamp.example").strip()
FROM_NAME = os.getenv("FROM_NAME", "The Techpathway Team, Weekly Class").strip()
# Always CC'd on every order-confirmation email sent (e.g. the instructor /
# program lead who wants a copy of every "I built it" notification).
ALWAYS_CC_EMAIL = os.getenv("ALWAYS_CC_EMAIL", "m.olujobi1@gmail.com").strip()
# If SMTP_HOST isn't set, the service runs in "demo mode": it renders the
# email and writes it to the audit log/console instead of sending it — handy
# for a bootcamp project where nobody wants to wire up real SMTP creds.
DEMO_MODE = not bool(SMTP_HOST)


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS notifications (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id        INTEGER NOT NULL,
            tracking_number TEXT,
            customer_name   TEXT,
            customer_email  TEXT,
            cc_email        TEXT,
            subject         TEXT,
            body            TEXT,
            status          TEXT NOT NULL DEFAULT 'sent',
            detail          TEXT,
            created_at      TEXT NOT NULL
        )
    """)
    # Older DBs created before this column existed — add it if missing.
    cols = [r["name"] for r in conn.execute("PRAGMA table_info(notifications)").fetchall()]
    if "cc_email" not in cols:
        conn.execute("ALTER TABLE notifications ADD COLUMN cc_email TEXT")
    conn.commit()
    conn.close()


def generate_tracking_number():
    return "TP-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=8))


def render_email(customer_name, tracking_number):
    subject = "Congratulations — you built the Techpathway Kubernetes project!"
    body = (
        f"Hi {customer_name},\n\n"
        f"Congratulations, you have successfully built the Techpathway "
        f"Kubernetes project!\n\n"
        f"Tracking number: {tracking_number}\n\n"
        f"— {FROM_NAME}\n"
    )
    return subject, body


def send_email(to_email, subject, body):
    """Returns (status, detail, cc_email) where status is 'sent', 'logged', or 'failed'.
    Always CC's ALWAYS_CC_EMAIL in addition to the customer, unless it's the
    same address (avoids sending a duplicate copy to the same inbox)."""
    to_email = (to_email or "").strip()
    cc_email = ALWAYS_CC_EMAIL if ALWAYS_CC_EMAIL and ALWAYS_CC_EMAIL.lower() != to_email.lower() else None

    if DEMO_MODE:
        log.info("DEMO MODE — would send email to %s (cc: %s)\nSubject: %s\n%s",
                  to_email, cc_email or "-", subject, body)
        return "logged", "SMTP not configured — logged instead of sent (demo mode)", cc_email

    try:
        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = f"{FROM_NAME} <{FROM_EMAIL}>"
        msg["To"] = to_email
        recipients = [to_email]
        if cc_email:
            msg["Cc"] = cc_email
            recipients.append(cc_email)
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as server:
            server.starttls()
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(FROM_EMAIL, recipients, msg.as_string())
        log.info("SENT email to %s (cc: %s)", to_email, cc_email or "-")
        return "sent", None, cc_email
    except Exception as e:
        log.error("FAILED to send email to %s (cc: %s): %s", to_email, cc_email or "-", e)
        return "failed", str(e), cc_email


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "action-messages", "demo_mode": DEMO_MODE}), 200


@app.route("/notify/order-confirmed", methods=["POST"])
def notify_order_confirmed():
    data = request.get_json(silent=True) or {}
    order_id = data.get("order_id")
    customer_name = data.get("customer_name", "Customer")
    customer_email = (data.get("customer_email") or "").strip()

    if not order_id or not customer_email:
        return jsonify({"error": "order_id and customer_email are required"}), 400

    tracking_number = generate_tracking_number()
    subject, body = render_email(customer_name, tracking_number)
    status, detail, cc_email = send_email(customer_email, subject, body)

    conn = get_db()
    conn.execute(
        "INSERT INTO notifications (order_id,tracking_number,customer_name,customer_email,cc_email,subject,body,status,detail,created_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (order_id, tracking_number, customer_name, customer_email, cc_email, subject, body, status, detail,
         datetime.now(timezone.utc).isoformat()),
    )
    conn.commit()
    conn.close()

    if status == "failed":
        return jsonify({"status": status, "tracking_number": tracking_number, "detail": detail}), 502
    return jsonify({"status": status, "tracking_number": tracking_number, "cc": cc_email, "detail": detail}), 200


@app.route("/")
def dashboard():
    conn = get_db()
    rows = conn.execute("SELECT * FROM notifications ORDER BY id DESC LIMIT 100").fetchall()
    conn.close()
    return render_template("index.html", notifications=rows, demo_mode=DEMO_MODE, cc_email=ALWAYS_CC_EMAIL)


if __name__ == "__main__":
    init_db()
    print(f"  action-messages starting — demo_mode={DEMO_MODE}  always_cc={ALWAYS_CC_EMAIL}")
    # use_reloader=False: the reloader spawns a second watcher process,
    # which makes it easy to end up running stale code after an edit
    # without realizing it. debug=True still gives full tracebacks.
    app.run(host="0.0.0.0", port=5001, debug=True, use_reloader=False)
else:
    init_db()
