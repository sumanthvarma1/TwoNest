"""add private couple moving workspace"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0010_moving_workspace"
down_revision = "0009_nest4_meetups_followups"
branch_labels = None
depends_on = None


def upgrade():
    if not inspect(op.get_bind()).has_table("moving_tasks"):
        op.create_table(
            "moving_tasks",
            sa.Column("id", sa.String(length=36), primary_key=True),
            sa.Column("couple_id", sa.String(length=36), sa.ForeignKey("couples.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title", sa.String(length=160), nullable=False),
            sa.Column("category", sa.String(length=40), nullable=False, server_default="planning"),
            sa.Column("due_date", sa.String(length=10), nullable=True),
            sa.Column("completed", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("created_by", sa.String(length=36), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_moving_tasks_couple_id", "moving_tasks", ["couple_id"])


def downgrade():
    if inspect(op.get_bind()).has_table("moving_tasks"):
        op.drop_index("ix_moving_tasks_couple_id", table_name="moving_tasks")
        op.drop_table("moving_tasks")
