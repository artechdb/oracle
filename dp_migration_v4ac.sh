#!/usr/bin/env bash
# dp_migrate.sh (v4ac) - Oracle 19c Data Pump migration & compare toolkit
# v4ac:
# - FULL Export/Import submenus restored
# - HTML compare + email
# - DDL generators incl. rewritten grant extractors (no OVD refs)
# - DRY_RUN_ONLY support for destructive ops
# - Directory checks and client-side logging

set -euo pipefail

#------------------------ Bootstrap & Paths ------------------------------------
CONFIG_FILE="${1:-dp_migrate.conf}"
SCRIPT_NAME="$(basename "$0")"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
WORK_DIR="${WORK_DIR:-/tmp/dp_migrate_${RUN_ID}}"
LOG_DIR="${LOG_DIR:-${WORK_DIR}/logs}"
PAR_DIR="${PAR_DIR:-${WORK_DIR}/parfiles}"
DDL_DIR="${DDL_DIR:-${WORK_DIR}/ddls}"
COMMON_DIR_NAME="${COMMON_DIR_NAME:-DP_DIR}"
COMPARE_DIR="${COMPARE_DIR:-${WORK_DIR}/compare}"

mkdir -p "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$DDL_DIR" "$COMPARE_DIR"

#------------------------ Pretty print & debug helpers -------------------------
ce()   { printf "%b\n" "$*"; }
ok()   { ce "\e[32m✔ $*\e[0m"; }
warn() { ce "\e[33m! $*\e[0m"; }
err()  { ce "\e[31m✘ $*\e[0m"; }

DEBUG="${DEBUG:-Y}"
debug() { if [[ "${DEBUG^^}" == "Y" ]]; then ce "\e[36m[DEBUG]\e[0m $*"; fi; }

#------------------------ Load Config -----------------------------------------
[[ -f "$CONFIG_FILE" ]] || { err "Config file not found: $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

need_vars=( SRC_EZCONNECT TGT_EZCONNECT SYS_PASSWORD NAS_PATH DUMPFILE_PREFIX )
for v in "${need_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { err "Missing required config variable: $v"; exit 1; }
done

#------------------------ Defaults / Tunables ---------------------------------
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

COMPARE_INCLUDE_TYPES="${COMPARE_INCLUDE_TYPES:-}"
COMPARE_EXCLUDE_TYPES="${COMPARE_EXCLUDE_TYPES:-}"
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"

ok "Using config: $CONFIG_FILE"
ok "Work: $WORK_DIR | Logs: $LOG_DIR | Parfiles: $PAR_DIR | DDLs: $DDL_DIR | Compare: $COMPARE_DIR"

#------------------------ Pre-flight checks -----------------------------------
for b in sqlplus expdp impdp; do
  command -v "$b" >/dev/null 2>&1 || { err "Missing required binary: $b"; exit 1; }
done
[[ -d "$NAS_PATH" ]] || { err "NAS mount path not found on this host: $NAS_PATH"; exit 1; }

#------------------------ Utility helpers -------------------------------------
mask_pwd() { sed 's#[^/"]\{1,\}@#***@#g' | sed 's#sys/[^@]*@#sys/****@#g'; }

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

run_sql() {
  local ez="$1"; shift
  local tag="${1:-sql}"; shift || true
  local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql(tag=$tag) on ${ez} -> $logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF
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

print_log() {
  local tag="$1"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  [[ -f "$logf" ]] && { echo "----- ${tag} -----"; cat "$logf"; echo "----- end (${tag}) -----"; } || true
}

#------------------------ Mail helpers ----------------------------------------
find_mailer() {
  if command -v mailx >/dev/null 2>&1; then echo "mailx"; return; fi
  if command -v mail >/dev/null 2>&1;  then echo "mail";  return; fi
  if command -v sendmail >/dev/null 2>&1; then echo "sendmail"; return; fi
  echo ""
}

email_file() {
  local file="$1" subject="$2"
  [[ "${MAIL_ENABLED^^}" != "Y" ]] && { warn "MAIL_ENABLED!=Y; skip email."; return 0; }
  [[ -z "${REPORT_EMAILS}" ]] && { warn "REPORT_EMAILS empty; skip email."; return 0; }
  local mailer; mailer="$(find_mailer)"
  [[ -z "$mailer" ]] && { warn "No mailer (mailx/mail/sendmail) found; skip email."; return 0; }

  local to="$REPORT_EMAILS"
  case "$mailer" in
    mailx)
      debug "Email via mailx to ${to} subj='${subject}' attach=$(basename "$file")"
      mailx -a "From: ${MAIL_FROM}" -a "Content-Type: text/html" -a "$file" -s "${subject}" $to < /dev/null || warn "mailx send failed"
      ;;
    mail)
      debug "Email via mail to ${to} subj='${subject}'"
      mail -s "${subject}" $to < "$file" || warn "mail send failed"
      ;;
    sendmail)
      debug "Email via sendmail to ${to} subj='${subject}'"
      {
        echo "From: ${MAIL_FROM}"
        echo "To: ${to}"
        echo "Subject: ${subject}"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        cat "$file"
      } | sendmail -t || warn "sendmail failed"
      ;;
  esac
  ok "Email queued to ${to}"
}

