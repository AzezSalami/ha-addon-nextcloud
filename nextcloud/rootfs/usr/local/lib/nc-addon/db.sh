#!/usr/bin/env bash
# Database engine abstraction (MariaDB/MySQL and PostgreSQL). Source, do not execute.
#
# Globals the caller sets before using the helpers:
#   DBTYPE  mysql | pgsql        (Nextcloud's own dbtype names)
#   DBH DBP DBU DBN              host, port, user, database
# The password is passed through the environment (db_set_password), never on a command line.

db_default_port() { case "$1" in pgsql) echo 5432 ;; *) echo 3306 ;; esac; }

# db_kind_to_type <mariadb|postgresql> -> mysql|pgsql
db_kind_to_type() { case "$1" in postgresql|postgres|pgsql) echo pgsql ;; *) echo mysql ;; esac; }

db_set_password() { MYSQL_PWD="$1"; PGPASSWORD="$1"; export MYSQL_PWD PGPASSWORD; }

_psql() { PGOPTIONS='-c client_min_messages=warning' psql -X -q -At -v ON_ERROR_STOP=1 -h "$DBH" -p "$DBP" -U "$DBU" "$@"; }
_mysql() { mariadb --connect-timeout=10 -N -h "$DBH" -P "$DBP" -u "$DBU" "$@"; }

# db_ping_server: can we log in at all? (PostgreSQL: any of the target DB / postgres / template1)
db_ping_server() {
    case "$DBTYPE" in
        pgsql) local d
            for d in "$DBN" postgres template1; do _psql -d "$d" -c 'SELECT 1' >/dev/null 2>&1 && return 0; done
            return 1 ;;
        *) _mysql -e 'SELECT 1' >/dev/null 2>&1 ;;
    esac
}

# db_exists: does the target database exist and is it usable by this user?
db_exists() {
    case "$DBTYPE" in
        pgsql) _psql -d "$DBN" -c 'SELECT 1' >/dev/null 2>&1 ;;
        *) _mysql -e "USE \`$DBN\`" >/dev/null 2>&1 ;;
    esac
}

# db_oc_tables: number of Nextcloud tables (prefix oc_) in the target database.
db_oc_tables() {
    case "$DBTYPE" in
        pgsql) _psql -d "$DBN" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') AND table_name LIKE 'oc\\_%'" ;;
        *) _mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DBN' AND table_name LIKE 'oc\\_%'" ;;
    esac
}

# db_any_tables: number of tables of any kind in the target database.
db_any_tables() {
    case "$DBTYPE" in
        pgsql) _psql -d "$DBN" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')" ;;
        *) _mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DBN'" ;;
    esac
}

# db_dump: consistent plain-SQL dump on stdout.
db_dump() {
    case "$DBTYPE" in
        pgsql) pg_dump --no-owner --no-privileges -h "$DBH" -p "$DBP" -U "$DBU" -d "$DBN" ;;
        *) mariadb-dump --single-transaction --quick --default-character-set=utf8mb4 --routines -h "$DBH" -P "$DBP" -u "$DBU" "$DBN" ;;
    esac
}

# db_dump_complete: reads a dump on stdin, succeeds only if it carries the engine's completion marker.
db_dump_complete() {
    local tail_text
    tail_text="$(tail -n 8)"
    case "$tail_text" in
        *"Dump completed"*|*"PostgreSQL database dump complete"*) return 0 ;;
        *) return 1 ;;
    esac
}

# db_reset: remove everything in the target database so a dump can be loaded (restore only).
db_reset() {
    case "$DBTYPE" in
        pgsql)
            # Nextcloud connects as its own role (oc_admin) which owns its tables but not the schema, so the
            # schema itself cannot be dropped. Drop only what this role owns; grants stay intact.
            _psql -d "$DBN" -f - >/dev/null <<'SQL'
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT schemaname, tablename FROM pg_tables
             WHERE tableowner = current_user AND schemaname NOT IN ('pg_catalog', 'information_schema') LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', r.schemaname, r.tablename);
    END LOOP;
    FOR r IN SELECT schemaname, sequencename FROM pg_sequences
             WHERE sequenceowner = current_user AND schemaname NOT IN ('pg_catalog', 'information_schema') LOOP
        EXECUTE format('DROP SEQUENCE IF EXISTS %I.%I CASCADE', r.schemaname, r.sequencename);
    END LOOP;
END $$;
SQL
            ;;
        *) _mysql -e "DROP DATABASE \`$DBN\`; CREATE DATABASE \`$DBN\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" ;;
    esac
}

# db_load: load a plain-SQL dump from stdin.
db_load() {
    case "$DBTYPE" in
        pgsql) _psql -d "$DBN" -f - >/dev/null ;;
        *) _mysql "$DBN" ;;
    esac
}
