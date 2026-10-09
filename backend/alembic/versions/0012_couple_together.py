"""add couple publication consent and shared relationship moments"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0012_couple_together"
down_revision = "0011_experience_waitlist"
branch_labels = None
depends_on = None


def upgrade():
    inspector = inspect(op.get_bind())
    if not inspector.has_table("couple_profiles"):
        op.create_table(
            "couple_profiles",
            sa.Column("couple_id", sa.String(length=36), sa.ForeignKey("couples.id", ondelete="CASCADE"), primary_key=True),
            sa.Column("relationship_stage", sa.String(length=40), nullable=False, server_default="dating"),
            sa.Column("general_area", sa.String(length=100), nullable=False, server_default=""),
            sa.Column("shared_interests", sa.JSON(), nullable=False),
            sa.Column("preferred_activities", sa.JSON(), nullable=False),
            sa.Column("food_preferences", sa.JSON(), nullable=False),
            sa.Column("social_energy", sa.String(length=40), nullable=False, server_default=""),
            sa.Column("children", sa.String(length=80), nullable=False, server_default=""),
            sa.Column("pets", sa.JSON(), nullable=False),
            sa.Column("languages", sa.JSON(), nullable=False),
            sa.Column("availability", sa.JSON(), nullable=False),
            sa.Column("event_budget_min", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("event_budget_max", sa.Integer(), nullable=False, server_default="100"),
            sa.Column("travel_interests", sa.JSON(), nullable=False),
            sa.Column("approved_a", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("approved_b", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
    inspector = inspect(op.get_bind())
    if not inspector.has_table("couple_moments"):
        op.create_table(
            "couple_moments",
            sa.Column("id", sa.String(length=36), primary_key=True),
            sa.Column("couple_id", sa.String(length=36), sa.ForeignKey("couples.id", ondelete="CASCADE"), nullable=False),
            sa.Column("created_by", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title", sa.String(length=120), nullable=False),
            sa.Column("details", sa.Text(), nullable=False, server_default=""),
            sa.Column("moment_type", sa.String(length=24), nullable=False, server_default="activity"),
            sa.Column("planned_for", sa.String(length=40), nullable=True),
            sa.Column("completed", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_couple_moments_couple_id", "couple_moments", ["couple_id"])


def downgrade():
    inspector = inspect(op.get_bind())
    if inspector.has_table("couple_moments"):
        op.drop_index("ix_couple_moments_couple_id", table_name="couple_moments")
        op.drop_table("couple_moments")
    if inspector.has_table("couple_profiles"):
        op.drop_table("couple_profiles")
