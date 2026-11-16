<p align="center"><img src="assets/icon-1024.png" width="160" alt="SimplePlug"></p>

# SimplePlug

*No pads, no helmets… just plugs.*

A minimal host for **a single AU plugin** (effect) with **2 inputs / 2 outputs**, for macOS.
The only settings: audio interface, buffer size and sample rate.

> **Windows**: see [windows/README.md](windows/README.md) (hosts a VST3 plugin; zip in the *Releases*).

## Install

### 1. Prerequisites

Apple's Command Line Tools (no need to install Xcode):

```bash
xcode-select --install
```

### 2. Get the project

```bash
git clone https://github.com/FLORIANSV35/SimplePlug.git
cd SimplePlug
```

### 3. Build

```bash
chmod +x build.sh version.sh   # make the scripts executable (once)
./build.sh
```

The script builds the app and ad-hoc signs it. Result: `build/SimplePlug.app`.

### 4. Run

```bash
open build/SimplePlug.app
```

On first launch macOS asks for **microphone** access: accept, it's what gives access to the audio
interface's inputs. If you refused by mistake:
System Settings › Privacy & Security › Microphone.

To keep it with your applications:

```bash
cp -R build/SimplePlug.app /Applications/
```

> If macOS blocks the app ("unidentified developer") after you copied or downloaded it:
> `xattr -dr com.apple.quarantine /Applications/SimplePlug.app`

## Usage

1. Pick your **audio interface** (at least 2 in / 2 out; channels 1-2 are used).
2. Set the **buffer** and **sample rate** (the approximate round-trip latency is shown).
   The **Buffer load** gauge shows compute time relative to the duration of one buffer:
   average, recent peak, and the number of **overruns** (above 100 %, the audio crackles).
   If it gets too high, increase the buffer.
3. Pick the **AU plugin**: its interface appears in the window.

All settings, including the plugin's state, are remembered.

## Versions

Versions follow `V<YY>.<MM>.<XX>`: year, month, and the number of commits made during that month
(resets every month), e.g. `V26.11.12`. They are computed from the git history by
[`version.sh`](version.sh) and stamped into the app by `build.sh` (visible in *SimplePlug › About*).

## Releasing

```bash
git push            # the commit to release must be on origin/main
./release.sh        # checks, builds, tags V<YY.MM.XX>, publishes, attaches the macOS and Windows zips
./release.sh --help # options: -n notes.md, -y, --dry-run, --no-windows
```

Every release needs its own commit, since the version is the number of commits made that month.

## Updates

SimplePlug checks the latest GitHub release at launch (at most once a day) and offers to install
it: download, verification, replacement and relaunch are automatic.
You can also do it by hand: **SimplePlug › Check for Updates…**

- The check contacts `api.github.com` (one request, no personal data).
- The app must be in a folder you can write to (e.g. `/Applications`).
- Since the app isn't notarized, macOS may ask for microphone access again after an update.
- Version 1.0.0 has no updater: install a newer release by hand once.

## Limitations

- AU effects only (no instruments).
- A single interface for input and output.
- Built for the machine's architecture (arm64 or x86_64): a plugin of another
  architecture won't load.
