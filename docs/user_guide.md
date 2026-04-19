# HarmoniaPlayer User Guide

Complete guide for using HarmoniaPlayer on macOS.

---

## Table of Contents

1. [Installation](#installation)
2. [Getting Started](#getting-started)
3. [Adding Music](#adding-music)
4. [Playback Control](#playback-control)
5. [Playlists](#playlists)
6. [File Info](#file-info)
7. [Mini Player](#mini-player)
8. [Settings](#settings)
9. [Keyboard Shortcuts](#keyboard-shortcuts)
10. [Troubleshooting](#troubleshooting)
11. [FAQ](#faq)
12. [Getting Help](#getting-help)

---

## Installation

### Requirements

- macOS 15.6 or later
- ~100 MB free disk space

### Install

Pre-built downloads will be available with the v0.1 release. Until then, see
[README.md](../README.md#build-from-source) for build-from-source instructions.

---

## Getting Started

### First Launch

1. Open HarmoniaPlayer
2. If you see a security warning:
   - Open **System Settings → Privacy & Security**
   - Click **"Open Anyway"** next to HarmoniaPlayer

### Main Window

```
┌─────────────────────────────────────────────────────────────┐
│ File   Edit   Playback   Window   Help                      │
├─────────────────────────────────────────────────────────────┤
│  Playlist 1  │  Playlist 2  │  +                            │  ← playlist tabs
├─────────────────────────────────────────────────────────────┤
│  [Album Art]   Track Title — Artist                         │
│                Album Name                                    │
│                ━━━━━●━━━━━━━━━━━━ 1:23 / 3:45                │
│                [⏮] [▶] [⏹] [⏭]   🔀  🔁   🔊 ─────●────      │
├─────────────────────────────────────────────────────────────┤
│  #  Title          Artist        Album       Duration  ...  │
│  1  Song A         Artist X      Album Y     3:45           │
│  2  Song B         Artist Z      Album W     2:58           │
│     ...                                                      │
└─────────────────────────────────────────────────────────────┘
```

### Interface overview

- **Playlist tabs (top):** switch between playlists; click `+` to create a new one
- **Now Playing area:** album artwork, track info, progress bar, transport controls, shuffle/repeat, volume
- **Playlist table (bottom):** your tracks with customisable columns; drag rows to reorder, click column headers to sort

---

## Adding Music

### Drag and drop

Drag files or entire folders from Finder into the playlist area. Directories
are scanned recursively — all supported audio files inside are added.

### File menu / shortcut

- **File → Add Files…** or press **`⌘O`**
- Select one or more files, click **Open**

### Supported formats (v0.1 Free)

HarmoniaPlayer v0.1 supports these audio formats:

- **MP3** — MPEG-1/2 Layer 3
- **AAC / M4A** — Advanced Audio Coding
- **ALAC** — Apple Lossless
- **WAV** — Waveform Audio
- **AIFF** — Audio Interchange File Format

Files in other formats (including FLAC, DSF, DFF) are skipped at import time
and listed in the "Unsupported Format" alert. Support for FLAC and DSD is
planned for v0.2 (Pro).

### Duplicate handling

By default, dropping a file that is already in the current playlist shows an
"Already in Playlist" alert listing the skipped files. You can allow
duplicates in **Settings → Playlist** if you prefer.

---

## Playback Control

### Playing a track

- **Double-click** any track in the playlist, or
- Select a track and press **`Space`** / click **Play**

### Transport controls

| Control | Action | Shortcut |
|---------|--------|----------|
| ⏮ | Previous track | `⌘←` |
| ▶ / ⏸ | Play / Pause | `Space` |
| ⏹ | Stop | `⌘.` |
| ⏭ | Next track | `⌘→` |
| — | Seek forward 5 s | `→` |
| — | Seek backward 5 s | `←` |

When a track ends, behaviour depends on the current repeat mode.

### Repeat & Shuffle

- **Repeat** (`⌘R`) cycles through three modes:
  - **Off:** advance to next track; stop after the last track
  - **Repeat All:** advance; loop from last to first
  - **Repeat One:** replay the current track indefinitely
- **Shuffle** (`⌘S`) toggles random-order playback within the active playlist

The current mode is shown on the transport bar.

### Progress bar

Click or drag the progress bar to seek. The time on the left is the current
position; the time on the right is the total duration.

### Volume

Use the volume slider in the Now Playing area (or drag it) to adjust output
level. A percentage label appears while you drag. Volume is saved across
app launches.

### ReplayGain

If your files have ReplayGain tags embedded, HarmoniaPlayer can apply them
to normalise loudness between tracks or albums. Choose the mode in
**Settings → ReplayGain:**

- **Off** — no adjustment (default)
- **Track** — apply per-track gain
- **Album** — apply album-level gain for consistent album playback

---

## Playlists

HarmoniaPlayer supports **multiple playlists** shown as tabs at the top
of the window. All playlists are saved automatically on quit and restored
on next launch.

### Create, rename, delete

- **New playlist:** click `+` in the tab bar, or **File → New Playlist**
- **Rename:** double-click the tab name, or **File → Rename Playlist**
- **Delete:** right-click the tab → Delete, or **File → Delete Playlist**

### Track operations

Right-click a track for the context menu:

- **Play** — start playback from this track
- **Play Next** — move this track to play right after the current one
- **Get Info** — open the File Info panel (⌘I)
- **Remove from Playlist** — delete the track from this playlist

Or use keyboard:

- **`Delete`** — remove selected tracks
- **Drag** rows to reorder

### Sorting columns

Click a column header to sort. Click again to reverse. A "Restore order"
button in the toolbar returns the playlist to the order you added files.

Available columns: Title, Artist, Album, Album Artist, Year, Track #,
Disc #, Genre, Composer, BPM, Comment, Bitrate, Sample Rate, Channels,
File Size, File Format, Duration.

Columns can be shown/hidden and reordered via the column header menu.

### Undo / Redo

Playlist operations (add, remove, move) support undo:

- **`⌘Z`** — undo
- **`⌘⇧Z`** — redo

Up to the most recent 10 operations are remembered.

### M3U8 import / export

- **File → Export Playlist…** saves the active playlist as an `.m3u8` file.
  You can choose between absolute or relative paths when exporting.
- **File → Import Playlist…** loads an `.m3u8` file as a new playlist tab.
  Files that no longer exist at the referenced path are skipped with a
  warning alert.

---

## File Info

Select a track and press **`⌘I`** (or right-click → Get Info) to open the
File Info window, showing:

- **Artwork:** embedded album artwork, with pixel dimensions
- **Tags:** Title, Artist, Album, Album Artist, Composer, Genre, Year,
  Track / Disc numbers, BPM, Comment, ReplayGain values
- **Technical info:** bitrate, sample rate, channel count, file size,
  file format
- **Source URLs:** files downloaded from the web have their
  `kMDItemWhereFroms` source URL shown; you can edit or clear this

File Info is a standalone window: it is resizable, draggable, and does
not block the main window, so you can keep playing music and continue
using the app while it is open. You can also open multiple File Info
windows at once (one per track) to compare tracks side by side. Close
each window with **`⌘W`** or the window's close button.

---

## Mini Player

Open a compact floating player window via **Window → Mini Player**
(**`⌘M`**). The Mini Player:

- Shows the current track title and artist with a marquee scroll for long names
- Provides previous / play / pause / next controls
- Can be set to float above other windows (**Settings → Mini Player → Always on Top**)
- Has adjustable scroll speed and pause length for the marquee text

Close the Mini Player to return focus to the main window.

---

## Settings

Open via **HarmoniaPlayer → Settings…** or **`⌘,`**.

### Playlist

- **Allow duplicate tracks** — by default, dropping a file already in the
  playlist is skipped. Enable to allow duplicates.

### Mini Player

- **Always on top** — floating window stays above other apps
- **Marquee speed / pause** — adjust how fast the track title scrolls
  when it's too long to fit

### ReplayGain

- Choose **Off / Track / Album** (see [Playback Control](#playback-control))

### Language

Choose the UI language: **System (follow macOS)**, **English**, **繁體中文**,
or **日本語**. Changing the language requires a restart.

---

## Keyboard Shortcuts

### Playback

| Shortcut | Action |
|----------|--------|
| `Space` | Play / Pause |
| `⌘.` | Stop |
| `⌘→` | Next track |
| `⌘←` | Previous track |
| `→` | Seek forward 5 s |
| `←` | Seek backward 5 s |
| `⌘R` | Cycle repeat mode |
| `⌘S` | Toggle shuffle |

### Playlist & File

| Shortcut | Action |
|----------|--------|
| `⌘O` | Add files |
| `⌘I` | Show File Info for selected track |
| `Delete` | Remove selected tracks |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |

### Window

| Shortcut | Action |
|----------|--------|
| `⌘M` | Open Mini Player |
| `⌘,` | Open Settings |
| `⌘Q` | Quit |

---

## Troubleshooting

### "File not found" alert at launch

A file in your saved playlist has been moved, renamed, or deleted since it
was added. The inaccessible track stays in the playlist but is marked as
unavailable — remove it, or put the file back at its original location.

### "Unsupported Format" alert when adding files

The file's format is not supported in v0.1. Free formats are MP3, AAC,
ALAC, WAV, AIFF. Formats like FLAC and DSD are planned for v0.2 (Pro).
Convert the file to a supported format, or wait for Pro.

### "Already in Playlist" alert

The dropped file is already in the current playlist. Either:
- Accept the skip (default behaviour), or
- Enable **Settings → Playlist → Allow duplicate tracks** if you want the
  file added again

### No sound

Check in order:

1. **System volume** — click the speaker in the menu bar; make sure it's
   not muted
2. **Output device** — System Settings → Sound → Output; select the correct
   device
3. **HarmoniaPlayer volume** — the slider in the Now Playing area might be
   at zero
4. **Try a different file** — if only one file is silent, that file may be
   corrupted

### Playback stutters or cracks

1. **High CPU load** — close other apps; check Activity Monitor
2. **Very high sample rate** — 192 kHz files may struggle on older Macs;
   try 44.1 or 48 kHz files
3. **External drive** — slow drives can cause dropouts; try copying the
   file to the internal drive

### App won't open due to macOS security

If you see *"HarmoniaPlayer cannot be opened because it is from an
unidentified developer"*:

1. Open **System Settings → Privacy & Security**
2. Scroll to the **Security** section
3. Click **"Open Anyway"** next to the HarmoniaPlayer message
4. Confirm **Open** in the dialog

### Playlists didn't restore

Playlists and settings are saved when you quit (⌘Q) or when macOS shuts
down normally. If the app was force-quit or crashed, some recent changes
may not have been saved. The data is stored via macOS bookmarks so it
survives relaunch even if the files move — as long as macOS can still
resolve the bookmark.

---

## FAQ

**Is HarmoniaPlayer free?**
Yes. v0.1 (Free tier) is free and open source (MIT). v0.2 will add a Pro
tier via a one-time in-app purchase for additional formats and features.

**What's the difference between Free and Pro?**
- **Free (v0.1):** MP3, AAC, ALAC, WAV, AIFF + all playback, playlist,
  metadata-reading, and UI features
- **Pro (v0.2, planned):** adds FLAC and DSD playback, tag editing,
  synchronised lyrics, gapless playback

**Is my music uploaded anywhere?**
No. HarmoniaPlayer is completely offline. All music stays on your Mac.
The app does not make any network calls for audio content.

**Can I edit tags?**
Not in v0.1 — tags are read-only. Tag editing is planned for v0.2.

**Does it support synchronised lyrics?**
Not in v0.1. LRC / synchronised lyrics are planned for v0.2 (Pro).

**Does it support gapless playback?**
Not in v0.1. Gapless playback is planned for v0.2 (Pro).

**Does it support streaming services?**
No. HarmoniaPlayer plays local files only.

**Where does HarmoniaPlayer store my data?**
Playlists, settings, language, volume, and similar preferences are stored
in macOS UserDefaults (standard app preferences storage). Audio files
themselves stay wherever you put them — HarmoniaPlayer just remembers
where they are via macOS security-scoped bookmarks.

**What macOS version do I need?**
macOS 15.6 or later.

---

## Getting Help

### Report a bug

1. Visit [GitHub Issues](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/issues)
2. Click **New Issue**
3. Include:
   - What you did
   - What happened vs what you expected
   - macOS version
   - HarmoniaPlayer version

### Request a feature

1. Visit [GitHub Discussions](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/discussions)
2. Click **New Discussion** → **Ideas**
3. Describe what you'd like

### Contact

- **Email:** [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub:** [@OneOfWolvesBilly](https://github.com/OneOfWolvesBilly)
- **Repository:** [HarmoniaPlayer](https://github.com/OneOfWolvesBilly/HarmoniaPlayer)