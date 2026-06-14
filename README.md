# Agentic Research Vault

Ein prüfbarer, agentischer KI-Recherche- und Audit-Workflow für einen persönlichen
Wissensspeicher (Obsidian-Vault). Aufträge kommen über Slack herein, ein oder
mehrere Agenten recherchieren parallel und schreiben Notizen, und **kein Text gilt
als fertig, bevor er ein Audit-Gate bestanden hat und ein Mensch ihn freigegeben
hat.**

> Dies ist eine Referenz-Implementierung („as-is", keine Garantie, kein
> Support-Versprechen). Sie zeigt das Verfahren, das hinter meinen Recherche-
> und Blog-Texten steht. Anpassung an die eigene Umgebung wird erwartet.

## Idee

Die zentrale Frage ist nicht „halluziniert die KI?", sondern: *Woran erkenne ich,
dass ein Text fertig ist?* Antwort: nicht wenn er überzeugend klingt, sondern wenn
er definierte Abnahmekriterien erfüllt — und ein verantwortlicher Mensch ihn
freigibt.

Drei Rollen sind sauber getrennt:

- **Recherche** (ein oder mehrere Agenten, parallel pro Teilthema)
- **Audit** (ein eigener Prüf-Agent, der jede Aussage auf Belegbarkeit prüft)
- **Freigabe** (der Mensch — an drei Stellen, mit der Möglichkeit zu ändern)

## Ablauf

```
Auftrag
  → Recherche-Agent(en) (parallel)
  → quick-Audit (>= 85)         [REWORK-Schleife bis bestanden]
  → 1. Mensch: sichten & ändern
  → Semantik-Check
  → 2. Mensch: Korrekturen abnicken
  → strict-Audit (>= 97)        [REWORK-Schleife bis bestanden]
  → 3. Mensch: finale Freigabe
  → Veröffentlichung
```

Eine erfundene Zahl oder eine Quelle, die die Aussage nicht trägt, blockiert die
Freigabe in jedem Modus — unabhängig vom Score.

## Aufbau

```
prompts/
  dispatcher.md         Start-Prompt der koordinierenden Claude-Session
  auditor.md            Subagent: Faktencheck / Belegpflicht / Scoring
  semantik-check.md     Subagent: semantische Präzision (kein Lektorat)
  note-conventions.md   Frontmatter, Tags, Wikilinks, Fußnoten-Pflicht
automation/
  dispatcher.sh         Eine Dispatcher-Runde (Slack lesen → Claude → Audit)
  slack-listener.py     Webhook-Listener (triggert dispatcher.sh)
  config.example.sh     Konfigurationsvorlage (nach config.sh kopieren)
  examples/
    com.example.slack-listener.plist   Beispiel-LaunchAgent (macOS)
```

## Zwei Konfigurationswege — wichtig zu verstehen

Das System hat **zwei Prozesse mit getrennter Konfiguration**:

- **`dispatcher.sh`** sourct `automation/config.sh` (Bash-Variablen).
- **`slack-listener.py`** liest **ausschließlich Umgebungsvariablen**
  (`DISPATCHER_CHANNEL`, `BLOG_CHANNEL`, `CONTROL_DIR`, `SLACK_SIGNING_SECRET`,
  optional `EXTRA_CHANNEL`/`EXTRA_DIR`). Ohne diese Env-Variablen baut der
  Listener keine Kanal-Routen und tut nichts.

Setze die Listener-Variablen dort, wo der Listener läuft — am einfachsten im
`EnvironmentVariables`-Block des LaunchAgents
(siehe `automation/examples/com.example.slack-listener.plist`).

## Audit-Modi & Schwellen

| Modus | Schwelle | Wofür |
|---|---|---|
| `quick` | ≥ 85 | Skizzen, frühe Entwürfe, Ideen |
| `standard` | ≥ 92 | Normale Wissensnotizen |
| `strict` | ≥ 97 | Veröffentlichung, Website, Recht/Finanzen/Medizin, harte Zahlen, Zitate |

Veröffentlichungs-/High-Stakes-Inhalte werden automatisch auf `strict` hochgestuft.

## Setup (Schritt für Schritt)

### 1. Voraussetzungen

