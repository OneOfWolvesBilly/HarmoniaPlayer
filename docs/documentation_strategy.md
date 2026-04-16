# Documentation Strategy

This document defines how documentation is organised, named, and maintained
across the HarmoniaPlayer repository and the broader Harmonia ecosystem.
The intended audience is documentation maintainers — contributors who
write, review, or update `.md` files.

---

## 1. Three-Repo Ecosystem

HarmoniaPlayer is one of three repositories. Each has a distinct documentation
role:

```
┌─────────────────────────────────┐
│  HarmoniaPlayer (this repo)     │  App-level docs
│  SwiftUI macOS application      │  - UI / UX, user guide
└──────────────┬──────────────────┘  - App architecture, module boundaries
               │ SPM dependency       - IAP, persistence, platform integration
               │
┌──────────────▼──────────────────┐  Deploy-package docs
│  HarmoniaCore-Swift             │  - SPM usage, version pinning
│  Swift Package (subtree split)  │  - Adapter catalogue
└──────────────┬──────────────────┘
               │ implements spec from
┌──────────────▼──────────────────┐  Specification docs
│  HarmoniaCore                   │  - Ports, services, models specs
│  Source repo (Swift + C++)      │  - Cross-platform contracts
└─────────────────────────────────┘  - Implementation guides per language
```

### 1.1 Documentation scope by repo

Each repo documents only its own concerns. When a topic crosses boundaries,
link to the source of truth rather than duplicating.

| Topic | Documented in |
|-------|---------------|
| User-facing features, UI, keyboard shortcuts | **HarmoniaPlayer** |
| App architecture (AppState, Integration Layer, module boundaries) | **HarmoniaPlayer** |
| IAP, persistence, SwiftUI patterns | **HarmoniaPlayer** |
| SPM package setup, version tagging workflow | **HarmoniaCore-Swift** |
| Port interfaces, service contracts, error types | **HarmoniaCore** |
| Apple/C++ adapter implementation notes | **HarmoniaCore** (`docs/impl/`) |

---

## 2. Directory Policy

All HarmoniaPlayer documentation lives under `docs/`. Root-level files are
limited to build/license essentials:

**Root level:**
- `README.md` — project overview, quick start, links
- `LICENSE` — MIT License (no `.md` extension)

**Under `docs/`:**

| File | Audience | Function |
|------|----------|----------|
| `architecture.md` | Anyone understanding the system | C4 diagrams, layer design, design principles |
| `api_reference.md` | Developers using the API | Complete public interface: types, properties, methods, protocols |
| `module_boundary.md` | Code reviewers | Allowed/forbidden dependencies, enforcement checklist, boundary examples |
| `implementation_guide_swift.md` | Developers writing code | Swift patterns, error handling, IAP, testing patterns |
| `development_guide.md` | New contributors | Setup, HarmoniaCore integration, cross-repo workflow, coding conventions, project structure |
| `workflow.md` | All contributors | SDD → TDD → commit cycle |
| `user_guide.md` | End users | Feature walkthrough, shortcuts, troubleshooting |
| `documentation_strategy.md` | Documentation maintainers | This document — naming and update rules |

**Under `docs/slice/`:**

| File | Purpose |
|------|---------|
| `HarmoniaPlayer_development_plan.md` | High-level roadmap across slices |
| `slice_NN_micro.md` | Per-slice spec — committed to repo |
| `slice_NN_micro_draft.md` | In-progress draft slice spec |
| `HarmoniaPlayer_slice_NN_micro.md` | **Local-only** detailed developer version — never pushed to git |

See section 5 for the two-spec-file pattern.

---

## 3. Per-Document Functional Definitions

When updating a document, the content must stay within that document's
functional scope. Don't let `api_reference.md` become a tutorial; don't
let `development_guide.md` become an API catalogue.

