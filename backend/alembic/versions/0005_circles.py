"""add guided circles, prompts, responses, chat and meeting plans"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0005_circles"
down_revision = "0004_member_blocks"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    existing = set(inspect(bind).get_table_names())
    if "circles" not in existing:
        op.create_table(
            "circles",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("theme", sa.String(48), nullable=False),
            sa.Column("area", sa.String(100), nullable=False),
            sa.Column("started_at", sa.String(40), nullable=False),
            sa.Column("created_by", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("status", sa.String(24), nullable=False, server_default="active"),
            sa.Column("max_members", sa.Integer(), nullable=False, server_default="8"),
        )
        op.create_index("ix_circles_theme", "circles", ["theme"])
        op.create_index("ix_circles_status", "circles", ["status"])
    if "circle_members" not in existing:
        op.create_table(
            "circle_members",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("circle_id", sa.String(36), sa.ForeignKey("circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("status", sa.String(24), nullable=False, server_default="active"),
            sa.UniqueConstraint("circle_id", "member_id"),
        )
        op.create_index("ix_circle_members_circle_id", "circle_members", ["circle_id"])
        op.create_index("ix_circle_members_member_id", "circle_members", ["member_id"])
    if "circle_prompts" not in existing:
        op.create_table(
            "circle_prompts",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("circle_id", sa.String(36), sa.ForeignKey("circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("week", sa.Integer(), nullable=False),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("prompt_type", sa.String(24), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.UniqueConstraint("circle_id", "week"),
        )
        op.create_index("ix_circle_prompts_circle_id", "circle_prompts", ["circle_id"])
    if "circle_responses" not in existing:
        op.create_table(
            "circle_responses",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("prompt_id", sa.String(36), sa.ForeignKey("circle_prompts.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("response_text", sa.Text(), nullable=False, server_default=""),
            sa.Column("voice_asset_key", sa.String(80), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("prompt_id", "member_id"),
        )
        op.create_index("ix_circle_responses_prompt_id", "circle_responses", ["prompt_id"])
        op.create_index("ix_circle_responses_member_id", "circle_responses", ["member_id"])
    if "circle_messages" not in existing:
        op.create_table(
            "circle_messages",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("circle_id", sa.String(36), sa.ForeignKey("circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sender_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_circle_messages_circle_id", "circle_messages", ["circle_id"])
        op.create_index("ix_circle_messages_sender_id", "circle_messages", ["sender_id"])
    if "circle_meeting_plans" not in existing:
        op.create_table(
            "circle_meeting_plans",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("circle_id", sa.String(36), sa.ForeignKey("circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("proposed_by", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("venue", sa.String(160), nullable=False),
            sa.Column("area", sa.String(100), nullable=False),
            sa.Column("starts_at", sa.String(40), nullable=False),
            sa.Column("status", sa.String(24), nullable=False, server_default="proposed"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_circle_meeting_plans_circle_id", "circle_meeting_plans", ["circle_id"])
    if "circle_meeting_votes" not in existing:
        op.create_table(
            "circle_meeting_votes",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("plan_id", sa.String(36), sa.ForeignKey("circle_meeting_plans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("attending", sa.Boolean(), nullable=False),
            sa.UniqueConstraint("plan_id", "member_id"),
        )
        op.create_index("ix_circle_meeting_votes_plan_id", "circle_meeting_votes", ["plan_id"])
        op.create_index("ix_circle_meeting_votes_member_id", "circle_meeting_votes", ["member_id"])


def downgrade():
    for table in ("circle_meeting_votes", "circle_meeting_plans", "circle_messages", "circle_responses", "circle_prompts", "circle_members", "circles"):
        if inspect(op.get_bind()).has_table(table):
            op.drop_table(table)
