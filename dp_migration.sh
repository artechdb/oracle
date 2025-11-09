#!/usr/bin/env bash
# =============================================================================
# dp_migrate.sh (v4ae) - Oracle 19c Data Pump migration & compare toolkit
# =============================================================================
# Features
# - Export / Import (FULL, SCHEMAS, TABLESPACES, TABLES)
# - Import prompts for DIRECTORY path & dumpfile pattern; shows parfile to confirm
# - DDL extraction for users/roles/profiles/privs/sequences/synonyms/tablespaces/etc.
# - Compare Source vs Target (no DB link):
#     A) EXTERNAL engine (TARGET external tables; needs DIRECTORY/NAS)
#     B) FILE engine     (NAS CSVs diff; needs DIRECTORY/NAS)
#     C) LOCAL/JUMPER    (no NAS, no external tables; spools locally & diffs)
# - HTML reports + optional email (INLINE body)
# - DRY_RUN_ONLY for destructive actions
# - Rich debug logging
#
# Usage:
#   ./dp_migrate_v4ae.sh dp_migrate.conf
#
# Example dp_migrate.conf keys:
#   SRC_EZCONNECT=host1:1521/ORCLCDB
#   TGT_EZCONNECT=host2:1521/ORCLCDB
#   SYS_PASSWORD=MySysPass
#   NAS_PATH=/mnt/dp   # used for EXTERNAL/FILE engines
#   DUMPFILE_PREFIX=projectX
#   PARALLEL=4
#   COMPRESSION=METADATA_ONLY
#   TABLE_EXISTS_ACTION=APPEND
#   SKIP_SCHEMAS=APPQOSSYS,AUDSYS,GSMADMIN_INTERNAL
#   SKIP_TABLESPACES=SYSTEM,SYSAUX,TEMP,UNDOTBS1,UNDOTBS2
#   REPORT_EMAILS=dba@example.com,lead@example.com
#   MAIL_ENABLED=Y
#   MAIL_FROM=noreply@example.com
#   MAIL_SUBJECT_PREFIX=[Oracle Compare]
#   EXACT_ROWCOUNT=N
#   LOCAL_COMPARE_DIR=/tmp/dp_compare
#   COMPARE_DIR=/tmp/dp_reports
#   COMPARE_ENGINE=EXTERNAL  # or FILE or LOCAL
#   MAIL_METHOD=auto         # auto|sendmail|mailutils|bsdmail|mailx
# =============================================================================

set -euo pipefail

CONFIG_FILE="${1:-dp_migrate.conf}"
SCRIPT_NAME="$(basename "$0")"
RUN_ID="$(date +%Y%m%d_%H%M%S)"

# ------------------------------ Paths -----------------------------------------
WORK_DIR="${WORK_DIR:-/tmp/dp_migrate_${RUN_ID}}"
LOG_DIR="${LOG_DIR:-${WORK_DIR}/logs}"
PAR_DIR="${PAR_DIR:-${WORK_DIR}/parfiles}"
DDL_DIR="${DDL_DIR:-${WORK_DIR}/ddls}"
COMPARE_DIR="${COMPARE_DIR:-${WORK_DIR}/compare}"
COMMON_DIR_NAME="${COMMON_DIR_NAME:-DP_DIR}"     # DB DIRECTORY object name (for EXTERNAL/FILE engines)
LOCAL_COMPARE_DIR="${LOCAL_COMPARE_DIR:-/tmp/dp_compare}"  # local CSVs when in LOCAL engine

mkdir -p "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$DDL_DIR" "$COMPARE_DIR" "$LOCAL_COMPARE_DIR"

# ------------------------ Pretty print & debug helpers -------------------------
ce()   { printf "%b\n" "$*"; }
ok()   { ce "\e[32m? $*\e[0m"; }
warn() { ce "\e[33m! $*\e[0m"; }
err()  { ce "\e[31m? $*\e[0m"; }
DEBUG="${DEBUG:-Y}"
debug() { if [[ "${DEBUG^^}" == "Y" ]]; then ce "\e[36m[DEBUG]\e[0m $*"; fi; }

# ------------------------------ Load Config -----------------------------------
[[ -f "$CONFIG_FILE" ]] || { err "Config file not found: $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

need_vars=( SRC_EZCONNECT TGT_EZCONNECT SYS_PASSWORD DUMPFILE_PREFIX )
for v in "${need_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { err "Missing required config variable: $v"; exit 1; }
done

# ----------------------------- Defaults ---------------------------------------
PARALLEL="${PARALLEL:-4}"
COMPRESSION="${COMPRESSION:-METADATA_ONLY}"
ENCRYPTION_PASSWORD="${ENCRYPTION_PASSWORD:-}"
TABLE_EXISTS_ACTION="${TABLE_EXISTS_ACTION:-APPEND}"
REMAP_SCHEMA="${REMAP_SCHEMA:-}"
REMAP_TABLESPACE="${REMAP_TABLESPACE:-}"
INCLUDE="${INCLUDE:-}"
EXCLUDE="${EXCLUDE:-}"
FLASHBACK_SCN="${FLASHBACK_SCN:-}"
FLASHBACK_TIME="${FLASHBACK_TIME:-}"
ESTIMATE_ONLY="${ESTIMATE_ONLY:-N}"
EXPDP_TRACE="${EXPDP_TRACE:-}"
IMPDP_TRACE="${IMPDP_TRACE:-}"

SCHEMAS_LIST_EXP="${SCHEMAS_LIST_EXP:-}"
SCHEMAS_LIST_IMP="${SCHEMAS_LIST_IMP:-}"

SKIP_SCHEMAS="${SKIP_SCHEMAS:-}"
SKIP_TABLESPACES="${SKIP_TABLESPACES:-SYSTEM,SYSAUX,TEMP,UNDOTBS1,UNDOTBS2}"

DRY_RUN_ONLY="${DRY_RUN_ONLY:-N}"

REPORT_EMAILS="${REPORT_EMAILS:-}"
MAIL_ENABLED="${MAIL_ENABLED:-Y}"
MAIL_FROM="${MAIL_FROM:-noreply@localhost}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[Oracle Compare]}"
MAIL_METHOD="${MAIL_METHOD:-auto}"

COMPARE_ENGINE="${COMPARE_ENGINE:-EXTERNAL}"  # EXTERNAL | FILE | LOCAL
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"

NAS_PATH="${NAS_PATH:-}"  # optional; required for EXTERNAL/FILE engines

ok "Using config: $CONFIG_FILE"
ok "Work: $WORK_DIR | Logs: $LOG_DIR | Parfiles: $PAR_DIR | DDLs: $DDL_DIR | Compare: $COMPARE_DIR"

# ---------------------------- Pre-flight checks --------------------------------
for b in sqlplus expdp impdp; do
  command -v "$b" >/dev/null 2>&1 || { err "Missing required binary: $b"; exit 1; }
done

mask_pwd() { sed 's#[^/"]\{1,\}@#***@#g' | sed 's#sys/[^@]*@#sys/****@#g'; }

# ------------------------------- SQL helper -----------------------------------
run_sql() {
  local ez="$1"; shift
  local tag="${1:-sql}"; shift || true
  local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql(tag=$tag) on ${ez} -> $logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
${sql}
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then
    err "SQL error: ${tag} (see $logf)"
    tail -n 120 "$logf" | mask_pwd | sed 's/^/  /'
    exit 1
  fi
  ok "SQL ok: ${tag}"
}

# Spool query results to a local file (client-side), not using DIRECTORY/UTL_FILE
run_sql_spool_local() {
  local ez="$1"; shift
  local tag="$1"; shift
  local out="$1"; shift
  local body="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_spool_local(tag=$tag) -> spool $out"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGESIZE 0 LINESIZE 4000 LONG 1000000 LONGCHUNKSIZE 1000000 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
SPOOL $out
${body}
SPOOL OFF
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then
    err "SQL error: ${tag} (see $logf)"
    tail -n 120 "$logf" | mask_pwd | sed 's/^/  /'
    exit 1
  fi
  ok "Spool ok: $out"
}

# ------------------------------- Mail helpers (INLINE HTML) -------------------
# Picks a working mailer automatically and sends the HTML file INLINE as body.
detect_mail_stack() {
  local forced="${MAIL_METHOD:-auto}"
  case "${forced}" in
    sendmail) command -v sendmail >/dev/null && { echo sendmail; return; } ;;
    mailutils) (mail --version 2>/dev/null | grep -qi "mailutils") && { echo mailutils; return; } ;;
    bsdmail)   (mail -V 2>/dev/null | grep -qi "bsd") && { echo bsdmail; return; } ;;
    mailx)     command -v mailx >/dev/null && { echo mailx; return; } ;;
    auto|*)    : ;;
  esac
  if command -v sendmail >/dev/null 2>&1; then echo sendmail; return; fi
  if mail --version 2>/dev/null | grep -qi "mailutils"; then echo mailutils; return; fi
  if mail -V 2>/dev/null | grep -qi "bsd"; then echo bsdmail; return; fi
  if command -v mailx >/dev/null 2>&1; then echo mailx; return; fi
  echo none
}