- **`README.md`** — project outline, installation, quick start, doc links. No deep technical content.
- **`api_reference.md`** — exhaustive signatures. Every public type, property, method, protocol must be listed. No tutorials.
- **`architecture.md`** — system design: C4 diagrams, layer relationships, design principles. No code examples beyond illustrative snippets.
- **`module_boundary.md`** — dependency rules, boundary examples, enforcement checklist. Reviewer reference.
- **`implementation_guide_swift.md`** — code-level patterns and working examples. The answer to "how do I implement X following project conventions?"
- **`development_guide.md`** — new-contributor setup including repo layout, SPM wiring, cross-repo workflow, test doubles, Swift 6 conventions, project tree. This is the broadest document.
- **`workflow.md`** — SDD → TDD red → confirm → TDD green → commit cycle. Commit atomicity rules.
- **`user_guide.md`** — end-user feature walkthrough. No developer content.
- **`documentation_strategy.md`** — this document.

---

## 4. Naming Conventions

### 4.1 Filenames

- **Lowercase with underscores:** `development_guide.md`, not `DEVELOPMENT_GUIDE.md` or `development-guide.md`
- **No date stamps in filenames** (Git tracks history)
- **Descriptive nouns, not verbs:** `architecture.md`, not `design_the_app.md`
- **English only** — no Traditional Chinese or romanisation in filenames

### 4.2 Filename prefixes

- **No prefix** for standard documents committed to the repo: `architecture.md`, `api_reference.md`, etc.
- **`HarmoniaPlayer_` prefix** is reserved for **local-only** detailed developer files (never pushed). This is enforced at the author's side — see section 5.

### 4.3 Document titles

First-line H1 matches the filename's intent:

```markdown
# HarmoniaPlayer Architecture        ← architecture.md
# HarmoniaPlayer API Reference       ← api_reference.md
# HarmoniaPlayer Module Boundary     ← module_boundary.md
```

---

## 5. Two-Spec-File Pattern (Slices)

Each development slice produces **two spec files**:

| File | Location | Content | Commit? |
|------|----------|---------|---------|
| `slice_0X_micro.md` | `docs/slice/` | Concise reference: Goal / Scope / Files / API / TDD plan / Commit plan | **Yes** (committed to repo) |
| `HarmoniaPlayer_slice_X_micro.md` | Same folder, ignored by git | Detailed developer version with working notes, alternatives considered, rough edges | **No** (local-only) |

**Why two files:** the committed spec stays minimal and readable for future
reference; the local file captures details and work-in-progress reasoning
that would clutter the repo.

**Enforcement:** the `HarmoniaPlayer_` prefix is in `.gitignore` for slice
files. Treat any accidentally-tracked `HarmoniaPlayer_slice_*.md` as a
mistake to be removed.

---

## 6. Language Rules

- **Document content is English only.** All committed `.md` files in
  `docs/` must be written in English.
- **No Chinese text inside English-only documents.** If a discussion
  happens in Traditional Chinese, translate the conclusions into English
  before committing them to the doc.
- **Chat/review discussion** between maintainers can use any language
  (Traditional Chinese is the project default).
- **Code, comments, commit messages are all English**, regardless of
  discussion language.

---

## 7. Content Rules

### 7.1 No third-party product or competitor brand names

Spec files, architecture docs, and any committed doc must not reference
competing products by name. If comparison context is needed, describe the
category ("foobar2000-style playlist UI" is acceptable in commit
descriptions but not in committed specs; use "tab-based playlist UI"
instead).

### 7.2 No manual timestamps

Git tracks modification time. Don't add "Last updated: YYYY-MM-DD" to doc
headers — it goes stale instantly.

Exception: version-specific documents may include a version header:

```markdown
# HarmoniaPlayer Architecture

> This document describes HarmoniaPlayer v0.1.
```

Use only when the doc is deliberately frozen to a version.

### 7.3 Cross-repo linking

Always link to the **source of truth**, not a copy.

- For HarmoniaCore **specifications**:
  ```
  https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md
  ```
- For HarmoniaCore **implementation guides**:
  ```
  https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/impl/04_services_impl.md
  ```
