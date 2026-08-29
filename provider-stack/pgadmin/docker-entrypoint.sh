#!/bin/sh
# Write credentials so pgAdmin can connect to TimescaleDB without a password
# dialog. We use a PostgreSQL service file (pg_service.conf) – libpq resolves
# host, port, user, dbname and password from it.  pgAdmin passes only
# "service=cdm_admin" in the connection string; its own password
# encryption/decryption is bypassed entirely.
mkdir -p /var/lib/pgadmin

# ── pg_service.conf (libpq service file) ─────────────────────────
# libpq picks this up via the PGSERVICEFILE env var (set below).
cat > /var/lib/pgadmin/pg_service.conf << EOF
[cdm_admin]
host=timescaledb
port=5432
dbname=cdm
user=postgres
password=${TSDB_PASSWORD:-changeme}
sslmode=prefer
EOF
chmod 600 /var/lib/pgadmin/pg_service.conf
export PGSERVICEFILE=/var/lib/pgadmin/pg_service.conf

# ── pgpassfile (kept for direct psql/libpq calls) ────────────────
printf 'timescaledb:5432:*:postgres:%s\n' "${TSDB_PASSWORD:-changeme}" \
  > /var/lib/pgadmin/pgpassfile
chmod 600 /var/lib/pgadmin/pgpassfile
export PGPASSFILE=/var/lib/pgadmin/pgpassfile

# Background job: after pgAdmin has initialised the DB, ensure the TimescaleDB
# server is configured correctly on every start.
PGADMIN_EMAIL="${PGADMIN_DEFAULT_EMAIL:-admin@cdm.local}"
export PGADMIN_EMAIL
(
  DB=/var/lib/pgadmin/pgadmin4.db
  until [ -f "$DB" ]; do sleep 1; done
  sleep 3   # wait for schema migration to complete
  /venv/bin/python3 - <<'PYEOF'
import os, sqlite3, time

DB    = "/var/lib/pgadmin/pgadmin4.db"
EMAIL = os.environ.get("PGADMIN_EMAIL", "admin@cdm.local")

# Loop so newly-created sharedserver rows (from OIDC logins) get fixed too
while True:
    try:
        con = sqlite3.connect(DB, timeout=60)
        # WAL mode: allows pgAdmin and this script to access the DB concurrently
        con.execute("PRAGMA journal_mode=WAL")
        con.execute("PRAGMA busy_timeout=60000")
        cur = con.cursor()

        server_cols = [r[1] for r in cur.execute("PRAGMA table_info(server)").fetchall()]

        # ── server table ──────────────────────────────────────────────────────
        # Remove duplicates: keep only the lowest-id entry for timescaledb:5432
        rows = cur.execute(
            "SELECT id FROM server WHERE host='timescaledb' AND port=5432 ORDER BY id"
        ).fetchall()
        if len(rows) > 1:
            ids_to_del = [r[0] for r in rows[1:]]
            cur.execute(
                "DELETE FROM server WHERE id IN ({})".format(",".join("?" * len(ids_to_del))),
                ids_to_del,
            )
            print("[pgadmin-init] Removed {} duplicate(s)".format(len(ids_to_del)), flush=True)

        sid = rows[0][0] if rows else None
        if sid:
            # Use service=cdm_admin so libpq resolves host/port/user/password
            # from pg_service.conf (PGSERVICEFILE env var). pgAdmin's own
            # password encryption is bypassed: save_password=0, password=NULL,
            # connection_params={} → no prompt, libpq handles auth itself.
            sql = (
                "UPDATE server SET "
                "  save_password=0, password=NULL, username='postgres',"
                "  service='cdm_admin',"
                "  passexec_cmd=NULL, passexec_expiration=NULL,"
                "  connection_params='{}'"
            )
            params = []
            if "shared" in server_cols:
                # shared_username controls the PostgreSQL username that
                # pgAdmin uses when auto-creating a SharedServer entry for
                # a new OIDC user.  Must be 'postgres', NOT the pgAdmin
                # admin email, otherwise every shared-server entry gets the
                # email as the PG username → auth failure.
                sql += ", shared=1, shared_username='postgres'"
            sql += " WHERE id=?"
            params.append(sid)
            cur.execute(sql, params)
            print("[pgadmin-init] server id={}: service=cdm_admin configured, shared=1".format(sid), flush=True)

        # ── sharedserver table ────────────────────────────────────────────────
        # For OIDC users pgAdmin uses the access-token as encryption key, so
        # any pre-encrypted password is unreadable. Clear password and let
        # libpq use PGPASSFILE env var directly.
        ss_rows = cur.execute(
            "SELECT id FROM sharedserver WHERE host='timescaledb' AND port=5432"
        ).fetchall()
        for (ss_id,) in ss_rows:
            existing = cur.execute(
                "SELECT username, save_password, password, service FROM sharedserver WHERE id=?",
                (ss_id,)
            ).fetchone()
            need_fix = (
                existing[0] != "postgres"
                or existing[1] != 0
                or existing[2] is not None
                or existing[3] != "cdm_admin"
            )
            if need_fix:
                cur.execute(
                    "UPDATE sharedserver SET username='postgres', save_password=0, password=NULL,"
                    "  service='cdm_admin', connection_params='{}' WHERE id=?",
                    (ss_id,),
                )
                print("[pgadmin-init] sharedserver id={}: service=cdm_admin configured".format(ss_id), flush=True)

        con.commit()
        con.close()
    except Exception as e:
        print("[pgadmin-init] ERROR: {}".format(e), flush=True)
        time.sleep(10)  # shorter retry on error
        continue

    time.sleep(60)
PYEOF
) &

exec /entrypoint.sh "$@"