email_inline_html() {
  local file="$1" subject="$2"
  [[ "${MAIL_ENABLED^^}" != "Y" ]] && { warn "MAIL_ENABLED!=Y; skip email."; return 0; }
  [[ -z "${REPORT_EMAILS}" ]] && { warn "REPORT_EMAILS empty; skip email."; return 0; }
  [[ ! -f "$file" ]] && { warn "email_inline_html: $file not found"; return 1; }

  local method; method="$(detect_mail_stack)"
  debug "Email stack detected: ${method}"

  case "$method" in
    sendmail)
      { echo "From: ${MAIL_FROM}"
        echo "To: ${REPORT_EMAILS}"
        echo "Subject: ${subject}"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo
        cat "$file"
      } | sendmail -t || { warn "sendmail failed"; return 1; }
      ;;
    mailutils)
      mail -a "From: ${MAIL_FROM}" \
           -a "MIME-Version: 1.0" \
           -a "Content-Type: text/html; charset=UTF-8" \
           -s "${subject}" ${REPORT_EMAILS} < "$file" \
        || { warn "mail (mailutils) send failed"; return 1; }
      ;;
    bsdmail)
      mail -a "From: ${MAIL_FROM}" \
           -a "MIME-Version: 1.0" \
           -a "Content-Type: text/html; charset=UTF-8" \
           -s "${subject}" ${REPORT_EMAILS} < "$file" \
        || { warn "mail (BSD) send failed"; return 1; }
      ;;
    mailx)
      if mailx -V 2>&1 | grep -qiE "heirloom|s-nail|nail"; then
        if mailx -a "Content-Type: text/html" -s test "$MAIL_FROM" </dev/null 2>&1 | grep -qi "unknown option"; then
          mailx -r "$MAIL_FROM" -s "${subject}" ${REPORT_EMAILS} < "$file" \
            || { warn "mailx send failed"; return 1; }
        else
          mailx -r "$MAIL_FROM" -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" ${REPORT_EMAILS} < "$file" \
            || { warn "mailx send failed"; return 1; }
        fi
      else
        mailx -s "${subject}" ${REPORT_EMAILS} < "$file" \
          || { warn "mailx (generic) send failed"; return 1; }
      fi
      ;;
    none)
      warn "No supported mailer (sendmail/mail/mailx) found; skipping email."
      return 1
      ;;
  esac

  ok "Inline email sent to ${REPORT_EMAILS} via ${method}"
}

# ----------------------- DIRECTORY helpers (for EXTERNAL/FILE) ----------------
ensure_directory_object() {
  local ez="$1" host_tag="$2" dir_name="${3:-$COMMON_DIR_NAME}" dir_path="$NAS_PATH"
  [[ -z "$dir_path" ]] && { err "NAS_PATH not set but required for this engine."; exit 1; }
  debug "ensure_directory_object(${dir_name}) on ${host_tag} -> ${ez}, path=${dir_path}"
  run_sql "$ez" "create_dir_${host_tag}" "
BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY ${dir_name} AS ''${dir_path}''';
  BEGIN EXECUTE IMMEDIATE 'GRANT READ,WRITE ON DIRECTORY ${dir_name} TO PUBLIC'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"
}

validate_directory_on_db() {
  local ez="$1" tag="$2"
  local logtag="dircheck_${tag}"
  debug "validate_directory_on_db(${COMMON_DIR_NAME}) on ${tag} -> ${ez}"
  run_sql "$ez" "$logtag" "
SET SERVEROUTPUT ON
DECLARE
  p VARCHAR2(4000);
  f UTL_FILE.FILE_TYPE;
  fname VARCHAR2(200) := '__dp_dir_test_${RUN_ID}.html';
BEGIN
  SELECT directory_path INTO p FROM all_directories WHERE directory_name=UPPER('${COMMON_DIR_NAME}');
  DBMS_OUTPUT.PUT_LINE('DIRECTORY=${COMMON_DIR_NAME} PATH='||p);
  BEGIN
    f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'), fname, 'W', 32767);
    UTL_FILE.PUT_LINE(f, '<html><body>UTL_FILE write test '||TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS')||'</body></html>');
    UTL_FILE.FCLOSE(f);
    DBMS_OUTPUT.PUT_LINE('UTL_FILE_WRITE=OK FILE='||fname);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('UTL_FILE_WRITE=ERROR '||SQLERRM);
  END;
END;
/
"
}

# Drop a table if it exists (used before creating external tables)
drop_table_if_exists() {
  local ez="$1" tname="${2^^}"
  run_sql "$ez" "drop_${tname}_${RUN_ID}" "
DECLARE
  v_cnt PLS_INTEGER;
  v_stmt VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_cnt
    FROM all_tables
   WHERE owner = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
     AND table_name = UPPER('${tname}');
  IF v_cnt > 0 THEN
     BEGIN EXECUTE IMMEDIATE 'DROP TABLE '||UPPER('${tname}')||' PURGE';
     EXCEPTION WHEN OTHERS THEN EXECUTE IMMEDIATE 'DROP TABLE '||UPPER('${tname}'); END;
  END IF;
END;
/
"
}

# -------------------------- Data Pump Core ------------------------------------
dp_run() {
  local tool="$1" ez="$2" pf="$3" tag="$4"
  local client_log="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.client.log"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  debug "dp_run(${tool}) tag=${tag} parfile=${pf} ez=${ez}"
  {
    echo "---- ${tool} environment ----"
    echo "date: $(date)"
    echo "host: $(hostname)"
    echo "ORACLE_HOME: ${ORACLE_HOME:-<unset>}"
    echo "PATH: $PATH"
    echo "which ${tool}: $(command -v $tool || echo not found)"
    echo "version:"; $tool -V || true
    echo "---- parfile (${pf}) ----"
    [[ -f "$pf" ]] && sed -E 's/(encryption_password=).*/\1*****/I' "$pf" || echo "<parfile not found>"
  } > "$client_log" 2>&1

  set +e
  ( set -o pipefail; $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} )
  local rc=$?
  set -e
  [[ $rc -ne 0 ]] && { err "[${tool}] FAILED (rc=$rc) — see ${client_log}"; exit $rc; }
  ok "[${tool}] SUCCESS — see ${client_log}"
}

par_common() {
  local mode="$1" tag="$2"
  local pf="${PAR_DIR}/${tag}_${RUN_ID}.par"
  debug "par_common(mode=${mode}, tag=${tag}) -> ${pf}"
  {
    echo "directory=${COMMON_DIR_NAME}"
    echo "logfile=${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log"
    echo "parallel=${PARALLEL}"
  } > "$pf"
  if [[ "$mode" == "expdp" ]]; then
    {
      echo "dumpfile=${DUMPFILE_PREFIX}_${tag}_${RUN_ID}_%U.dmp"
      echo "compression=${COMPRESSION}"
      [[ -n "$FLASHBACK_SCN"  ]] && echo "flashback_scn=${FLASHBACK_SCN}"
      [[ -n "$FLASHBACK_TIME" ]] && echo "flashback_time=${FLASHBACK_TIME}"
      [[ -n "$INCLUDE"        ]] && echo "include=${INCLUDE}"
      [[ -n "$EXCLUDE"        ]] && echo "exclude=${EXCLUDE}"
      [[ "${ESTIMATE_ONLY^^}" == "Y" ]] && echo "estimate_only=Y"
      [[ -n "$ENCRYPTION_PASSWORD" ]] && { echo "encryption=encrypt_password"; echo "encryption_password=${ENCRYPTION_PASSWORD}"; }
      [[ -n "$EXPDP_TRACE" ]] && echo "trace=${EXPDP_TRACE}"
    } >> "$pf"
  else
    {
      echo "table_exists_action=${TABLE_EXISTS_ACTION}"
      [[ -n "$REMAP_SCHEMA"     ]] && echo "remap_schema=${REMAP_SCHEMA}"
      [[ -n "$REMAP_TABLESPACE" ]] && echo "remap_tablespace=${REMAP_TABLESPACE}"
      [[ -n "$INCLUDE"          ]] && echo "include=${INCLUDE}"
      [[ -n "$EXCLUDE"          ]] && echo "exclude=${EXCLUDE}"
      [[ -n "$ENCRYPTION_PASSWORD" ]] && echo "encryption_password=${ENCRYPTION_PASSWORD}"
      [[ -n "$IMPDP_TRACE" ]] && echo "trace=${IMPDP_TRACE}"
    } >> "$pf"
  fi
  echo "$pf"
}

confirm_edit_value() {
  local label="$1" val="${2:-}" ans
  echo "${label}: ${val}"
  read -rp "Use this value? (Y to accept, N to edit) [Y/N]: " ans
  if [[ "${ans^^}" == "N" ]]; then
    read -rp "Enter new ${label}: " val
  fi
  echo "$val"
}

# ------------------------------ EXPORT MENUS ----------------------------------
get_nonmaintained_schemas() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql "$SRC_EZCONNECT" "list_nonmaint_users_${RUN_ID}" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS ( SELECT username FROM dba_users WHERE oracle_maintained='N'${pred} )
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/list_nonmaint_users_${RUN_ID}.log"
}

get_nonmaintained_schemas_tgt() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql "$TGT_EZCONNECT" "tgt_nonmaint_users_${RUN_ID}" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS ( SELECT username FROM dba_users WHERE oracle_maintained='N'${pred} )
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/tgt_nonmaint_users_${RUN_ID}.log"
}

exp_full_menu() {
  while true; do
    cat <<'EOS'
Export FULL (choose content):
  1) metadata_only  (CONTENT=METADATA_ONLY)
  2) full           (CONTENT=ALL)
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; pf=$(par_common expdp "exp_full_meta"); { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_meta" ;;
      2) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; pf=$(par_common expdp "exp_full_all");  { echo "full=Y"; echo "content=ALL"; }           >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_all"  ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_schemas_menu() {
  while true; do
    cat <<'EOS'
Export SCHEMAS:
  1) All accounts (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) User input or value from conf (SCHEMAS_LIST_EXP) with confirmation
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; schemas="$(get_nonmaintained_schemas)"; schemas="$(confirm_edit_value "Schemas" "$schemas")"; pf=$(par_common expdp "exp_schemas_auto"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_auto" ;;
      2) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; init="${SCHEMAS_LIST_EXP:-}"; [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init; schemas="$(confirm_edit_value "Schemas" "$init")"; pf=$(par_common expdp "exp_schemas_user"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_user" ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_tablespaces() {
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tablespaces (comma-separated): " tbs
  pf=$(par_common expdp "exp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tbs"
}

exp_tables() {
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  pf=$(par_common expdp "exp_tables")
  echo "tables=${tabs}" >> "$pf"
  dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tables"
}

export_menu() {
  while true; do
    cat <<'EOS'
Export Menu:
  1) FULL database (metadata_only / full)
  2) SCHEMAS      (all non-maintained / user|conf)
  3) TABLESPACES  (transport)
  4) TABLES
  5) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) exp_full_menu ;;
      2) exp_schemas_menu ;;
      3) exp_tablespaces ;;
      4) exp_tables ;;
      5) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

# ------------------------------ IMPORT HELPERS --------------------------------
prompt_import_dump_location() {
  local def_name="${COMMON_DIR_NAME:-DP_DIR}"
  read -rp "Target DB DIRECTORY object name to use/create [${def_name}]: " dname
  IMPORT_DIR_NAME="${dname:-$def_name}"

  echo "Enter absolute OS path on the TARGET database server where dumpfiles (.dmp) are stored."
  echo "Example: /u02/exports/prod_2025_11_01"
  read -rp "Path: " IMPORT_DIR_PATH
  [[ -z "$IMPORT_DIR_PATH" ]] && { err "Path cannot be empty."; return 1; }

  echo "Enter dumpfile pattern or list (as impdp expects)."
  echo "Examples: dumpfile%U.dmp   OR   exp_sunday_%U.dmp   OR   file1.dmp,file2.dmp"
  read -rp "Dumpfile(s): " IMPORT_DUMPFILE_PATTERN
  [[ -z "$IMPORT_DUMPFILE_PATTERN" ]] && { err "Dumpfile pattern cannot be empty."; return 1; }

  debug "Creating/refreshing DIRECTORY ${IMPORT_DIR_NAME} => ${IMPORT_DIR_PATH} on TARGET"
  run_sql "$TGT_EZCONNECT" "import_dir_create_${RUN_ID}" "
BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY ${IMPORT_DIR_NAME} AS ''${IMPORT_DIR_PATH}''';
  BEGIN EXECUTE IMMEDIATE 'GRANT READ,WRITE ON DIRECTORY ${IMPORT_DIR_NAME} TO PUBLIC'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"
  ok "Directory ${IMPORT_DIR_NAME} -> ${IMPORT_DIR_PATH} is ready on TARGET"
}

