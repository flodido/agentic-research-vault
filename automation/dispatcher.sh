#!/bin/bash
# Dispatcher
# Läuft periodisch via LaunchAgent/Cron oder wird vom Webhook-Listener getriggert.
# Kill switch: "!stop" im Auftragskanal → pausiert. "!start" → fortsetzen.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
CONTROL="$CONTROL_DIR"
STOP_FILE="$CONTROL/DISPATCHER-STOP"
LAST_SEEN_FILE="$CONTROL/DISPATCHER-LAST-SEEN-MAIN-TS"
AUDIT_QUEUE="$CONTROL/AUDIT-QUEUE.md"
IS_BLOG=0
WEBHOOK_TS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --blog) IS_BLOG=1; shift ;;
        --ts)   WEBHOOK_TS="${2:-}"; shift 2 ;;
        *)      shift ;;
    esac
done
CLAUDE="$CLAUDE_BIN"
CHANNEL="$DISPATCHER_CHANNEL"
USER_ID="$ALLOWED_USER"
BOT_USER_ID="$BOT_USER"
LOG="$CONTROL/DISPATCHER-RUN.log"
if [ "$IS_BLOG" = "1" ]; then
    LOCK_FILE="$CONTROL/DISPATCHER-BLOG-RUNNING.lock"
else
    LOCK_FILE="$CONTROL/DISPATCHER-RUNNING.lock"
fi

# Token aus ~/.zshrc laden (nicht im Repo gespeichert)
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null
TOKEN="${SLACK_BOT_TOKEN:?Fehler: SLACK_BOT_TOKEN nicht gesetzt. Bitte in der Umgebung (z. B. ~/.zshrc) eintragen.}"

cd "$VAULT" || exit 1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

slack_post() {
    curl -s -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"channel\":\"$CHANNEL\",\"text\":\"$1\"}" \
        "https://slack.com/api/chat.postMessage" > /dev/null
}

slack_react() {
    local name="$1"
    local ts="$2"
    local ch="${3:-$CHANNEL}"
    curl -s -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"channel\":\"$ch\",\"name\":\"$name\",\"timestamp\":\"$ts\"}" \
        "https://slack.com/api/reactions.add" > /dev/null
}

# Letzte Nachrichten holen (nur Text-Nachrichten vom User)
RECENT=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "https://slack.com/api/conversations.history?channel=$CHANNEL&limit=20")

# Kill-Switch: !stop prüfen
if echo "$RECENT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
msgs = [m for m in d.get('messages', []) if m.get('user') == '$USER_ID' and '!stop' in m.get('text', '')]
sys.exit(0 if msgs else 1)
" 2>/dev/null; then
    touch "$STOP_FILE"
    slack_post "⏸ Dispatcher pausiert. Sende \`!start\` um ihn fortzusetzen."
    log "STOP-Befehl empfangen. Dispatcher pausiert."
    exit 0
fi

# Kill-Switch: !start prüfen
if echo "$RECENT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
msgs = [m for m in d.get('messages', []) if m.get('user') == '$USER_ID' and '!start' in m.get('text', '')]
sys.exit(0 if msgs else 1)
" 2>/dev/null; then
    rm -f "$STOP_FILE"
    slack_post "▶️ Dispatcher läuft wieder."
    log "START-Befehl empfangen. Dispatcher fortgesetzt."
fi

# Stop-Datei prüfen
if [ -f "$STOP_FILE" ]; then
    log "Dispatcher pausiert (STOP-Datei vorhanden). Überspringe Runde."
    exit 0
fi

