import os

import pytest

from execution import service
from execution import store
from execution.models import ActionStatus, ActionType, ExecutionMode


@pytest.fixture(autouse=True)
def _clean_store(monkeypatch):
    monkeypatch.setenv("EXECUTION_MODE", "paper")
    store._pending.clear()
    store._paper_positions.clear()
    yield
    store._pending.clear()
    store._paper_positions.clear()


def test_signal_only_blocks_propose(monkeypatch):
    monkeypatch.setenv("EXECUTION_MODE", "signal_only")
    with pytest.raises(RuntimeError):
        service.propose_open(symbol="BTCUSDT", side="LONG", quantity=0.01)


def test_propose_requires_approval_before_position():
    action = service.propose_open(
        symbol="BTCUSDT",
        side="LONG",
        quantity=0.01,
        entry=100.0,
        stop_loss=95.0,
        take_profit=110.0,
    )
    assert action.status == ActionStatus.PENDING
    assert store.get_paper_positions() == []

    rejected = service.reject(action.id)
    assert rejected.status == ActionStatus.REJECTED
    assert store.get_paper_positions() == []


def test_approve_opens_paper_position():
    action = service.propose_open(symbol="ETHUSDT", side="SHORT", quantity=0.5, entry=2000.0)
    done = service.approve(action.id)
    assert done.status == ActionStatus.EXECUTED
    assert done.action == ActionType.OPEN
    positions = store.get_paper_positions()
    assert len(positions) == 1
    assert positions[0]["symbol"] == "ETHUSDT"
    assert positions[0]["side"] == "SHORT"


def test_approve_close_after_open():
    open_action = service.propose_open(symbol="SOLUSDT", side="LONG", quantity=2.0, entry=150.0)
    service.approve(open_action.id)
    close_action = service.propose_close(symbol="SOLUSDT")
    assert close_action.status == ActionStatus.PENDING
    done = service.approve(close_action.id)
    assert done.status == ActionStatus.EXECUTED
    assert store.get_paper_positions() == []


def test_mode_info_paper():
    info = service.mode_info()
    assert info["mode"] == ExecutionMode.PAPER.value
    assert info["can_propose"] is True