par_common_imp_with_dump() {
  local tag="$1"
  local pf="${PAR_DIR}/${tag}_${RUN_ID}.par"
  debug "Creating impdp parfile: ${pf}"
  {
    echo "directory=${IMPORT_DIR_NAME}"
    echo "dumpfile=${IMPORT_DUMPFILE_PATTERN}"
    echo "logfile=${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log"
    echo "parallel=${PARALLEL}"
    echo "table_exists_action=${TABLE_EXISTS_ACTION}"
    [[ -n "$REMAP_SCHEMA"     ]] && echo "remap_schema=${REMAP_SCHEMA}"
    [[ -n "$REMAP_TABLESPACE" ]] && echo "remap_tablespace=${REMAP_TABLESPACE}"
    [[ -n "$INCLUDE"          ]] && echo "include=${INCLUDE}"
    [[ -n "$EXCLUDE"          ]] && echo "exclude=${EXCLUDE}"
    [[ -n "$ENCRYPTION_PASSWORD" ]] && echo "encryption_password=${ENCRYPTION_PASSWORD}"
    [[ -n "$IMPDP_TRACE"      ]] && echo "trace=${IMPDP_TRACE}"
  } > "$pf"
  echo "$pf"
}

show_and_confirm_parfile() {
  local pf="$1"
  echo "----- PARFILE: ${pf} -----"
  sed -E 's/(encryption_password=).*/\1*****/I' "$pf"
  echo "---------------------------"
  local ans
  read -rp "Proceed with impdp using this parfile? [Y/N]: " ans
  [[ "${ans^^}" == "Y" ]] && return 0 || return 1
}

# ------------------------------- IMPORT MENUS ---------------------------------
imp_full_menu() {
  while true; do
    cat <<'EOS'
Import FULL (choose content):
  1) metadata_only  (CONTENT=METADATA_ONLY)
  2) full           (CONTENT=ALL)
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        pf=$(par_common_imp_with_dump "imp_full_meta"); { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"
        if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_meta"; else warn "Cancelled."; fi
        ;;
      2)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        pf=$(par_common_imp_with_dump "imp_full_all");  { echo "full=Y"; echo "content=ALL"; } >> "$pf"
        if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_all"; else warn "Cancelled."; fi
        ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_schemas_menu() {
  while true; do
    cat <<'EOS'
Import SCHEMAS:
  1) All accounts (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) User input or value from conf (SCHEMAS_LIST_IMP / SCHEMAS_LIST_EXP) with confirmation
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        schemas="$(get_nonmaintained_schemas_tgt)"
        schemas="$(confirm_edit_value "Schemas to import" "$schemas")"
        pf=$(par_common_imp_with_dump "imp_schemas_auto"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_auto"; else warn "Cancelled."; fi
        ;;
      2)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        init="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"
        [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init
        schemas="$(confirm_edit_value "Schemas to import" "$init")"
        pf=$(par_common_imp_with_dump "imp_schemas_user"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_user"; else warn "Cancelled."; fi
        ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_tablespaces() {
  prompt_import_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Transported tablespaces (comma-separated): " tbs
  pf=$(par_common_imp_with_dump "imp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tbs"; else warn "Cancelled."; fi
}

imp_tables() {
  prompt_import_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  pf=$(par_common_imp_with_dump "imp_tables")
  echo "tables=${tabs}" >> "$pf"
  if show_and_confirm_parfile "$pf"; then dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tables"; else warn "Cancelled."; fi
}

import_menu() {
  while true; do
    cat <<'EOS'
Import Menu
  1) FULL database
  2) SCHEMAS
  3) TABLESPACES
  4) TABLES
  5) Cleanup (drop users/objects)  [Dangerous; honors DRY_RUN_ONLY]
  6) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) imp_full_menu ;;
      2) imp_schemas_menu ;;
      3) imp_tablespaces ;;
      4) imp_tables ;;
      5) import_cleanup_menu ;;
      6) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

# ------------------------- Import Cleanup (TARGET) -----------------------------
csv_to_inlist() {
  local csv="${1:-}" out="" tok
  IFS=',' read -r -a arr <<< "$csv"
  for tok in "${arr[@]}"; do
    tok="$(echo "$tok" | awk '{$1=$1;print}')"
    [[ -z "$tok" ]] && continue
    tok="${tok^^}"
    out+="${out:+,}'${tok}'"
  done
  echo "$out"
}

report_user_list() {
  local tag="$1" inlist="${2:-}" q
  if [[ -z "$inlist" ]]; then
    q="SELECT username FROM dba_users WHERE oracle_maintained='N' ORDER BY username"
  else
    q="SELECT username FROM dba_users WHERE oracle_maintained='N' AND UPPER(username) IN (${inlist}) ORDER BY username"
  fi
  run_sql "$TGT_EZCONNECT" "${tag}" "
SET HEADING ON PAGES 200 LINES 200 FEEDBACK ON
COLUMN USERNAME FORMAT A30
PROMPT === USER LIST (TARGET) ===
${q};
PROMPT === TOTAL USERS ===
SELECT COUNT(*) AS cnt FROM (${q});
/
"
}

report_object_counts() {
  local tag="$1" inlist="${2:-}" owner_pred
  if [[ -z "$inlist" ]]; then
    owner_pred="owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')"
  else
    owner_pred="UPPER(owner) IN (${inlist})"
  fi

  run_sql "$TGT_EZCONNECT" "${tag}" "
SET HEADING ON PAGES 200 LINES 200 FEEDBACK ON
COLUMN OWNER FORMAT A30
COLUMN OBJECT_TYPE FORMAT A25
PROMPT === OBJECT COUNTS BY OWNER & TYPE (TARGET) ===
SELECT owner, object_type, COUNT(*) AS cnt
FROM dba_objects
WHERE ${owner_pred}
  AND object_name NOT LIKE 'BIN$%'
GROUP BY owner, object_type
ORDER BY owner, object_type;
PROMPT === TOTAL OBJECTS (TARGET) ===
SELECT COUNT(*) AS total_objects
FROM dba_objects
WHERE ${owner_pred}
  AND object_name NOT LIKE 'BIN$%';
/
"
}

drop_users_cascade_all_nonmaint() {
  local users_csv; users_csv="$(get_nonmaintained_schemas_tgt)"
  local inlist; inlist="$(csv_to_inlist "$users_csv")"

  report_user_list "dry_users_all" "$inlist"
  report_object_counts "dry_objs_all" "$inlist"

  if [[ "${DRY_RUN_ONLY^^}" == "Y" ]]; then
    warn "DRY_RUN_ONLY=Y: Skipping DROP USER execution."
    return
  fi

  local confirm
  echo "This will DROP ALL above users (CASCADE) on TARGET: ${TGT_EZCONNECT}"
  read -rp "Type YES to proceed (anything else cancels): " confirm
  [[ "$confirm" == "YES" ]] || { warn "Cancelled."; return; }

  run_sql "$TGT_EZCONNECT" "drop_users_all" "
SET SERVEROUTPUT ON
DECLARE v_stmt VARCHAR2(4000);
BEGIN
  FOR r IN (SELECT username FROM dba_users WHERE oracle_maintained='N' AND UPPER(username) IN (${inlist}) ORDER BY username) LOOP
    v_stmt := 'DROP USER '||r.username||' CASCADE';
    BEGIN EXECUTE IMMEDIATE v_stmt; DBMS_OUTPUT.PUT_LINE('DROPPED USER: '||r.username);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAILED: '||v_stmt||' - '||SQLERRM); END;
  END LOOP;
END;
/
"
}