- For HarmoniaCore-Swift package:
  ```
  https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift
  ```

Relative links for in-repo docs:
```markdown
See [Module Boundaries](module_boundary.md) for enforcement rules.
```

### 7.4 Avoid duplicating HarmoniaCore specs

If a topic is already documented in HarmoniaCore, link to it rather than
copying. HarmoniaPlayer docs should describe **how the app consumes** the
spec, not re-derive the spec.

---

## 8. Documentation Audit Rule

When updating a document — especially after any code change — read the
**full** document line by line and cross-check every claim against the
actual `.swift` files in the repo. This applies to:

- Every code example — verify type names, method signatures, access
  levels, parameter labels against the real code
- Every type mentioned in prose — verify it exists and is public
- Every file path and filename — verify it matches the repo
- Every feature described — verify it is actually implemented (or clearly
  marked as planned)

**Grep-only audits are insufficient.** A keyword search can miss stale
paragraphs that don't contain the keyword. Read the document start to
finish.

For `api_reference.md` specifically: every public type, property, and
method must be listed. Use a directory listing of `Shared/Models/` and
`Shared/Services/` as the checklist.

---

## 9. Update Triggers

When any of the following happens, the listed documents must be updated
in the same commit (or in a separate `docs(...)` commit immediately
following):

| Change | Documents to update |
|--------|---------------------|
| Add / remove `.swift` file | `api_reference.md` (if public API), `development_guide.md` project structure tree |
| Rename / move file | All docs referencing the old path |
| Change public method signature | `api_reference.md`, `implementation_guide_swift.md` (if in examples) |
| Change module boundary | `module_boundary.md`, `architecture.md` |
| Add / remove keyboard shortcut | `user_guide.md` |
| Change persistence key | `api_reference.md` persistence table |
| Change cross-repo wiring (SPM, provider) | `development_guide.md`, `implementation_guide_swift.md`, `README.md` |

---

## 10. Commit Conventions for Docs

Documentation commits use conventional-commits prefixes:

- `docs:` — general documentation updates
- `docs(file):` — updates to a specific file
- `chore(docs):` — typo fixes, formatting, link repair
- `feat(docs):` — new documentation sections or files
- `fix(docs):` — correcting technical errors

**Format rules (project-wide):**
- Bullet points use `-` only; no `*` or `•`
- Facts only in bullets; no prose paragraphs in commit bodies
- Spec commits are separate from code commits

**Examples:**

```
docs(architecture): remove Linux / C++ platform references

- Remove Section 3.2 Linux / C++ (deferred from HarmoniaCore)
- Update C4 Level 1 to show only macOS path
- Update design principles to remove cross-platform language

chore(docs): fix outdated ioError mapping in api_reference

- Correct CoreError.ioError → PlaybackError mapping
- Old: .outputError
- New: .failedToOpenFile

feat(docs): add workflow.md for SDD → TDD → commit cycle
```

---

## 11. Pre-Commit Documentation Checklist

Before committing documentation changes:

- [ ] All cross-repo links verified to resolve
- [ ] All in-repo relative links verified to resolve
- [ ] No manual timestamps added
- [ ] Document language is English only
- [ ] No competitor brand names introduced
- [ ] All code examples match actual `.swift` files
- [ ] Type names, method signatures, access levels match code
- [ ] Filename references match actual filenames (case-sensitive)
- [ ] Commit message follows convention
- [ ] No duplication of HarmoniaCore specs (link instead)
- [ ] Full document read end-to-end (not grep-only)

---

## 12. Quality Standards

### Clarity

- Short paragraphs (3–5 sentences)
- Bullet points for enumerations
- Tables for cross-reference lookup
- Code blocks for anything a reader might copy

### Accuracy

- Every code example compiles against the current repo
- No invented types, methods, or features
- Planned features clearly marked as such ("v0.2 Pro", "deferred")

### Navigation

- Table of contents for documents over ~200 lines
- Section numbering consistent within each document
- Cross-references to other docs use relative paths