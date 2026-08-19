from __future__ import annotations

import os

from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field

from ai.analyst import analyze_market
from auth.single_user import authenticate
from data.tabdeal import TabdealPublicClient
from scanner.best_market import best_market
from scanner.engine import scan_symbol, signal_to_dict

app = FastAPI(title="Crypto Signal Scanner", version="0.3.0")
security = HTTPBasic()
client = TabdealPublicClient()


class ScanRequest(BaseModel):
    symbol: str = Field(min_length=3, max_length=30)
    timeframe: str = Field(default="15m", pattern=r"^(1m|5m|15m|1h)$")
    capital: float = Field(gt=0)
    risk_percent: float = Field(default=1.0, gt=0, le=5)


class BestRequest(BaseModel):
    timeframe: str = Field(default="15m", pattern=r"^(1m|5m|15m|1h)$")
    capital: float = Field(gt=0)
    risk_percent: float = Field(default=1.0, gt=0, le=5)
    max_markets: int = Field(default=50, ge=1, le=200)


class AIAnalysisRequest(BaseModel):
    signal: dict


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


@app.post("/best")
def best(request: BestRequest, _: str = Depends(require_owner)) -> dict:
    try:
        return best_market(client, request.timeframe, request.capital, request.risk_percent, request.max_markets)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Market scan unavailable") from exc


@app.post("/ai/analyze")
def ai_analyze(request: AIAnalysisRequest, _: str = Depends(require_owner)) -> dict:
    try:
        return analyze_market(request.signal)
    except RuntimeError as exc:
        message = str(exc)
        if "OPENAI_API_KEY" in message:
            raise HTTPException(status_code=503, detail="AI analysis is not configured") from exc
        raise HTTPException(status_code=502, detail=message) from exc
