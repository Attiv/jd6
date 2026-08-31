# Qianwen Full-Pinyin Keydao Overlay Design

## Scope

Use Keydao 6 behind Qianwen's `qw` full-pinyin entry while preserving the vendor `qw_double` scheme. Keep automatic updates enabled.

## Mapping

- Generate `qw.schema.yaml` from `xmjd6.schema.yaml` with `schema_id: qw` and dictionary alias `qw`.
- Map `xmjd6.extended.{prism,reverse,table}.bin` to `qw.{prism,reverse,table}.bin`.
- Preserve the source schema, built schema, and prism of vendor `qw_double` byte-for-byte.
- Permit degraded deployment on Qianwen 1.2.x: translation works through the full-pinyin text path, while processor-based functions may remain unavailable.

## Verification

The isolated test verifies `qw` receives Keydao and `qw_double` remains unchanged. Live verification checks that `qw` is active, its binaries match the Keydao build, stock double-pinyin hashes are unchanged, and automatic updates remain enabled.