drop_objects_for_owners_plsql() {
  local inlist="$1"
  run_sql "$TGT_EZCONNECT" "drop_objs_block_${RUN_ID}" "
SET SERVEROUTPUT ON
DECLARE
  PROCEDURE exec_ddl(p_sql IN VARCHAR2) IS BEGIN EXECUTE IMMEDIATE p_sql; EXCEPTION WHEN OTHERS THEN NULL; END;
  PROCEDURE drop_for_owner(p_owner IN VARCHAR2) IS
  BEGIN
    FOR r IN (SELECT object_name FROM dba_objects WHERE owner=p_owner AND object_type='SYNONYM') LOOP exec_ddl('DROP SYNONYM '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT mview_name object_name FROM dba_mviews WHERE owner=p_owner) LOOP exec_ddl('DROP MATERIALIZED VIEW '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT view_name object_name FROM dba_views WHERE owner=p_owner) LOOP exec_ddl('DROP VIEW '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT trigger_name object_name FROM dba_triggers WHERE table_owner=p_owner) LOOP exec_ddl('DROP TRIGGER '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT object_name FROM dba_objects WHERE owner=p_owner AND object_type='PACKAGE BODY') LOOP exec_ddl('DROP PACKAGE BODY '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT object_name FROM dba_objects WHERE owner=p_owner AND object_type='PACKAGE') LOOP exec_ddl('DROP PACKAGE '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT procedure_name object_name FROM dba_procedures WHERE owner=p_owner AND object_type='PROCEDURE') LOOP exec_ddl('DROP PROCEDURE '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT object_name FROM dba_objects WHERE owner=p_owner AND object_type='FUNCTION') LOOP exec_ddl('DROP FUNCTION '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT type_name object_name FROM dba_types WHERE owner=p_owner) LOOP exec_ddl('DROP TYPE '||p_owner||'.\"'||r.object_name||'\"' || ' FORCE'); END LOOP;
    FOR r IN (SELECT sequence_name object_name FROM dba_sequences WHERE sequence_owner=p_owner) LOOP exec_ddl('DROP SEQUENCE '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT index_name object_name FROM dba_indexes WHERE owner=p_owner AND table_owner=p_owner) LOOP exec_ddl('DROP INDEX '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
    FOR r IN (SELECT table_name object_name FROM dba_tables WHERE owner=p_owner) LOOP exec_ddl('DROP TABLE '||p_owner||'.\"'||r.object_name||'\" CASCADE CONSTRAINTS PURGE'); END LOOP;
  END;
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE oracle_maintained='N' AND UPPER(username) IN (${inlist}) ORDER BY username) LOOP
    DBMS_OUTPUT.PUT_LINE('Dropping objects for '||u.username);
    drop_for_owner(u.username);
  END LOOP;
END;
/
"
}

drop_objects_all_nonmaint() {
  local users_csv; users_csv="$(get_nonmaintained_schemas_tgt)"
  local inlist; inlist="$(csv_to_inlist "$users_csv")"

  report_user_list "dry_users_obj_all" "$inlist"
  report_object_counts "dry_objs_obj_all" "$inlist"

  if [[ "${DRY_RUN_ONLY^^}" == "Y" ]]; then
    warn "DRY_RUN_ONLY=Y: Skipping DROP OBJECTS execution."
    return
  fi
  local confirm
  echo "This will DROP ALL OBJECTS for the above owners on TARGET (users remain)."
  read -rp "Type YES to proceed (anything else cancels): " confirm
  [[ "$confirm" == "YES" ]] || { warn "Cancelled."; return; }
  drop_objects_for_owners_plsql "$inlist"
}

drop_users_cascade_listed() {
  local base="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"
  [[ -z "$base" ]] && read -rp "Enter schemas to DROP (comma-separated): " base
  local schemas; schemas="$(confirm_edit_value "Drop these users" "$base")"
  local inlist; inlist="$(csv_to_inlist "$schemas")"

  report_user_list "dry_users_listed" "$inlist"
  report_object_counts "dry_objs_listed" "$inlist"

  if [[ "${DRY_RUN_ONLY^^}" == "Y" ]]; then
    warn "DRY_RUN_ONLY=Y: Skipping DROP USER execution."
    return
  fi
  local confirm
  echo "This will DROP these users CASCADE on TARGET: ${schemas}"
  read -rp "Type YES to proceed (anything else cancels): " confirm
  [[ "$confirm" == "YES" ]] || { warn "Cancelled."; return; }

  run_sql "$TGT_EZCONNECT" "drop_users_listed" "
SET SERVEROUTPUT ON
DECLARE v_stmt VARCHAR2(4000);
BEGIN
  FOR r IN (
    SELECT username FROM dba_users
    WHERE oracle_maintained='N' AND UPPER(username) IN (${inlist})
    ORDER BY username
  ) LOOP
    v_stmt := 'DROP USER '||r.username||' CASCADE';
    BEGIN EXECUTE IMMEDIATE v_stmt; DBMS_OUTPUT.PUT_LINE('DROPPED USER: '||r.username);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAILED: '||v_stmt||' - '||SQLERRM); END;
  END LOOP;
END;
/
"
}

drop_objects_listed() {
  local base="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"
  [[ -z "$base" ]] && read -rp "Enter schemas (owners) to purge objects for (comma-separated): " base
  local owners; owners="$(confirm_edit_value "Purge objects for owners" "$base")"
  local inlist; inlist="$(csv_to_inlist "$owners")"

  report_user_list "dry_users_obj_listed" "$inlist"
  report_object_counts "dry_objs_obj_listed" "$inlist"

  if [[ "${DRY_RUN_ONLY^^}" == "Y" ]]; then
    warn "DRY_RUN_ONLY=Y: Skipping DROP OBJECTS execution."
    return
  fi
  local confirm
  echo "This will DROP ALL OBJECTS for these owners on TARGET (users remain): ${owners}"
  read -rp "Type YES to proceed (anything else cancels): " confirm
  [[ "$confirm" == "YES" ]] || { warn "Cancelled."; return; }

  drop_objects_for_owners_plsql "$inlist"
}

import_cleanup_menu() {
  while true; do
    cat <<EOS
Import Cleanup (TARGET) - DANGEROUS  $( [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && echo "[DRY_RUN_ONLY=Y]" )
  1) Drop ALL users CASCADE (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) Drop ALL objects of ALL users (exclude Oracle-maintained; honors SKIP_SCHEMAS) [users kept]
  3) Drop users CASCADE listed in imp schemas (SCHEMAS_LIST_IMP/SCHEMAS_LIST_EXP)
  4) Drop ALL objects of users listed in imp schemas [users kept]
  5) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) drop_users_cascade_all_nonmaint ;;
      2) drop_objects_all_nonmaint ;;
      3) drop_users_cascade_listed ;;
      4) drop_objects_listed ;;
      5) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

# ------------------------------ DDL Extraction --------------------------------
ddl_spool() {
  local out="$1"; shift
  local body="$*"
  local conn="sys/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"

  sqlplus -s "$conn" <<SQL >"$out" 2>"${out}.log"
SET LONG 1000000 LONGCHUNKSIZE 1000000 LINES 32767 PAGES 0 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE',            FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS',        TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS',    TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'OID',                FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR',      TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY',             TRUE);
END;
/
${body}
EXIT
SQL
  if grep -qi "ORA-" "${out}.log"; then
    err "DDL extract error in $(basename "$out")"
    tail -n 50 "${out}.log" | mask_pwd | sed 's/^/  /'
    return 1
  fi
  ok "DDL file created: $out"
}

