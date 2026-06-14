#!/bin/bash
# Lokale Konfiguration (Vorlage)
# Kopieren nach config.sh und anpassen:
#   cp automation/config.example.sh automation/config.sh
#
# config.sh ist gitigniert und enthält persönliche IDs und Pfade.

# ── Pfade ────────────────────────────────────────────────────────────────────
VAULT="$HOME/Vault"               # Vault-Wurzel — einziger Wert der beim Umzug geändert werden muss
CONTROL_DIR="$VAULT/_CONTROL"

# Unter welchem Benutzer Claude laufen soll, falls das Skript als root gestartet
# wird (z. B. via LaunchDaemon). Bei Start als normaler Nutzer ignoriert.
RUN_AS_USER="$(id -un)"

# ── Slack ────────────────────────────────────────────────────────────────────
DISPATCHER_CHANNEL="C_DISPATCHER_ID"   # Channel-ID des Auftragskanals
BLOG_CHANNEL="C_BLOG_ID"               # Channel-ID der Publishing-Pipeline (optional)
ALLOWED_USER="U_YOUR_USER_ID"          # Deine Slack-User-ID (einziger berechtigter Nutzer)
BOT_USER="U_BOT_USER_ID"               # User-ID des Bots

# ── Optionaler Zusatzkanal ───────────────────────────────────────────────────
# Beliebiger weiterer Kanal, der eine eigene Companion-Anwendung triggert.
# Leer lassen, wenn nicht benötigt.
EXTRA_CHANNEL=""                       # Channel-ID
EXTRA_DIR=""                           # Projektpfad der Companion-Anwendung

# ── Tools ────────────────────────────────────────────────────────────────────
CLAUDE_BIN="$HOME/.local/bin/claude"
MCP_CONFIG="$HOME/.claude/mcp.json"

# ── Secrets ──────────────────────────────────────────────────────────────────
# SLACK_BOT_TOKEN NICHT hier setzen. Aus der Umgebung laden (z. B. ~/.zshrc):
#   export SLACK_BOT_TOKEN="xoxb-..."
