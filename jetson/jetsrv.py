#!/usr/bin/env python3
"""Minimal asyncio WebSocket server for ingesting watch/phone GPS fixes."""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional, Set

import jsonschema
import websockets

logging.basicConfig(level=logging.INFO)
LOGGER = logging.getLogger("iosTracker.jetsrv")

_clients: Set[websockets.WebSocketServerProtocol] = set()
_schema: Optional[Dict[str, Any]] = None
_FIX_LOG_PATH = Path(__file__).resolve().parent / "fixes.jsonl"


def _append_fix_line(line: str) -> None:
    """Append a JSON line to the fix log on disk."""
    _FIX_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(_FIX_LOG_PATH, "a", encoding="utf-8") as f:
        f.write(line)


async def _persist_fix(fix: Dict[str, Any]) -> None:
    """Persist a validated fix to disk without blocking the event loop."""
    try:
        line = json.dumps(fix, separators=(",", ":")) + "\n"
        await asyncio.to_thread(_append_fix_line, line)
    except Exception as exc:
        LOGGER.warning("failed to persist fix: %s", exc)


def _load_schema() -> Dict[str, Any]:
    """Load and parse the location-fix JSON schema from disk.

    Returns:
        Parsed JSON schema dictionary.

    Raises:
        FileNotFoundError: If schema file doesn't exist.
        json.JSONDecodeError: If schema file contains invalid JSON.
    """
    schema_path = Path(__file__).parent.parent / "schema" / "location-fix.schema.json"
    LOGGER.info("loading schema from %s", schema_path)

    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)

    LOGGER.info("schema loaded successfully")
    return schema


def _validate_fix(fix: Any) -> tuple[bool, Optional[str]]:
    """Validate a location fix against the JSON schema.

    Args:
        fix: Parsed JSON payload to validate.

    Returns:
        Tuple of (is_valid, error_message). error_message is None if valid.
    """
    if _schema is None:
        return False, "schema not loaded"

    try:
        jsonschema.validate(instance=fix, schema=_schema)
        return True, None
    except jsonschema.ValidationError as e:
        # Extract the most relevant error information
        error_path = ".".join(str(p) for p in e.absolute_path) if e.absolute_path else "root"
        error_msg = f"validation error at '{error_path}': {e.message}"
        return False, error_msg
    except jsonschema.SchemaError as e:
        # Schema itself is invalid (shouldn't happen after successful load)
        return False, f"schema error: {e.message}"


async def _send_error_response(
    ws: websockets.WebSocketServerProtocol,
    error: str,
    fix_data: Optional[Dict[str, Any]] = None
) -> None:
    """Send an error response back to the client.

    Args:
        ws: WebSocket connection.
        error: Error message to send.
        fix_data: Optional fix data that caused the error (for context).
    """
    try:
        error_response = {
            "status": "error",
            "message": error,
        }
        if fix_data is not None:
            # Include a sanitized version of the problematic data for debugging
            error_response["received"] = {
                k: v for k, v in fix_data.items()
                if k in {"ts_unix_ms", "source", "seq"}
            }

        await ws.send(json.dumps(error_response))
    except Exception as e:
        LOGGER.warning("failed to send error response: %s", e)


async def handler(ws: websockets.WebSocketServerProtocol) -> None:
    """Register each client, validate, and log inbound JSON payloads.

    Validates all incoming messages against the location-fix JSON schema.
    Sends error responses for invalid payloads and logs validation failures.
    """
    LOGGER.info("client connected from %s", ws.remote_address)
    _clients.add(ws)
    stream_counts = {"iOS": 0, "watchOS": 0}

    try:
        async for message in ws:
            # Parse JSON
            try:
                fix = json.loads(message)
            except json.JSONDecodeError as e:
                error_msg = f"invalid JSON: {e.msg} at position {e.pos}"
                LOGGER.warning("received non-JSON payload from %s: %s", ws.remote_address, error_msg)
                await _send_error_response(ws, error_msg)
                continue

            # Validate against schema
            is_valid, error = _validate_fix(fix)
            if not is_valid:
                LOGGER.error(
                    "validation failed for fix from %s: %s | payload=%s",
                    ws.remote_address,
                    error,
                    json.dumps(fix)
                )
                await _send_error_response(ws, error, fix if isinstance(fix, dict) else None)
                continue

            # Valid fix - log and process
            source = fix.get("source", "unknown")
            if source in stream_counts:
                stream_counts[source] += 1

            LOGGER.info(
                "[%s #%d] lat=%.6f lon=%.6f acc=%.1fm speed=%.1fm/s seq=%s",
                source,
                stream_counts.get(source, 0),
                fix.get("lat", 0.0),
                fix.get("lon", 0.0),
                fix.get("h_accuracy_m", 0.0),
                fix.get("speed_mps", 0.0),
                fix.get("seq", -1)
            )
            LOGGER.debug("fix=%s", fix)
            asyncio.create_task(_persist_fix(fix))

    except websockets.ConnectionClosed:
        LOGGER.info(
            "client disconnected from %s (iOS: %d fixes, watchOS: %d fixes)",
            ws.remote_address,
            stream_counts.get("iOS", 0),
            stream_counts.get("watchOS", 0)
        )
    finally:
        _clients.discard(ws)


async def main() -> None:
    """Start the WebSocket server with schema validation.

    Loads the JSON schema at startup and begins accepting connections.
    """
    global _schema

    # Load schema at startup
    try:
        _schema = _load_schema()
    except FileNotFoundError as e:
        LOGGER.error("schema file not found: %s", e)
        raise
    except json.JSONDecodeError as e:
        LOGGER.error("invalid schema JSON: %s", e)
        raise

    async with websockets.serve(
        handler,
        "0.0.0.0",
        8765,
        ping_interval=15,
        ping_timeout=30,
        max_size=1_048_576,
    ):
        LOGGER.info("listening on ws://0.0.0.0:8765 with schema validation enabled")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
