# Publishing Alloy on a website

A public release has three parts:

| Part | What it is | Size | Built with |
|---|---|---|---|
| `Alloy-<version>.pkg` | The installer. **This is the download link for your site.** It checks the Mac, installs the app and Rosetta 2, then Alloy downloads everything else with one click. | about 2.5 MB | `scripts/release.sh` |
| `Alloy-<version>.dmg` | The same app as a disk image, for people who prefer to drag it to Applications. | about 3 MB | `scripts/release.sh` |
| `alloy-<id>.tar.xz` + `components.json` | The game engine (Wine with DXMT, GStreamer video, GnuTLS, MoltenVK). The app downloads it from **Setup → Game engine → Install**. | about 300 MB download, 1.5 GB installed | `scripts/package-runtime.sh` |
| Source code | This repository, including `patches/wine`, plus the open-source parts of CrossOver the engine was built from | | git |

The app and the engine are separate downloads on purpose. The app stays small, the engine can be updated without a new app,
and each engine package is checked against the SHA-256 in `components.json` before it is unpacked.

## Before the first release

These are decisions only you can make. Alloy does not make them for you.

1. **Choose a licence for Alloy's own code** and add a `LICENSE` file. MIT, Apache-2.0 and GPL-3.0 are common choices.
   Alloy starts Wine as a separate program and links none of it, so any of these works. See [DEPENDENCIES.md](DEPENDENCIES.md).
2. **Get an Apple Developer ID** (Apple Developer Program, USD 99 per year). Without one, macOS on other Macs refuses to
   open the app ("Apple could not verify…"). Do not tell people to turn off Gatekeeper.
   - In Xcode → Settings → Accounts, or at developer.apple.com, create two certificates: **Developer ID Application**
     (signs the app and the disk image) and **Developer ID Installer** (signs the `.pkg`).
   - Store notarisation credentials once:
     `xcrun notarytool store-credentials alloy --apple-id <you@example.com> --team-id <TEAMID>`
     (it asks for an app-specific password from appleid.apple.com).
3. **Pick a bundle ID** you control, for example `com.yourname.alloy`. The default `local.alloy.Alloy` is a placeholder.
4. **Have the terms of use reviewed.** [TERMS.md](TERMS.md) is a plain-language starting point, not legal advice. Ask a
   lawyer to check it for the countries you publish in, then edit `Sources/AlloyCore/Guides/Guides.swift` (the app
   shows that text) and run `alloyctl write-docs docs` to update the copy for your website. Raise `Terms.version`
   whenever the meaning changes: everyone is asked to accept again.
5. **Pick where the files live.** GitHub Releases works well: files up to 2 GB each, free, and it serves HTTPS.
   Alloy only downloads from HTTPS addresses (and from `127.0.0.1` for testing).
6. **Check the name.** "Metal" is an Apple trademark, and Apple's
   [guidelines for third parties](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) ask that
   Apple marks not be used as part of a product name. Decide whether to keep "Alloy" before the website, domain and
   bundle ID are fixed; renaming later costs more.
7. **Publish from a clean repository.** Start the public repository from a fresh commit (or squash the history) so it
   carries the author name and email you choose, and leave out internal notes such as `docs/ASSESSMENT.md`.
   Run `git log --format='%an <%ae>' | sort -u` on the public repository to check.

## 1. Build the game engine without your user name in it

Build folders end up inside binaries (debug info, `__FILE__`). The current engine on this Mac was built in folders under
your home folder, so about 1,500 of its files contain your macOS user name. People who download it can read that.

Build everything in a neutral folder (`/tmp/alloy-build`), with a separate data folder so your own Alloy library is
untouched. Needs mingw-w64, bison, autoconf, automake and libtool from Homebrew; about 30 minutes on an M4.

```bash
# 1. Base Wine from CrossOver's sources, with patches/wine. MoltenVK (Apache-2.0) comes from an existing build.
scripts/build-wine.sh <crossover-sources-26.3.0.tar.gz> "/Applications/Wine Devel.app/Contents/Resources/wine/lib/libMoltenVK.dylib"

# 2. Turn it into an Alloy engine with DXMT, in a throwaway data folder.
export ALLOY_DATA_DIR=/tmp/alloy-build/data
alloyctl import-wine /tmp/alloy-build/install "Alloy Wine 11.0 (CrossOver 26.3 sources)"
alloyctl import-dxmt <dxmt-v0.80 folder> /private/tmp/alloy-build/data/Runtimes/<wine-runtime>/wine/bin/wine \
  "https://github.com/3Shain/dxmt/releases/tag/v0.80 sha256 <sha>"

# 3. GnuTLS, GStreamer and the rebuilt Wine modules.
ALLOY_WINE_WORK=/tmp/alloy-build/patch scripts/patch-wine-runtime.sh <crossover-sources-26.3.0.tar.gz> \
  /tmp/alloy-build/data/Runtimes/<dxmt-runtime>
```