- [Claude Code CLI](https://claude.com/claude-code) installiert und eingeloggt
- Python 3 (nur Standardbibliothek nötig) und `curl`
- Ein Slack-Bot mit den Scopes `chat:write`, `reactions:write`,
  `channels:history`, `groups:history` und aktivierten **Event Subscriptions**
  (Event `message.channels` / `message.groups`)
- Ein **öffentlich erreichbarer HTTPS-Endpunkt**, der auf den Listener-Port
  (Standard `9877`) zeigt — Slack muss den Webhook erreichen. In der Praxis ein
  Tunnel wie Cloudflare Tunnel, ngrok oder Tailscale Funnel. Die Request-URL in
  der Slack-App ist dann `https://<dein-host>/slack/events`.

### 2. Vault & Verzeichnisse

```bash
# Vault-Wurzel und Steuerverzeichnis anlegen (Pfad frei wählbar)
mkdir -p "$HOME/Vault/_CONTROL"
```

`dispatcher.sh` legt darin Log-, Lock- und State-Dateien an — der Ordner muss
vorher existieren.

### 3. Konfiguration

```bash
cp automation/config.example.sh automation/config.sh
# config.sh mit echten Channel-/User-IDs und VAULT-Pfad füllen
chmod +x automation/dispatcher.sh

# Secrets in die Umgebung (z. B. ~/.zshrc):
export SLACK_BOT_TOKEN="xoxb-..."       # nutzt dispatcher.sh
export SLACK_SIGNING_SECRET="..."       # nutzt slack-listener.py
```

### 4. Subagenten installieren

Kopiere die Prompt-Dateien in dein Claude-Agents-Verzeichnis (projekt- oder
benutzerweit), z. B.:

```bash
mkdir -p .claude/agents
cp prompts/auditor.md prompts/semantik-check.md .claude/agents/
```

Beide Dateien tragen YAML-Frontmatter (`name`, `description`, `tools`) und sind
damit als Subagenten `auditor` bzw. `semantik-check` aufrufbar. `dispatcher.md`
dient als Start-Prompt der koordinierenden Dispatcher-Session, `note-conventions.md`
als Referenz für das Notizformat.

### 5. Listener dauerhaft betreiben

`slack-listener.py` muss permanent laufen und seine Konfiguration über
**Umgebungsvariablen** bekommen (siehe Abschnitt „Zwei Konfigurationswege").
Auf macOS am einfachsten per LaunchAgent:

```bash
cp automation/examples/com.example.slack-listener.plist \
   ~/Library/LaunchAgents/com.example.slack-listener.plist
# Platzhalter (<PFAD>, IDs, Secret) in der plist ersetzen, dann:
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.slack-listener.plist
```

Der Listener triggert `dispatcher.sh` pro eingehender Nachricht. Zum Testen ohne
Slack lässt sich eine Runde auch manuell starten: `bash automation/dispatcher.sh`.

## Sicherheitshinweise

- `automation/config.sh` ist gitigniert und enthält IDs/Pfade — niemals committen.
- Tokens und das Signing Secret kommen aus der Umgebung, nie aus dem Repo.
- Der Listener verifiziert die Slack-Signatur, sofern `SLACK_SIGNING_SECRET`
  gesetzt ist — im Produktivbetrieb immer setzen.
- Der Dispatcher verarbeitet ausschließlich Nachrichten des einen konfigurierten
  `ALLOWED_USER`.
- `dispatcher.sh` startet Claude mit `--permission-mode bypassPermissions`. Das
  ist für autonomen Betrieb gedacht — nur in einer Umgebung verwenden, der du
  vertraust.

## Anpassbarkeit — auch ohne Slack

Der **Kern** dieses Frameworks ist der Qualitätsprozess, nicht der Transportweg:

```
Recherche (Agent) → quick-Audit → Mensch → Semantik-Check → Mensch → strict-Audit → Mensch → Veröffentlichung
```

Dieser Kern steckt in den **Prompts** (`prompts/`) und ist von Slack unabhängig.
Die `automation/` ist nur die mitgelieferte *Eingangs- und Freigabe-Schicht* —
hier zufällig über Slack.

Wer keinen Slack-Workspace nutzt, ersetzt die Transport-Schicht und behält den
Rest:

- **Ganz ohne Automatisierung:** Die Prompts direkt in einer Claude-Code-Session
  verwenden. Aufträge tippst du selbst, Freigaben gibst du im Dialog. Es braucht
  dann weder `dispatcher.sh`, `slack-listener.py` noch einen Tunnel.
- **Anderer Kanal:** `slack-listener.py` durch einen eigenen Eingang ersetzen
  (z. B. ein Telegram-Bot, eine E-Mail-Mailbox, ein Datei-Watcher auf einem
  `_INBOX/`-Ordner, ein simples Web-Formular). Erwartet wird nur: einen Auftrag
  entgegennehmen → `dispatcher.sh` (oder direkt Claude) anstoßen → Ergebnis/Frei-
  gabe zurückspielen.
- **Andere Freigabe-Geste:** Statt Slack-Reaktionen (✅/📝/❌) eine beliebige
  bestätigende Eingabe — die drei menschlichen Freigabepunkte bleiben gleich.

Die Slack-spezifischen Teile sind bewusst auf `automation/` konzentriert; an den
Prompts musst du dafür nichts ändern.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