#------------------------ DIRECTORY helpers -----------------------------------
ensure_directory_object() {
  local ez="$1" host_tag="$2" dir_name="${3:-$COMMON_DIR_NAME}" dir_path="$NAS_PATH"
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
  print_log "$logtag"
}

#------------------------ Data Pump core --------------------------------------
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
    echo "version:"
    $tool -V || true
    echo "---- parfile (${pf}) ----"
    if [[ -f "$pf" ]]; then
      sed -E 's/(encryption_password=).*/\1*****/I' "$pf"
    else
      echo "<parfile not found>"
    fi
    echo "---------------------------"
  } > "$client_log" 2>&1

  set +e
  ( set -o pipefail; $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} )
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    err "[${tool}] FAILED (rc=$rc) — see ${client_log}"
    exit $rc
  else
    ok "[${tool}] SUCCESS — see ${client_log}"
  fi
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
      if [[ -n "$ENCRYPTION_PASSWORD" ]]; then echo "encryption=encrypt_password"; echo "encryption_password=${ENCRYPTION_PASSWORD}"; fi
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

#------------------------ Export Menus ----------------------------------------
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
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; local pf; pf=$(par_common expdp "exp_full_meta"); { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_meta" ;;
      2) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; local pf; pf=$(par_common expdp "exp_full_all");  { echo "full=Y"; echo "content=ALL"; }           >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_all"  ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

get_nonmaintained_schemas() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do
      s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue
      pred+=" AND UPPER(username) NOT LIKE '${s^^}'"
    done
  fi
  run_sql "$SRC_EZCONNECT" "list_nonmaint_users_${RUN_ID}" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS (
  SELECT username
  FROM dba_users
  WHERE oracle_maintained='N'${pred}
)
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/list_nonmaint_users_${RUN_ID}.log"
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
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; local schemas; schemas="$(get_nonmaintained_schemas)"; schemas="$(confirm_edit_value "Schemas" "$schemas")"; local pf; pf=$(par_common expdp "exp_schemas_auto"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_auto" ;;
      2) ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"; local init="${SCHEMAS_LIST_EXP:-}"; [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init; local schemas; schemas="$(confirm_edit_value "Schemas" "$init")"; local pf; pf=$(par_common expdp "exp_schemas_user"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_user" ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_tablespaces() {
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tablespaces (comma-separated): " tbs
  local pf; pf=$(par_common expdp "exp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tbs"
}

exp_tables() {
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  local pf; pf=$(par_common expdp "exp_tables")
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

#------------------------ Import Menus ----------------------------------------
get_nonmaintained_schemas_tgt() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql "$TGT_EZCONNECT" "tgt_nonmaint_users_${RUN_ID}" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS (
  SELECT username
  FROM dba_users
  WHERE oracle_maintained='N'${pred}
)
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/tgt_nonmaint_users_${RUN_ID}.log"
}

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
      1) ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"; local pf; pf=$(par_common impdp "imp_full_meta"); { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"; dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_meta" ;;
      2) ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"; local pf; pf=$(par_common impdp "imp_full_all");  { echo "full=Y"; echo "content=ALL"; }           >> "$pf"; dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_all"  ;;
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
      1) ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"; local schemas; schemas="$(get_nonmaintained_schemas_tgt)"; schemas="$(confirm_edit_value "Schemas" "$schemas")"; local pf; pf=$(par_common impdp "imp_schemas_auto"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_auto" ;;
      2) ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"; local base="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"; [[ -z "$base" ]] && read -rp "Enter schemas (comma-separated): " base; local schemas; schemas="$(confirm_edit_value "Schemas" "$base")"; local pf; pf=$(par_common impdp "imp_schemas_user"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"; dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_user" ;;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_tablespaces() {
  ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
  read -rp "Transported tablespaces (comma-separated): " tbs
  local pf; pf=$(par_common impdp "imp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tbs"
}