`package-runtime.sh` warns when it still finds your user name; publish only when it reports none.

## 2. Package the engine

The package must carry the licence texts of everything in it. DXMT's release download has none, so its MIT `LICENSE`
is kept in this repository as `licenses-extra/dxmt/LICENSE`. Then:

```bash
ALLOY_SOURCES_TARBALL=<crossover-sources-26.3.0.tar.gz> \
ALLOY_WINE_WORK=/tmp/alloy-build/patch \
ALLOY_EXTRA_LICENSES=licenses-extra \
scripts/package-runtime.sh /tmp/alloy-build/data/Runtimes/<dxmt-runtime> release/ \
  dxmt-0.80-cx26.3-1 "Alloy Game Engine (DXMT 0.80)" 0.80
```

This writes `release/alloy-dxmt-0.80-cx26.3-1.tar.xz` and adds it to `release/components.json`, newest first. The app
offers the first entry. The package gets a `licenses/` folder (Wine, GStreamer, GLib, GnuTLS, GMP, nettle, MoltenVK, FreeType,
vkd3d, libffi, pcre2, proxy-libintl, DXMT) and leaves out headers, static libraries, backups and the build machine's folder
names from `alloy-runtime.json`. The script names any licence it could not find; publish only when it names none.

Package IDs must stay unique: Alloy records which ID it installed and offers **Install Update** when the first entry's ID
is one it does not have.

### Test it before uploading

```bash
cd release && python3 -m http.server 8765 --bind 127.0.0.1
```

In Alloy, open **Advanced → Settings → Downloads**, enter `http://127.0.0.1:8765/components.json`, then use
**Setup → Game engine → Install**. Clear the field afterwards.

## 3. Upload

Alloy reads a fixed address, `https://flake.co.in/alloy/components.json` (built into the app by `build-app.sh`), so
the engine can move or be updated without a new app. The engine itself is too big for Cloudflare's 25 MiB file limit,
so it lives elsewhere:

1. Upload everything in `release/` (the `.tar.xz`, `SOURCES.md`, the sources archive and the CrossOver source
   tarball) to one public folder, for example a GitHub release with the tag `engine-0.80`.
2. Copy `release/components.json` to `flake-site/engine/components.json`.
3. In `flake-site/build.py`, set `ENGINE_BASE_URL` to that folder's address, for example
   `https://github.com/<owner>/<repo>/releases/download/engine-0.80`, run `python3 build.py` and upload `public/`.

Until `ENGINE_BASE_URL` is set, no `components.json` is published and Alloy says the engine isn't available yet.

## 4. Build the installer and the app

```bash
ALLOY_VERSION=1.0 \
ALLOY_STAGE=Beta \
ALLOY_BUNDLE_ID=com.yourname.alloy \
ALLOY_COMPONENTS_URL=https://github.com/<owner>/<repo>/releases/latest/download/components.json \
ALLOY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ALLOY_INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
ALLOY_NOTARY_PROFILE=alloy \
scripts/release.sh
```

`release.sh` builds a release app and signs it with the hardened runtime. It then makes `build/Alloy-1.0.0.pkg`
(with `scripts/make-installer.sh`) and `build/Alloy-1.0.0.dmg`. It sends both to Apple for notarisation, staples
the tickets, checks them with `spctl` and prints their SHA-256 for your download page.

Without the identities you get unsigned files that only open on your own Mac.

### What the installer does

