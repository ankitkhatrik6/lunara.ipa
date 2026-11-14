<div align="center">

# Lunara for Android

<img src="logo.png" alt="Lunara logo" width="120" height="120" />

### A free and open source music player for Android

Stream the YouTube Music catalogue, play it through Media3, and follow
time-synced lyrics. No advertisements, no tracking, no account required.

<br />

[![Platform](https://img.shields.io/badge/Platform-Android-27CE65?style=flat-square&logo=android&logoColor=27CE65&labelColor=000000)](#installation)
[![Kotlin](https://img.shields.io/badge/Language-Kotlin-27CE65?style=flat-square&logo=kotlin&logoColor=27CE65&labelColor=000000)](#technology)
[![Jetpack Compose](https://img.shields.io/badge/UI-Jetpack_Compose-27CE65?style=flat-square&logo=jetpackcompose&logoColor=27CE65&labelColor=000000)](#technology)
[![Media3](https://img.shields.io/badge/Audio-Media3-27CE65?style=flat-square&logo=android&logoColor=27CE65&labelColor=000000)](#technology)
[![Gradle](https://img.shields.io/badge/Build-Gradle-27CE65?style=flat-square&logo=gradle&logoColor=27CE65&labelColor=000000)](#building)
[![License](https://img.shields.io/badge/License-GPL--3.0-27CE65?style=flat-square&logo=gnu&logoColor=27CE65&labelColor=000000)](LICENSE)

[![Android Build](https://img.shields.io/badge/CI-Android_Release-27CE65?style=flat-square&logo=githubactions&logoColor=27CE65&labelColor=000000)](https://github.com/ankitkhatrik6/Lunara/actions/workflows/android-release.yml)
[![Releases](https://img.shields.io/badge/Releases-lunara--releases-27CE65?style=flat-square&logo=github&logoColor=27CE65&labelColor=000000)](https://github.com/ankitkhatrik6/lunara-releases/releases)

<br />

[Overview](#overview) &nbsp;|&nbsp; [Features](#features) &nbsp;|&nbsp; [Installation](#installation) &nbsp;|&nbsp; [Architecture](#architecture) &nbsp;|&nbsp; [Building](#building) &nbsp;|&nbsp; [Troubleshooting](#troubleshooting)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Architecture](#architecture)
- [Technology](#technology)
- [Building](#building)
- [Continuous Integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Author](#author)

---

## Overview

Lunara is a free and open source music player for Android. It streams the YouTube Music catalogue through the InnerTube API, plays audio with the AndroidX Media3 engine, and displays time-synced lyrics. There are no advertisements, no tracking, and no account required.

## Features

| Feature | Description |
|---------|-------------|
| **YouTube Music catalogue** | Search, live suggestions, browse, artists, albums, and playlists through the InnerTube `WEB_REMIX` client. |
| **Reliable playback** | The playable audio stream is resolved per track against the InnerTube player endpoint using several public client identities. Playback runs through Media3 with lock screen and notification controls. |
| **Synced lyrics** | Time-synced and plain lyrics with a priority chain of providers: Paxsenix, LRCLIB, Better Lyrics, KuGou, and LyricsPlus. |
| **Queue management** | Play next, add to queue, reorder, remove, and clear. |
| **Mini player and full player** | Scrubbable seek bar, repeat (all, one, off), shuffle, and a sleep timer. |
| **Spotify import** | Paste a public playlist link and Lunara matches the tracks into an offline-ready playlist. |
| **Offline downloads** | Save high-bitrate audio locally for offline playback. |
| **Local device music** | The MediaStore scanner integrates files already on the device. |
| **Local persistence** | Liked songs, playlists, search history, profile, and listening statistics are stored on device with Room. |
| **Personalised home** | Time-based greeting, listening history, trending, popular albums, recommended playlists, and a local Top 20. |

## Installation

Download the latest signed APK from the [Releases](https://github.com/ankitkhatrik6/lunara-releases/releases) page and install it.

> [!NOTE]
> If you previously installed an earlier or unofficial build of Lunara, uninstall it once before installing the latest release. See [Troubleshooting](#troubleshooting) for details.

## Architecture

The project is a multi-module Gradle build. The `app` module contains the application and UI, and the remaining modules provide the data sources it depends on.

| Module | Purpose |
|--------|---------|
| `app` | Application entry point, Compose UI, playback service, database, and downloads. |
| `innertube` | YouTube Music InnerTube client and stream resolution. |
| `lrclib` | LRCLIB lyrics provider. |
| `paxsenix` | Paxsenix lyrics provider. |
| `betterlyrics` | Better Lyrics provider. |
| `kugou` | KuGou lyrics provider. |
| `shazamkit` | ShazamKit integration. |

Supporting directories:

| Directory | Purpose |
|-----------|---------|
| `.github/workflows` | CI workflows for Android and iOS releases. |
| `fastlane/metadata/android` | Store listing metadata. |
| `scripts`, `tools` | Build and maintenance helpers. |
| `site` | Project website. |

## Technology

| Area | Choice |
|------|--------|
| Platform | Android, Kotlin, Jetpack Compose, Material 3 |
| Audio | AndroidX Media3 (ExoPlayer and MediaSession) with an OkHttp data source |
| Extraction | In-app InnerTube client (player endpoint with client rotation) |
| Lyrics | Paxsenix, LRCLIB, Better Lyrics, KuGou, and LyricsPlus |
| Database | AndroidX Room |
| Images | Coil |
| Networking | OkHttp |
| Build | Gradle (Kotlin DSL), multi-module |

## Building

### Requirements

- JDK 17 or newer
- Android SDK

### Build commands

```bash
git clone https://github.com/ankitkhatrik6/Lunara.git
cd Lunara

# Unit tests
./gradlew testDebugUnitTest

# Debug build
./gradlew assembleDebug

# Release build
./gradlew assembleRelease
```

### Build outputs

| Build type | Path |
|------------|------|
| Debug | `app/build/outputs/apk/debug/app-debug.apk` |
| Release | `app/build/outputs/apk/release/app-release.apk` |

## Continuous Integration

| Workflow | Platform | Runner |
|----------|----------|--------|
| [`android-release.yml`](.github/workflows/android-release.yml) | Android APK (debug and release) | GitHub Actions, Ubuntu, Gradle |

Artifacts are available in the GitHub Actions run summary.

## Troubleshooting

<details>
<summary><b>"App not installed" or "package conflict"</b></summary>

<br />

This happens when a build is installed over a previous build that has the same package name but a different signing certificate, or when the version code is not increased. To resolve it:

1. Uninstall the previously installed Lunara build.
2. Install the latest release APK.

Subsequent updates from the same release channel install without conflict.

</details>

<details>
<summary><b>"Play Protect blocked this app because the developer is unknown"</b></summary>

<br />

Play Protect shows this warning for applications that are not distributed through Google Play. When the warning appears, choose to install anyway, or add Lunara to the allowed list in the Play Store settings under Play Protect.

</details>

## License

Lunara is released under the [GNU General Public License v3.0](LICENSE).

Lunara is an independent project. It is not affiliated with, endorsed by, or sponsored by Google LLC, YouTube, or Spotify AB.

## Author

Designed and developed by **Ankit**, a BSc CSIT student and full-stack developer based in Kathmandu, Nepal.

[![GitHub](https://img.shields.io/badge/GitHub-ankitkhatrik6-27CE65?style=flat-square&logo=github&logoColor=27CE65&labelColor=000000)](https://github.com/ankitkhatrik6)
[![Portfolio](https://img.shields.io/badge/Portfolio-ankitkhatri.me-27CE65?style=flat-square&logo=googlechrome&logoColor=27CE65&labelColor=000000)](https://ankitkhatri.me)
[![Instagram](https://img.shields.io/badge/Instagram-21ank1t-27CE65?style=flat-square&logo=instagram&logoColor=27CE65&labelColor=000000)](https://instagram.com/21ank1t)

---

<div align="center">

Built with Kotlin and Jetpack Compose.

</div>