imp_tables() {
  ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  local pf; pf=$(par_common impdp "imp_tables")
  echo "tables=${tabs}" >> "$pf"
  dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tables"
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

#------------------------ Cleanup (Import) ------------------------------------
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
  print_log "${tag}"
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
  print_log "${tag}"
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

  run_sql "$TGT_EZCONNECT" "drop_objs_all" "
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
    FOR r IN (SELECT type_name object_name FROM dba_types WHERE owner=p_owner) LOOP exec_ddl('DROP TYPE '||p_owner||'.\"'||r.object_name||'\" FORCE'); END LOOP;
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
    WHERE oracle_maintained='N'
      AND UPPER(username) IN (${inlist})
    ORDER BY username
  ) LOOP
    v_stmt := 'DROP USER '||r.username||' CASCADE';
    BEGIN EXECUTE IMMEDIATE v_stmt; DBMS_OUTPUT.PUT_LINE('DROPPED USER: '||r.username);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAILED: '||v_stmt||' - '||SQLERRM);
    END;
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

  run_sql "$TGT_EZCONNECT" "drop_objs_listed" "
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
    FOR r IN (SELECT type_name object_name FROM dba_types WHERE owner=p_owner) LOOP exec_ddl('DROP TYPE '||p_owner||'.\"'||r.object_name||'\" FORCE'); END LOOP;
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

#------------------------ DDL Extraction --------------------------------------
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
WHERE NVL(oracle_maintained, 'N') = 'N'
ORDER BY role;
"; }

# System + Role grants (no OVD refs)
ddl_privs_to_roles() {
  local f="${DDL_DIR}/04_sys_and_role_grants_${RUN_ID}.sql"
  ddl_spool "$f" "
SELECT 'GRANT '||privilege||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';'
FROM dba_sys_privs
WHERE grantee NOT IN ('GGADMIN','SCHEDULER_ADMIN','DATAPUMP_IMP_FULL_DATABASE','DATAPUMP_EXP_FULL_DATABASE','CONNECT','RESOURCE','DBA')
  AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
  AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
UNION ALL
SELECT 'GRANT '||granted_role||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';'
FROM dba_role_privs
WHERE grantee NOT IN ('SCHEDULER_ADMIN','DATAPUMP_IMP_FULL_DATABASE','DATAPUMP_EXP_FULL_DATABASE','CONNECT','RESOURCE','DBA')
  AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
  AND granted_role NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
ORDER BY 1;
"
}

