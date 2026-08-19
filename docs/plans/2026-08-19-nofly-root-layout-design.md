# No-Fly Branch Root Layout Design

## Goal

Make Git branch selection correspond directly to the active Rime scheme:

- `main` keeps the original fly-key scheme.
- `feature/xmjd6-nofly` exposes the no-fly scheme at the repository root.

After checking out either branch in `~/Library/Rime`, a Rime redeploy should
activate that branch's dictionaries without copying files from a nested bundle.

## Layout

Promote the generated `xmjd6-nofly/` bundle into the branch root. Files with
the same paths, including schemas, dictionaries, defaults, Lua modules, OpenCC
resources, and fonts, replace their original branch versions. Remove the nested
bundle after promotion so there is only one authoritative runtime copy.

Keep repository tooling and documentation that are not part of the generated
bundle. Preserve the local working-tree modifications to `installation.yaml`
and `user.yaml`; these machine-specific files must not be staged or committed.

## Branch Switching

The intended workflow is:

```bash
git checkout main
git checkout feature/xmjd6-nofly
```

Rime must be redeployed after switching because compiled artifacts can outlive
the source files from the previous branch.

## Verification

Automated checks verify the root schema name and representative conversions:

- `超`: `wz`, not `jz`.
- `春`: `wwv`, not `jwv`.
- `找`: `qz`, not `fz`.
- `中`: `qy`, not `fy`.
- `装`: `qx`, not `fm` or `fx`.
- `光`: `gx`, not `gm`.
- Native codes `均 jw`, `无 wj`, `求 qq`, and `服 fj` remain available.

The root scheme is also compiled in an isolated temporary directory. The final
Git status must show only the pre-existing local modifications to
`installation.yaml` and `user.yaml`.
