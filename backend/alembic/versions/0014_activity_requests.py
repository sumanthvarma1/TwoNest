"""Persistent activity availability, requests, join decisions and group messages."""
from alembic import op
import sqlalchemy as sa

revision = "0014_activity_requests"
down_revision = "0013_guided_onboarding"
branch_labels = None
depends_on = None


def upgrade():
    existing = set(sa.inspect(op.get_bind()).get_table_names())
    if "activity_availability" not in existing:
        op.create_table("activity_availability",
            sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
            sa.Column("area", sa.String(100), nullable=False, server_default=""),
            sa.Column("categories", sa.JSON(), nullable=False),
            sa.Column("mode", sa.String(16), nullable=False, server_default="both"),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False))
    if "activity_requests" not in existing:
        op.create_table("activity_requests",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("host_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("category", sa.String(32), nullable=False),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("description", sa.Text(), nullable=False, server_default=""),
            sa.Column("mode", sa.String(16), nullable=False, server_default="in_person"),
            sa.Column("area", sa.String(100), nullable=False, server_default=""),
            sa.Column("meeting_details", sa.String(500), nullable=False, server_default=""),
            sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("companion_limit", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("status", sa.String(24), nullable=False, server_default="open"),
            sa.Column("revision", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
        for name in ("host_id", "starts_at", "expires_at"):
            op.create_index(f"ix_activity_requests_{name}", "activity_requests", [name])
    if "activity_joins" not in existing:
        op.create_table("activity_joins",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("request_id", sa.String(36), sa.ForeignKey("activity_requests.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("note", sa.String(300), nullable=False, server_default=""),
            sa.Column("status", sa.String(24), nullable=False, server_default="pending"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("request_id", "member_id"))
        for name in ("request_id", "member_id"):
            op.create_index(f"ix_activity_joins_{name}", "activity_joins", [name])
    if "activity_messages" not in existing:
        op.create_table("activity_messages",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("request_id", sa.String(36), sa.ForeignKey("activity_requests.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sender_id", sa.String(36), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
        for name in ("request_id", "sender_id"):
            op.create_index(f"ix_activity_messages_{name}", "activity_messages", [name])


def downgrade():
    for table in ("activity_messages", "activity_joins", "activity_requests", "activity_availability"):
        op.drop_table(table)
