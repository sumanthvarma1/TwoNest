"""member onboarding and discovery preferences"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0002_onboarding_profile"
down_revision = "0001_foundation"
branch_labels = None
depends_on = None


def upgrade():
    if inspect(op.get_bind()).has_table("onboarding_profiles"):
        return
    op.create_table(
        "onboarding_profiles",
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("date_of_birth", sa.String(length=10), nullable=True),
        sa.Column("pronouns", sa.String(length=40), nullable=False, server_default=""),
        sa.Column("gender_identity", sa.String(length=60), nullable=False, server_default=""),
        sa.Column("sexual_orientation", sa.String(length=60), nullable=False, server_default=""),
        sa.Column("dating_preferences", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("friendship_intention", sa.String(length=60), nullable=False, server_default=""),
        sa.Column("search_radius_km", sa.Integer(), nullable=False, server_default="40"),
        sa.Column("languages", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("availability", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("dietary_requirements", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("accessibility_needs", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("event_budget_min", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("event_budget_max", sa.Integer(), nullable=False, server_default="100"),
    )


def downgrade():
    if inspect(op.get_bind()).has_table("onboarding_profiles"):
        op.drop_table("onboarding_profiles")
