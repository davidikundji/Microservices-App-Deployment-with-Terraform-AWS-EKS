"""
techpathway-warehouse — app.py
(formerly warehouse-service — renamed for containerization/ECR)

Standalone microservice for Techpathway BothCamp. Owns inventory + order
fulfillment tracking. It has its own SQLite datastore (separate from the main
app's shop DB) and its own small web UI — this is meant to feel like the
internal tool a warehouse team would actually use, not just an API.

The main app POSTs to /warehouse/orders whenever an order is placed (admin
"New Order" form or the public storefront checkout, both of which now
auto-confirm on creation). This service decrements stock and creates a
fulfillment record that moves through:
  received -> picking -> packed -> shipped
"""

import os, sqlite3, logging
from datetime import datetime, timezone

from flask import Flask, request, jsonify, render_template, redirect, url_for
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
log = logging.getLogger("techpathway-warehouse")
logging.basicConfig(level=logging.INFO)

DB_PATH = os.path.join(os.path.dirname(__file__), "warehouse.db")
STATUS_FLOW = ["received", "picking", "packed", "shipped"]

# Mirrors the 8 TC products from the main app's db_init.py so this service has
# something to track independently of the storefront's own database.
SEED_INVENTORY = [
    ("TC-001", "Classic Slim Blazer",           30, 8),
    ("TC-002", "Luxury Oil Wax Tote Bag",       20, 5),
    ("TC-003", "Minimalist White Sneakers",     50, 10),
    ("TC-004", "Knit Polo — Sage Blue",         45, 10),
    ("TC-005", "Cashmere Zip Set — Oat",        25, 5),
    ("TC-006", "Canadian Club Jersey",          60, 12),
    ("TC-007", "Wide-Leg Dress Pants — Navy",   35, 8),
    ("TC-008", "Brogue Oxford Dress Shoes",     15, 5),
]


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS inventory (
            sku            TEXT PRIMARY KEY,
            product_name   TEXT NOT NULL,
            quantity       INTEGER NOT NULL DEFAULT 0,
            reorder_level  INTEGER NOT NULL DEFAULT 5,
            updated_at     TEXT
        );
        CREATE TABLE IF NOT EXISTS warehouse_orders (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id       INTEGER NOT NULL,
            customer_name  TEXT,
            status         TEXT NOT NULL DEFAULT 'received',
            created_at     TEXT NOT NULL,
            updated_at     TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS warehouse_order_items (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            warehouse_order_id  INTEGER NOT NULL REFERENCES warehouse_orders(id) ON DELETE CASCADE,
            sku                 TEXT,
            product_name        TEXT,
            quantity            INTEGER NOT NULL,
            unit_price          REAL
        );
    """)
    for sku, name, qty, reorder in SEED_INVENTORY:
        conn.execute(
            "INSERT OR IGNORE INTO inventory (sku,product_name,quantity,reorder_level,updated_at) VALUES (?,?,?,?,?)",
            (sku, name, qty, reorder, datetime.now(timezone.utc).isoformat()),
        )
    conn.commit()
    conn.close()


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "techpathway-warehouse"}), 200


# ── API used by the main app ────────────────────────────────────────────────
@app.route("/warehouse/orders", methods=["POST"])
def receive_order():
    data = request.get_json(silent=True) or {}
    order_id = data.get("order_id")
    customer_name = data.get("customer_name", "Unknown")
    items = data.get("items", [])
    if not order_id:
        return jsonify({"error": "order_id is required"}), 400

    conn = get_db()
    now = datetime.now(timezone.utc).isoformat()
    cur = conn.execute(
        "INSERT INTO warehouse_orders (order_id,customer_name,status,created_at,updated_at) VALUES (?,?,?,?,?)",
        (order_id, customer_name, "received", now, now),
    )
    wo_id = cur.lastrowid
    for item in items:
        sku = item.get("sku")
        qty = int(item.get("quantity", 0) or 0)
        conn.execute(
            "INSERT INTO warehouse_order_items (warehouse_order_id,sku,product_name,quantity,unit_price) VALUES (?,?,?,?,?)",
            (wo_id, sku, item.get("name"), qty, item.get("price")),
        )
        if sku and qty:
            conn.execute(
                "UPDATE inventory SET quantity = MAX(quantity - ?, 0), updated_at = ? WHERE sku = ?",
                (qty, now, sku),
            )
    conn.commit()
    conn.close()
    return jsonify({"warehouse_order_id": wo_id, "status": "received"}), 201


@app.route("/warehouse/inventory", methods=["GET"])
def api_inventory():
    conn = get_db()
    rows = conn.execute("SELECT * FROM inventory ORDER BY product_name").fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])


@app.route("/warehouse/inventory/<sku>/adjust", methods=["POST"])
def adjust_inventory(sku):
    data = request.get_json(silent=True) or request.form
    delta = int(data.get("delta", 0) or 0)
    conn = get_db()
    conn.execute(
        "UPDATE inventory SET quantity = MAX(quantity + ?, 0), updated_at = ? WHERE sku = ?",
        (delta, datetime.now(timezone.utc).isoformat(), sku),
    )
    conn.commit()
    conn.close()
    if request.is_json:
        return jsonify({"status": "ok"})
    return redirect(url_for("dashboard"))


@app.route("/warehouse/orders/<int:wo_id>/status", methods=["POST"])
def advance_status(wo_id):
    data = request.get_json(silent=True) or request.form
    new_status = data.get("status")
    if new_status not in STATUS_FLOW:
        return jsonify({"error": f"status must be one of {STATUS_FLOW}"}), 400
    conn = get_db()
    conn.execute(
        "UPDATE warehouse_orders SET status = ?, updated_at = ? WHERE id = ?",
        (new_status, datetime.now(timezone.utc).isoformat(), wo_id),
    )
    conn.commit()
    conn.close()
    if request.is_json:
        return jsonify({"status": "ok"})
    return redirect(url_for("dashboard"))


# ── Dashboard UI ─────────────────────────────────────────────────────────────
@app.route("/")
def dashboard():
    conn = get_db()
    inventory = conn.execute("SELECT * FROM inventory ORDER BY product_name").fetchall()
    orders = conn.execute("SELECT * FROM warehouse_orders ORDER BY created_at DESC LIMIT 50").fetchall()
    orders_by_status = {s: [] for s in STATUS_FLOW}
    for o in orders:
        items = conn.execute(
            "SELECT * FROM warehouse_order_items WHERE warehouse_order_id = ?", (o["id"],)
        ).fetchall()
        orders_by_status.setdefault(o["status"], []).append({"order": o, "items": items})
    conn.close()
    return render_template(
        "index.html",
        inventory=inventory,
        orders_by_status=orders_by_status,
        status_flow=STATUS_FLOW,
    )


if __name__ == "__main__":
    init_db()
    print("  techpathway-warehouse starting on :5002")
    # use_reloader=False: the reloader spawns a second watcher process,
    # which makes it easy to end up running stale code after an edit
    # without realizing it. debug=True still gives full tracebacks.
    app.run(host="0.0.0.0", port=5002, debug=True, use_reloader=False)
else:
    init_db()
