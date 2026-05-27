# Brain Dashboard

> Requires [Obsidian](https://obsidian.md) with the [Dataview plugin](https://github.com/blacksmithgu/obsidian-dataview).
> Open this vault in Obsidian and enable Dataview to render the queries below.
>
> Without Obsidian, the brain-session skill provides equivalent runtime queries
> against the same wiki/ files at the start of every Claude Code or Gemini CLI session.

---

## Open Items

```dataview
TABLE type, team, owner, raised
FROM "wiki/decisions"
WHERE status = "open"
SORT raised ASC
```

## Active Projects

```dataview
TABLE project_type, team
FROM "wiki/projects"
WHERE status.delivery = "active" OR status.personal = "active" OR status.leadership = "active"
SORT team ASC
```

## Stale Items
*Open decisions or questions with no update in 30+ days*

```dataview
TABLE type, team, owner, raised
FROM "wiki/decisions"
WHERE status = "open" AND date(today) - date(raised) > dur(30 days)
SORT raised ASC
```

## Recently Resolved

```dataview
TABLE type, team, resolved
FROM "wiki/decisions"
WHERE status = "resolved"
SORT resolved DESC
LIMIT 10
```

---

<!-- ──────────────────────────────────────────────────────────────────────── -->
<!-- OPTIONAL SECTIONS                                                        -->
<!-- Add or remove sections below to match your personal areas in config.yml  -->
<!-- ──────────────────────────────────────────────────────────────────────── -->

<!--
## Upcoming Travel

```dataview
TABLE date, file.link AS destination
FROM "wiki/projects/personal"
WHERE type = "project" AND contains(tags, "travel") AND status.personal = "active"
SORT date ASC
```

## Recent Theatre

```dataview
TABLE date, venue, rating
FROM "wiki/theatre"
WHERE status = "seen"
SORT date DESC
LIMIT 10
```

## Upcoming Theatre

```dataview
TABLE date, venue
FROM "wiki/theatre"
WHERE status = "upcoming"
SORT date ASC
```
-->
