#!/usr/bin/env python3
"""
Slack Webhook Listener
Läuft permanent als LaunchAgent (KeepAlive).
Empfängt Slack Event Subscriptions, validiert die Signatur und triggert
dispatcher.sh im Hintergrund.

Konfiguration ausschließlich über Umgebungsvariablen (keine Secrets im Code):
  HOME, DISPATCHER_CHANNEL, BLOG_CHANNEL, EXTRA_CHANNEL, EXTRA_DIR,
  SLACK_SIGNING_SECRET
"""
import hashlib
import hmac
import http.server
import json
import logging
import os
import signal
import subprocess
import threading
import time
import urllib.request

PORT = 9877
HOME              = os.environ.get("HOME", "")
DISPATCHER_CHANNEL = os.environ.get("DISPATCHER_CHANNEL", "")
BLOG_CHANNEL       = os.environ.get("BLOG_CHANNEL", "")
EXTRA_CHANNEL      = os.environ.get("EXTRA_CHANNEL", "")
EXTRA_DIR          = os.environ.get("EXTRA_DIR", "")
FRAMEWORK_DIR      = os.path.dirname(os.path.abspath(__file__))
CONTROL_DIR        = os.environ.get("CONTROL_DIR", os.path.join(HOME, "Vault/_CONTROL"))
LOCK_FILE_DISPATCHER = os.path.join(CONTROL_DIR, "DISPATCHER-RUNNING.lock")
LOCK_FILE_BLOG       = os.path.join(CONTROL_DIR, "DISPATCHER-BLOG-RUNNING.lock")
LOG_FILE           = os.path.join(CONTROL_DIR, "slack-listener.log")

_DISPATCHER_SH = ["/bin/bash", os.path.join(FRAMEWORK_DIR, "dispatcher.sh")]

# Optionaler Webhook-Port einer Companion-Anwendung (statt subprocess-Trigger).
EXTRA_WEBHOOK_PORT = int(os.environ.get("EXTRA_WEBHOOK_PORT", "0") or "0")


def build_channel_routes() -> dict:
    routes = {}
    if DISPATCHER_CHANNEL:
        routes[DISPATCHER_CHANNEL] = ("dispatcher", _DISPATCHER_SH)
    if BLOG_CHANNEL:
        routes[BLOG_CHANNEL] = ("dispatcher-blog", _DISPATCHER_SH + ["--blog"])
    if EXTRA_CHANNEL and EXTRA_DIR:
        venv_python = os.path.join(EXTRA_DIR, ".venv/bin/python")
        script      = os.path.join(EXTRA_DIR, "main.py")
        routes[EXTRA_CHANNEL] = ("extra", [venv_python, script, "--once"])
    return routes


logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


def verify_slack_signature(body: bytes, headers) -> bool:
    secret = os.environ.get("SLACK_SIGNING_SECRET", "")
    if not secret:
        logging.warning("SLACK_SIGNING_SECRET nicht gesetzt — Signaturprüfung übersprungen")
        return True
    ts  = headers.get("X-Slack-Request-Timestamp", "")
    sig = headers.get("X-Slack-Signature", "")
    if not ts or not sig:
        return False
    try:
        if abs(time.time() - float(ts)) > 300:
            logging.warning("Replay-Angriff: Timestamp zu alt")
            return False
    except ValueError:
        return False
    base     = f"v0:{ts}:{body.decode('utf-8')}"
    expected = "v0=" + hmac.new(secret.encode(), base.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)


def is_lock_active(lock_file: str) -> bool:
    if not os.path.exists(lock_file):
        return False
    try:
        age = time.time() - os.path.getmtime(lock_file)
        if age > 600:
            os.remove(lock_file)
            return False
        return True
    except OSError:
        return False


def startup_scan():
    """Nach Neustart Dispatcher für alle Kanäle triggern — fängt verpasste Nachrichten auf."""
    time.sleep(5)  # kurz warten bis HTTP-Server sicher oben ist
    logging.info("Startup-Scan: prüfe auf verpasste Nachrichten nach Neustart")
    routes = build_channel_routes()
    if not routes:
        logging.warning("Startup-Scan: keine Kanäle konfiguriert — abgebrochen")
        return
    for channel, (name, cmd) in routes.items():
        if name == "extra":
            continue  # Companion-Anwendung hat eigenen Poll-Mechanismus
        logging.info(f"Startup-Scan: triggere {name}")
        trigger(name, cmd)


def trigger_extra() -> None:
    if not EXTRA_WEBHOOK_PORT:
        return
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:{EXTRA_WEBHOOK_PORT}/trigger",
            method="POST",
            data=b"",
        )
        urllib.request.urlopen(req, timeout=2)
        logging.info("Companion-Anwendung via Webhook getriggert")
    except Exception as exc:
        logging.warning(f"Companion-Webhook nicht erreichbar ({exc}) — kein Fallback")


def trigger(name: str, cmd: list[str]):
    if name == "extra":
        trigger_extra()
        return
    if name == "dispatcher" and is_lock_active(LOCK_FILE_DISPATCHER):
        logging.info("Dispatcher läuft bereits — Skip")
        return
    if name == "dispatcher-blog" and is_lock_active(LOCK_FILE_BLOG):
        logging.info("Dispatcher-Blog läuft bereits — Skip")
        return
    logging.info(f"Starte {name} im Hintergrund")
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


class SlackHandler(http.server.BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path not in ("/slack/events", "/"):
            self._respond(404)
            return

        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length)

        if not verify_slack_signature(body, self.headers):
            logging.warning("Ungültige Slack-Signatur — abgelehnt")
            self._respond(401)
            return

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self._respond(400)
            return

        # Slack URL-Verifikation beim App-Setup
        if payload.get("type") == "url_verification":
            challenge = payload.get("challenge", "")
            self._respond(200, json.dumps({"challenge": challenge}).encode(), "application/json")
            logging.info("URL-Verifikation beantwortet")
            return

        # Sofort 200 antworten (Slack erwartet < 3 s)
        self._respond(200)

        event = payload.get("event", {})
        if event.get("type") == "message" and not event.get("bot_id"):
            channel = event.get("channel", "")
            msg_ts  = event.get("ts", "")
            routes  = build_channel_routes()
            route   = routes.get(channel)
            if route:
                name, cmd = route
                if name == "dispatcher-blog" and msg_ts:
                    cmd = cmd + ["--ts", msg_ts]
                trigger(name, cmd)
            else:
                logging.info(f"Unbekannter Kanal {channel} — ignoriert")

    def _respond(self, status: int, body: bytes = b"", content_type: str = "text/plain"):
        self.send_response(status)
        if body:
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def log_message(self, fmt, *args):
        logging.info(fmt % args)


class FrameworkHTTPServer(http.server.HTTPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    def _shutdown(signum, frame):
        logging.info(f"Signal {signum} empfangen — Listener beendet sich.")
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    logging.info(f"Slack Webhook Listener gestartet auf Port {PORT}")
    threading.Thread(target=startup_scan, daemon=True).start()
    try:
        server = FrameworkHTTPServer(("0.0.0.0", PORT), SlackHandler)
        server.serve_forever()
    except Exception as e:
        logging.error(f"Listener abgestürzt: {e}", exc_info=True)
        raise
