# 🧭 Documentation Strategy

This document defines how all documents in the HarmoniaPlayer repository are structured, named, and maintained.  
It ensures every file under `/docs/` follows a consistent convention for clarity, discoverability, and synchronization with the codebase.

---

## 📁 Directory Policy

All project documentation lives under `/docs/`.

- System‑level files use lowercase with dots (e.g., `core.structure.md`).
- Public documents are written in English.
- Internal or bilingual references use Traditional Chinese duplicates where needed (e.g., `架構.md` mirrors `architecture.md`).
- Avoid capital letters in filenames (for cross‑platform Git consistency).

---

## 🧩 Document Categories

| Category | File Examples | Purpose |
|-----------|----------------|----------|
| **System Architecture** | `architecture.md`, `架構.md` | Directory and file hierarchy overview (tree + inline comments). |
| **Development Guides** | `DEVELOPMENT_GUIDE.md` | Open‑Core / IAP implementation and review policy. |
| **Technical Specs** | `core.structure.md`, `app.macos.md`, `adapters.overview.md` | Layer‑specific design and functional details. |
| **Version Records** | `CHANGELOG.md`, `CHANGELOG_CURSEFORGE.md` | Developer and user‑facing change logs. |
| **Meta Documentation** | `documentation.strategy.md` | Rules for document creation, naming, and maintenance. |

---

## 🧠 Maintenance Rules

- All documentation must remain synchronized with the repository’s source code and folder structure.  
- When introducing a new module, a corresponding spec file (`*.md`) must be added under `/docs/`.  
- Obsolete documents must be removed during refactors to prevent duplication or confusion.  
- Major revisions to structure or format must be reflected in both English and Chinese versions if dual‑language versions exist.  

---

### System Architecture Docs (architecture.md / 架構.md)

**Owner:** Billy (sole maintainer)

**Format**
- Tree + inline comments.
- Alphabetical sorting: folders first, then files.
- Must list real files (including `Package.swift`, `README.md`, `LICENSE`, and key test files).

**Update Policy**
- Update in the **same commit/PR** whenever folders/files are added, removed, or renamed.
- If missed, fix within **7 days** (weekly audit is acceptable).

**Version Control**
- Mention architecture changes in commit messages  
  (e.g., `chore(docs): update architecture tree for Adapters/*`).

**Scope**
- While single‑maintainer, no extra approval or review process is required.

---

## 🧾 Commit Convention

Each documentation update should use one of the following prefixes:

- `docs:` for general documentation updates.  
- `chore(docs):` for maintenance tasks such as sorting or cleanup.  
- `feat(docs):` when adding new documentation categories or major guides.

Example:
```
chore(docs): update architecture.md after refactoring Adapters structure
```

---

## 📦 Version Synchronization

- Documentation revisions are versioned alongside the codebase.  
- When a new release tag is created, ensure `/docs/architecture.md` and related layer specs reflect the state of the repository.  
- Changelog entries must include documentation updates when they affect developers or end‑users.

---

_Last updated by Billy — HarmoniaSuite Project_