ddl_users() { local f="${DDL_DIR}/01_users_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('USER', username)
FROM dba_users
WHERE oracle_maintained = 'N'
ORDER BY username;
"; }

ddl_profiles() { local f="${DDL_DIR}/02_profiles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('PROFILE', profile)
FROM (SELECT DISTINCT profile FROM dba_profiles ORDER BY 1);
"; }

ddl_roles() { local f="${DDL_DIR}/03_roles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('ROLE', role)
FROM dba_roles
WHERE NVL(oracle_maintained,'N')='N'
ORDER BY role;
"; }

# System privileges & role grants (no OVD refs)
ddl_privs_to_roles() { local f="${DDL_DIR}/04_sys_and_role_grants_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT 'GRANT '||privilege||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';'
FROM dba_sys_privs
WHERE grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
  AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
UNION ALL
SELECT 'GRANT '||granted_role||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';'
FROM dba_role_privs
WHERE grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
  AND granted_role NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
ORDER BY 1;
"; }

# Object grants to users (from DBA_TAB_PRIVS)
ddl_sysprivs_to_users() { local f="${DDL_DIR}/05_user_obj_privs_${RUN_ID}.sql"; ddl_spool "$f" "
WITH src AS (
  SELECT grantee, owner, table_name, privilege, grantable, grantor
  FROM dba_tab_privs
  WHERE grantee <> 'PUBLIC'
    AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
    AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
    AND grantee NOT LIKE 'C##%'
)
SELECT 'GRANT '||privilege||' ON '||owner||'.\"'||table_name||'\" TO '||grantee||
       DECODE(grantable,'YES',' WITH GRANT OPTION','')||' /* grantor '||grantor||' */;'
FROM src
ORDER BY grantee, owner, table_name, privilege;
"; }

ddl_sequences_all_users() { local f="${DDL_DIR}/06_sequences_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', sequence_name, owner)
FROM dba_sequences
WHERE owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, sequence_name;
"; }

ddl_public_synonyms() { local f="${DDL_DIR}/07_public_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, 'PUBLIC')
FROM dba_synonyms
WHERE owner='PUBLIC'
ORDER BY synonym_name;
"; }

ddl_private_synonyms_all_users() { local f="${DDL_DIR}/08_private_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, owner)
FROM dba_synonyms
WHERE owner <> 'PUBLIC'
  AND owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, synonym_name;
"; }

to_inlist_upper() {
  local csv="$1" out="" tok
  IFS=',' read -r -a arr <<< "$csv"
  for tok in "${arr[@]}"; do
    tok="$(echo "$tok" | awk '{$1=$1;print}')"
    [[ -z "$tok" ]] && continue
    tok="${tok^^}"
    out+="${out:+,}'${tok}'"
  done
  printf "%s" "$out"
}

ddl_all_ddls_all_users() {
  local f="${DDL_DIR}/09_all_ddls_${RUN_ID}.sql"
  local types_clause; types_clause="$(to_inlist_upper "TABLE,INDEX,VIEW,SEQUENCE,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE_BODY,MATERIALIZED_VIEW,TYPE,SYNONYM")"
  ddl_spool "$f" "
WITH owners AS ( SELECT username AS owner FROM dba_users WHERE oracle_maintained='N' ),
objs AS (
  SELECT owner, object_type, object_name
  FROM dba_objects
  WHERE owner IN (SELECT owner FROM owners)
    AND object_type IN (${types_clause})
    AND object_name NOT LIKE 'BIN$%%'
    AND temporary='N'
)
SELECT DBMS_METADATA.GET_DDL(object_type, object_name, owner)
FROM objs
ORDER BY owner, object_type, object_name;
"; }

ddl_tablespaces() {
  local f="${DDL_DIR}/10_tablespaces_${RUN_ID}.sql"
  local skip_clause; skip_clause="$(to_inlist_upper "$SKIP_TABLESPACES")"
  ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('TABLESPACE', tablespace_name)
FROM dba_tablespaces
WHERE UPPER(tablespace_name) NOT IN (${skip_clause})
ORDER BY tablespace_name;
"; }

ddl_role_grants_to_users() { local f="${DDL_DIR}/11_role_grants_to_users_${RUN_ID}.sql"; ddl_spool "$f" "
WITH u AS (SELECT username FROM dba_users WHERE oracle_maintained='N'),
r AS (
  SELECT grantee AS username, LISTAGG(role, ',') WITHIN GROUP (ORDER BY role) AS roles
  FROM (
    SELECT grantee, granted_role AS role
    FROM dba_role_privs
    WHERE default_role='YES'
  )
  GROUP BY grantee
)
SELECT 'ALTER USER '||username||' DEFAULT ROLE '||NVL(roles, 'ALL')||';'
FROM u LEFT JOIN r USING (username)
ORDER BY username;
"; }

ddl_directories() { local f="${DDL_DIR}/13_directories_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DIRECTORY', directory_name)
FROM (SELECT DISTINCT directory_name FROM dba_directories ORDER BY 1);
"; }

ddl_db_links_by_owner() {
  read -rp "Enter owner for DB links (schema name): " owner
  owner="${owner^^}"
  local f="${DDL_DIR}/14_db_links_${owner}_${RUN_ID}.sql"
  ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DB_LINK', db_link, owner)
FROM dba_db_links
WHERE owner = UPPER('${owner}')
ORDER BY db_link;
"
  warn "Note: DB link passwords may be masked/omitted depending on version/security."
}

ddl_menu_wrapper() {
  while true; do
    cat <<'EOS'
DDL Extraction (Source DB):
  1) USERS (exclude Oracle-maintained)
  2) PROFILES
  3) ROLES (exclude Oracle-maintained)
  4) PRIVILEGES -> ROLES   [system + role grants]
  5) OBJECT PRIVS -> USERS [from DBA_TAB_PRIVS]
  6) SEQUENCES for USERS (exclude Oracle-maintained)
  7) PUBLIC SYNONYMS
  8) PRIVATE SYNONYMS for USERS (exclude Oracle-maintained)
  9) ALL OBJECT DDLs for USERS (exclude Oracle-maintained) [heavy]
 10) TABLESPACE DDLs (skip system/temp/undo)
 11) DEFAULT ROLES per USER (ALTER USER DEFAULT ROLE ...)
 12) DIRECTORY OBJECTS
 13) DB LINKS by OWNER (prompt)
  B) Back
EOS
    read -rp "Choose: " c
    case "${c^^}" in
      1) ddl_users ;; 2) ddl_profiles ;; 3) ddl_roles ;; 4) ddl_privs_to_roles ;;
      5) ddl_sysprivs_to_users ;; 6) ddl_sequences_all_users ;; 7) ddl_public_synonyms ;;
      8) ddl_private_synonyms_all_users ;; 9) ddl_all_ddls_all_users ;; 10) ddl_tablespaces ;;
      11) ddl_role_grants_to_users ;; 12) ddl_directories ;; 13) ddl_db_links_by_owner ;;
      B) break ;; * ) warn "Invalid choice" ;;
    esac
  done
}

# ----------------------- COMPARE: Common helpers ------------------------------
ensure_local_dir() { mkdir -p "$1" || { echo "Cannot create $1"; exit 1; }; }

normalize_sorted() {
  local in="$1" out="$2"
  if [[ -f "$in" ]]; then tr -d '\r' < "$in" | awk 'NF' | sort -u > "$out"; else : > "$out"; fi
}

emit_set_delta_html() {
  local title="$1" left_csv="$2" right_csv="$3" html="$4"
  local L="$(mktemp)" R="$(mktemp)"
  normalize_sorted "$left_csv"  "$L"
  normalize_sorted "$right_csv" "$R"
  echo "<h3>${title}</h3>" >> "$html"
  echo "<table><tr><th>Only in Source</th><th>Only in Target</th></tr><tr><td valign='top'><pre>" >> "$html"
  comm -23 "$L" "$R" | sed 's/&/\&amp;/g;s/</\&lt;/g' >> "$html"
  echo "</pre></td><td valign='top'><pre>" >> "$html"
  comm -13 "$L" "$R" | sed 's/&/\&amp;/g;s/</\&lt;/g' >> "$html"
  echo "</pre></td></tr></table>" >> "$html"
  rm -f "$L" "$R"
}

emit_rowcount_delta_html() {
  local title="$1" left_csv="$2" right_csv="$3" html="$4"
  local L="$(mktemp)" R="$(mktemp)"
  normalize_sorted "$left_csv"  "$L"
  normalize_sorted "$right_csv" "$R"
  echo "<h3>${title}</h3><table><tr><th>Table</th><th>Source</th><th>Target</th><th>Delta</th></tr>" >> "$html"
  awk -F'|' '
    NR==FNR { l[$1]=$2; next }
    { r[$1]=$2 }
    END{
      for (k in l) keys[k]=1
      for (k in r) keys[k]=1
      PROCINFO["sorted_in"]="@ind_str_asc"
      for (k in keys){
        ls=(k in l)?l[k]:""; rs=(k in r)?r[k]:""
        delta="SAME"
        if (ls=="" && rs!="") delta="ONLY_IN_TARGET"
        else if (ls!="" && rs=="") delta="ONLY_IN_SOURCE"
        else if (ls!=rs) delta="DIFF"
        if (delta!="SAME"){
          gsub(/&/,"\\&amp;",k); gsub(/</,"\\&lt;",k)
          gsub(/&/,"\\&amp;",ls); gsub(/</,"\\&lt;",ls)
          gsub(/&/,"\\&amp;",rs); gsub(/</,"\\&lt;",rs)
          printf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", k, ls, rs, delta)
        }
      }
    }' "$L" "$R" >> "$html"
  echo "</table>" >> "$html"
  rm -f "$L" "$R"
}

# ----------------------- COMPARE: LOCAL/JUMPER (no NAS) -----------------------
# Spoolers (LOCAL): both SRC and TGT write to LOCAL_COMPARE_DIR
snapshot_objects_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  run_sql_spool_local "$ez" "snap_${who}_objects_${schema}" "$out" "
SET COLSEP '|'
SELECT object_type||'|'||object_name||'|'||status
FROM dba_objects
WHERE owner=UPPER('${schema}')
  AND temporary='N'
  AND object_name NOT LIKE 'BIN$%'
ORDER BY object_type, object_name;
"
}
snapshot_rowcounts_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  if [[ "${EXACT_ROWCOUNT^^}" == "Y" ]]; then
    run_sql_spool_local "$ez" "snap_${who}_rowcnt_exact_${schema}" "$out" "
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE v_cnt NUMBER;
BEGIN
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner=UPPER('${schema}') ORDER BY table_name) LOOP
    BEGIN EXECUTE IMMEDIATE 'SELECT COUNT(1) FROM '||UPPER('${schema}')||'.\"'||t.table_name||'\"' INTO v_cnt;
         DBMS_OUTPUT.PUT_LINE(t.table_name||'|'||v_cnt);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(t.table_name||'|#ERR#'); END;
  END LOOP;
END;
/
"
  else
    run_sql_spool_local "$ez" "snap_${who}_rowcnt_stats_${schema}" "$out" "
