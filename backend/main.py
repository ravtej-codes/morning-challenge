"""Backup API for the Morning Challenge app.

Firestore layout:
  apps/morning-challenge/mornings/{YYYY-MM-DD}
  apps/morning-challenge/attempts/{uuid}       one go through the next-action flow
  apps/morning-challenge/config/next-action-prompt
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
UUID_RE = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")


def mornings():
    return db.collection("apps").document("morning-challenge").collection("mornings")


def attempts():
    return db.collection("apps").document("morning-challenge").collection("attempts")


def prompt_doc():
    return db.collection("apps").document("morning-challenge").collection("config").document("next-action-prompt")


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


@app.get("/attempts")
def list_attempts():
    return jsonify([d.to_dict() for d in attempts().stream()])


@app.put("/attempts/<attempt_id>")
def put_attempt(attempt_id):
    if not UUID_RE.match(attempt_id):
        abort(400)
    body = request.get_json(silent=True)
    if not isinstance(body, dict) or body.get("id") != attempt_id:
        abort(400)
    ref = attempts().document(attempt_id)
    existing = ref.get()
    # Uploads can arrive out of order: keep the one updated later.
    if existing.exists and existing.to_dict().get("updatedAt", 0) > body.get("updatedAt", 0):
        return jsonify(existing.to_dict()), 409
    ref.set(body)
    return jsonify(body)


@app.get("/prompt")
def get_prompt():
    doc = prompt_doc().get()
    if not doc.exists:
        abort(404)
    return jsonify(doc.to_dict())


@app.put("/prompt")
def put_prompt():
    body = request.get_json(silent=True)
    text = body.get("instructions") if isinstance(body, dict) else None
    # DeepSeek's JSON mode rejects a prompt that doesn't mention json.
    if not isinstance(text, str) or "json" not in text.lower():
        abort(400)
    doc = prompt_doc().get()
    version = doc.to_dict().get("version", 0) + 1 if doc.exists else 1
    saved = {"version": version, "instructions": text}
    prompt_doc().set(saved)
    return jsonify(saved)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
