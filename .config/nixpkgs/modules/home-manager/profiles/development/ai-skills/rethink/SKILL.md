---
name: rethink
description: >-
  Stress-test a proposed architecture, interface, or complex implementation
  when simpler or more maintainable alternatives may exist.
---

# Rethink the Design

## Goal

Use available requirements, code, callers, and tests to reduce the breadth of
changes, cognitive load, and hidden dependencies without hiding essential domain
complexity. Do not force a redesign when the current design is proportionate.

## Lenses

1. **Ownership:** Is this compensating for an upstream bug, missing abstraction,
   or misplaced responsibility? Can the owning module absorb complexity currently
   pushed to callers?
2. **Depth:** Does each module hide substantial functionality behind a simple
   interface? Look for shallow wrappers and pass-through layers. Merge adjacent
   layers that provide the same abstraction only when neither hides a distinct
   decision or ownership boundary.
3. **Interface:** Is the API general enough and convenient for current needs?
   What can be removed or inferred? Can configuration, errors, special cases, or
   invalid states be designed out of existence without hiding genuine domain
   constraints?
4. **Information hiding:** Is each design decision known in one place, or leaked
   through parameters, types, sequencing requirements, or duplicated logic?

## Output

Report only findings that would materially change a boundary, interface,
ownership, or total complexity. If evidence is insufficient, state what is
missing. If no material finding exists, state that the current design is
proportionate.

For each finding, give the evidence, concrete issue, smallest viable alternative,
and trade-offs. When the smallest local patch differs from the simplest durable
design, distinguish them and recommend which is proportionate to the user's
needs.
