---
title: Updates
description: How GearMac finds, verifies and installs new versions.
---

GearMac keeps itself up to date, and there's nothing to set up.

## How it works

1. **Once a day**, GearMac checks GitHub for a newer release on its channel. If a check fails, it
   tries again two hours later. The first check runs 30 seconds after launch, so it doesn't slow
   down login.
2. When there's a new release, a window shows **what changed**, taken from the release notes.
3. One click downloads it, with a progress bar and a **Cancel** button that stops the download.
4. GearMac verifies the download, installs it and offers to **relaunch**.

If you choose **Later**, GearMac stops offering that version. It still offers newer ones.

**Check for Updates** always looks for a newer version, including one you skipped. It's in the
launcher, the GearMac menu bar menu and **Settings → About**.

## It waits until you're not busy

The update window never interrupts you. It waits while the palette is open, a snippet is expanding,
an extension command is running, the uninstaller is working, you're recording a shortcut, or a
dialog is open. It tries again every two minutes for half an hour, then goes back to checking once a
day.

Each version is offered at most once per launch.

## Channels stay separate

The stable version only updates to stable releases, and the beta only to beta releases. They're
separate apps, and an update never switches you from one to the other.

On an Intel Mac, GearMac only installs the universal build. If a release doesn't include one,
GearMac doesn't offer it, so it never installs a build that won't open.

## Safety checks

Nothing is installed unless every check passes. If any check fails, the app you're running stays
exactly as it was.

- **The signature must show that the download is GearMac**, signed the same way as the copy you're
  running.
- The app identifier and version must match what's expected.
- GearMac never runs `xattr` or asks for an administrator password. If it can't write to
  `/Applications`, it tells you instead of working around it.

Updating never changes your settings, clipboard history, notes, snippets or anything else you
created.

## Homebrew

GearMac's Homebrew casks tell Homebrew that the app updates itself, so `brew upgrade`
**skips GearMac**. It never reports GearMac as outdated, never downloads it again, and never rolls
back a copy that updated itself.

`brew install`, `brew uninstall` and `brew list` work as usual.

## Supporting GearMac

GearMac is free and open source. **Support GearMac**, in the launcher, the menu bar and
**Settings → About**, opens a small window with a link to support the project.

About once a month, this window may open by itself, but never on the day you install GearMac and
never while you're busy. To stop it, clear the reminder checkbox in the window.
