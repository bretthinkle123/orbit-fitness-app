"""Crypto facade — the ONLY module that performs hashing/crypto operations in
the app (CLAUDE.md: "all crypto/hashing... routes through one
`src/orbit/crypto/` facade — never inline"). T1 needs just the uid-hashing
used by the logging facade; later tasks extend this module rather than
hashing inline at the call site.
"""

import hashlib


def hash_uid(owner_uid: str) -> str:
    """One-way hash of a Firebase UID for logs/audit events.

    `owner_uid` is never written to a log verbatim (`logging-conventions`);
    this hash gives every event a stable, correlatable-but-opaque actor
    reference instead.
    """
    return hashlib.sha256(owner_uid.encode("utf-8")).hexdigest()[:16]