# Object grants to users (from DBA_TAB_PRIVS), no OVD refs
ddl_sysprivs_to_users() {
  local f="${DDL_DIR}/05_user_obj_privs_${RUN_ID}.sql"
  ddl_spool "$f" "
WITH src AS (
  SELECT grantee, owner, table_name, privilege, grantable, grantor
  FROM dba_tab_privs
  WHERE grantee <> 'PUBLIC'
    AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
    AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
    AND grantee NOT LIKE 'C##%'
    AND table_name NOT IN (SELECT directory_name FROM dba_directories)
)
SELECT 'GRANT '||privilege||' ON '||owner||'.\"'||table_name||'\" TO '||grantee||
       DECODE(grantable,'YES',' WITH GRANT OPTION','')||' /* grantor '||grantor||' */;'
FROM src
ORDER BY grantee, owner, table_name, privilege;
"
}

ddl_sequences_all_users() { local f="${DDL_DIR}/06_sequences_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', sequence_name, owner)
FROM dba_sequences
WHERE owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, sequence_name;
"; }
ddl_public_synonyms() { local f="${DDL_DIR}/07_public_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, 'PUBLIC')
FROM dba_synonyms
WHERE owner = 'PUBLIC'
ORDER BY synonym_name;
"; }
ddl_private_synonyms_all_users() { local f="${DDL_DIR}/08_private_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, owner)
FROM dba_synonyms
WHERE owner <> 'PUBLIC'
  AND owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, synonym_name;
"; }
ddl_all_ddls_all_users() {
  local f="${DDL_DIR}/09_all_ddls_${RUN_ID}.sql"
  local types_clause; types_clause="$(to_inlist_upper "TABLE,INDEX,VIEW,SEQUENCE,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE_BODY,MATERIALIZED_VIEW,TYPE,SYNONYM")"
  ddl_spool "$f" "
WITH owners AS (
  SELECT username AS owner FROM dba_users WHERE oracle_maintained='N'
),
objs AS (
  SELECT owner, object_type, object_name
  FROM dba_objects
  WHERE owner IN (SELECT owner FROM owners)
    AND object_type IN (${types_clause})
    AND object_name NOT LIKE 'BIN$%%'
    AND temporary = 'N'
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
  FROM dba_role_privs
  WHERE default_role = 'YES' AND grantee IN (SELECT username FROM u)
  GROUP BY grantee
)
SELECT 'ALTER USER '||username||' DEFAULT ROLE '||
       NVL(roles, 'ALL') || ';'
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
      B) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

#------------------------ Compare (no DB link) --------------------------------
snapshot_src_objects_csv() {
  local schema="${1^^}"
  [[ -z "$schema" ]] && { warn "Schema empty"; return 1; }
  local fname="${schema}_src_${RUN_ID}.csv"
  debug "snapshot_src_objects_csv(${schema}) -> ${fname} in ${COMMON_DIR_NAME} (on SOURCE)"

  run_sql "$SRC_EZCONNECT" "snap_src_csv_${schema}" "
SET SERVEROUTPUT ON
DECLARE
  f UTL_FILE.FILE_TYPE;
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'), '${fname}', 'W', 32767);
  FOR r IN (
    SELECT object_type, object_name, status
    FROM dba_objects
    WHERE owner = UPPER('${schema}')
      AND temporary = 'N'
      AND object_name NOT LIKE 'BIN$%'
    ORDER BY object_type, object_name
  ) LOOP
    UTL_FILE.PUT_LINE(f, r.object_type||'|'||r.object_name||'|'||r.status);
  END LOOP;
  UTL_FILE.FCLOSE(f);
END;
/
"
  ok "Source CSV snapshot written: ${NAS_PATH}/${fname}"
}

create_src_external_on_target() {
  local schema="${1^^}"
  local fname="${schema}_src_${RUN_ID}.csv"
  debug "create_src_external_on_target(${schema}) -> file=${fname}, dir=${COMMON_DIR_NAME}"

  run_sql "$TGT_EZCONNECT" "drop_ext_${schema}" "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE src_obj_snap_ext PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
"

  run_sql "$TGT_EZCONNECT" "create_ext_${schema}" "
CREATE TABLE src_obj_snap_ext (
  object_type    VARCHAR2(30),
  object_name    VARCHAR2(128),
  status         VARCHAR2(7)
)
ORGANIZATION EXTERNAL
( TYPE ORACLE_LOADER
  DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    FIELDS TERMINATED BY '|'
    MISSING FIELD VALUES ARE NULL
    ( object_type CHAR(30),
      object_name CHAR(128),
      status      CHAR(7) )
  )
  LOCATION ('${fname}')
)
REJECT LIMIT UNLIMITED;
/
"
  ok "External table src_obj_snap_ext created (TARGET) over ${fname}"
}

compare_one_schema_sql_external() {
  local schema="${1^^}"
  [[ -z "$schema" ]] && { warn "Schema empty"; return 1; }

  ensure_directory_object "$SRC_EZCONNECT" "src"
  ensure_directory_object "$TGT_EZCONNECT" "tgt"
  validate_directory_on_db "$SRC_EZCONNECT" "src"
  validate_directory_on_db "$TGT_EZCONNECT" "tgt"

  snapshot_src_objects_csv "$schema"
  create_src_external_on_target "$schema"

  local html="${COMPARE_DIR}/compare_${schema}_${RUN_ID}.html"
  local conn="sys/${SYS_PASSWORD}@${TGT_EZCONNECT} as sysdba"
  sqlplus -s "$conn" <<SQL >"$html" 2>"${html}.log"
SET MARKUP HTML ON SPOOL ON ENTMAP OFF
SPOOL $html
PROMPT <h2>Schema Compare Report: ${schema}</h2>
PROMPT <p>Run ID: ${RUN_ID} | Source: ${SRC_EZCONNECT} | Target: ${TGT_EZCONNECT}</p>
PROMPT <h3>Delta (SOURCE CSV vs TARGET)</h3>
WITH
src AS (
  SELECT object_type, object_name, status
  FROM src_obj_snap_ext s
),
tgt AS (
  SELECT object_type, object_name, status
  FROM dba_objects t
  WHERE t.owner = UPPER('${schema}')
    AND t.temporary = 'N'
    AND t.object_name NOT LIKE 'BIN$%'
),
j AS (
  SELECT
    COALESCE(src.object_type, tgt.object_type) AS object_type,
    COALESCE(src.object_name, tgt.object_name) AS object_name,
    src.status AS src_status,
    tgt.status AS tgt_status,
    CASE
      WHEN src.object_name IS NOT NULL AND tgt.object_name IS NULL THEN 'ONLY_IN_SOURCE'
      WHEN src.object_name IS NULL AND tgt.object_name IS NOT NULL THEN 'ONLY_IN_TARGET'
      WHEN src.status IS NOT NULL AND tgt.status IS NOT NULL AND src.status <> tgt.status THEN 'STATUS_DIFFERS'
      ELSE 'SAME'
    END AS delta_kind
  FROM src
  FULL OUTER JOIN tgt
    ON src.object_type = tgt.object_type
   AND src.object_name = tgt.object_name
)
SELECT object_type, object_name, src_status, tgt_status, delta_kind
FROM j
WHERE delta_kind <> 'SAME'
ORDER BY delta_kind, object_type, object_name
/
PROMPT <h3>Summary</h3>
WITH
src_cnt AS (SELECT COUNT(*) cnt FROM src_obj_snap_ext),
tgt_cnt AS (SELECT COUNT(*) cnt FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'),
j AS (
  SELECT CASE
           WHEN src.object_name IS NOT NULL AND tgt.object_name IS NULL THEN 'ONLY_IN_SOURCE'
           WHEN src.object_name IS NULL AND tgt.object_name IS NOT NULL THEN 'ONLY_IN_TARGET'
           WHEN src.status IS NOT NULL AND tgt.status IS NOT NULL AND src.status <> tgt.status THEN 'STATUS_DIFFERS'
           ELSE 'SAME'
         END AS delta_kind
  FROM src_obj_snap_ext src
  FULL OUTER JOIN
       (SELECT object_type, object_name, status
          FROM dba_objects
         WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%') tgt
    ON src.object_type=tgt.object_type AND src.object_name=tgt.object_name
)
SELECT * FROM (
  SELECT 'Source total objects' AS metric, (SELECT cnt FROM src_cnt) AS value FROM dual
  UNION ALL
  SELECT 'Target total objects', (SELECT cnt FROM tgt_cnt) FROM dual
  UNION ALL
  SELECT 'DDL only in source', NVL(COUNT(CASE WHEN delta_kind='ONLY_IN_SOURCE' THEN 1 END),0) FROM j
  UNION ALL
  SELECT 'DDL only in target', NVL(COUNT(CASE WHEN delta_kind='ONLY_IN_TARGET' THEN 1 END),0) FROM j
  UNION ALL
  SELECT 'Status differs',     NVL(COUNT(CASE WHEN delta_kind='STATUS_DIFFERS' THEN 1 END),0) FROM j
)
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

  if grep -qi "ORA-" "${html}.log"; then
    warn "HTML compare generation hit errors (see ${html}.log)"
  else
    ok "HTML compare report: ${html}"
  fi

  local subj="${MAIL_SUBJECT_PREFIX} Schema Compare - ${schema} - ${RUN_ID}"
  email_file "$html" "$subj"

  run_sql "$TGT_EZCONNECT" "drop_ext_post_${schema}" "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE src_obj_snap_ext PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
"
}

compare_many_sql_external() {
  local list_input="$1"
  local schemas_list=""
  if [[ -n "$list_input" ]]; then
    schemas_list="$list_input"
  else
    schemas_list="$(get_nonmaintained_schemas)"
    [[ -z "$schemas_list" ]] && { warn "No non-maintained schemas found on source."; return 0; }
    ok "Auto-compare schemas (from source): ${schemas_list}"
  fi

  local index="${COMPARE_DIR}/compare_index_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare Index ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare Index</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}</p>"
    echo "<table><tr><th>#</th><th>Schema</th><th>Report</th></tr>"
  } > "$index"

  local i=0
  IFS=',' read -r -a arr <<< "$schemas_list"
  for s in "${arr[@]}"; do
    s="$(echo "$s" | awk '{$1=$1;print}')"
    [[ -z "$s" ]] && continue
    i=$((i+1))
    compare_one_schema_sql_external "$s"
    local f="compare_${s^^}_${RUN_ID}.html"
    echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"
  done
  echo "</table></body></html>" >> "$index"
  ok "Index HTML: ${index}"
  email_file "$index" "${MAIL_SUBJECT_PREFIX} Compare Index - ${RUN_ID}"
}

#------------------------ Show jobs / cleanup dir ------------------------------
show_jobs() {
  ce "Logs under $LOG_DIR and NAS path: $NAS_PATH"
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

#------------------------ Menus & Main ----------------------------------------
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
Compare Objects (Source vs Target):
  1) SQL delta (NO DB LINK) for one schema (HTML + email)
  2) SQL delta (NO DB LINK) for multiple schemas (ENTER = all non-maintained on source) [HTML + email]
  3) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) read -rp "Schema name: " s; compare_one_schema_sql_external "$s" ;;
      2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_sql_external "${list:-}";;
      3) break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

main_menu() {
  while true; do
    cat <<EOS

======== Oracle 19c Migration & DDL (${SCRIPT_NAME} v4ac) ========
Source: ${SRC_EZCONNECT}
Target: ${TGT_EZCONNECT}
NAS:    ${NAS_PATH}
PARALLEL=${PARALLEL}  COMPRESSION=${COMPRESSION}  TABLE_EXISTS_ACTION=${TABLE_EXISTS_ACTION}
DDL out: ${DDL_DIR}
Compare out: ${COMPARE_DIR}
=============================================================

1) Precheck & create DIRECTORY on source and target
2) Data Pump (EXP/IMP)         -> sub menu
3) Monitor/Status              -> DBA_DATAPUMP_JOBS + tail logs
4) Drop DIRECTORY objects      -> cleanup
5) DDL Extraction (Source DB)  -> sub menu
6) Compare Objects (NO DB LINK)-> sub menu (HTML + email)
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
