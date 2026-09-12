# Security incident response

## Triage and containment

1. Open a private incident channel, assign an incident lead, record UTC times,
   affected versions/services, evidence sources and decisions.
2. Stop affected deployments or update distribution when continued operation
   increases harm. Preserve minimal logs and snapshots without message bodies.
3. Revoke affected sessions/devices. Rotate relay token peppers, database/Redis
   credentials, TLS keys and cloud credentials according to exposure. Token
   pepper rotation invalidates every relay session and requires reauthentication.
4. If a release-signing key is suspected, stop releases, use the platform's
   recovery/rotation process, and notify users through an independently
   authenticated channel. Never publish an unsigned emergency updater.

## Scenario playbooks

- Database leak: assume routing metadata and encrypted envelopes escaped;
  rotate credentials, validate retention deletion, analyze whether any
  plaintext or token material was incorrectly stored, and notify accurately.
- Backend compromise: isolate instances, revoke sessions, rotate all instance
  and infrastructure secrets, rebuild from reviewed source and clean images,
  and inspect authorization/integrity evidence.
- Dependency vulnerability: determine reachable vulnerable code, create a
  regression test, update and rebuild in staging, scan the resulting artifacts,
  then deploy through signed channels.
- AI/privacy leak: disable cloud AI, revoke provider credentials, preserve the
  consent/audit record without retaining prompt content, and determine the
  exact selected data disclosed.

## Recovery

Restore encrypted backups into an isolated environment, verify schema and row
counts, validate ciphertext/retention invariants, run authorization and E2E
tests, rotate restored credentials, and only then return traffic gradually.

## Closure

Publish affected versions, impact, containment, user action, and fixed version.
Add tests for the root cause and track follow-up owners. Never claim that E2EE
protected data unless the affected path was actually E2EE in that build.