SET COLSEP '|'
SELECT t.table_name||'|'||NVL(s.num_rows,-1)
FROM dba_tables t
LEFT JOIN dba_tab_statistics s
  ON s.owner=t.owner AND s.table_name=t.table_name AND s.object_type='TABLE'
WHERE t.owner=UPPER('${schema}')
ORDER BY t.table_name;
"
  fi
}
snapshot_sys_privs_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  run_sql_spool_local "$ez" "snap_${who}_sysprivs_${schema}" "$out" "
SET COLSEP '|'
SELECT privilege||'|'||admin_option
FROM dba_sys_privs
WHERE grantee=UPPER('${schema}')
ORDER BY privilege;
"
}
snapshot_role_privs_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  run_sql_spool_local "$ez" "snap_${who}_roleprivs_${schema}" "$out" "
SET COLSEP '|'
SELECT granted_role||'|'||admin_option||'|'||default_role
FROM dba_role_privs
WHERE grantee=UPPER('${schema}')
ORDER BY granted_role;
"
}
snapshot_tabprivs_on_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  run_sql_spool_local "$ez" "snap_${who}_tabprivs_on_${schema}" "$out" "
SET COLSEP '|'
SELECT owner||'|'||table_name||'|'||grantee||'|'||privilege||'|'||grantable||'|'||grantor
FROM dba_tab_privs
WHERE owner=UPPER('${schema}') AND grantee <> 'PUBLIC'
ORDER BY owner, table_name, grantee, privilege;
"
}
snapshot_tabprivs_to_local() {
  local ez="$1" who="$2" schema="${3^^}" out="${4}"
  run_sql_spool_local "$ez" "snap_${who}_tabprivs_to_${schema}" "$out" "
SET COLSEP '|'
SELECT owner||'|'||table_name||'|'||grantee||'|'||privilege||'|'||grantable||'|'||grantor
FROM dba_tab_privs
WHERE grantee=UPPER('${schema}')
ORDER BY owner, table_name, privilege;
"
}

compare_one_schema_local() {
  local schema="${1^^}"
  ensure_local_dir "$LOCAL_COMPARE_DIR"
  local S="${LOCAL_COMPARE_DIR}"

  snapshot_objects_local      "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_objects_${RUN_ID}.csv"
  snapshot_rowcounts_local    "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_rowcounts_${RUN_ID}.csv"
  snapshot_sys_privs_local    "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_sys_privs_${RUN_ID}.csv"
  snapshot_role_privs_local   "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_role_privs_${RUN_ID}.csv"
  snapshot_tabprivs_on_local  "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_obj_privs_on_${RUN_ID}.csv"
  snapshot_tabprivs_to_local  "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_obj_privs_to_${RUN_ID}.csv"

  snapshot_objects_local      "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_objects_${RUN_ID}.csv"
  snapshot_rowcounts_local    "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_rowcounts_${RUN_ID}.csv"
  snapshot_sys_privs_local    "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_sys_privs_${RUN_ID}.csv"
  snapshot_role_privs_local   "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_role_privs_${RUN_ID}.csv"
  snapshot_tabprivs_on_local  "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_obj_privs_on_${RUN_ID}.csv"
  snapshot_tabprivs_to_local  "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_obj_privs_to_${RUN_ID}.csv"

  local html="${COMPARE_DIR}/compare_local_${schema}_${RUN_ID}.html"
  ensure_local_dir "$COMPARE_DIR"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare (LOCAL) ${schema}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px} pre{white-space:pre-wrap}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare (LOCAL/Jumper): ${schema}</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}<br/>Local: ${LOCAL_COMPARE_DIR}</p>"
  } > "$html"

  emit_set_delta_html "Objects (type|name|status)" \
    "${S}/${schema}_src_objects_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_objects_${RUN_ID}.csv" \
    "$html"

  emit_rowcount_delta_html "Rowcount differences (table|count)" \
    "${S}/${schema}_src_rowcounts_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_rowcounts_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "System Privileges (priv|admin)" \
    "${S}/${schema}_src_sys_privs_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_sys_privs_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Role Grants (role|admin|default)" \
    "${S}/${schema}_src_role_privs_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_role_privs_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Object Privileges ON ${schema} objects (owner|table|grantee|priv|grantable|grantor)" \
    "${S}/${schema}_src_obj_privs_on_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_obj_privs_on_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Object Privileges TO ${schema} user (owner|table|grantee|priv|grantable|grantor)" \
    "${S}/${schema}_src_obj_privs_to_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_obj_privs_to_${RUN_ID}.csv" \
    "$html"

  echo "</body></html>" >> "$html"
  ok "HTML (LOCAL/Jumper): ${html}"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Schema Compare LOCAL - ${schema} - ${RUN_ID}"
}

compare_many_local() {
  local list_input="${1:-}"
  local schemas_list=""
  if [[ -n "$list_input" ]]; then
    schemas_list="$list_input"
  else
    schemas_list="$(get_nonmaintained_schemas)"
    [[ -z "$schemas_list" ]] && { warn "No non-maintained schemas found on source."; return 0; }
    ok "Auto-compare LOCAL mode (source list): ${schemas_list}"
  fi

  ensure_local_dir "$COMPARE_DIR"
  local index="${COMPARE_DIR}/compare_local_index_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare LOCAL Index ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare Index (LOCAL/Jumper)</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}</p>"
    echo "<table><tr><th>#</th><th>Schema</th><th>Report</th></tr>"
  } > "$index"

  local i=0
  IFS=',' read -r -a arr <<< "$schemas_list"
  for s in "${arr[@]}"; do
    s="$(echo "$s" | awk '{$1=$1;print}')"
    [[ -z "$s" ]] && continue
    i=$((i+1))
    compare_one_schema_local "$s"
    local f="compare_local_${s^^}_${RUN_ID}.html"
    echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"
  done
  echo "</table></body></html>" >> "$index"
  ok "Index HTML (LOCAL): ${index}"
  email_inline_html "$index" "${MAIL_SUBJECT_PREFIX} Compare LOCAL Index - ${RUN_ID}"
}

# ----------------------- COMPARE: FILE mode (needs NAS) -----------------------
snapshot_src_objects_csv() {
  local schema="${1^^}"
  local fname="${schema}_src_objects_${RUN_ID}.csv"
  run_sql "$SRC_EZCONNECT" "snap_src_objects_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT object_type, object_name, status
              FROM dba_objects
             WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'
             ORDER BY object_type, object_name) LOOP
    UTL_FILE.PUT_LINE(f, r.object_type||'|'||r.object_name||'|'||r.status);
  END LOOP;
  UTL_FILE.FCLOSE(f);
END;
/
"
}
snapshot_tgt_objects_csv() {
  local schema="${1^^}"
  local fname="${schema}_tgt_objects_${RUN_ID}.csv"
  run_sql "$TGT_EZCONNECT" "snap_tgt_objects_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT object_type, object_name, status
              FROM dba_objects
             WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'
             ORDER BY object_type, object_name) LOOP
    UTL_FILE.PUT_LINE(f, r.object_type||'|'||r.object_name||'|'||r.status);
  END LOOP;
  UTL_FILE.FCLOSE(f);
