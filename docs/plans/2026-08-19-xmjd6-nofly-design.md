# XMJD6 No-Fly Windows Bundle Design

## Goal

Create a standalone `xmjd6-nofly/` distribution directory for Windows Weasel
users. The bundle must preserve the current XMJD6 dictionaries, features, code
shortening, shape codes, comments, weights, and candidate order while removing
the fly-key split:

- `ch` always uses `J` in an initial position.
- `zh` always uses `Q` in an initial position.
- `uang` always uses `X` in a final position.

The existing Rime user directory remains untouched. The bundle is not designed
to coexist with the current schema, so its internal resource names remain the
original `xmjd6` names.

## Packaging

The generated directory is a complete, source-only Windows distribution:

```text
xmjd6-nofly/
├── README.md
├── default.yaml
├── default.custom.yaml
├── weasel.custom.yaml
├── xmjd6.schema.yaml
├── xmjd6.extended.dict.yaml
├── converted dictionaries
├── shared reverse-lookup dictionaries and schemas
├── lua/xmjd6/
├── opencc/
├── symbols.yaml
├── conversion-report.txt
└── verify_windows.cmd
```

macOS `build/` artifacts are excluded. Windows users must redeploy with Weasel.
Windows defaults are taken from `default_win.yaml` and
`default.custom_win.yaml`.

## Conversion Architecture

A deterministic Python builder scans the dictionaries imported by
`xmjd6.extended.dict.yaml`, classifies their encoding format, and writes a
converted snapshot into `xmjd6-nofly/`.

Only phonetic positions are changed. The builder must never globally replace
letters because the same letters can be native initials, finals, shape codes,
or custom shortcut codes.

The standard code structures are:

- Single character: initial, final, then zero or more shape codes.
- Two-character phrase: two sound codes, then shape codes.
- Three-character phrase: three initials, then shape codes.
- Four-or-more-character phrase: the first three initials and the final
  character initial, then shape codes.
- WXW/630 phrase: first-character initial followed by the second character's
  shape code.

Sound dictionaries are converted structurally. Symbols, links, English data,
and explicitly user-defined shortcut codes are copied unchanged.

Pronunciation context, the original code, and word length are combined to
distinguish fly-key initials from ordinary `j`, `w`, `f`, and `q` initials. For
example, both historical `春 jwv` and `春 wwv` normalize to `jwv`, while
native `均 jw` remains unchanged.

When multiple historical fly-key entries collapse to the same text and code,
only the first entry is retained. Different texts that converge on the same
code remain separate candidates in their existing relative order.

## Ambiguity Handling

The builder must not silently guess unresolved standard entries. It uses:

1. The existing code structure.
2. Source pinyin comments where available.
3. Contextual pinyin readings for phrases.
4. A small explicit override table for genuine ambiguous exceptions.

Unresolved standard entries are written to `conversion-report.txt` and cause
the build to fail until an override is supplied. Non-phonetic custom tables are
reported as copied rather than transformed.

## Windows Priorities

- Keep original schema and dictionary identifiers for maximum Lua and Weasel
  compatibility.
- Use Windows-specific default behavior and include `weasel.custom.yaml`.
- Use UTF-8 text and a Windows `.cmd` verification helper.
- Avoid symlinks, shell scripts, absolute macOS paths, and precompiled macOS
  artifacts.
- The current task only produces the directory; it does not install it into the
  active Rime user data directory.

## Verification

Automated tests cover representative conversions and non-conversions:

- `超`: `wz`/`wzvo` to `jz`/`jzvo`.
- `春`: `wwv` to `jwv`.
- `穿`: `wt...` to `jt...`.
- `找`: `fz` and `qz` collapse to `qz`.
- `中`: `fy` to `qy`.
- `装`: `fm` and `fx` collapse to `qx`.
- `光`: `gm` and `gx` collapse to `gx`.
- `均 jw`, `无 wj`, `求 qq`, and `服 fj` remain unchanged.

Bundle-level checks verify that:

- Every imported table exists.
- YAML resource names and imports are valid.
- Standard entries contain no remaining fly-key alternatives.
- Shape-code suffixes, comments, weights, and candidate order are preserved.
- Duplicate text/code rows created by conversion are removed.
- The standalone directory compiles with `rime_deployer` in a temporary
  staging directory.
- Existing project files outside the generated directory, builder, tests, and
  documentation are not modified.
