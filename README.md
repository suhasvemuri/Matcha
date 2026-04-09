<div align="center">
  <img src="Assets/Matcha-Icon.png" width="128" alt="Matcha icon">

  <h1>Matcha</h1>
  <p>Native macOS menu bar scores for cricket and football, with favorites, standings, rich match detail, and where-to-watch discovery.</p>

  <p>
    <a href="https://github.com/suhasvemuri/Matcha/releases"><img src="https://img.shields.io/github/downloads/suhasvemuri/Matcha/total.svg" alt="Downloads"></a>
    <a href="https://github.com/suhasvemuri/Matcha/blob/main/License"><img src="https://img.shields.io/github/license/suhasvemuri/Matcha" alt="License"></a>
    <img src="https://img.shields.io/badge/macOS-26.0%2B-blue.svg" alt="macOS 26+">
    <img src="https://img.shields.io/badge/version-0.9-6f7bf7.svg" alt="Version 0.9">
  </p>
</div>

<br>

<img src="Assets/Matcha-Preview.gif" width="100%" alt="Matcha animated preview"><br/>

## What Matcha Is

Matcha is a macOS menu bar app built around fast score checking without opening a full sports website or a heavy desktop app.

It is designed first for:

- Cricket
- Football / Soccer

It also has secondary coverage for:

- Formula 1
- NFL
- NBA

## What It Does

- Live and upcoming match list for favorited teams and competitions
- Rich cricket scorecards with innings, batters, bowlers, fall of wickets, and match context
- Football match detail and standings support
- Favorites-based feed so the menu stays focused and short
- Search-based discovery for teams and competitions
- “Where to Watch” matching using IPTV M3U + EPG data
- Streamed provider support for inline preview / watch options
- Pinning for selected live scores in the menu bar
- Match detail popovers with overview, scorecard, and standings
- Native macOS settings, menu bar workflow, and launch-at-login support

## Coverage Focus

Matcha is currently tuned around the sports and competitions that matter most in this project:

- ICC tournaments
- IPL
- Premier League
- UEFA competitions
- La Liga
- FIFA competitions

Other sports remain supported in the codebase where available, but the product direction is centered on cricket and football.

## Installation

**Requires macOS 26.0 or later**

### Manual Install

1. Download the latest release from [GitHub Releases](https://github.com/suhasvemuri/Matcha/releases).
2. Move `Matcha.app` to `/Applications`.
3. Launch the app from Applications or Spotlight.

If macOS shows a verification warning on first launch, open:

- `System Settings`
- `Privacy & Security`
- `Open Anyway`

## Current Status

This repository tracks the active `Matcha` build and UI work.

Version `0.9` is the current pre-1.0 milestone:

- core scores UI is working
- favorites and search are working
- IPTV and Streamed watch discovery are wired
- in-app update plumbing is wired

Signed public auto-update releases are still being finished.

## Tech

- SwiftUI
- AppKit
- Sparkle
- DynamicNotchKit
- LaunchAtLogin
- KeyboardShortcuts

## Ownership

Maintained by [suhasvemuri](https://github.com/suhasvemuri).

## License

This project is licensed under the [GPLv3 License](License).