END;
/
"
}
snapshot_src_rowcounts_csv() {
  local schema="${1^^}"
  local fname="${schema}_src_rowcounts_${RUN_ID}.csv"
  if [[ "${EXACT_ROWCOUNT^^}" == "Y" ]]; then
    run_sql "$SRC_EZCONNECT" "snap_src_rowcounts_exact_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE; v_sql VARCHAR2(4000); v_cnt NUMBER;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner=UPPER('${schema}') ORDER BY table_name) LOOP
    v_sql := 'SELECT COUNT(1) FROM '||UPPER('${schema}')||'.\"'||t.table_name||'\"';
    BEGIN EXECUTE IMMEDIATE v_sql INTO v_cnt; UTL_FILE.PUT_LINE(f, t.table_name||'|'||v_cnt);
    EXCEPTION WHEN OTHERS THEN UTL_FILE.PUT_LINE(f, t.table_name||'|#ERR#'); END;
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
  else
    run_sql "$SRC_EZCONNECT" "snap_src_rowcounts_stats_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT table_name, NVL(num_rows,-1) AS num_rows
              FROM dba_tab_statistics
             WHERE owner=UPPER('${schema}') AND object_type='TABLE'
             ORDER BY table_name) LOOP
    UTL_FILE.PUT_LINE(f, r.table_name||'|'||r.num_rows);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
  fi
}
snapshot_tgt_rowcounts_csv() {
  local schema="${1^^}"
  local fname="${schema}_tgt_rowcounts_${RUN_ID}.csv"
  if [[ "${EXACT_ROWCOUNT^^}" == "Y" ]]; then
    run_sql "$TGT_EZCONNECT" "snap_tgt_rowcounts_exact_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE; v_sql VARCHAR2(4000); v_cnt NUMBER;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner=UPPER('${schema}') ORDER BY table_name) LOOP
    v_sql := 'SELECT COUNT(1) FROM '||UPPER('${schema}')||'.\"'||t.table_name||'\"';
    BEGIN EXECUTE IMMEDIATE v_sql INTO v_cnt; UTL_FILE.PUT_LINE(f, t.table_name||'|'||v_cnt);
    EXCEPTION WHEN OTHERS THEN UTL_FILE.PUT_LINE(f, t.table_name||'|#ERR#'); END;
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
  else
    run_sql "$TGT_EZCONNECT" "snap_tgt_rowcounts_stats_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT table_name, NVL(num_rows,-1) AS num_rows
              FROM dba_tab_statistics
             WHERE owner=UPPER('${schema}') AND object_type='TABLE'
             ORDER BY table_name) LOOP
    UTL_FILE.PUT_LINE(f, r.table_name||'|'||r.num_rows);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
  fi
}
snapshot_src_tabprivs_on_schema_csv() {
  local schema="${1^^}"
  local fname="${schema}_src_obj_privs_on_${RUN_ID}.csv"
  run_sql "$SRC_EZCONNECT" "snap_src_obj_privs_on_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT owner, table_name, grantee, privilege, grantable, grantor
              FROM dba_tab_privs
             WHERE owner=UPPER('${schema}') AND grantee <> 'PUBLIC'
             ORDER BY owner, table_name, grantee, privilege) LOOP
    UTL_FILE.PUT_LINE(f, r.owner||'|'||r.table_name||'|'||r.grantee||'|'||r.privilege||'|'||r.grantable||'|'||r.grantor);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
}
snapshot_tgt_tabprivs_on_schema_csv() {
  local schema="${1^^}"
  local fname="${schema}_tgt_obj_privs_on_${RUN_ID}.csv"
  run_sql "$TGT_EZCONNECT" "snap_tgt_obj_privs_on_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT owner, table_name, grantee, privilege, grantable, grantor
              FROM dba_tab_privs
             WHERE owner=UPPER('${schema}') AND grantee <> 'PUBLIC'
             ORDER BY owner, table_name, grantee, privilege) LOOP
    UTL_FILE.PUT_LINE(f, r.owner||'|'||r.table_name||'|'||r.grantee||'|'||r.privilege||'|'||r.grantable||'|'||r.grantor);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
}
snapshot_src_tabprivs_to_user_csv() {
  local schema="${1^^}"
  local fname="${schema}_src_obj_privs_to_${RUN_ID}.csv"
  run_sql "$SRC_EZCONNECT" "snap_src_obj_privs_to_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT owner, table_name, grantee, privilege, grantable, grantor
              FROM dba_tab_privs
             WHERE grantee=UPPER('${schema}')
             ORDER BY owner, table_name, privilege) LOOP
    UTL_FILE.PUT_LINE(f, r.owner||'|'||r.table_name||'|'||r.grantee||'|'||r.privilege||'|'||r.grantable||'|'||r.grantor);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
}
snapshot_tgt_tabprivs_to_user_csv() {
  local schema="${1^^}"
  local fname="${schema}_tgt_obj_privs_to_${RUN_ID}.csv"
  run_sql "$TGT_EZCONNECT" "snap_tgt_obj_privs_to_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${fname}','W',32767);
  FOR r IN (SELECT owner, table_name, grantee, privilege, grantable, grantor
              FROM dba_tab_privs
             WHERE grantee=UPPER('${schema}')
             ORDER BY owner, table_name, privilege) LOOP
    UTL_FILE.PUT_LINE(f, r.owner||'|'||r.table_name||'|'||r.grantee||'|'||r.privilege||'|'||r.grantable||'|'||r.grantor);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
}

compare_one_schema_file_mode() {
  local schema="${1^^}"
  [[ -z "$NAS_PATH" ]] && { err "NAS_PATH not set; FILE mode requires shared NAS."; return 1; }
  ensure_directory_object "$SRC_EZCONNECT" "src"
  ensure_directory_object "$TGT_EZCONNECT" "tgt"
  validate_directory_on_db "$SRC_EZCONNECT" "src"
  validate_directory_on_db "$TGT_EZCONNECT" "tgt"

  snapshot_src_objects_csv            "$schema"
  snapshot_tgt_objects_csv            "$schema"
  snapshot_src_rowcounts_csv          "$schema"
  snapshot_tgt_rowcounts_csv          "$schema"
  snapshot_src_tabprivs_on_schema_csv "$schema"
  snapshot_tgt_tabprivs_on_schema_csv "$schema"
  snapshot_src_tabprivs_to_user_csv   "$schema"
  snapshot_tgt_tabprivs_to_user_csv   "$schema"

  local html="${COMPARE_DIR}/compare_file_${schema}_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare (FILE) ${schema}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px} pre{white-space:pre-wrap}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare (FILE mode): ${schema}</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}<br/>NAS: ${NAS_PATH}</p>"
  } > "$html"

  emit_set_delta_html "Objects (type|name|status)" \
    "${NAS_PATH}/${schema}_src_objects_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_objects_${RUN_ID}.csv" \
    "$html"

  emit_rowcount_delta_html "Rowcount differences (table|count)" \
    "${NAS_PATH}/${schema}_src_rowcounts_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_rowcounts_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "System Privileges (priv|admin)" \
    "${NAS_PATH}/${schema}_src_sys_privs_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_sys_privs_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Role Grants (role|admin|default)" \
    "${NAS_PATH}/${schema}_src_role_privs_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_role_privs_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Object Privileges ON ${schema} objects" \
    "${NAS_PATH}/${schema}_src_obj_privs_on_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_obj_privs_on_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Object Privileges TO ${schema} user" \
    "${NAS_PATH}/${schema}_src_obj_privs_to_${RUN_ID}.csv" \
    "${NAS_PATH}/${schema}_tgt_obj_privs_to_${RUN_ID}.csv" \
    "$html"

  echo "</body></html>" >> "$html"
  ok "HTML (FILE mode): ${html}"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Schema Compare FILE - ${schema} - ${RUN_ID}"
}

compare_many_file_mode() {
  local list_input="${1:-}"
  local schemas_list=""
  if [[ -n "$list_input" ]]; then
    schemas_list="$list_input"
  else
    schemas_list="$(get_nonmaintained_schemas)"
    [[ -z "$schemas_list" ]] && { warn "No non-maintained schemas found on source."; return 0; }
    ok "Auto-compare FILE mode (from source list): ${schemas_list}"
  fi

  local index="${COMPARE_DIR}/compare_file_index_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare FILE Index ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare Index (FILE mode)</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}</p>"
    echo "<table><tr><th>#</th><th>Schema</th><th>Report</th></tr>"
  } > "$index"

  local i=0
  IFS=',' read -r -a arr <<< "$schemas_list"
  for s in "${arr[@]}"; do
    s="$(echo "$s" | awk '{$1=$1;print}')"
    [[ -z "$s" ]] && continue
    i=$((i+1))
    compare_one_schema_file_mode "$s"
    local f="compare_file_${s^^}_${RUN_ID}.html"
    echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"
  done
  echo "</table></body></html>" >> "$index"
  ok "Index HTML (FILE mode): ${index}"
  email_inline_html "$index" "${MAIL_SUBJECT_PREFIX} Compare FILE Index - ${RUN_ID}"
}

