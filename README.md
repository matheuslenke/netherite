# Netherite

A native macOS note-taking app for folder-based writing vaults.

## Features

- Opens a vault folder that contains notes, folders, git metadata, and `.netherite/config.json`.
- Reads Markdown, plain text, code, CSV/TSV, JSON/YAML/TOML, RTF/HTML/DOCX via text extraction, PDFs with in-app preview plus text extraction, images as metadata text, and binary files as hex previews.
- Provides Original, Preview, and Split modes for Markdown and source text.
- Edits LaTeX project files and renders `.tex` roots to an in-app PDF preview with `latexmk`, including multi-file projects with bibliographies and assets.
- Adapts the editor, preview, and inspector for smaller windows, with a subtle optional workspace tint.
- Includes file search, in-file find count, document stats, backlinks for `[[Wiki Links]]`, save/reveal/open/delete actions, and native macOS shortcuts.
- Integrates git actions for initialize, refresh, pull, commit, push, status, and per-file history/diff.
- Opens Terminal with the vault context for `codex`, `claude`, or a plain shell session.

## Build

```sh
./script/build_and_run.sh --verify
```

## Development

```sh
./script/build_and_run.sh --hot-reload
```

The hot-reload mode watches `Package.swift` and `Sources/`, then rebuilds and relaunches the app when code changes.

## Package

```sh
./script/package_dmg.sh
```

The generated installer image is `dist/Netherite.dmg`.
