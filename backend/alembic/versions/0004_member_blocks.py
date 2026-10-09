"""persist member blocking and unmatching"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0004_member_blocks"
down_revision = "0003_compatibility_answers"
branch_labels = None
depends_on = None


def upgrade():
    if inspect(op.get_bind()).has_table("member_blocks"):
        return
    op.create_table(
        "member_blocks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("blocker_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("blocked_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("blocker_id", "blocked_id"),
    )
    op.create_index("ix_member_blocks_blocker_id", "member_blocks", ["blocker_id"])
    op.create_index("ix_member_blocks_blocked_id", "member_blocks", ["blocked_id"])


def downgrade():
    if inspect(op.get_bind()).has_table("member_blocks"):
        op.drop_table("member_blocks")
