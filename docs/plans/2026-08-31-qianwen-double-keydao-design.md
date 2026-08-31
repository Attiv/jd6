# Qianwen Double-Pinyin Keydao Overlay Design

## Scope

Change the existing Qianwen Rime synchronization so Keydao 6 replaces only Qianwen's `qw_double` scheme. Preserve the vendor `qw` full-pinyin scheme and its compiled artifacts unchanged.

## Mapping

- Generate `schemas/qw_double.schema.yaml` from `xmjd6.schema.yaml` with `schema_id: qw_double` and translator dictionaries named `qw_double`.
- Generate the compiled `rime_user/build/qw_double.schema.yaml` from the deployed Keydao schema.
- Map `xmjd6.extended.{prism,reverse,table}.bin` to `qw_double.{prism,reverse,table}.bin`.
- Continue copying Keydao source files, Lua, OpenCC, support files, and optional runtime data as before.
- Validate `qw_double.schema.yaml` in `status`; do not treat a modified or vendor `qw.schema.yaml` as the overlay marker.

## Invariants

- Do not overwrite `schemas/qw.schema.yaml` or `build/qw.schema.yaml`.
- Do not overwrite `build/qw.{prism,reverse,table}.bin`.
- Preserve the vendor `default.yaml`, Qime runtime data, and update-control behavior.

## Verification

The isolated integration fixture stores distinct vendor markers in the full-pinyin and double-pinyin files. After sync, it must prove the full-pinyin files are byte-identical while the double-pinyin schema and binaries contain the Keydao overlay. Live verification checks that `qw` remains `千问拼音` and `qw_double` becomes `键道6·仰望星空`.
