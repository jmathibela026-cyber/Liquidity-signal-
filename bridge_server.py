"""
Liquidity Signal - MT5 Bridge Server
-------------------------------------
Sits between the browser app (which analyzes chart screenshots with Gemini)
and the MT5 Expert Advisor (which places trades).

Run this on the SAME PC that runs your MT5 terminal.

    pip install flask
    python bridge_server.py

Then:
  - In the browser app's settings (gear icon), set "Bridge URL" to
    http://<this-pc's-LAN-IP>:5000  (find your LAN IP with `ipconfig` on
    Windows). If the phone/browser and MT5 are on the same PC, you can use
    http://127.0.0.1:5000 instead.
  - Set the same SHARED_SECRET below in both this file and the app's
    "Shared secret" field, and in the EA's SharedSecret input.
  - Attach LiquiditySignalEA.mq5 to a chart in MT5, and make sure
    Tools > Options > Expert Advisors > "Allow WebRequest for listed URL"
    includes this bridge's address (e.g. http://127.0.0.1:5000).

Security note: this is a minimal local bridge for personal/demo use.
It is NOT hardened for exposure to the public internet. Keep it on your
LAN, behind your router, and never port-forward it.
"""

from flask import Flask, request, jsonify
import threading
import time

app = Flask(__name__)

# CHANGE THIS to match the "Shared secret" field in the browser app and the
# SharedSecret input in the EA. Anyone with this string can inject signals.
SHARED_SECRET = "change-this-secret"

# Only a signal newer than this many seconds old will be handed to the EA.
# Protects against the EA acting on a stale signal after being offline.
MAX_SIGNAL_AGE_SECONDS = 120

_lock = threading.Lock()
_state = {
    "next_id": 1,
    "latest": None,  # dict: id, received_at, signal, symbol, stopLoss, takeProfit, ...
}


def _check_secret(req):
    return req.headers.get("X-Signal-Secret", "") == SHARED_SECRET


@app.route("/signal", methods=["POST"])
def post_signal():
    if not _check_secret(request):
        return jsonify({"error": "bad secret"}), 401

    body = request.get_json(force=True, silent=True)
    if not body:
        return jsonify({"error": "invalid or missing JSON body"}), 400

    if body.get("signal") not in ("BUY", "SELL"):
        return jsonify({"error": "signal must be BUY or SELL"}), 400
    if not body.get("symbol"):
        return jsonify({"error": "symbol is required"}), 400
    if body.get("stopLoss") is None or body.get("takeProfit") is None:
        return jsonify({"error": "stopLoss and takeProfit are required"}), 400

    with _lock:
        record = {
            "id": _state["next_id"],
            "received_at": time.time(),
            "signal": body["signal"],
            "symbol": body["symbol"],
            "stopLoss": float(body["stopLoss"]),
            "takeProfit": float(body["takeProfit"]),
            "confidence": body.get("confidence"),
            "entrySetupType": body.get("entrySetupType"),
            "htfBias": body.get("htfBias"),
            "reasoning": body.get("reasoning"),
        }
        _state["next_id"] += 1
        _state["latest"] = record

    print(f"[bridge] received signal #{record['id']}: {record['signal']} {record['symbol']} "
          f"SL={record['stopLoss']} TP={record['takeProfit']}")
    return jsonify({"ok": True, "id": record["id"]})


@app.route("/signal/latest", methods=["GET"])
def get_latest():
    if not _check_secret(request):
        return jsonify({"error": "bad secret"}), 401

    after_id = request.args.get("after", default=0, type=int)

    with _lock:
        latest = _state["latest"]

    if latest is None or latest["id"] <= after_id:
        return jsonify({"signal": None})

    age = time.time() - latest["received_at"]
    if age > MAX_SIGNAL_AGE_SECONDS:
        return jsonify({"signal": None, "stale": True, "age_seconds": age})

    return jsonify(latest)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})


if __name__ == "__main__":
    print("Liquidity Signal bridge server starting on http://0.0.0.0:5000")
    print("Remember to set the same SHARED_SECRET in the browser app and the EA.")
    app.run(host="0.0.0.0", port=5000)
