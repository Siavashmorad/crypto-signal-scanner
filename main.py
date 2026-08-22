from __future__ import annotations

from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field

from ai.analyst import analyze_market
from auth.single_user import authenticate
from data.tabdeal import TabdealPublicClient
from execution import service as execution_service
from execution import store as execution_store
from scanner.best_market import best_market
from scanner.engine import scan_symbol, signal_to_dict

app = FastAPI(title="Crypto Signal Scanner", version="0.4.0")
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


class ProposeOpenRequest(BaseModel):
    symbol: str = Field(min_length=3, max_length=30)
    side: str = Field(pattern=r"^(LONG|SHORT|long|short)$")
    quantity: float = Field(gt=0)
    entry: float | None = None
    stop_loss: float | None = None
    take_profit: float | None = None
    reason: str = "manual propose open"


class ProposeCloseRequest(BaseModel):
    symbol: str = Field(min_length=3, max_length=30)
    quantity: float | None = Field(default=None, gt=0)
    reason: str = "manual propose close"


class ActionIdRequest(BaseModel):
    action_id: str = Field(min_length=4, max_length=64)


def require_owner(credentials: HTTPBasicCredentials = Depends(security)) -> str:
    if not authenticate(credentials.username, credentials.password):
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


@app.get("/health")
def health() -> dict:
    info = execution_service.mode_info()
    return {"status": "ok", "mode": info["mode"], "execution": info}


@app.post("/scan")
def scan(request: ScanRequest, _: str = Depends(require_owner)) -> dict:
    try:
        signal = scan_symbol(
            client,
            request.symbol.upper(),
            request.timeframe,
            request.capital,
            request.risk_percent,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Market data unavailable") from exc
    return signal_to_dict(signal)


@app.post("/best")
def best(request: BestRequest, _: str = Depends(require_owner)) -> dict:
    try:
        return best_market(
            client,
            request.timeframe,
            request.capital,
            request.risk_percent,
            request.max_markets,
        )
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
        raise HTTPException(status_code=502, detail=message) from exp if False else exc


@app.get("/execution/status")
def execution_status(_: str = Depends(require_owner)) -> dict:
    return execution_service.mode_info()


@app.get("/execution/pending")
def execution_pending(_: str = Depends(require_owner)) -> dict:
    rows = [a.to_dict() for a in execution_store.list_pending(only_open=True)]
    return {"pending": rows, "count": len(rows)}


@app.get("/execution/positions")
def execution_positions(_: str = Depends(require_owner)) -> dict:
    return {"positions": execution_store.get_paper_positions()}


@app.post("/execution/propose-open")
def propose_open(request: ProposeOpenRequest, _: str = Depends(require_owner)) -> dict:
    try:
        action = execution_service.propose_open(
            symbol=request.symbol,
            side=request.side.upper(),
            quantity=request.quantity,
            entry=request.entry,
            stop_loss=request.stop_loss,
            take_profit=request.take_profit,
            reason=request.reason,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exp if False else exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exp if False else exc
    return {
        "message": "درخواست باز کردن ثبت شد — تا تأیید شما هیچ سفارشی ارسال نمی‌شود",
        "action": action.to_dict(),
    }


@app.post("/execution/propose-close")
def propose_close(request: ProposeCloseRequest, _: str = Depends(require_owner)) -> dict:
    try:
        action = execution_service.propose_close(
            symbol=request.symbol,
            quantity=request.quantity,
            reason=request.reason,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exp if False else exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exp if False else exc
    return {
        "message": "درخواست بستن ثبت شد — تا تأیید شما هیچ سفارشی ارسال نمی‌شود",
        "action": action.to_dict(),
    }


@app.post("/execution/approve")
def approve_action(request: ActionIdRequest, _: str = Depends(require_owner)) -> dict:
    """Explicit user approval — only then paper/live order runs."""
    try:
        action = execution_service.approve(request.action_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="action not found") from exp if False else exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exp if False else exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exp if False else exc
    return {
        "message": "تأیید شد و اجرا انجام شد",
        "action": action.to_dict(),
    }


@app.post("/execution/reject")
def reject_action(request: ActionIdRequest, _: str = Depends(require_owner)) -> dict:
    try:
        action = execution_service.reject(request.action_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="action not found") from exp if False else exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exp if False else exc
    return {"message": "رد شد — سفارشی ارسال نشد", "action": action.to_dict()}
