from __future__ import annotations

import os

from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field

from auth.single_user import authenticate
from scanner.engine import scan_symbol, signal_to_dict
from data.tabdeal import TabdealPublicClient

app = FastAPI(title="Crypto Signal Scanner", version="0.1.0")
security = HTTPBasic()
client = TabdealPublicClient()


class ScanRequest(BaseModel):
    symbol: str = Field(min_length=3, max_length=30)
    timeframe: str = Field(default="15m", pattern=r"^(1m|5m|15m|1h)$")
    capital: float = Field(gt=0)
    risk_percent: float = Field(default=1.0, gt=0, le=5)


def require_owner(credentials: HTTPBasicCredentials = Depends(security)) -> str:
    if not authenticate(credentials.username, credentials.password):
        raise HTTPException(status_code=401, detail="Invalid credentials", headers={"WWW-Authenticate": "Basic"})
    return credentials.username


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "mode": os.getenv("EXECUTION_MODE", "signal_only")}


@app.post("/scan")
def scan(request: ScanRequest, _: str = Depends(require_owner)) -> dict:
    try:
        signal = scan_symbol(client, request.symbol.upper(), request.timeframe, request.capital, request.risk_percent)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Market data unavailable") from exc
    return signal_to_dict(signal)
