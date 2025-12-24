# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2025-12-24

### ✨ Added
- Added `docs/user_guide.md` — end-user usage notes and workflows (draft).
- Added a C4 Level 1 system context diagram to `docs/architecture.md`.
- Documented HarmoniaPlayer ↔ HarmoniaCore boundaries and integration expectations
  (HarmoniaPlayer consumes HarmoniaCore services; it does not re-implement audio logic).

### 🐞 Fixed
- Fixed documentation cross-links / paths after documentation restructuring.
- Clarified wording to separate app-level responsibilities (HarmoniaPlayer) from framework-level specs (HarmoniaCore).

### 🔧 Changed
- Moved/renamed documentation files into `docs/` with standardized filenames:
  - `architecture.md` → `docs/architecture.md`
  - `DEVELOPMENT_GUIDE.md` → `docs/development_guide.md`
  - `documentation.strategy.md` → `docs/documentation_strategy.md`
- Updated `README.md` to reflect the new documentation entry points.

## [1.0.1] - 2025-10-25

### ✨ Added
- Added `architecture.md` — full project structure (alphabetically sorted, tree + inline comments)
- Added `documentation.strategy.md` — document naming, structure, and maintenance policy
- Initialized `CHANGELOG.md` for future documentation tracking
- Added `docs/roadmap.md` and `docs/spec.phase1.md` for upcoming development

### 🐞 Fixed
- None

### 🔧 Changed
- Updated `README.md` — added document links section and last-updated footer

## [1.0.0] - 2025-10-21

### ✨ Added
- Added `README.md` — project overview, architecture summary, and open-core/IAP explanation
- Added `DEVELOPMENT_GUIDE.md` — developer guide for Open-Core model and IAP integration
- Added `LICENSE` — MIT License © Chih-hao (Billy) Chen

### 🐞 Fixed
- None

### 🔧 Changed
- None