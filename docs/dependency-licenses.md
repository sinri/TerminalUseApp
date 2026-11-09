# Dependency license review

[文档导航](README.md)

Reviewed on 2026-11-05 against `pubspec.lock`, the resolved local package licenses,
Flutter 3.47.9 SDK notices, `macos/Podfile.lock`, and the bundled Nerd Fonts license.

## Conclusion and scope

The application’s original code is licensed under **GPL-3.0-only**. The resolved
Dart package licenses (MIT, BSD-3-Clause and Apache-2.0) permit inclusion in a
GPLv3 application when their copyright, license and applicable NOTICE requirements
are retained. This does not relicense third-party components.

The three non-SDK direct runtime dependencies are `cupertino_icons` 1.0.9,
`flutter_pty` 0.4.2 and `xterm` 4.0.0, all MIT. `zmodem` 0.0.6 is an MIT
transitive dependency. The PTY native build compiles its own C implementation;
its bundled Dart API headers have BSD-style notices. The macOS Pod lockfile adds
only FlutterMacOS and flutter_pty, not an additional unrelated Pod dependency.

Flutter itself uses BSD-3-Clause. **The Flutter Engine is not MIT as a whole**:
its generated `sky_engine/LICENSE` is a collection of third-party notices,
including BSD/MIT, Apache-2.0, ICU/Unicode, FreeType and other notices. Preserve
the exact engine/platform notices when distributing binaries. The review found
no GPLv3 incompatibility in the inspected dependency notices; it is not an
exhaustive legal assessment of every platform SDK or future binary build.

## Resolved Dart packages

Includes runtime, transitive, development/test and SDK packages; a row is not a
claim that the package ships in every release binary. SDK package license
identification uses the inherited Flutter LICENSE where appropriate.

| Package | Resolved version / SDK | License |
| --- | --- | --- |
| `async` | 2.13.1 | BSD-3-Clause |
| `boolean_selector` | 2.1.2 | BSD-3-Clause |
| `characters` | 1.4.1 | BSD-3-Clause |
| `clock` | 1.1.2 | Apache-2.0 |
| `collection` | 1.19.1 | BSD-3-Clause |
| `convert` | 3.1.2 | BSD-3-Clause |
| `cupertino_icons` | 1.0.9 | MIT |
| `equatable` | 2.1.0 | MIT |
| `fake_async` | 1.3.3 | Apache-2.0 |
| `ffi` | 2.2.0 | BSD-3-Clause |
| `file` | 7.0.1 | BSD-3-Clause |
| `flutter` | Flutter 3.47.9 | BSD-3-Clause |
| `flutter_driver` | Flutter 3.47.9 | BSD-3-Clause |
| `flutter_lints` | 6.0.0 | BSD-3-Clause |
| `flutter_launcher_icons` (icon generation, development only) | 0.14.4 | MIT |
| `flutter_pty` | 0.4.2 | MIT |
| `flutter_test` | Flutter 3.47.9 | BSD-3-Clause |
| `fuchsia_remote_debug_protocol` | Flutter 3.47.9 | BSD-3-Clause |
| `integration_test` | Flutter 3.47.9 | BSD-3-Clause |
| `leak_tracker` | 11.0.2 | BSD-3-Clause |
| `leak_tracker_flutter_testing` | 3.0.10 | BSD-3-Clause |
| `leak_tracker_testing` | 3.0.2 | BSD-3-Clause |
| `lints` | 6.1.0 | BSD-3-Clause |
| `matcher` | 0.12.20 | BSD-3-Clause |
| `material_color_utilities` | 0.13.0 | Apache-2.0 |
| `meta` | 1.19.0 | BSD-3-Clause |
| `path` | 1.9.1 | BSD-3-Clause |
| `platform` | 3.1.6 | BSD-3-Clause |
| `process` | 5.0.6 | BSD-3-Clause |
| `quiver` | 3.2.2 | Apache-2.0 |
| `sky_engine` | Flutter 3.47.9 | Flutter Engine aggregated third-party notices |
| `source_span` | 1.10.2 | BSD-3-Clause |
| `stack_trace` | 1.12.1 | BSD-3-Clause |
| `stream_channel` | 2.1.4 | BSD-3-Clause |
| `string_scanner` | 1.4.1 | BSD-3-Clause |
| `sync_http` | 0.3.1 | BSD-3-Clause |
| `term_glyph` | 1.2.2 | BSD-3-Clause |
| `test_api` | 0.7.12 | BSD-3-Clause |
| `typed_data` | 1.4.0 | BSD-3-Clause |
| `vector_math` | 2.4.4 | BSD-3-Clause |
| `vm_service` | 15.4.0 | BSD-3-Clause |
| `web` | 1.1.1 | BSD-3-Clause |
| `webdriver` | 3.2.0 | Apache-2.0 |
| `xterm` | 4.0.0 | MIT |
| `zmodem` | 0.0.6 | MIT |

## 2026-11-09 inventory correction

The lockfile also contains the following transitive packages, omitted from the
original table. Versions were checked against `pubspec.lock` and license labels
against the resolved local LICENSE texts. This completes the package-name
inventory; it does not mean every development dependency ships in the app.

| Package | Resolved version | License |
| --- | --- | --- |
| `archive` | 4.6.0 | MIT |
| `args` | 2.7.0 | BSD-3-Clause |
| `checked_yaml` | 2.0.4 | BSD-3-Clause |
| `cli_util` | 0.4.2 | BSD-3-Clause |
| `image` | 4.12.0 | MIT |
| `json_annotation` | 4.12.0 | BSD-3-Clause |
| `posix` | 6.5.4 | MIT |
| `yaml` | 3.1.4 | MIT |

## Bundled assets and distribution

- `assets/fonts/SymbolsNerdFontMono-Regular.ttf` remains under its upstream Nerd
  Fonts terms; retain `assets/fonts/NERD-FONTS-LICENSE.txt` and its MIT/OFL notices.
  OFL font bundling is permitted with software, but the font itself must retain
  its font license, attribution and any applicable reserved-name restrictions.
  The application GPL does not replace those terms.
- Material Icons and Cupertino Icons retain their upstream notices. Flutter
  collects package/font licenses for binary distribution; preserve those
  generated notices as well as native engine notices.
- Retain third-party copyright statements, complete license texts and any
  applicable NOTICE files when redistributing their code or binaries.
- When distributing GPL application binaries, provide the corresponding source
  and build materials as required by GPLv3. A root LICENSE alone is not a complete
  binary-release compliance process.
- Recheck this inventory after changing the lockfile, Flutter version, bundled
  assets or platform dependencies. No project copyright ownership determination
  or relicensing of third-party assets is implied by this inventory.

## Primary references

- [GNU license compatibility list](https://www.gnu.org/licenses/license-list.html)
- [Apache 2.0 and GPLv3 compatibility](https://www.apache.org/licenses/GPL-compatibility.html)
- [OFL font bundling guidance](https://openfontlicense.org/how-to-use-ofl-fonts/)
- [Official GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.txt)

The package rows were checked against the locally resolved license files, rather
than inferred solely from package registry labels. No dependency versions were
changed during this review.