if [ "$IS_BLOG" = "1" ]; then
    if [ -n "$WEBHOOK_TS" ]; then
        # ts direkt aus dem Webhook-Payload — funktioniert auch für Thread-Replies
        TRIGGER_TS="$WEBHOOK_TS"
    else
        # Fallback: neueste offene Top-Level-Nachricht per API holen
        TRIGGER_TS=$(curl -s \
            -H "Authorization: Bearer $TOKEN" \
            "https://slack.com/api/conversations.history?channel=$BLOG_CHANNEL&limit=10" | \
            python3 -c "
import sys, json
from decimal import Decimal
d = json.load(sys.stdin)
msgs = [m for m in d.get('messages', [])
        if m.get('user') == '$USER_ID'
        and not m.get('bot_id')
        and not any(r.get('name') in ('white_check_mark','heavy_check_mark') for r in m.get('reactions', []))]
print(max(msgs, key=lambda m: Decimal(m['ts']))['ts'] if msgs else '')
" 2>/dev/null)
    fi
    if [ -n "$TRIGGER_TS" ]; then
        slack_react "eyes" "$TRIGGER_TS" "$BLOG_CHANNEL"
    fi
    log "Blog-Trigger empfangen. Starte Dispatcher-Blog-Runde..."
else
# Nur Claude starten, wenn in der bereits geholten History oder in einem
# relevanten Thread eine neue offene Nachricht vom Nutzer vorhanden ist.
# Die lokale Last-Seen-Datei verhindert Wiederholungen, falls Slack keine
# Reaktionen liefert oder Claude die erledigt-Reaktion nicht setzen konnte.
LAST_SEEN=""
[ -f "$LAST_SEEN_FILE" ] && LAST_SEEN=$(cat "$LAST_SEEN_FILE" 2>/dev/null)

TRIGGER_DECISION=$(printf '%s' "$RECENT" | LAST_SEEN="$LAST_SEEN" USER_ID="$USER_ID" BOT_USER_ID="$BOT_USER_ID" CHANNEL="$CHANNEL" TOKEN="$TOKEN" python3 -c '
import json, os, sys, urllib.parse, urllib.request
from decimal import Decimal, InvalidOperation

user_id = os.environ["USER_ID"]
bot_user_id = os.environ["BOT_USER_ID"]
channel = os.environ["CHANNEL"]
token = os.environ["TOKEN"]
last_seen = os.environ.get("LAST_SEEN", "").strip()

def to_decimal(value):
    try:
        return Decimal(value)
    except (InvalidOperation, TypeError):
        return Decimal("0")

try:
    d = json.load(sys.stdin)
except Exception:
    print("ERROR")
    raise SystemExit

if not d.get("ok", False):
    print("ERROR")
    raise SystemExit

def is_done(message):
    reactions = message.get("reactions", [])
    reaction_names = {r.get("name") for r in reactions}
    return "white_check_mark" in reaction_names or "heavy_check_mark" in reaction_names

def is_processable_user_message(message):
    text = message.get("text", "").strip()
    return (
        message.get("user") == user_id
        and "bot_id" not in message
        and not text.startswith("!")
        and not is_done(message)
        and bool(message.get("ts"))
    )

def slack_thread_replies(parent_ts):
    query = urllib.parse.urlencode({"channel": channel, "ts": parent_ts, "limit": 100})
    request = urllib.request.Request(
        f"https://slack.com/api/conversations.replies?{query}",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            result = json.load(response)
    except Exception:
        return []
    if not result.get("ok", False):
        return []
    return result.get("messages", [])

baseline_messages = []
candidates = []
for m in d.get("messages", []):
    ts = m.get("ts", "")

    if m.get("user") == user_id and "bot_id" not in m and ts:
        baseline_messages.append(ts)

    if is_processable_user_message(m):
        candidates.append(ts)

    reply_users = set(m.get("reply_users", []))
    should_check_thread = m.get("reply_count", 0) > 0 and (not reply_users or bot_user_id in reply_users or user_id in reply_users)
    if should_check_thread and ts:
        for reply in slack_thread_replies(ts):
            reply_ts = reply.get("ts", "")
            if reply_ts and reply.get("user") == user_id and "bot_id" not in reply:
                baseline_messages.append(reply_ts)
            if reply_ts != ts and is_processable_user_message(reply):
                candidates.append(reply_ts)

if not last_seen:
    latest_seen = max(baseline_messages, key=to_decimal) if baseline_messages else "0"
    print(f"INIT {latest_seen}")
    raise SystemExit

if not candidates:
    print("NONE")
    raise SystemExit

latest = max(candidates, key=to_decimal)
if to_decimal(latest) > to_decimal(last_seen):
    print(f"RUN {latest}")
else:
    print("NONE")
')

if [ "$TRIGGER_DECISION" = "ERROR" ]; then
    log "Slack-History konnte nicht lokal geprüft werden. Überspringe Claude."
    exit 0
fi

if [[ "$TRIGGER_DECISION" == INIT\ * ]]; then
    echo "${TRIGGER_DECISION#INIT }" > "$LAST_SEEN_FILE"
    log "Last-Seen initialisiert (${TRIGGER_DECISION#INIT }). Überspringe Claude."
    exit 0
fi

if [ "$TRIGGER_DECISION" = "NONE" ]; then
    if [ -f "$AUDIT_QUEUE" ] && grep -Eq '^- \[ \] ' "$AUDIT_QUEUE"; then
        TRIGGER_TS=""
        log "Offene Audit-Queue gefunden. Starte Dispatcher-Audit-Runde..."
    else
        log "Keine neue unverarbeitete Slack-Nachricht und keine offene Audit-Queue. Überspringe Claude."
        exit 0
    fi
else
    TRIGGER_TS="${TRIGGER_DECISION#RUN }"
    echo "$TRIGGER_TS" > "$LAST_SEEN_FILE"
fi
fi  # IS_BLOG else-Ende

# Lock setzen — verhindert parallele Dispatcher-Läufe
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Dispatcher ausführen
if [ "$IS_BLOG" = "0" ] && [ -n "$TRIGGER_TS" ]; then
    slack_react "eyes" "$TRIGGER_TS"
    log "Starte Dispatcher-Runde für Slack-Nachricht $TRIGGER_TS..."
fi

log "Claude startet (PID $$, user $(id -un))..."

# Der vollständige Dispatcher-Auftrag steht in prompts/dispatcher.md.
# Hier wird eine kompakte Single-Run-Variante übergeben.
CLAUDE_PROMPT="Du bist der Dispatcher. Führe genau eine Runde aus:
1. Lies den Auftragskanal (Kanal-ID: $CHANNEL) - die letzten 20 Nachrichten.
2. Hauptkanal: Verarbeite NUR Nachrichten von User-ID $USER_ID ohne ✅-Reaktion und ohne bot_id.
3. Threads: Wenn eine Nachricht reply_count > 0 hat und reply_users $BOT_USER_ID oder $USER_ID enthält, lies den Thread. Verarbeite dort Replies von User-ID $USER_ID ohne ✅-Reaktion und ohne bot_id genauso wie Hauptkanal-Nachrichten.
4. Ignoriere Nachrichten die mit ! beginnen (Steuerbefehle).
5. Für jede neue Nachricht oder Thread-Reply: analysiere und führe aus.
6. Wenn dabei eine neue oder wesentlich geänderte Wissensdatei in Research/, Data/Processed/, _INBOX/ oder vergleichbaren Markdown-Notizen entsteht: bestimme den Audit-Modus. Explizite Angaben des Nutzers übernehmen; sonst standard setzen. Automatisch strict setzen bei Veröffentlichung, Website, Blogartikel, LinkedIn, Kundenbezug, Recht/DSGVO, Finanzen, Medizin, harten Zahlen, Zitaten oder High-Stakes-Themen.
7. Belege jede Sachbehauptung mit Fußnoten, trage die Datei mit Audit-Modus in _CONTROL/AUDIT-QUEUE.md ein und starte den Subagenten auditor mit run_in_background: true. Mache danach sofort mit der nächsten Kanal-Nachricht weiter — der Auditor läuft parallel. Der Auditor schreibt nur in die Note selbst (Frontmatter); LOG.md, TASKS.md und AUDIT-QUEUE.md aktualisierst du nach Rückmeldung des Subagenten.
8. Eine Erstellung ist erst abgeschlossen, wenn auditor approved vergibt und die Modus-Schwelle erreicht ist: quick >= 85, standard >= 92, strict >= 97. Erst dann antworte im Thread mit Fertigmeldung und setze ✅ auf die ursprüngliche Nachricht.
9. Bei Audit-Score unter der Modus-Schwelle: arbeite die Nachbesserungsanweisungen selbst ab oder gib sie an den ausführenden Agenten zurück; danach erneut auditieren. Keine Fertigmeldung und keine Erledigt-Markierung vor Freigabe.
10. Wenn keine neuen Nachrichten vorhanden sind, aber _CONTROL/AUDIT-QUEUE.md offene Einträge enthält: bearbeite genau diese Audit-/Nacharbeitsrunde.
11. Wenn weder neue Nachrichten noch offene Audit-Einträge vorhanden sind: tue nichts, gib keine Ausgabe.
Vault-Pfad: $VAULT"

if [ "$(id -u)" = "0" ]; then
    # Als root (LaunchDaemon): Claude als regulärer Nutzer starten, sonst blockiert bypassPermissions
    sudo -n -u "$RUN_AS_USER" -H \
        "$CLAUDE" --print \
        --permission-mode bypassPermissions \
        "$CLAUDE_PROMPT" \
        --add-dir "$VAULT" \
        >> "$LOG" 2>&1
else
    "$CLAUDE" --print \
        --permission-mode bypassPermissions \
        "$CLAUDE_PROMPT" \
        --add-dir "$VAULT" \
        >> "$LOG" 2>&1
fi
CLAUDE_EXIT=$?

log "Dispatcher-Runde abgeschlossen (Claude exit: $CLAUDE_EXIT)."
