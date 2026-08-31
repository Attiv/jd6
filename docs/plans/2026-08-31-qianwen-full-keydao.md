# Qianwen Full-Pinyin Keydao Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the proven Keydao-on-`qw` mapping while preserving native `qw_double` and enabled updates.

**Architecture:** Retarget the existing schema and binary aliases from `qw_double` to `qw`. Keep the compatibility-engine decision as a degraded-mode capability rather than a hard blocker.

**Tech Stack:** Bash, embedded Python schema transformation, Rime deployment artifacts, Qianwen relaunch helper.

---

1. Change the isolated fixture to require Keydao under `qw` and unchanged vendor `qw_double` files.
2. Retarget schema generation, binary aliases, and status checks to `qw`.
3. Restore degraded deployment when the old key-event compatibility engine cannot load.
4. Update the handoff document and embedded source payloads.
5. Deploy to Qianwen 1.2.10.34, select full pinyin, verify `qw_double` hashes, and confirm updates remain enabled.
