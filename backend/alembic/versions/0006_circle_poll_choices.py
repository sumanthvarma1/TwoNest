"""store Circle poll choices and member selections"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0006_circle_poll_choices"
down_revision = "0005_circles"
branch_labels = None
depends_on = None


def upgrade():
    inspector = inspect(op.get_bind())
    if inspector.has_table("circle_prompts") and "options" not in {c["name"] for c in inspector.get_columns("circle_prompts")}: 
        with op.batch_alter_table("circle_prompts") as batch:
            batch.add_column(sa.Column("options", sa.JSON(), nullable=False, server_default="[]"))
    inspector = inspect(op.get_bind())
    if inspector.has_table("circle_responses") and "selected_options" not in {c["name"] for c in inspector.get_columns("circle_responses")}: 
        with op.batch_alter_table("circle_responses") as batch:
            batch.add_column(sa.Column("selected_options", sa.JSON(), nullable=False, server_default="[]"))


def downgrade():
    inspector = inspect(op.get_bind())
    if inspector.has_table("circle_responses") and "selected_options" in {c["name"] for c in inspector.get_columns("circle_responses")}: 
        with op.batch_alter_table("circle_responses") as batch:
            batch.drop_column("selected_options")
    inspector = inspect(op.get_bind())
    if inspector.has_table("circle_prompts") and "options" in {c["name"] for c in inspector.get_columns("circle_prompts")}: 
        with op.batch_alter_table("circle_prompts") as batch:
            batch.drop_column("options")
