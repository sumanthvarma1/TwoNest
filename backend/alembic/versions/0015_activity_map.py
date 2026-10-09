"""Opt-in coarse map presence and participant-only meetup coordinates."""
from alembic import op
import sqlalchemy as sa
revision = "0015_activity_map"
down_revision = "0014_activity_requests"
branch_labels = None
depends_on = None

def upgrade():
    for table, columns in {
        "activity_availability": [sa.Column("latitude", sa.Float()), sa.Column("longitude", sa.Float()), sa.Column("show_on_map", sa.Boolean(), nullable=False, server_default=sa.false())],
        "activity_requests": [sa.Column("latitude", sa.Float()), sa.Column("longitude", sa.Float()), sa.Column("meeting_latitude", sa.Float()), sa.Column("meeting_longitude", sa.Float()), sa.Column("meeting_name", sa.String(200), nullable=False, server_default="")],
    }.items():
        existing = {column["name"] for column in sa.inspect(op.get_bind()).get_columns(table)}
        for column in columns:
            if column.name not in existing: op.add_column(table, column)

def downgrade():
    for table, columns in {"activity_availability": ["latitude", "longitude", "show_on_map"], "activity_requests": ["latitude", "longitude", "meeting_latitude", "meeting_longitude", "meeting_name"]}.items():
        with op.batch_alter_table(table) as batch:
            for name in columns: batch.drop_column(name)
