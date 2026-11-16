<p align="center"><img src="../assets/icon-windows.png" width="128" alt="SimplePlug"></p>

# SimplePlug for Windows

A minimal host for **a single VST3 plugin** (effect) with **2 inputs / 2 outputs**.
Same idea as the macOS version (which hosts an AU plugin: Audio Units don't exist on Windows,
the equivalent is **VST3**).

Settings: audio interface, sample rate and buffer size. A **Buffer load** gauge shows compute
time relative to the duration of one buffer (above 100 %, the audio crackles: increase the buffer).

> **Experimental**: built automatically by GitHub Actions, developed and code-tested on macOS.
> Feedback from real Windows audio interfaces is welcome.

## Install

1. Download `SimplePlug-V<version>-windows-x64.zip` (the *Releases* page, or the artifact of the
   latest build in the *Actions* tab) and unzip it wherever you like.
2. Run `SimplePlug.exe`. The program isn't signed, so SmartScreen may show
   "Windows protected your PC": click **More info › Run anyway**.
3. Nothing to install, no prerequisites (the C++ runtime is included).

## Usage

- **Audio device type**: pick **ASIO** if your interface has an ASIO driver (lowest latency).
  Otherwise *Windows Audio* (WASAPI) or DirectSound. The "Control Panel" button opens the ASIO driver's own panel.
- **Input / Output**, **Sample rate**, **Audio buffer size**: directly adjustable. Only 2 channels
  (one stereo pair) are used for input and output.
- **VST3 plugin**: the list comes from scanning `C:\Program Files\Common Files\VST3`
  (and the user folder). Use **Rescan** after installing a plugin.
  If a plugin crashes the scan, it is skipped at the next launch.
- Settings and plugin state are remembered (`%APPDATA%\SimplePlug`).
- **Updates**: the app checks the latest GitHub release (at most once a day) and offers to open the
  download. There is no automatic install on Windows.

## Versions

`V<YY>.<MM>.<XX>`: year, month, number of commits made that month (resets every month).
Computed by [`version.sh`](../version.sh); the CI passes it to CMake.

## Build it yourself

Prerequisites: Visual Studio 2022 ("Desktop development with C++" workload), CMake ≥ 3.22, Git.

```powershell
cmake -S windows -B build -A x64 -DSIMPLEPLUG_VERSION=26.11.12   # version is optional (defaults to 0.0.0)
cmake --build build --config Release
# → build\SimplePlug_artefacts\Release\SimplePlug.exe
```

JUCE 9.0.5 is downloaded automatically by CMake.

## License

This version uses the [JUCE](https://juce.com) framework under the **AGPLv3** license
(with its bundled ASIO headers); its source code is therefore distributed under the **GNU AGPL v3**,
see the `LICENSE` file. The macOS version (the `Sources/` folder) is independent.
