# API Reference: rules

Source file: `tender/frappe/src/compliance/rules.py`

## Module Description

Rule loading and deterministic applicability matching.

Rules are Tender Compliance Rule records (fixture-shipped, desk-editable).
A rule applies to a bid when:

- it is enabled, AND
- its ``regimes`` list (comma-separated regime codes) is empty or contains
  the bid's regime, AND
- its scope is Universal, or its scope is Conditional and its JSON
  ``trigger_condition`` matches the bid context (see ``condition_matches``).

``condition_matches`` semantics (pure data comparison, no AI):

- ``"<field>_over": N``  -> context[field] is set and > N
- ``"<field>_under": N`` -> context[field] is set and <= N
- ``"<field>_matches": [p, q]`` -> normalized (lowercased, whitespace-collapsed)
  context[field] CONTAINS any normalized pattern - used for buyer matching on
  the bid's ``institution`` (the OCDS buyer name cached from the tender feed).
  Patterns are fixture data; no buyer name is ever hard-coded here.
- ``"<field>": [a, b]``  -> context[field] in [a, b]
- ``"<field>": value``   -> context[field] == value

A Conditional rule with neither a parsable trigger nor a regime restriction
never auto-applies - it stays desk-visible guidance a human can act on.

## Documented Module Functions

### `def parse_json_field(raw)`

Parses a JSON Code field defensively; returns {} / None on bad data.

### `def parse_regimes(raw)`

Splits the comma-separated regimes field into a set of codes.

### `def text_matches_any(actual, patterns)`

True when the normalized actual text contains any normalized pattern.

A plain substring test over normalized text - deterministic and desk-
auditable. Patterns come from fixture data (e.g. a rule's trigger
condition listing buyer-name fragments); an empty/missing actual value
or pattern list never matches.

### `def condition_matches(condition, context)`

Deterministically matches a trigger-condition dict against a context dict.

### `def rule_applies(rule, context)`

True when a Tender Compliance Rule record applies to the bid context.

### `def get_applicable_rules(bid, rule_class=None)`

Enabled rules that apply to this bid, Fatal-first then by rule_code.

### `def get_scoring_rule(rule_code)`

Loads one Scoring Rule's params dict by rule_code, or None.
