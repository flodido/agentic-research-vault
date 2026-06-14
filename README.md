# BrainVault Framework

Ein prüfbarer KI-Recherche- und Audit-Workflow für einen persönlichen
Wissensspeicher (Obsidian-Vault). Aufträge kommen über Slack herein, Claude
recherchiert und schreibt Notizen, und **kein Text gilt als fertig, bevor er ein
Audit-Gate bestanden hat und ein Mensch ihn freigegeben hat.**

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
```

## Audit-Modi & Schwellen

| Modus | Schwelle | Wofür |
|---|---|---|
| `quick` | ≥ 85 | Skizzen, frühe Entwürfe, Ideen |
| `standard` | ≥ 92 | Normale Wissensnotizen |
| `strict` | ≥ 97 | Veröffentlichung, Website, Recht/Finanzen/Medizin, harte Zahlen, Zitate |

Veröffentlichungs-/High-Stakes-Inhalte werden automatisch auf `strict` hochgestuft.

## Setup (Kurzfassung)

1. **Voraussetzungen:** Claude Code CLI, Python 3, ein Slack-Bot mit
   `chat:write`, `reactions:write`, `channels:history` und Event Subscriptions.
2. **Konfiguration:**
   ```bash
   cp automation/config.example.sh automation/config.sh
   # config.sh mit echten Channel-/User-IDs und Pfaden füllen
   export SLACK_BOT_TOKEN="xoxb-..."        # z. B. in ~/.zshrc
   export SLACK_SIGNING_SECRET="..."        # für den Webhook-Listener
   ```
3. **Prompts** in die Claude-Agents-Konfiguration übernehmen
   (`auditor.md` und `semantik-check.md` als Subagenten, `dispatcher.md` als
   Start-Prompt der Dispatcher-Session).
4. **Betrieb:** `slack-listener.py` permanent laufen lassen (LaunchAgent/systemd);
   er triggert `dispatcher.sh` pro eingehender Nachricht.

## Sicherheitshinweise

- `automation/config.sh` ist gitigniert und enthält IDs/Pfade — niemals committen.
- Tokens kommen aus der Umgebung, nie aus dem Repo.
- Der Dispatcher verarbeitet ausschließlich Nachrichten des einen konfigurierten
  `ALLOWED_USER`.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