# -------------------- COMPARE: EXTERNAL engine (needs NAS) --------------------
create_exts_for_schema() {
  local schema="${1^^}"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_OBJS_EXT"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_ROWCOUNTS_EXT"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_TABPRIVS_ON_EXT"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_TABPRIVS_TO_EXT"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_SYS_PRIVS_EXT"
  drop_table_if_exists "$TGT_EZCONNECT" "SRC_ROLE_PRIVS_EXT"

  run_sql "$TGT_EZCONNECT" "create_ext_objs_${schema}" "
CREATE TABLE src_objs_ext (
  object_type VARCHAR2(30),
  object_name VARCHAR2(128),
  status      VARCHAR2(7)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( object_type CHAR(30), object_name CHAR(128), status CHAR(7) )
  )
  LOCATION ('${schema}_src_objects_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
  run_sql "$TGT_EZCONNECT" "create_ext_row_${schema}" "
CREATE TABLE src_rowcounts_ext (
  table_name VARCHAR2(128),
  num_rows   VARCHAR2(30)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( table_name CHAR(128), num_rows CHAR(30) )
  )
  LOCATION ('${schema}_src_rowcounts_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
  run_sql "$TGT_EZCONNECT" "create_ext_tabprivs_on_${schema}" "
CREATE TABLE src_tabprivs_on_ext (
  owner      VARCHAR2(128),
  table_name VARCHAR2(128),
  grantee    VARCHAR2(128),
  privilege  VARCHAR2(40),
  grantable  VARCHAR2(3),
  grantor    VARCHAR2(128)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( owner CHAR(128), table_name CHAR(128), grantee CHAR(128),
      privilege CHAR(40), grantable CHAR(3), grantor CHAR(128) )
  )
  LOCATION ('${schema}_src_obj_privs_on_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
  run_sql "$TGT_EZCONNECT" "create_ext_tabprivs_to_${schema}" "
CREATE TABLE src_tabprivs_to_ext (
  owner      VARCHAR2(128),
  table_name VARCHAR2(128),
  grantee    VARCHAR2(128),
  privilege  VARCHAR2(40),
  grantable  VARCHAR2(3),
  grantor    VARCHAR2(128)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( owner CHAR(128), table_name CHAR(128), grantee CHAR(128),
      privilege CHAR(40), grantable CHAR(3), grantor CHAR(128) )
  )
  LOCATION ('${schema}_src_obj_privs_to_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
  run_sql "$TGT_EZCONNECT" "create_ext_sysprivs_${schema}" "
CREATE TABLE src_sys_privs_ext (
  privilege     VARCHAR2(40),
  admin_option  VARCHAR2(3)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( privilege CHAR(40), admin_option CHAR(3) )
  )
  LOCATION ('${schema}_src_sys_privs_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
  run_sql "$TGT_EZCONNECT" "create_ext_roleprivs_${schema}" "
CREATE TABLE src_role_privs_ext (
  granted_role  VARCHAR2(128),
  admin_option  VARCHAR2(3),
  default_role  VARCHAR2(3)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    ( granted_role CHAR(128), admin_option CHAR(3), default_role CHAR(3) )
  )
  LOCATION ('${schema}_src_role_privs_${RUN_ID}.csv')
) REJECT LIMIT UNLIMITED;
/
"
}

compare_one_schema_sql_external() {
  local schema="${1^^}"
  [[ -z "$NAS_PATH" ]] && { err "NAS_PATH not set; EXTERNAL engine requires shared NAS."; return 1; }
  ensure_directory_object "$SRC_EZCONNECT" "src"
  ensure_directory_object "$TGT_EZCONNECT" "tgt"
  validate_directory_on_db "$SRC_EZCONNECT" "src"
  validate_directory_on_db "$TGT_EZCONNECT" "tgt"

  snapshot_src_objects_csv "$schema"
  snapshot_src_rowcounts_csv "$schema"
  snapshot_src_tabprivs_on_schema_csv "$schema"
  snapshot_src_tabprivs_to_user_csv "$schema"
  run_sql "$SRC_EZCONNECT" "src_sys_privs_to_csv_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${schema}_src_sys_privs_${RUN_ID}.csv','W',32767);
  FOR r IN (SELECT privilege, admin_option FROM dba_sys_privs WHERE grantee=UPPER('${schema}') ORDER BY privilege) LOOP
    UTL_FILE.PUT_LINE(f, r.privilege||'|'||r.admin_option);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"
  run_sql "$SRC_EZCONNECT" "src_role_privs_to_csv_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'),'${schema}_src_role_privs_${RUN_ID}.csv','W',32767);
  FOR r IN (SELECT granted_role, admin_option, default_role FROM dba_role_privs WHERE grantee=UPPER('${schema}') ORDER BY granted_role) LOOP
    UTL_FILE.PUT_LINE(f, r.granted_role||'|'||r.admin_option||'|'||r.default_role);
  END LOOP; UTL_FILE.FCLOSE(f);
END;
/
"

  create_exts_for_schema "$schema"

  local html="${COMPARE_DIR}/compare_${schema}_${RUN_ID}.html"
  local conn="sys/${SYS_PASSWORD}@${TGT_EZCONNECT} as sysdba"
  sqlplus -s "$conn" <<SQL >"$html" 2>"${html}.log"
SET MARKUP HTML ON SPOOL ON ENTMAP OFF
SPOOL $html
PROMPT <h2>Schema Compare Report (EXTERNAL): ${schema}</h2>
PROMPT <p>Run ID: ${RUN_ID} | Source via NAS: ${NAS_PATH} | Target: ${TGT_EZCONNECT}</p>

PROMPT <h3>Delta (SOURCE CSV vs TARGET Objects)</h3>
WITH src AS (SELECT * FROM src_objs_ext),
     tgt AS (SELECT object_type, object_name, status FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%')
SELECT COALESCE(src.object_type, tgt.object_type) AS object_type,
       COALESCE(src.object_name, tgt.object_name) AS object_name,
       src.status AS src_status, tgt.status AS tgt_status,
       CASE
         WHEN src.object_name IS NOT NULL AND tgt.object_name IS NULL THEN 'ONLY_IN_SOURCE'
         WHEN src.object_name IS NULL AND tgt.object_name IS NOT NULL THEN 'ONLY_IN_TARGET'
         WHEN src.status IS NOT NULL AND tgt.status IS NOT NULL AND src.status <> tgt.status THEN 'STATUS_DIFFERS'
         ELSE 'SAME'
       END AS delta_kind
FROM src FULL OUTER JOIN tgt
  ON src.object_type=tgt.object_type AND src.object_name=tgt.object_name
WHERE (src.object_name IS NULL OR tgt.object_name IS NULL OR src.status<>tgt.status)
ORDER BY delta_kind, 1,2
/

PROMPT <h3>Invalid Objects on Target</h3>
SELECT object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE owner=UPPER('${schema}') AND status='INVALID'
GROUP BY object_type
ORDER BY object_type
/
SPOOL OFF
EXIT
SQL

  if grep -qi "ORA-" "${html}.log"; then warn "HTML compare generation hit errors (see ${html}.log)"; else ok "HTML compare report: ${html}"; fi
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Schema Compare (EXTERNAL) - ${schema} - ${RUN_ID}"
}

compare_many_sql_external() {
  local list_input="$1"
  local schemas_list=""
  if [[ -n "$list_input" ]]; then schemas_list="$list_input"; else schemas_list="$(get_nonmaintained_schemas)"; fi
  [[ -z "$schemas_list" ]] && { warn "No non-maintained schemas found on source."; return 0; }
  local index="${COMPARE_DIR}/compare_external_index_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare (EXTERNAL) Index ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px}</style>"
    echo "</head><body><h2>Schema Compare Index (EXTERNAL)</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}</p>"
    echo "<table><tr><th>#</th><th>Schema</th><th>Report</th></tr>"
  } > "$index"
  local i=0
  IFS=',' read -r -a arr <<< "$schemas_list"
  for s in "${arr[@]}"; do
    s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue
    i=$((i+1))
    compare_one_schema_sql_external "$s"
    local f="compare_${s^^}_${RUN_ID}.html"
    echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"
  done
  echo "</table></body></html>" >> "$index"
  ok "Index HTML (EXTERNAL): ${index}"
  email_inline_html "$index" "${MAIL_SUBJECT_PREFIX} Compare EXTERNAL Index - ${RUN_ID}"
}

# ------------------------------ Job view / cleanup ----------------------------
show_jobs() {
  ce "Logs under $LOG_DIR"
  read -rp "Show DBA_DATAPUMP_JOBS on which DB? (src/tgt): " side
  case "${side,,}" in
    src) run_sql "$SRC_EZCONNECT" "jobs_src_${RUN_ID}" "SET LINES 220 PAGES 200
COL owner_name FOR A20
COL job_name FOR A30
COL state FOR A12
SELECT owner_name, job_name, state, operation, job_mode, degree, attached_sessions
FROM dba_datapump_jobs ORDER BY 1,2; /" ;;
    tgt) run_sql "$TGT_EZCONNECT" "jobs_tgt_${RUN_ID}" "SET LINES 220 PAGES 200
COL owner_name FOR A20
COL job_name FOR A30
COL state FOR A12
SELECT owner_name, job_name, state, operation, job_mode, degree, attached_sessions
FROM dba_datapump_jobs ORDER BY 1,2; /" ;;
    *) warn "Unknown choice";;
  esac
  for f in "$LOG_DIR"/*.log; do [[ -f "$f" ]] || continue; echo "---- $(basename "$f") (tail -n 20) ----"; tail -n 20 "$f"; done
}

cleanup_dirs() {
  read -rp "Drop DIRECTORY ${COMMON_DIR_NAME} on (src/tgt/both)? " side
  case "${side,,}" in
    src) run_sql "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
    tgt) run_sql "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
    both) run_sql "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
          run_sql "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
    *) warn "No action";;
  esac
}

# -------------------------------- Menus ---------------------------------------
export_import_menu() {
  while true; do
    cat <<'EOS'
Data Pump:
  1) Export -> sub menu
  2) Import -> sub menu
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) export_menu ;;
      2) import_menu ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

compare_schema_menu() {
  while true; do
    cat <<'EOS'
Compare Objects (Source vs Target)
  Engine:
    A) EXTERNAL tables on TARGET (needs DIRECTORY/NAS)
    B) FILE mode (CSV + shell diff; needs DIRECTORY/NAS)
    C) LOCAL/JUMPER (CSV spooled locally; NO NAS, NO ext tables)
  Actions:
    1) One schema (HTML + email)
    2) Multiple schemas (ENTER = all non-maintained on source) [HTML + email]
    3) Back
EOS
    read -rp "Choose engine [A/B/C]: " eng
    eng="${eng^^}"
    case "$eng" in
      A)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back]: " c
        case "$c" in
          1) read -rp "Schema name: " s; compare_one_schema_sql_external "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_sql_external "${list:-}";;
          3) break ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      B)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back]: " c
        case "$c" in
          1) read -rp "Schema name: " s; compare_one_schema_file_mode "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_file_mode "${list:-}";;
          3) break ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      C)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back]: " c
        case "$c" in
          1) read -rp "Schema name: " s; compare_one_schema_local "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_local "${list:-}";;
          3) break ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      *) warn "Unknown engine. Choose A, B, or C." ;;
    esac
  done
}

main_menu() {
  while true; do
    cat <<EOS

======== Oracle 19c Migration & DDL (${SCRIPT_NAME} v4ae) ========
Source: ${SRC_EZCONNECT}
Target: ${TGT_EZCONNECT}
NAS:    ${NAS_PATH:-<not used in LOCAL engine>}
PARALLEL=${PARALLEL}  COMPRESSION=${COMPRESSION}  TABLE_EXISTS_ACTION=${TABLE_EXISTS_ACTION}
DDL out: ${DDL_DIR}
Compare out: ${COMPARE_DIR}
==================================================================

1) Precheck & create DIRECTORY on source and target (for EXTERNAL/FILE engines)
2) Data Pump (EXP/IMP)         -> sub menu
3) Monitor/Status              -> DBA_DATAPUMP_JOBS + tail logs
4) Drop DIRECTORY objects      -> cleanup
5) DDL Extraction (Source DB)  -> sub menu
6) Compare Objects             -> sub menu (choose EXTERNAL / FILE / LOCAL)
7) Quit
EOS
    read -rp "Choose: " choice
    case "$choice" in
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$SRC_EZCONNECT" "src"; validate_directory_on_db "$TGT_EZCONNECT" "tgt";;
      2) export_import_menu ;;
      3) show_jobs ;;
      4) cleanup_dirs ;;
      5) ddl_menu_wrapper ;;
      6) compare_schema_menu ;;
      7) exit 0 ;;
      *) warn "Invalid choice.";;
    esac
  done
}

main_menu