| Step | Where | What happens |
|---|---|---|
| Mac check | Installer | Refuses Intel Macs and macOS before 14 (Installer's own checks, so no "this package will run a program" warning) |
| Welcome | Installer | What will be installed, and that Alloy is not affiliated with CodeWeavers, Apple, Microsoft or Valve |
| Licence | Installer | The [terms of use](TERMS.md). A note at the top says that agreeing also installs Rosetta 2 and accepts Apple's licence for it |
| App | Installer | `Alloy.app` in `/Applications`, even if another copy exists elsewhere (Installer asks for an administrator password, as for any app in /Applications) |
| Rosetta 2 | `postinstall` | Installed with `softwareupdate --install-rosetta --agree-to-license` if missing; a failure (for example offline) does not fail the install |
| Terms | `postinstall` | Writes the accepted terms version to `/Library/Application Support/Alloy/AcceptedTerms`, so the app doesn't ask again |
| Open | `postinstall` | Opens Alloy for the person at the screen (not for command-line or managed installs) |
| Engine and components | Alloy | The setup wizard opens at its Install page, checks free space, then **Install Everything** downloads the game engine and the Visual C++ and Wine Mono installers, each checked against its checksum |

The wizard's Install page runs the same `SetupRunner` that `alloyctl setup <components.json URL>` runs, so you can check a
release from Terminal. The installer's pages come from `alloyctl installer-pages`, which uses the same text as the app.

Test the package before publishing: `installer -pkginfo -pkg build/Alloy-1.0.0.pkg` and
`pkgutil --expand build/Alloy-1.0.0.pkg /tmp/pkg-check` show what is inside. To try the whole flow, run the `.pkg` on a
spare Mac or a new macOS user account. `ALLOY_DRY_RUN=1 sh scripts/installer/postinstall x / / /` prints what the
script would do, without root.

## 5. The download page

State plainly:

- **Requirements:** a Mac with Apple silicon (M1 or later), macOS 14 or later, about 2 GB free. Alloy installs Rosetta 2
  from Setup if needed (the engine is an x86_64 build).
- **What works:** list only games you have actually tested ([COMPATIBILITY.md](COMPATIBILITY.md)). Do not promise that
  every Windows game runs. Anti-cheat games (Easy Anti-Cheat, BattlEye, Vanguard) generally do not.
- **DirectX 12:** needs Apple's D3DMetal, which people add themselves from Apple's Game Porting Toolkit. Never host D3DMetal.
- **Not affiliated:** Alloy is not made by or affiliated with CodeWeavers, Apple, Microsoft or Valve. Do not use
  CrossOver's name or logo for the app or its marketing.
- **Source and licences:** link to the repository and to the source offer below.
- **Download button** pointing at the `.pkg`, with the `.dmg` as a second link.
- **SHA-256** of both files.
- **Terms and guide:** link to (or copy) [TERMS.md](TERMS.md) and [GRAPHICS-GUIDE.md](GRAPHICS-GUIDE.md).

## Licences you must follow when you publish the engine

The engine package contains LGPL software, so offering it for download has conditions. See [DEPENDENCIES.md](DEPENDENCIES.md)
for the full table.

- **Wine, GStreamer, GLib, GnuTLS, proxy-libintl (LGPL-2.1+), nettle and GMP (LGPL-3+ / GPL-2+):** the licence texts
  are in the package's `licenses/` folder. Also publish the exact source you built from, next to the package or with a
  written offer: `crossover-sources-26.3.0.tar.gz` (from CodeWeavers' source page), the `patches/wine` folder from this
  repository, and the build scripts.
- **DXMT (MIT), libffi (MIT), pcre2 (BSD), FreeType (FreeType licence), vkd3d (LGPL):** their notices are in `licenses/`.
- **MoltenVK (Apache-2.0):** its licence is in `licenses/`.
- **Visual C++ runtime and Wine Mono** are not in the package. Alloy downloads them per game from Microsoft and WineHQ
  and checks their checksums.
- **D3DMetal** is never in the package (Apple's licence does not allow redistribution).

A simple way to meet the source requirement is a `SOURCES.md` in each engine release with links to the exact tarballs and
a commit of this repository.

## Checklist

- [x] `LICENSE` added (GPL-3.0)
- [ ] Name decided (see "Check the name"); bundle ID set with `ALLOY_BUNDLE_ID`
- [ ] Public repository starts from a clean history without internal notes
- [ ] Terms of use reviewed; `docs/TERMS.md` regenerated with `alloyctl write-docs docs`
- [ ] Engine rebuilt in a neutral folder; `package-runtime.sh` printed no user name or licence warning
- [ ] Engine tested from `127.0.0.1` on a Mac (or a new macOS user account) without Alloy installed
- [ ] `components.json` and the engine uploaded; the fixed address opens in a browser
- [ ] Installer and app built with `release.sh`; notarisation succeeded for both and `spctl` says "accepted"
- [ ] The `.pkg` installed on a spare Mac or new user account: Alloy opened, **Install Everything** finished
- [ ] Download page lists requirements, tested games, licences, source links and the SHA-256
