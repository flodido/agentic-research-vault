# Note Conventions

Diese Konvention gilt fuer neue oder wesentlich geaenderte Obsidian-Notizen,
besonders fuer Dateien unter `Research/`, `Data/Processed/` und verarbeitete
`_INBOX/`-Inhalte.

Ziel: Notizen sollen auffindbar, auditierbar und fuer Dispatcher/Subagenten
einheitlich weiterverarbeitbar sein.

## Grundprinzipien

- Jede Wissensnotiz beginnt mit YAML-Frontmatter.
- Tags sind klein geschrieben und verwenden Bindestriche statt Leerzeichen.
- Tags bleiben grob genug, um spaeter wirklich nutzbar zu sein.
- Feine Zusammenhaenge entstehen ueber `[[Wikilinks]]`, nicht ueber immer neue
  Spezialtags.
- Jede nicht-triviale Sachbehauptung braucht eine Fussnote im Format `[^id]`.
- Eine reine Quellenliste am Ende reicht nicht aus.
- Neue Wissensnotizen starten mit `audit.status: pending`, bis der Auditor
  freigibt.

## Standard-Frontmatter

```yaml
---
tags: [thema, technologie, notiztyp]
status: idee|konzept|in-arbeit|review|approved|archiv
erstellt: YYYY-MM-DD
session: dispatcher|subagent
bezuege: "[[Verwandte Note]]; externer oder lokaler Kontext"
audit:
  status: pending
  auditor: auditor
  mode: quick|standard|strict
---
```

Nicht jede Note braucht jedes Feld. `tags`, `status`, `erstellt` und bei
auditpflichtigen Wissensnotizen `audit` sind der Default.

## Status-Werte

| Status | Bedeutung |
|---|---|
| `idee` | Roher Gedanke, noch nicht strukturiert |
| `konzept` | Plan, Architektur, Entscheidungsgrundlage |
| `in-arbeit` | Noch aktiv in Bearbeitung |
| `review` | Inhalt steht, wartet auf Pruefung/Freigabe |
| `approved` | Auditor- oder Nutzerfreigabe abgeschlossen |
| `archiv` | Nicht mehr aktiv, nur historisch relevant |

## Audit-Felder

Vor dem Audit:

```yaml
audit:
  status: pending
  auditor: auditor
  mode: standard
```

Nach Freigabe:

```yaml
audit:
  status: approved
  auditor: auditor
  mode: standard
  score: NN
  audited: YYYY-MM-DD
```

Bei Skizzen oder fruehen Entwuerfen kann `quick` genutzt werden. Fuer
Veroeffentlichung, Website, Kundenbezug, Recht/DSGVO, Finanzen, Medizin, harte
Zahlen, Zitate oder sonstige High-Stakes-Inhalte gilt `strict`.

## Tagging

Tags beschreiben:

- Domain: z. B. `homelab`, `dsgvo`, `qa`
- Technologie: z. B. `docker`, `linux-host`, `slack`, `anthropic`, `caddy`
- Notiztyp: `konzept`, `recherche`, `analyse`, `artikel-entwurf`,
  `zusammenfassung`

Beispiele:

```yaml
tags: [homelab, paperless, linux-host, docker, server-architektur, konzept]
tags: [dsgvo, anthropic, slack, analyse]
tags: [ki-agenten, qa, prompt-versioning, recherche]
```

Vermeiden:

- Tags mit Leerzeichen
- einmalige Fantasietags
- zu viele Varianten fuer dasselbe Thema, z. B. `macmini`, `mac-mini`,
  `m4-mac-mini`
- Tags fuer Details, die besser als Wikilink oder Abschnitt im Text stehen

## Wikilinks

Nutze `[[Wikilinks]]` fuer echte inhaltliche Beziehungen:

- verwandte Konzepte
- Vorgaenger-/Folgenotizen
- zentrale Projekte
- wiederkehrende Systeme

Empfohlen direkt nach dem Titel oder im Frontmatter-Feld `bezuege`.

Beispiel:

```markdown
**Verwandte Notizen:** [[Homelab-Umbau-Paperless-Linux-Host]] · [[MailPilot]]
```

## Dateinamen

Dateinamen sind sprechend, stabil und ohne Sonderzeichen, soweit praktikabel.

Muster:

```text
Thema-Unterthema-Kontext.md
```

Beispiele:

```text
Homelab-Umbau-Paperless-Linux-Host.md
Best-Practices-Versionierung-LLM-Agenten-Prompts-2026.md
```

## Quellen und Fussnoten

Jede konkrete Sachbehauptung, Zahl, rechtliche Aussage, Produktangabe,
Vergleich oder Aktualitaetsaussage braucht eine Fussnote.

Format:

```markdown
Paperless laeuft im aktuellen Setup als Docker-Compose-Stack.[^paperless-compose]

[^paperless-compose]: `pfad/zur/docker-compose.yml`, Services `webserver`, `db`, `broker`, gelesen am YYYY-MM-DD.
```

Fuer Webquellen:

```markdown
[^quelle-1]: Titel, Herausgeber/Autor, URL, abgerufen am YYYY-MM-DD.
```

## Minimalvorlage

```markdown
---
tags: [thema, notiztyp]
status: konzept
erstellt: YYYY-MM-DD
audit:
  status: pending
  auditor: auditor
  mode: standard
---

# Titel

## Ausgangslage

## Einordnung

## Offene Fragen

## Naechste Schritte

## Quellen

[^quelle-1]: Quelle, Abschnitt, URL oder lokaler Pfad, abgerufen am YYYY-MM-DD.
```

## Anwendung durch Agenten

Dispatcher und Subagenten sollen diese Konvention verwenden, wenn sie neue
Notizen anlegen oder bestehende Notizen wesentlich erweitern.

Wenn eine bestehende Note ein anderes Format nutzt, nicht blind alles umbauen.
Nur bei wesentlicher Bearbeitung vorsichtig annaehern und bestehende Inhalte
erhalten.
