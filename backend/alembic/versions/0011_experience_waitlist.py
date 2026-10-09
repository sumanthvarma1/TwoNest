"""add FIFO waitlist for capacity-limited experiences"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0011_experience_waitlist"
down_revision = "0010_moving_workspace"
branch_labels = None
depends_on = None


def upgrade():
    if not inspect(op.get_bind()).has_table("experience_waitlist"):
        op.create_table(
            "experience_waitlist",
            sa.Column("id", sa.String(length=36), primary_key=True),
            sa.Column("experience_id", sa.String(length=36), sa.ForeignKey("experiences.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("status", sa.String(length=24), nullable=False, server_default="waiting"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("experience_id", "user_id"),
        )
        op.create_index("ix_experience_waitlist_experience_id", "experience_waitlist", ["experience_id"])
        op.create_index("ix_experience_waitlist_user_id", "experience_waitlist", ["user_id"])


def downgrade():
    if inspect(op.get_bind()).has_table("experience_waitlist"):
        op.drop_index("ix_experience_waitlist_user_id", table_name="experience_waitlist")
        op.drop_index("ix_experience_waitlist_experience_id", table_name="experience_waitlist")
        op.drop_table("experience_waitlist")
