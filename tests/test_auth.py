import os

from auth.single_user import authenticate, password_hash


def test_single_user_auth(monkeypatch):
    monkeypatch.setenv("SIGNAL_SCANNER_USERNAME", "owner")
    monkeypatch.setenv("SIGNAL_SCANNER_PASSWORD_HASH", password_hash("secret"))
    assert authenticate("owner", "secret")
    assert not authenticate("other", "secret")
    assert not authenticate("owner", "wrong")
