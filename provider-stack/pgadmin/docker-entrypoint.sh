#!/bin/sh
# Write the pgpass file from the injected TSDB_PASSWORD env var.
mkdir -p /var/lib/pgadmin
printf 'timescaledb:5432:*:postgres:%s\n' "${TSDB_PASSWORD:-changeme}" \
  > /var/lib/pgadmin/pgpassfile
chmod 600 /var/lib/pgadmin/pgpassfile
# Tell libpq where the passfile lives – bypasses pgAdmin's server-mode path remapping
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
        con = sqlite3.connect(DB, timeout=10)
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
            # password=NULL + save_password=0: pgAdmin skips decryption.
            # libpq uses PGPASSFILE env var (set above) for authentication.
            # save_password=1 + password=NULL: pgAdmin skips the preemptive
            # password dialog ("not save_password" condition is False) but
            # _decode_password is also skipped (encpass=NULL). libpq then uses
            # the PGPASSFILE env var for actual authentication.
            sql = (
                "UPDATE server SET "
                "  save_password=1, password=NULL, username='postgres',"
                "  passexec_cmd=NULL, passexec_expiration=NULL,"
                "  connection_params='{\"sslmode\": \"prefer\", \"passfile\": \"/var/lib/pgadmin/pgpassfile\"}'"
            )
            params = []
            if "shared" in server_cols:
                sql += ", shared=1, shared_username=?"
                params.append(EMAIL)
            sql += " WHERE id=?"
            params.append(sid)
            cur.execute(sql, params)
            print("[pgadmin-init] server id={}: passfile configured, shared=1".format(sid), flush=True)

        # ── sharedserver table ────────────────────────────────────────────────
        # For OIDC users pgAdmin uses the access-token as encryption key, so
        # any pre-encrypted password is unreadable. Clear password and let
        # libpq use PGPASSFILE env var directly.
        ss_rows = cur.execute(
            "SELECT id FROM sharedserver WHERE host='timescaledb' AND port=5432"
        ).fetchall()
        for (ss_id,) in ss_rows:
            existing = cur.execute(
                "SELECT username, save_password, password, connection_params FROM sharedserver WHERE id=?",
                (ss_id,)
            ).fetchone()
            import json as _json
            cp = _json.loads(existing[3]) if existing[3] else {}
            need_fix = (
                existing[0] != "postgres"
                or existing[1] != 1
                or existing[2] is not None
                or cp.get("passfile") != "/var/lib/pgadmin/pgpassfile"
            )
            if need_fix:
                cur.execute(
                    "UPDATE sharedserver SET username='postgres', save_password=1, password=NULL,"
                    "  connection_params='{\"sslmode\": \"prefer\", \"passfile\": \"/var/lib/pgadmin/pgpassfile\"}' WHERE id=?",
                    (ss_id,),
                )
                print("[pgadmin-init] sharedserver id={}: cleared password, username=postgres".format(ss_id), flush=True)

        con.commit()
        con.close()
    except Exception as e:
        print("[pgadmin-init] ERROR: {}".format(e), flush=True)

    time.sleep(30)
PYEOF
) &

exec /entrypoint.sh "$@"
