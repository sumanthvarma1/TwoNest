"""add private couple-scoped home-mode answers"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0008_home_mode_answers"
down_revision = "0007_discovery_controls"
branch_labels = None
depends_on = None


def upgrade():
    if inspect(op.get_bind()).has_table("home_mode_answers"):
        return
    op.create_table(
        "home_mode_answers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("couple_id", sa.String(length=36), sa.ForeignKey("couples.id", ondelete="CASCADE"), nullable=False),
        sa.Column("member_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("question_id", sa.String(length=80), nullable=False),
        sa.Column("value", sa.JSON(), nullable=False),
        sa.Column("is_private", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("couple_id", "member_id", "question_id", name="uq_home_mode_answer_member_question"),
    )
    op.create_index("ix_home_mode_answers_couple_id", "home_mode_answers", ["couple_id"])
    op.create_index("ix_home_mode_answers_member_id", "home_mode_answers", ["member_id"])


def downgrade():
    if inspect(op.get_bind()).has_table("home_mode_answers"):
        op.drop_index("ix_home_mode_answers_member_id", table_name="home_mode_answers")
        op.drop_index("ix_home_mode_answers_couple_id", table_name="home_mode_answers")
        op.drop_table("home_mode_answers")
