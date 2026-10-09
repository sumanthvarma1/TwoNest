"""persist discovery pause and travel mode"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0007_discovery_controls"
down_revision = "0006_circle_poll_choices"
branch_labels = None
depends_on = None


def upgrade():
    inspector = inspect(op.get_bind())
    if not inspector.has_table("onboarding_profiles"):
        return
    columns = {column["name"] for column in inspector.get_columns("onboarding_profiles")}
    with op.batch_alter_table("onboarding_profiles") as batch:
        if "discovery_paused" not in columns:
            batch.add_column(sa.Column("discovery_paused", sa.Boolean(), nullable=False, server_default=sa.false()))
        if "travel_mode_area" not in columns:
            batch.add_column(sa.Column("travel_mode_area", sa.String(length=100), nullable=False, server_default=""))
        if "travel_mode_until" not in columns:
            batch.add_column(sa.Column("travel_mode_until", sa.String(length=10), nullable=True))


def downgrade():
    inspector = inspect(op.get_bind())
    if not inspector.has_table("onboarding_profiles"):
        return
    columns = {column["name"] for column in inspector.get_columns("onboarding_profiles")}
    with op.batch_alter_table("onboarding_profiles") as batch:
        for name in ("travel_mode_until", "travel_mode_area", "discovery_paused"):
            if name in columns:
                batch.drop_column(name)
