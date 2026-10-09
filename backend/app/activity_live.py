"""Local single-process live invalidation. No private data travels in events.
Use Redis/pubsub before running multiple API workers or replicas.
"""
import asyncio
from fastapi import WebSocket, WebSocketDisconnect, HTTPException
from .db import SessionLocal
from .auth import current_user

class ActivityLiveHub:
    def __init__(self): self.queues: set[asyncio.Queue] = set()

    async def publish(self):
        for queue in tuple(self.queues):
            if queue.empty(): queue.put_nowait("refresh")

    async def connect(self, socket: WebSocket, validate):
        with SessionLocal() as db:
            try:
                user = current_user(socket.headers.get("authorization"), db)
                validate(user, db)
                user_id = user.id
            except HTTPException:
                await socket.close(code=1008); return
        await socket.accept()
        queue = asyncio.Queue(maxsize=1); self.queues.add(queue)
        try:
            await socket.send_json({"type": "ready"})
            while True:
                try: await asyncio.wait_for(queue.get(), timeout=20)
                except asyncio.TimeoutError: pass
                with SessionLocal() as db:
                    from .models import User
                    active = db.get(User, user_id)
                    if not active or active.deleted_at:
                        await socket.close(code=1008); break
                    validate(active, db)
                # Re-fetch through authorized REST endpoints on both changes and expiry ticks.
                await socket.send_json({"type": "refresh"})
        except (WebSocketDisconnect, RuntimeError, HTTPException):
            pass
        finally: self.queues.discard(queue)

live_hub = ActivityLiveHub()
