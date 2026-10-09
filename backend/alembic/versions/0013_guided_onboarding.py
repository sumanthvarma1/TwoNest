"""Persist guided onboarding and partner age preferences."""
from alembic import op
import sqlalchemy as sa

revision = "0013_guided_onboarding"
down_revision = "0012_couple_together"
branch_labels = None
depends_on = None


def upgrade():
    existing = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("onboarding_profiles")}
    columns = [
        sa.Column("preferred_age_min", sa.Integer(), nullable=False, server_default="18"),
        sa.Column("preferred_age_max", sa.Integer(), nullable=False, server_default="80"),
        sa.Column("onboarding_step", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("onboarding_completed", sa.Boolean(), nullable=False, server_default=sa.false()),
    ]
    for column in columns:
        if column.name not in existing:
            op.add_column("onboarding_profiles", column)


def downgrade():
    with op.batch_alter_table("onboarding_profiles") as batch:
        for name in ("onboarding_completed", "onboarding_step", "preferred_age_max", "preferred_age_min"):
            batch.drop_column(name)
