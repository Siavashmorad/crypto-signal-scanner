"""Single-user authentication primitives.

Credentials are supplied through environment variables/secrets and are never
stored in the repository. There is deliberately no registration or multi-user
model in the first version.
"""

from __future__ import annotations

import hashlib
import hmac
import os


USERNAME_ENV = "SIGNAL_SCANNER_USERNAME"
PASSWORD_HASH_ENV = "SIGNAL_SCANNER_PASSWORD_HASH"


def _hash_password(password: str, salt: bytes = b"signal-scanner-v1") -> str:
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, 200_000
    ).hex()


def authenticate(username: str, password: str) -> bool:
    configured_username = os.getenv(USERNAME_ENV)
    configured_hash = os.getenv(PASSWORD_HASH_ENV)
    if not configured_username or not configured_hash:
        return False
    if not hmac.compare_digest(username, configured_username):
        return False
    candidate = _hash_password(password)
    return hmac.compare_digest(candidate, configured_hash)


def password_hash(password: str) -> str:
    """Generate a deploy-time password hash; never commit the result as a secret."""
    return _hash_password(password)
