"""Backup API for the Morning Challenge app.

Firestore layout: apps/morning-challenge/mornings/{YYYY-MM-DD}
Every request must carry the header  X-Token: <APP_TOKEN>.
"""
import hmac
import os
import re

from flask import Flask, abort, jsonify, request
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client()
TOKEN = os.environ["APP_TOKEN"].strip()
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def mornings():
    return db.collection("apps").document("morning-challenge").collection("mornings")


@app.before_request
def check_token():
    if request.path == "/healthz":
        return
    sent = request.headers.get("X-Token", "")
    if not hmac.compare_digest(sent.encode(), TOKEN.encode()):
        abort(401)


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/mornings")
def list_mornings():
    return jsonify([d.to_dict() for d in mornings().stream()])


@app.put("/mornings/<date>")
def put_morning(date):
    if not DATE_RE.match(date):
        abort(400)
    body = request.get_json(silent=True)
    if not isinstance(body, dict) or body.get("date") != date:
        abort(400)
    ref = mornings().document(date)
    existing = ref.get()
    # Same date in both places: keep the one updated later.
    if existing.exists and existing.to_dict().get("updatedAt", 0) > body.get("updatedAt", 0):
        return jsonify(existing.to_dict()), 409
    ref.set(body)
    return jsonify(body)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
