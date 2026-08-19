# No-Fly Keyboard Guide Design

## Goal

Add a self-contained Chinese guide for the `feature/xmjd6-nofly` branch and a
matching no-fly keyboard diagram. The guide must make the W/J/X/M distinctions
easy to remember and record exactly what changed when the original fly-key
scheme was converted.

## Audience and Language

The primary audience is a Windows Weasel user who may also inspect or switch
Git branches. The user-facing guide is written in Simplified Chinese because
it documents a Chinese input method for Chinese users. Project design and
implementation records remain in English.

## Keyboard Diagram

Use the supplied 2048 x 640 keyboard image as the edit source. Preserve its
black background, peach key outlines and letters, blue finals, purple special
keys, red logo, spacing, proportions, and every unchanged label.

Remove only the three fly-key alternatives:

- Remove the pink `zh` from `F`; keep `F` as the native initial and `an` final.
- Remove the pink `ch` from `J`; keep `J` as the native initial and `er`/`u`
  finals.
- Remove the blue `uang` from `M`; keep `M` as the native initial and `ian`
  final.

Keep the canonical assignments visible:

- `Q`: native `q`, mapped initial `zh`, finals `iu` and `ua`.
- `W`: native `w`, mapped initial `ch`, finals `ei` and `un`.
- `X`: native `x`, zero initial, finals `iang` and `uang`.

Save the final asset as `guide/xmjd6-nofly-keyboard.png` and reference it from
the guide using a relative Markdown link.

## Guide Structure

Create `guide/无飞键版说明.md` with:

1. A short definition of the no-fly rules: `ch -> W`, `zh -> Q`, and
   `uang -> X` in phonetic positions.
2. The keyboard image.
3. A complete QWERTY key table covering native initials, mapped initials,
   finals, and unchanged special/shape keys.
4. A focused explanation of Q/W/F/J/X/M so native initials are not confused
   with mapped initials or finals.
5. Before/after examples and a fly-key versus no-fly comparison.
6. A technical change log describing structural code conversion, reading
   disambiguation, stable de-duplication, copied custom dictionaries, preserved
   metadata, branch-root packaging, and Windows-first defaults.
7. Conversion statistics and automated verification results.
8. Windows and macOS test instructions, with Windows presented first.

## Accuracy Rules

The guide must distinguish a keyboard letter from a phonetic slot. For
example, mapping `ch` to W does not rewrite a native `w` or `j` globally. Shape
suffixes, weights, comments, headers, BOM/line endings, and candidate order are
preserved. Only identical text-plus-code rows created by normalization are
collapsed; different candidates sharing a code remain ordered.

The documented conversion totals are:

- Input entries: 1,259,654.
- Output entries: 1,251,653.
- Converted entries: 195,446.
- Collapsed duplicates: 8,001.
- Unresolved standard entries: 0.

## Verification

Add a focused Python test that checks the guide and image exist, validates the
PNG signature and wide keyboard aspect ratio, and asserts the essential
mappings, examples, statistics, branch command, and redeployment instructions
are present. Run this test together with both existing no-fly test suites.
