# Smart Audio & Subtitle Track Selection (SAST) for mpv

An intelligent **mpv** script that automatically selects the best audio track and matching Russian subtitles based on language tags, title keywords, channel count, and codec quality. It also loads external subtitle files when available.

**Ideal for users who prefer original-language audio with Russian subtitles.**  
The logic is optimized for this use case, but can easily be adapted for any other language/region.

## What the script does

On file load (and when tracks change), the script:

1. Scans all audio and subtitle tracks.
2. Selects the **best audio track** according to a smart priority system that depends on whether full Russian subtitles are present.
3. Selects matching **Russian subtitles**:
   - Full Russian subtitles when the audio is *not* Russian.
   - Forced / signs-only Russian subtitles when the audio *is* Russian.
4. Automatically loads external subtitles (`.ass`, `.ssa`, `.srt`, `.vtt`) that have the same name as the video file (if they exist next to it).
5. Keeps subtitles in sync when you manually change the audio track.

### Audio selection priority

**When full Russian subtitles are available:**
1. Original language audio (non-Russian / non-English, non-commentary)
2. Other non-Russian / non-English tracks
3. English audio

**When full Russian subtitles are NOT available:**
1. Russian audio
2. Original language audio
3. English audio
4. Any other non-commentary track

Within the selected group the script prefers:
- Higher channel count
- Better codec (TrueHD → DTS-HD MA → DTS-HD → PCM/FLAC → E-AC-3 → DTS → AC-3 → Opus → AAC → MP3)

Commentary and audio-description tracks are always skipped.

### Subtitle selection logic

- If **external** subtitles are present → they are preferred.
- If current audio is **Russian** → forced / signs Russian subtitles are selected.
- If current audio is **not Russian** → full Russian subtitles are selected.
- If nothing suitable is found → subtitles are disabled.

## How it works

- Uses `track-list` to build internal caches of audio and subtitle tracks.
- Detects languages and special track types via strict language code matching (`ru`, `rus`, `en`, `eng`) and extensive keyword lists in track titles (supports both English and Russian keywords).
- Built-in debouncing mechanism on `file-loaded` and `tracks-changed` events prevents race conditions and event spam.
- Observes the `aid` property so that changing audio manually also updates subtitles.

## Installation

1. Copy `sast.lua` into your mpv scripts directory:
   - Linux / macOS: `~/.config/mpv/scripts/`
   - Windows: `%APPDATA%\mpv\scripts\`
2. Restart mpv or open a new file.

No configuration file is required.

## What you can easily customize

### 1. Keyword lists (most important)

All detection is driven by these tables at the top of the file:

- `COMMENTARY_KEYWORDS` — tracks to skip (commentary, director’s comments, audio description…)
- `FORCED_EXCLUDE_KEYWORDS` — words that mark a track as forced/signs (used to *exclude* them from full-subtitle detection)
- `RUSSIAN_FULL_KEYWORDS` — words that identify full Russian subtitles
- `RUSSIAN_FORCED_KEYWORDS` — words that identify forced / signs Russian subtitles

You can freely add or remove entries (both English and local-language variants are already included).

### 2. Code priority

```lua
local CODEC_PRIORITY = {
	["truehd"] = 8,
	["dts-hd ma"] = 7,
	-- ...
}
```

Change the numbers or add new codecs to adjust preference order.

### 3. Audio selection priorities

Look for the `priorities` table inside `choose_best_audio_track()`.  
You can reorder, add, or remove the predicate functions to suit your preferences.

### 4. Language detection helpers

Functions such as:
- `is_russian_audio()`
- `is_english_audio()`
- `is_original_audio()`
- `is_full_russian_sub()`
- `is_forced_russian_sub()`

can be modified if you want to support additional languages or different detection rules (uses exact matching for language tags like `ru`, `rus`, `en`, `eng`).

### 5. External subtitle extensions

In `get_external_sub_path()`:

```lua
for _, ext in ipairs({ ".ass", ".ssa", ".srt", ".vtt" }) do
```

Add or remove extensions as needed.

### 6. Timing and debouncing

A short debouncing delay (`0.1` s via `track_update_timer`) is used on `file-loaded` and `tracks-changed` to prevent event spamming and allow mpv to finish probing tracks. You can adjust this value in the script if you experience issues on slower systems or network drives.

## Adapting for other languages / regions

The script is currently tuned for **Russian subtitles + original audio**.  
To adapt it for another language (e.g. Spanish, French, Japanese…):

1. Replace all Russian-related keyword lists with equivalents for your language.
2. Update the language-matching functions (`is_russian_audio`, `is_full_russian_sub`, etc.) to check for your language codes.
3. Adjust the priority order in `choose_best_audio_track()` if needed.

Because the logic is driven almost entirely by configurable keyword tables and simple language checks, porting to another region is straightforward.

## Requirements

- mpv with Lua support (standard in virtually all builds)
- Tracks that contain proper language tags and/or descriptive titles for best results

## Notes

- If you encounter any bugs, errors, or have ideas on how to improve the script, please let me know! You can open an **Issue** here on GitHub or submit a **Pull Request**. I will gladly find the time to review your feedback and fix any problems.

---

Minimal, dependency-free, and fully automatic — just drop it into your scripts folder and enjoy original audio with properly selected Russian subtitles.

---

## Support

If you find this script useful, you can support my work with a voluntary donation. If you'd like to fuel my coding with a warm cup of coffee, any support is greatly appreciated! ❤️

[![DonationAlerts](https://img.shields.io/badge/Support-DonationAlerts-orange?style=for-the-badge&logo=coffee)](https://www.donationalerts.com/r/zatserkovnyy)
