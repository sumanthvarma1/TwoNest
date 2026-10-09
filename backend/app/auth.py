"""Shared request identity dependency for the local API."""
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session
from .db import get_db
from .models import User


def current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> User:
    token = (authorization or "").removeprefix("Bearer ")
    user = db.get(User, token)
    if not user or user.deleted_at:
        raise HTTPException(401, "Sign in required")
    return user
