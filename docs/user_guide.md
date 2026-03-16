# HarmoniaPlayer User Guide

Complete guide for using HarmoniaPlayer music player.

---

## Table of Contents

1. [Installation](#installation)
2. [Getting Started](#getting-started)
3. [Adding Music](#adding-music)
4. [Playback Control](#playback-control)
5. [Keyboard Shortcuts](#keyboard-shortcuts)
6. [Playlist Management](#playlist-management)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

---

## Installation

### Download Pre-Built App

*(Pre-built downloads coming in v0.1 release)*

### Build from Source

See [README.md](../README.md#build-from-source) for build instructions.

**Requirements:**
- macOS 13.0 or later
- 100 MB free disk space

---

## Getting Started

### First Launch

1. **Open HarmoniaPlayer**
   - Double-click the app icon
   - If you see a security warning:
     - Open **System Settings** → **Privacy & Security**
     - Click **"Open Anyway"**

2. **Main Interface**

```
┌──────────────────────────────────────────────┐
│  File  Edit  Playback  Window  Help          │
├──────────────────────────────────────────────┤
│  [⏮] [▶️] [⏭] [⏹]                          │
├──────────────┬───────────────────────────────┤
│              │                               │
│  Playlist    │   Now Playing                 │
│              │                               │
│  (empty)     │   🎵 Album Art Placeholder    │
│              │                               │
│  Drag files  │   No Track Loaded             │
│  here or     │                               │
│  click +     │   [━━━━━━━━━━━━━━━] 0:00      │
│              │                               │
│              │   Status: Stopped             │
│              │                               │
└──────────────┴───────────────────────────────┘
```

### Interface Overview

HarmoniaPlayer uses a **customizable 3-column layout**. You can show/hide panels via the **View** menu.

**Toolbar (Top):**
- ⏮ Previous Track
- ▶️ Play / ⏸ Pause
- ⏭ Next Track
- ⏹ Stop
- **[View]** - Toggle panel visibility
- **[Settings]** - Open preferences

**Left Panel - Playlist** (always visible):
- List of tracks in queue
- Click `+` to add files
- Drag and drop to add files

**Center Panel - Waveform Display** (optional):
- Visual representation of audio waveform
- Shows amplitude over time
- Current position indicator (playhead)
- Click anywhere to seek to that position
- Zoom controls (+ / - buttons)
- **Toggle**: View → Show Waveform (⌘W)

**Right Panel - Now Playing** (optional):
- Album art (placeholder in current version)
- Track title and artist
- Progress bar with time (0:42 / 3:45)
- Playback status
- Volume control
- **Toggle**: View → Show Now Playing (⌘I)

### View Presets

You can quickly switch between different layouts to suit your needs:

**1. Minimal View** (⌘1) - Playlist only
- Perfect for distraction-free listening
- Shows only essential controls and playlist
- Smallest window size

**2. Standard View** (⌘2) - Playlist + Now Playing
- Balanced layout for everyday use
- Shows track info and album art
- Good for casual listening

**3. Full View** (⌘3) - All panels (default)
- Complete audio workstation experience
- Shows waveform, playlist, and track info
- Ideal for audio editing or detailed playback control

**How to switch:**
- Menu: View → Presets → [Select preset]
- Keyboard: ⌘1 (Minimal), ⌘2 (Standard), ⌘3 (Full)

Your layout preference is automatically saved and restored on next launch.

---

## Adding Music

### Method 1: Drag and Drop

1. Open **Finder**
2. Navigate to your music folder
3. Select audio files
4. **Drag** files onto the **Playlist** area
5. Files appear in the list

### Method 2: File Menu

1. Click the **`+`** button in playlist header
   - Or use menu: **File → Add to Playlist**
2. Browse and select audio files
3. Click **"Open"**
4. Files appear in the playlist

### Method 3: Keyboard Shortcut

1. Press **`⌘O`** (Command-O)
2. Select files
3. Click **"Open"**

### Supported Formats

**Free Version:**
- ✅ **MP3** - MPEG-1/2 Layer 3
- ✅ **AAC** - Advanced Audio Coding (M4A)
- ✅ **ALAC** - Apple Lossless (M4A)
- ✅ **WAV** - Waveform Audio File
- ✅ **AIFF** - Audio Interchange File Format

**Pro Version (v0.2+):**
- All Free formats
- ✅ **FLAC** - Free Lossless Audio Codec
- ✅ **DSD** - Direct Stream Digital (DSF/DFF)

---

## Playback Control

### Play a Track

**Method 1: Double-click**
- Double-click any track in the playlist

**Method 2: Select and play**
1. Click to select a track
2. Press **`Space`** or click **Play** button

### Basic Controls

| Button | Action | Keyboard |
|--------|--------|----------|
| ▶️ Play | Start playback | `Space` |
| ⏸️ Pause | Pause playback | `Space` |
| ⏹️ Stop | Stop and reset | `⌘.` |
| ⏮️ Previous | Go to previous track | `⌘←` |
| ⏭️ Next | Go to next track | `⌘→` |
| 🔁 Repeat | Cycle repeat mode (Off → All → One) | `⌘R` |

### Progress Bar

**Seek to Position:**
1. Click anywhere on the progress bar
2. Playback jumps to that position

**Scrub Through Track:**
1. Click and hold on the playhead
2. Drag left or right
3. Release to play from new position

**Time Display:**
- Left side: Current position (e.g., `1:23`)
- Right side: Total duration (e.g., `3:45`)
- Format: `minutes:seconds`

### Playback Behavior

**Auto-Advance:**
- When a track finishes, behavior depends on repeat mode (see below)

**Repeat Modes:**
- **Off** (default): When a track finishes, plays next track. If on last track, playback stops
- **Repeat All** 🔁: When last track finishes, loops back to the first track
- **Repeat One** 🔂: Current track repeats indefinitely

Cycle through modes by clicking the Repeat button or pressing `⌘R`.

**Resume Playback:**
- If you pause, playback resumes from same position
- If you stop, next play starts from beginning

---

## Keyboard Shortcuts

### Essential Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Play / Pause |
| `⌘.` | Stop |
| `⌘→` | Next Track |
| `⌘←` | Previous Track |
| `→` | Seek Forward 5 seconds |
| `←` | Seek Backward 5 seconds |
| `⌘R` | Cycle Repeat Mode (Off → All → One) |
| `⌘O` | Add Files to Playlist |

### Playlist Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘A` | Select All Tracks |
| `Delete` | Remove Selected Track(s) |
| `↑` / `↓` | Navigate Playlist |
| `Enter` | Play Selected Track |

### Window Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘W` | Toggle Waveform Display |
| `⌘I` | Toggle Now Playing Panel |
| `⌘1` | Minimal View Preset |
| `⌘2` | Standard View Preset |
| `⌘3` | Full View Preset |
| `⌘,` | Open Settings |
| `⌘Q` | Quit HarmoniaPlayer |

---

## Playlist Management

### Reorder Tracks

1. Click and hold on a track
2. Drag to new position
3. Drop to move

### Remove Tracks

**Method 1: Delete Key**
1. Select track(s)
2. Press `Delete` key

**Method 2: Context Menu**
1. Right-click on track
2. Select **"Remove from Playlist"**

### Clear Entire Playlist

1. Select all tracks (`⌘A`)
2. Press `Delete`

### Current Limitations (v0.1)

- ❌ Cannot save playlists
- ❌ Cannot create multiple playlists
- ❌ Cannot edit track metadata

*These features are planned for future versions.*

---

## Troubleshooting

### "File not found" Error

**Cause:** File was moved or deleted after being added to playlist

**Solution:**
1. Remove the track from playlist
2. Re-add the file from its new location

### "Format not supported" Error

**Cause:** Audio file format is not supported by current version

**Solutions:**
- **Free version:** Only supports MP3, AAC, ALAC, WAV, AIFF
- **For FLAC/DSD:** Upgrade to Pro version (v0.2+)
- **Alternative:** Convert file to supported format using:
  - iTunes / Music app (for AAC/ALAC)
  - Online converters (for MP3)

### No Sound

**Check these:**

1. **System volume not muted**
   - Check volume in menu bar
   - Press `F12` to increase volume

2. **Correct output device selected**
   - Open **System Settings** → **Sound**
   - Check **Output** tab
   - Select correct speakers/headphones

3. **HarmoniaPlayer not paused**
   - Check playback state in app
   - Click Play button

4. **Audio file not corrupted**
   - Try playing a different file
   - Try opening file in another app

### Playback Stuttering

**Possible causes:**

1. **High CPU usage**
   - Open **Activity Monitor**
   - Check if CPU is overloaded
   - Close other applications

2. **Very high sample rate files**
   - 192kHz files may stutter on older Macs
   - Try 44.1kHz or 48kHz files instead

3. **External drive slow**
   - If playing from external USB drive
   - Try copying file to internal drive

### App Won't Open (macOS Security)

**If you see:** _"HarmoniaPlayer cannot be opened because it is from an unidentified developer"_

**Solution:**
1. Open **System Settings**
2. Go to **Privacy & Security**
3. Scroll to **Security** section
4. Click **"Open Anyway"** next to HarmoniaPlayer message
5. Click **"Open"** in confirmation dialog

### Playlist Empty After Restarting App

**Current behavior (v0.1):**
- Playlists are **not** saved when you quit
- This is expected in v0.1

**Workaround:**
- Keep app running (minimize instead of quit)

**Future:**
- Playlist persistence coming in v0.3

---

## FAQ

### General Questions

**Q: Is HarmoniaPlayer free?**  
**A:** Yes, the Free version is completely free and open source (MIT License).

**Q: What's the difference between Free and Pro?**  
**A:**
- **Free:** MP3, AAC, ALAC, WAV, AIFF
- **Pro (v0.2+):** All Free formats + FLAC + DSD

**Q: How do I upgrade to Pro?**  
**A:** Pro version will be available via in-app purchase in v0.2 (Q1 2026).

**Q: Is my music uploaded anywhere?**  
**A:** No. HarmoniaPlayer is **completely offline**. All music stays on your Mac.

### Features

**Q: Can I edit metadata (tags)?**  
**A:** Not in v0.1. Metadata editing is planned for v0.2 (Pro).

**Q: Can I see album art?**  
**A:** Not in v0.1. Album art display is planned for v0.2.

**Q: Does it support repeat / loop playback?**  
**A:** Yes. Use the Repeat button or `⌘R` to cycle through Off, Repeat All, and Repeat One modes.

**Q: Does it support gapless playback?**  
**A:** Not yet. Gapless playback is planned for a future version.

**Q: Can I create multiple playlists?**  
**A:** Not in v0.1. Multiple playlists are planned for v0.3.

**Q: Can I save my playlists?**  
**A:** Not in v0.1. Playlist persistence is planned for v0.3.

### Platform Support

**Q: Is there an iOS version?**  
**A:** Not yet. iOS support is planned for v0.3 (Q2 2026).

**Q: Does it work on Windows or Linux?**  
**A:** No. HarmoniaPlayer is macOS/iOS only. However, the underlying framework (HarmoniaCore) will support Linux in the future.

**Q: What macOS version do I need?**  
**A:** macOS 13.0 (Ventura) or later.

### Technical

**Q: Where does HarmoniaPlayer store its data?**  
**A:** Currently, no data is stored (v0.1 has no persistence).

**Q: Can I use this with my DAW?**  
**A:** HarmoniaPlayer is designed as a music player, not a production tool. Use your DAW's built-in players for production.

**Q: Does it support streaming services?**  
**A:** No. HarmoniaPlayer only plays local files.

---

## Getting Help

### Report a Bug

1. Visit [GitHub Issues](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/issues)
2. Click **"New Issue"**
3. Describe the problem:
   - What you did
   - What happened
   - What you expected
   - macOS version
   - HarmoniaPlayer version

### Request a Feature

1. Visit [GitHub Discussions](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/discussions)
2. Click **"New Discussion"**
3. Category: **Ideas**
4. Describe your feature request

### Additional Resources

- **Documentation**: [GitHub Docs](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/tree/main/docs)
- **Architecture**: [architecture.md](architecture.md)
- **Development**: [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md)

---

## What's Next?

For development plans and upcoming features, see the [Project Roadmap](../README.md#milestones-non-binding).

---

## 📧 Need Help?

For questions, bug reports, or feature requests:

- **Email**: [harmonia.audio.project@gmail.com](mailto:harmonia.audio.project@gmail.com)
- **GitHub Issues**: [HarmoniaPlayer Issues](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/issues)
- **Documentation**: [GitHub Docs](https://github.com/OneOfWolvesBilly/HarmoniaPlayer/tree/main/docs)