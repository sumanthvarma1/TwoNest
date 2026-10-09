"""persist private compatibility answers"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0003_compatibility_answers"
down_revision = "0002_onboarding_profile"
branch_labels = None
depends_on = None


def upgrade():
    if inspect(op.get_bind()).has_table("compatibility_answers"):
        return
    op.create_table(
        "compatibility_answers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("question_id", sa.String(length=80), nullable=False),
        sa.Column("category", sa.String(length=40), nullable=False),
        sa.Column("value", sa.JSON(), nullable=False),
        sa.Column("importance", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("deal_breaker", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_private", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "question_id", name="uq_compatibility_answer_user_question"),
    )
    op.create_index("ix_compatibility_answers_user_id", "compatibility_answers", ["user_id"])


def downgrade():
    if inspect(op.get_bind()).has_table("compatibility_answers"):
        op.drop_table("compatibility_answers")
