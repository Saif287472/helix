# Domain Context

## Responsibility

Domain types describe peers, sessions, messages, requests, files, groups, and
trust state.

## Target Rule

Domain must not import Flutter, Riverpod, SQLite, WebRTC, `dart:io`, platform
channels, crypto implementation packages, or secure storage.

## Current Caveat

Domain models are Flutter-free, but `core/constants.dart` still exposes platform
detection helpers backed by `dart:io`. Keep that code isolated from entities and
move it to `helix_platform` if package purity becomes a hard release gate.

## Invariants

- Fingerprints are identity/trust anchors.
- Session IDs are not trust anchors.
- Message IDs and file IDs remain distinct.

## Required Tests

Validation tests for model constraints and any value-object behavior.

## High-Risk Areas

Trust state, thread status, message/file identity, and group membership models.
