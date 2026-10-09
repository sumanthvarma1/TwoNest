"""add Nest4 meetup, private follow-up and consent-gated group chat"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0009_nest4_meetups_followups"
down_revision = "0008_home_mode_answers"
branch_labels = None
depends_on = None


def upgrade():
    inspector = inspect(op.get_bind())
    if not inspector.has_table("nest4_meeting_plans"):
        op.create_table(
            "nest4_meeting_plans",
            sa.Column("id", sa.String(length=36), primary_key=True),
            sa.Column("match_id", sa.String(length=36), sa.ForeignKey("couple_matches.id", ondelete="CASCADE"), nullable=False),
            sa.Column("created_by", sa.String(length=36), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("title", sa.String(length=120), nullable=False),
            sa.Column("venue", sa.String(length=160), nullable=False),
            sa.Column("area", sa.String(length=100), nullable=False),
            sa.Column("starts_at", sa.String(length=40), nullable=False),
            sa.Column("status", sa.String(length=24), nullable=False, server_default="proposed"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_nest4_meeting_plans_match_id", "nest4_meeting_plans", ["match_id"])
    inspector = inspect(op.get_bind())
    if not inspector.has_table("nest4_meeting_votes"):
        op.create_table(
            "nest4_meeting_votes",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("plan_id", sa.String(length=36), sa.ForeignKey("nest4_meeting_plans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("attending", sa.Boolean(), nullable=False),
            sa.UniqueConstraint("plan_id", "member_id"),
        )
        op.create_index("ix_nest4_meeting_votes_plan_id", "nest4_meeting_votes", ["plan_id"])
        op.create_index("ix_nest4_meeting_votes_member_id", "nest4_meeting_votes", ["member_id"])
    inspector = inspect(op.get_bind())
    if not inspector.has_table("nest4_followup_decisions"):
        op.create_table(
            "nest4_followup_decisions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("match_id", sa.String(length=36), sa.ForeignKey("couple_matches.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("decision", sa.String(length=32), nullable=False),
            sa.Column("details", sa.Text(), nullable=False, server_default=""),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("match_id", "member_id"),
        )
        op.create_index("ix_nest4_followup_decisions_match_id", "nest4_followup_decisions", ["match_id"])
        op.create_index("ix_nest4_followup_decisions_member_id", "nest4_followup_decisions", ["member_id"])
    inspector = inspect(op.get_bind())
    if not inspector.has_table("nest4_messages"):
        op.create_table(
            "nest4_messages",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("match_id", sa.String(length=36), sa.ForeignKey("couple_matches.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sender_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_nest4_messages_match_id", "nest4_messages", ["match_id"])
        op.create_index("ix_nest4_messages_sender_id", "nest4_messages", ["sender_id"])


def downgrade():
    inspector = inspect(op.get_bind())
    for table, indexes in (
        ("nest4_messages", ("ix_nest4_messages_sender_id", "ix_nest4_messages_match_id")),
        ("nest4_followup_decisions", ("ix_nest4_followup_decisions_member_id", "ix_nest4_followup_decisions_match_id")),
        ("nest4_meeting_votes", ("ix_nest4_meeting_votes_member_id", "ix_nest4_meeting_votes_plan_id")),
        ("nest4_meeting_plans", ("ix_nest4_meeting_plans_match_id",)),
    ):
        if inspector.has_table(table):
            for index in indexes:
                op.drop_index(index, table_name=table)
            op.drop_table(table)
