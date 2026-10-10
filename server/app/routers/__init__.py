"""라우터 등록. 모든 라우터는 `/v1` 아래에 붙는다 (NFR-10).

공용 파일이다. 새 라우터를 추가할 때는 아래 목록에 한 줄만 더하고, 다른 줄은 건드리지 않는다.
"""

from fastapi import APIRouter

from app.routers import characters, creation, health, messages, profile

api_routers: list[APIRouter] = [
    health.router,
    characters.router,
    messages.router,
    profile.router,
    creation.router,
]
