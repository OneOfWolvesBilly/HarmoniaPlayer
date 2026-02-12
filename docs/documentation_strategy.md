# 🧭 Documentation Strategy

This document defines how documentation is organized in HarmoniaPlayer.

---

## 🌐 HarmoniaSuite Ecosystem

HarmoniaPlayer is part of a multi-repository ecosystem:

```
HarmoniaCore (Main)
├── apple-swift/              → Becomes → HarmoniaCore-Swift (SPM)
├── linux-cpp/                → Future
└── docs/specs/               → Specifications

HarmoniaPlayer (This Repo)
└── depends on → HarmoniaCore-Swift
```

---

## 📁 Directory Policy

All documentation lives under `/docs/` (except root-level files).

**Root-level files:**
- `README.md` - Project overview and quick start
- `CHANGELOG.md` - Version history
- `LICENSE.md` - MIT License

**Documentation files:**
- `docs/architecture.md` - System architecture
- `docs/development_guide.md` - Developer guide
- `docs/documentation_strategy.md` - This file
- `docs/user_guide.md` - End-user usage and interaction guide

---

## 🧩 Document Categories

| Category | Files | Purpose |
|----------|-------|---------|
| **Architecture** | `architecture.md` | System design and structure |
| **Development** | `development_guide.md` | Setup, workflow, IAP integration |
| **User Docs** | `user_guide.md` | How to use the app |
| **Meta** | `documentation_strategy.md` | Documentation policy |
| **Changelog** | `CHANGELOG.md` | Version history |

---

## 📝 Documentation Scope

### This Repository (HarmoniaPlayer)

Documents **application-level** concerns:
- ✅ UI/UX architecture
- ✅ User guides
- ✅ IAP integration
- ✅ Platform-specific app logic
- ✅ Development setup

**Does NOT document:**
- ❌ Core audio logic → See HarmoniaCore
- ❌ Port specifications → See HarmoniaCore
- ❌ Adapter implementations → See HarmoniaCore-Swift

### HarmoniaCore Repository

Documents **framework-level** concerns:
- Platform-agnostic specifications
- Port interfaces
- Service contracts
- Cross-platform behavior

### HarmoniaCore-Swift Repository

Documents **implementation-level** concerns:
- Swift-specific implementation notes
- Apple platform adapters
- SPM package usage

---

## 🔗 Cross-Repository Linking

Always link to the **source of truth**.

### For Specifications

Link to HarmoniaCore main repository:

```markdown
[DecoderPort Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md#decoderport)
```

### For Implementation

Link to HarmoniaCore-Swift repository:

```markdown
[AVAssetReaderDecoderAdapter](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift/blob/main/Sources/HarmoniaCore/AVAssetReaderDecoderAdapter.swift)
```

### For SPM Integration

Link to HarmoniaCore-Swift package:

```markdown
[HarmoniaCore-Swift Package](https://github.com/OneOfWolvesBilly/HarmoniaCore-Swift)
```

---

## 🧠 Maintenance Rules

### When to Update Architecture Docs

Update `architecture.md` when:
- Adding/removing directories
- Changing project structure
- Adding new targets
- Modifying dependency setup

**Policy:** Update in the **same commit** as code changes.

**Example commit:**
```bash
git commit -m "feat: add iOS target

- Created iOS/Free/ directory
- Updated architecture.md to reflect new structure"
```

### When to Update CHANGELOG

Update `CHANGELOG.md` when:
- Adding new features
- Fixing bugs
- Making breaking changes
- Releasing new versions

**Format:** Follow [Keep a Changelog](https://keepachangelog.com/)

**Example:**
```markdown
## [Unreleased]

### ✨ Added
- iOS Free target support
- Album art display

### 🐞 Fixed
- Playback state sync issue
```

### When to Update User Guide

Update `user_guide.md` when:
- Changing UI behavior
- Adding new features
- Modifying keyboard shortcuts
- Updating supported formats

### When to Update Development Guide

Update `DEVELOPMENT_GUIDE.md` when:
- Changing development setup process
- Adding new dependencies
- Modifying build configuration
- Updating IAP integration

---

## 🧾 Commit Convention

Use these prefixes for documentation commits:

- `docs:` - General documentation updates
- `chore(docs):` - Maintenance (sorting, cleanup)
- `feat(docs):` - New documentation sections
- `fix(docs):` - Correction of errors

**Examples:**
```bash
docs: update architecture.md after HarmoniaCore extraction
chore(docs): fix typos in DEVELOPMENT_GUIDE.md
feat(docs): add user_guide.md with keyboard shortcuts
fix(docs): correct SPM dependency URL in README.md
```

---

## 🔄 Synchronization with HarmoniaCore

### Avoid Duplication

HarmoniaPlayer documentation should:
- **Link to** HarmoniaCore docs for technical details
- **Focus on** UI/UX and app-level architecture
- **Avoid duplicating** HarmoniaCore specifications

### Example: Audio Format Support

**❌ Bad (duplicates HarmoniaCore spec):**
```markdown
## Supported Formats

### DecoderPort Implementation Details
The AVAssetReaderDecoderAdapter uses AVFoundation's AVAssetReader...
(lengthy technical explanation)
```

**✅ Good (links to source of truth):**
```markdown
## Supported Formats

**Free Version:**
- MP3, AAC, ALAC, WAV, AIFF

**Pro Version (v0.2+):**
- All Free formats + FLAC, DSD

For technical details on audio decoding, see [HarmoniaCore DecoderPort Specification](https://github.com/OneOfWolvesBilly/HarmoniaCore/blob/main/docs/specs/03_ports.md#decoderport).
```

### When to Document Locally

Document in HarmoniaPlayer when:
- Describing **UI-level** behavior (how the app uses HarmoniaCore)
- Explaining **user-facing** features
- Detailing **platform-specific** app logic (macOS menu bar, iOS background audio)

Document in HarmoniaCore when:
- Defining **port interfaces**
- Specifying **service contracts**
- Explaining **cross-platform** audio behavior

---

## ⏰ Version Tracking

### Do NOT Use Manual Timestamps

❌ **Bad:**
```markdown
# Architecture

...

Last updated: 2026-01-15
```

✅ **Good:**
```markdown
# Architecture

...

(No timestamp - Git tracks this automatically)
```

### Where Time Information Lives

| Requirement | Location |
|-------------|----------|
| **Document modification time** | Git commit timestamp |
| **Feature release time** | `CHANGELOG.md` |
| **Version correspondence** | Document header (optional) |
| **Roadmap timeline** | `README.md` Roadmap section |

### Optional: Version Tagging

If a document describes a specific version:

```markdown
# HarmoniaPlayer Architecture

> This document describes HarmoniaPlayer v0.1 architecture.

...
```

Only use this when:
- Document is **version-specific** (not updated frequently)
- Major architectural changes between versions
- Need to maintain historical documentation

---

## 📋 Documentation Checklist

Before committing documentation changes:

- [ ] All cross-repository links are valid
- [ ] No manual timestamps added
- [ ] CHANGELOG.md updated (if applicable)
- [ ] architecture.md updated (if structure changed)
- [ ] Commit message follows convention
- [ ] No duplication of HarmoniaCore specs
- [ ] All code examples compile
- [ ] Markdown formatting is correct

---

## 🎯 Quality Standards

### Clear and Concise

- Use simple language
- Short paragraphs (3-5 sentences max)
- Bullet points for lists
- Code examples for clarity

### Accurate

- Test all code examples
- Verify all links
- Keep synchronized with codebase
- Update when behavior changes

### Accessible

- Use headings for navigation
- Add table of contents for long docs
- Include examples
- Link to related documentation
