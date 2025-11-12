#!/usr/bin/env bash
# dp_migrate.sh - Oracle 19c Data Pump migration & compare toolkit
# v5.0 (fresh consolidated build)
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
CONF_FILE="${1:-dp_migrate.conf}"
START_TS="$(date +%Y%m%d_%H%M%S)"
RUN_ID="${START_TS}_$$"
WORK_BASE="${WORK_BASE:-/tmp/dp_migrate_${RUN_ID}}"
LOG_DIR="${WORK_BASE}/logs"
DDL_DIR="${WORK_BASE}/ddls"
PAR_DIR="${WORK_BASE}/parfiles"
CMP_DIR="${WORK_BASE}/compare"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[DP-MIGRATE]}"
DEBUG="${DEBUG:-0}"
mkdir -p "$WORK_BASE" "$LOG_DIR" "$DDL_DIR" "$PAR_DIR" "$CMP_DIR"
say(){ printf "%s\n" "$*"; }
say_to_user(){ while read -r line; do echo "$line"; done; }
ok(){ printf "[ OK ] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*" >&2; }
err(){ printf "[FAIL] %s\n" "$*" >&2; }
debug(){ [[ "$DEBUG" == "1" ]] && printf "[DEBUG] %s\n" "$*" >&2 || true; }
toggle_debug(){ if [[ "$DEBUG" == "1" ]]; then DEBUG=0; ok "DEBUG turned OFF"; else DEBUG=1; ok "DEBUG turned ON"; fi; }
mask_pwd(){ sed -E 's#(//?)([^:@/]+):([^@/]+)@#\1\2:****@#g; s#(password=)[^ ]+#\1****#Ig'; }
press_enter(){ read -r -p "Press <Enter> to continue..." _ || true; }
if [[ ! -f "$CONF_FILE" ]]; then
  err "Config file not found: $CONF_FILE"
  exit 1
fi
. "$CONF_FILE"
: "${SRC_EZCONNECT:?missing SRC_EZCONNECT in conf}"
: "${TGT_EZCONNECT:?missing TGT_EZCONNECT in conf}"
: "${SYS_USER:?missing SYS_USER in conf}"
: "${SYS_PASSWORD:?missing SYS_PASSWORD in conf}"
DEFAULT_DIR_SRC="${DEFAULT_DIR_SRC:-DATAPUMP_DIR}"
DEFAULT_DIR_TGT="${DEFAULT_DIR_TGT:-DATAPUMP_DIR}"
MAIL_TO="${MAIL_TO:-}"
SKIP_SCHEMAS="${SKIP_SCHEMAS:-}"
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"
email_inline_html(){
  local html="$1" subj="$2"
  [[ ! -s "$html" ]] && { warn "No HTML to email ($html)"; return 0; }
  if [[ -n "${MAIL_TO:-}" ]]; then
    debug "Email ${MAIL_TO} subj='${subj}'"
    if command -v sendmail >/dev/null 2>&1; then
      { printf "Subject: %s\nContent-Type: text/html; charset=UTF-8\nTo: %s\n\n" "$subj" "$MAIL_TO"; cat "$html"; } | sendmail -t || warn "sendmail failed"
    elif command -v mail >/dev/null 2>&1; then
      mail -a "Content-Type: text/html" -s "$subj" "$MAIL_TO" <"$html" || warn "bsd mail failed"
    elif command -v mailx >/dev/null 2>&1; then
      mailx -a "Content-Type: text/html" -s "$subj" "$MAIL_TO" <"$html" || warn "mailx failed"
    elif command -v mutt >/dev/null 2>&1; then
      mutt -e 'set content_type="text/html"' -s "$subj" -- "$MAIL_TO" <"$html" || warn "mutt failed"
    else
      warn "No mailer found"
    fi
  else
    warn "MAIL_TO not set; skip email"
  fi
}
run_sql(){
  local ez="$1"; shift
  local tag="${1:-sql}"; shift || true
  local sql="$*"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql ${tag} on ${ez} -> $logf"
  sqlplus -s "$conn" >"$logf" 2>&1 <<SQL
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${sql}
/
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then
    err "SQL error: ${tag} (see $logf)"
    tail -n 80 "$logf" | mask_pwd
    exit 1
  fi
  ok "SQL ok: ${tag}"
}
run_sql_try(){
  local ez="$1"; shift
  local tag="${1:-sqltry}"; shift || true
  local sql="$*"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_try ${tag} on ${ez} -> $logf"
  set +e
  sqlplus -s "$conn" >"$logf" 2>&1 <<SQL
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${sql}
/
EXIT
SQL
  local rc=$?
  set -e
  if grep -qi "ORA-" "$logf"; then rc=1; fi
  if [[ $rc -ne 0 ]]; then
    warn "SQL (non-fatal) error on ${tag} — see $logf"
    tail -n 60 "$logf" | mask_pwd
    return 1
  fi
  ok "SQL ok (non-fatal): ${tag}"
  return 0
}
run_sql_spool_local(){
  local ez="$1"; shift
  local tag="$1"; shift
  local out="$1"; shift
  local body="$*"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_spool_local ${tag} -> spool $out ; log=$logf"
  sqlplus -s "$conn" >"$logf" 2>&1 <<SQL
SET PAGESIZE 0 LINESIZE 4000 LONG 1000000 LONGCHUNKSIZE 1000000 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
SPOOL $out
${body}
SPOOL OFF
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then
    err "SQL error: ${tag} (see $logf)"
    tail -n 80 "$logf" | mask_pwd
    exit 1
  fi
  ok "Spool ok: $out"
}
run_sql_capture(){
  local ez="$1"
  local body="$2"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local tmp="${LOG_DIR}/.capture_${RUN_ID}_$$.out"
  set +e
  sqlplus -s "$conn" >"$tmp" 2>&1 <<SQL
SET PAGES 0 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMSPOOL ON LINES 32767
SET LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${body}
/
EXIT
SQL
  local rc=$?
  set -e
  if grep -qi "ORA-" "$tmp"; then rc=1; fi
  if [[ $rc -ne 0 ]]; then echo ""; rm -f "$tmp"; return 0; fi
  awk 'NF{last=$0} END{print last}' "$tmp"
  rm -f "$tmp"
  return 0
}
run_sql_capture_all(){
  local ez="$1"
  local body="$2"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local tmp="${LOG_DIR}/.capall_${RUN_ID}_$$.out"
  set +e
  sqlplus -s "$conn" >"$tmp" 2>&1 <<SQL
SET PAGES 0 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMSPOOL ON LINES 32767
SET LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${body}
/
EXIT
SQL
  local rc=$?
  set -e
  cat "$tmp"
  rm -f "$tmp"
  return 0
}
_db_ident_block(){ cat <<'SQL'
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 400
WITH
  vdb AS (SELECT name db_name, dbid, db_unique_name, cdb FROM v$database),
  ver AS (SELECT MAX(banner) banner FROM v$version WHERE banner LIKE 'Oracle Database%'),
  patch AS (
    SELECT NVL(MAX(version||' '||REGEXP_REPLACE(description,' Patch','')), 'N/A') last_patch
    FROM dba_registry_sqlpatch
    WHERE action='APPLY' AND status='SUCCESS'
  ),
  nls AS (
    SELECT MAX(CASE WHEN parameter='NLS_CHARACTERSET' THEN value END) AS nls_charset,
           MAX(CASE WHEN parameter='NLS_NCHAR_CHARACTERSET' THEN value END) AS nls_nchar
    FROM nls_database_parameters
  ),
  con AS (SELECT sys_context('userenv','con_name') con_name FROM dual)
SELECT
  'DB_NAME='||vdb.db_name||CHR(10)||
  'DB_UNIQUE_NAME='||vdb.db_unique_name||CHR(10)||
  'CON_NAME='||con.con_name||CHR(10)||
  'CDB='||vdb.cdb||CHR(10)||
  'VERSION='||ver.banner||CHR(10)||
  'PATCH='||patch.last_patch||CHR(10)||
  'NLS_CHARACTERSET='||nls.nls_charset||CHR(10)||
  'NLS_NCHAR_CHARACTERSET='||nls.nls_nchar
FROM vdb, ver, patch, nls, con;
SQL
}
show_db_identity(){
  local ez="$1" which="$2"
  local info
  info="$(run_sql_capture_all "$ez" "$(_db_ident_block)")"
  echo "---- ${which} ----" | say_to_user
  if [[ -z "${info// }" ]]; then
    echo "(connection ok, but identity query returned no rows)" | say_to_user
  else
    echo "$info" | say_to_user
  fi
}
db_connection_validation(){
  ok "Validating connections…"
  show_db_identity "$SRC_EZCONNECT" "SOURCE"
  show_db_identity "$TGT_EZCONNECT" "TARGET"
  ok "Validation step finished."
  press_enter
}
check_or_create_directory(){
  local ez="$1" dir_name="$2" os_path="$3" scope="$4"
  debug "check_or_create_directory(${scope}) ${dir_name} => ${os_path}"
  run_sql_try "$ez" "dircheck_${scope}" "
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_directories WHERE directory_name = UPPER('${dir_name}');
  IF n = 0 THEN
    EXECUTE IMMEDIATE q'[CREATE OR REPLACE DIRECTORY ${dir_name} AS '${os_path}']';
  ELSE
    EXECUTE IMMEDIATE q'[CREATE OR REPLACE DIRECTORY ${dir_name} AS '${os_path}']';
  END IF;
END;
/
"
  if [[ $? -ne 0 ]]; then
    warn "[${scope}] DIRECTORY create/validate failed for ${dir_name} -> ${os_path}"
    return 1
  fi
  ok "[${scope}] DIRECTORY ready: ${dir_name}"
  return 0
}
ddl_spool(){
  local out="$1"; shift
  local label="${1:-}"; shift || true
  local body="$*"
  [[ -z "$label" ]] && label="$(basename "${out%.sql}" | sed 's/^[0-9]\+_//')"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"
  local seslog="${out}.log"
  local tmp="${out}.tmp.body"
  debug "DDL spool -> ${out} (label=${label})"
  sqlplus -s "$conn" >"$tmp" 2>"$seslog" <<SQL
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767 LONG 1000000 LONGCHUNKSIZE 1000000 TRIMSPOOL ON TRIMOUT ON VERIFY OFF
SET DEFINE OFF
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
/
EXIT
SQL
  {
    cat <<'SQL'
-- Generated by ${SCRIPT_NAME} @ ${RUN_ID}
SET TERMOUT ON ECHO ON FEEDBACK ON LINES 32767 PAGES 0 SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE ON
COLUMN V_DBNAME NEW_VALUE V_DBNAME
COLUMN V_TS     NEW_VALUE V_TS
SELECT name V_DBNAME FROM v$database;
SELECT TO_CHAR(SYSDATE,'YYYYMMDD_HH24MISS') V_TS FROM dual;
SQL
    echo "DEFINE V_SCRIPT='${label}'"
    cat <<'SQL'
SPOOL &&V_DBNAME._&&V_SCRIPT._&&V_TS..log
SET DEFINE OFF
SQL
  } > "$out"
  cat "$tmp" >> "$out"
  echo "SPOOL OFF" >> "$out"
  rm -f "$tmp"
  if grep -qi "ORA-" "$seslog"; then
    err "DDL extract error in $(basename "$out") — see $seslog"
    tail -n 80 "$seslog" | mask_pwd
    return 1
  fi
  ok "DDL file created (with dynamic SPOOL prolog): $out"
}
_skip_users_in_list(){
  if [[ -z "${SKIP_SCHEMAS:-}" ]]; then echo "''"; return; fi
  awk -v list="$SKIP_SCHEMAS" 'BEGIN{n=split(list,a,","); for(i=1;i<=n;i++){gsub(/^ *| *$/,"",a[i]); printf i>1?",":""; printf "'"%s"'", a[i]} }'
}
ddl_sysprivs_to_users(){
  local out="${DDL_DIR}/sysprivs_to_users_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "sysprivs_to_users" "
SELECT DBMS_METADATA.get_granted_ddl('SYSTEM_GRANT', grantee)||';'
  FROM dba_sys_privs
 WHERE grantee NOT IN (${_skip});
"
}
ddl_privs_to_roles(){
  local out="${DDL_DIR}/privs_to_roles_${RUN_ID}.sql"
  ddl_spool "$out" "privs_to_roles" "
SELECT DBMS_METADATA.get_granted_ddl('SYSTEM_GRANT', role)||';'
  FROM dba_sys_privs
 WHERE grantee IN (SELECT role FROM dba_roles)
 ORDER BY role;
"
}
ddl_role_grants_to_users(){
  local out="${DDL_DIR}/role_grants_to_users_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "role_grants_to_users" "
SELECT DBMS_METADATA.get_granted_ddl('ROLE_GRANT', grantee)||';'
  FROM dba_role_privs
 WHERE grantee NOT IN (${_skip})
 ORDER BY grantee;
"
  echo "/* Optional: ensure default role ALL */" >>"$out"
  run_sql_capture_all "$SRC_EZCONNECT" "SELECT username FROM dba_users WHERE oracle_maintained='N';"     | awk 'NF{printf "ALTER USER %s DEFAULT ROLE ALL;\n", $0}' >>"$out" || true
}
ddl_public_synonyms(){
  local out="${DDL_DIR}/public_synonyms_${RUN_ID}.sql"
  ddl_spool "$out" "public_synonyms" "
SELECT DBMS_METADATA.get_ddl('SYNONYM','', 'PUBLIC')||';' FROM dual;
"
}
ddl_private_synonyms(){
  local out="${DDL_DIR}/private_synonyms_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "private_synonyms" "
SELECT DBMS_METADATA.get_ddl('SYNONYM', synonym_name, owner)||';'
  FROM dba_synonyms
 WHERE owner NOT IN ('PUBLIC') AND owner NOT IN (${_skip});
"
}
ddl_sequences_all_users(){
  local out="${DDL_DIR}/sequences_all_users_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "sequences_all_users" "
SELECT DBMS_METADATA.get_ddl('SEQUENCE', sequence_name, sequence_owner)||';'
  FROM dba_sequences
 WHERE sequence_owner NOT IN (${_skip});
"
}
ddl_roles(){
  local out="${DDL_DIR}/roles_${RUN_ID}.sql"
  ddl_spool "$out" "roles" "
SELECT DBMS_METADATA.get_ddl('ROLE', role)||';'
  FROM dba_roles
 WHERE oracle_maintained='N'
 ORDER BY role;
"
}
ddl_profiles(){
  local out="${DDL_DIR}/profiles_${RUN_ID}.sql"
  ddl_spool "$out" "profiles" "
SELECT DBMS_METADATA.get_ddl('PROFILE', profile)||';'
  FROM dba_profiles
 GROUP BY profile
 ORDER BY profile;
"
}
ddl_tablespaces(){
  local out="${DDL_DIR}/tablespaces_${RUN_ID}.sql"
  ddl_spool "$out" "tablespaces" "
SELECT DBMS_METADATA.get_ddl('TABLESPACE', tablespace_name)||';' FROM dba_tablespaces;
"
}
ddl_directories(){
  local out="${DDL_DIR}/directories_${RUN_ID}.sql"
  ddl_spool "$out" "directories" "
SELECT DBMS_METADATA.get_ddl('DIRECTORY', directory_name)||';' FROM dba_directories;
"
}
ddl_db_links(){
  local out="${DDL_DIR}/dblinks_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "dblinks" "
SELECT DBMS_METADATA.get_ddl('DB_LINK', db_link, owner)||';'
  FROM dba_db_links
 WHERE owner NOT IN (${_skip});
"
}
ddl_all_users_objects(){
  local out="${DDL_DIR}/all_users_objects_${RUN_ID}.sql"
  local _skip="$(_skip_users_in_list)"
  ddl_spool "$out" "all_users_objects" "
SELECT DBMS_METADATA.get_ddl(object_type, object_name, owner)||';'
  FROM dba_objects
 WHERE owner NOT IN (${_skip})
   AND object_type IN ('TABLE','INDEX','VIEW','MATERIALIZED VIEW','TRIGGER','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TYPE','SYNONYM','SEQUENCE')
 ORDER BY owner, object_type, object_name;
"
}
par_common(){
  local mode="${1:-full}"
  local content="DIRECTORY=${PAR_DIRNAME}
LOGTIME=ALL
METRICS=Y
PARALLEL=${PARALLEL:-1}
COMPRESSION=${COMPRESSION:-ALL}"
  if [[ "$mode" == "schemas" && -n "${SCHEMAS_CSV:-}" ]]; then
    content="$content
SCHEMAS=${SCHEMAS_CSV}"
  fi
  echo "$content"
}
dp_run(){
  local tool="$1" ez="$2" pf="$3" tag="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba"
  local client_log="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.client.log"
  debug "dp_run ${tool} on ${ez} parfile=$pf"
  set +e
  ${tool} parfile="$pf" >"$client_log" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    err "${tool} failed (rc=$rc). See $client_log"
  else
    ok "${tool} completed. See $client_log"
  fi
  dp_emit_html_and_email "$tool" "$tag" "$pf" "$client_log"
  press_enter
}
dp_emit_html_and_email(){
  local tool="$1" tag="$2" pf="$3" client_log="$4"
  local html="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.html"
  cat > "$html" <<'HTML'
<html><head><meta charset="utf-8"><title>__TITLE__</title>
<style>
body{font-family:Arial,Helvetica,sans-serif}
pre{white-space:pre-wrap;border:1px solid #ddd;padding:10px;background:#fafafa}
.box{border:1px solid #ccc;padding:10px;margin:8px 0}
</style>
</head><body>
<h2>__HEADER__</h2>
<p><b>Run:</b> __RUNID__ <b>Tool:</b> __TOOL__ <b>Tag:</b> __TAG__</p>
<div class="box"><h3>Parfile</h3><pre>
__PARFILE__
</pre></div>
<div class="box"><h3>Client Log</h3><pre>
__CLIENTLOG__
</pre></div>
</body></html>
HTML
  sed -i "s/__TITLE__/${tool^^} ${tag} ${RUN_ID}/g" "$html"
  sed -i "s/__HEADER__/${tool^^} job completed/g" "$html"
  sed -i "s/__RUNID__/${RUN_ID}/g" "$html"
  sed -i "s/__TOOL__/${tool}/g" "$html"
  sed -i "s/__TAG__/${tag}/g" "$html"
  local par_tmp="${LOG_DIR}/.tmp_par_${RUN_ID}.txt"
  if [[ -f "$pf" ]]; then
    sed -E 's/(encryption_password=).*/\1*****/I' "$pf" | sed 's/&/\&amp;/g;s/</\&lt;/g' > "$par_tmp"
  else
    echo "(parfile not found: $pf)" > "$par_tmp"
  fi
  perl -0777 -pe "s/__PARFILE__/`sed -e 's/[\\&]/\\&/g' "$par_tmp"`/g" -i "$html" 2>/dev/null ||   sed -i "s|__PARFILE__|$(sed -e 's/[\/&]/\&/g' "$par_tmp")|g" "$html"
  local log_tmp="${LOG_DIR}/.tmp_log_${RUN_ID}.txt"
  if [[ -f "$client_log" ]]; then
    sed 's/&/\&amp;/g;s/</\&lt;/g' "$client_log" > "$log_tmp"
  else
    echo "(client log not found: $client_log)" > "$log_tmp"
  fi
  perl -0777 -pe "s/__CLIENTLOG__/`sed -e 's/[\\&]/\\&/g' "$log_tmp"`/g" -i "$html" 2>/dev/null ||   sed -i "s|__CLIENTLOG__|$(sed -e 's/[\/&]/\&/g' "$log_tmp")|g" "$html"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} ${tool^^} ${tag} ${RUN_ID}" || true
}
export_full(){
  local ez="$1"
  read -r -p "EXPORT (FULL). Enter server filesystem path for dumpfiles: " dirpath
  [[ -z "$dirpath" ]] && { warn "No path provided."; return; }
  local dpdir="${DEFAULT_DIR_SRC}"
  if ! check_or_create_directory "$ez" "$dpdir" "$dirpath" "src"; then
    warn "Could not validate/create DIRECTORY on source. Returning to Export menu."; return; fi
  read -r -p "Dumpfile name (pattern ok, e.g. expfull_%U.dmp): " dump_pat
  dump_pat="${dump_pat:-expfull_%U.dmp}"
  read -r -p "Content [a=ALL, m=METADATA_ONLY] (a/m): " cm
  local content="ALL"; [[ "$cm" == "m" ]] && content="METADATA_ONLY"
  local pf="${dirpath}/exp_full_${RUN_ID}.par"
  {
    echo "DIRECTORY=${dpdir}"; echo "DUMPFILE=${dump_pat}"; echo "LOGFILE=exp_full_${RUN_ID}.log"
    echo "CONTENT=${content}"; echo "FULL=Y"; echo "PARALLEL=${PARALLEL:-1}"; echo "LOGTIME=ALL"; echo "METRICS=Y"
  } > "$pf"
  say "Parfile preview [$pf]:"; sed -n '1,200p' "$pf"
  read -r -p "Proceed with EXPDP FULL? (y/N): " go; [[ "$go" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  dp_run expdp "$ez" "$pf" "full"
}
export_schemas(){
  local ez="$1"
  read -r -p "EXPORT (SCHEMAS). Enter server filesystem path for dumpfiles: " dirpath
  [[ -z "$dirpath" ]] && { warn "No path provided."; return; }
  local dpdir="${DEFAULT_DIR_SRC}"
  if ! check_or_create_directory "$ez" "$dpdir" "$dirpath" "src"; then
    warn "Could not validate/create DIRECTORY on source. Returning to Export menu."; return; fi
  read -r -p "Schemas (CSV) or leave blank to export all non-maintained: " schemas_csv
  if [[ -z "$schemas_csv" ]]; then
    schemas_csv="$(run_sql_capture_all "$ez" "SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM dba_users WHERE oracle_maintained='N';")"
  fi
  read -r -p "Dumpfile name (pattern ok, e.g. expschemas_%U.dmp): " dump_pat
  dump_pat="${dump_pat:-expschemas_%U.dmp}"
  read -r -p "Content [a=ALL, m=METADATA_ONLY] (a/m): " cm
  local content="ALL"; [[ "$cm" == "m" ]] && content="METADATA_ONLY"
  local pf="${dirpath}/exp_schemas_${RUN_ID}.par"
  {
    echo "DIRECTORY=${dpdir}"; echo "DUMPFILE=${dump_pat}"; echo "LOGFILE=exp_schemas_${RUN_ID}.log"
    echo "CONTENT=${content}"; echo "SCHEMAS=${schemas_csv}"; echo "PARALLEL=${PARALLEL:-1}"; echo "LOGTIME=ALL"; echo "METRICS=Y"
  } > "$pf"
  say "Parfile preview [$pf]:"; sed -n '1,200p' "$pf"
  read -r -p "Proceed with EXPDP SCHEMAS? (y/N): " go; [[ "$go" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  dp_run expdp "$ez" "$pf" "schemas"
}
import_full(){
  local ez="$1"
  read -r -p "IMPORT (FULL). Enter server filesystem path where dumpfiles reside: " dirpath
  [[ -z "$dirpath" ]] && { warn "No path provided."; return; }
  local dpdir="${DEFAULT_DIR_TGT}"
  if ! check_or_create_directory "$ez" "$dpdir" "$dirpath" "tgt"; then
    warn "Could not validate/create DIRECTORY on target. Returning to Import menu."; return; fi
  read -r -p "Dumpfile name (e.g. expfull_%U.dmp): " dump_pat
  dump_pat="${dump_pat:-expfull_%U.dmp}"
  local pf="${dirpath}/imp_full_${RUN_ID}.par"
  { echo "DIRECTORY=${dpdir}"; echo "DUMPFILE=${dump_pat}"; echo "LOGFILE=imp_full_${RUN_ID}.log"; echo "FULL=Y"; echo "PARALLEL=${PARALLEL:-1}"; echo "LOGTIME=ALL"; echo "METRICS=Y"; } > "$pf"
  say "Parfile preview [$pf]:"; sed -n '1,200p' "$pf"
  read -r -p "Proceed with IMPDP FULL? (y/N): " go; [[ "$go" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  dp_run impdp "$ez" "$pf" "full"
}
import_schemas(){
  local ez="$1"
  read -r -p "IMPORT (SCHEMAS). Enter server filesystem path where dumpfiles reside: " dirpath
  [[ -z "$dirpath" ]] && { warn "No path provided."; return; }
  local dpdir="${DEFAULT_DIR_TGT}"
  if ! check_or_create_directory "$ez" "$dpdir" "$dirpath" "tgt"; then
    warn "Could not validate/create DIRECTORY on target. Returning to Import menu."; return; fi
  read -r -p "Dumpfile name (e.g. expschemas_%U.dmp): " dump_pat
  dump_pat="${dump_pat:-expschemas_%U.dmp}"
  read -r -p "Schemas (CSV) or leave blank to import all contained: " schemas_csv
  local pf="${dirpath}/imp_schemas_${RUN_ID}.par"
  { echo "DIRECTORY=${dpdir}"; echo "DUMPFILE=${dump_pat}"; echo "LOGFILE=imp_schemas_${RUN_ID}.log"; [[ -n "$schemas_csv" ]] && echo "SCHEMAS=${schemas_csv}"; echo "PARALLEL=${PARALLEL:-1}"; echo "LOGTIME=ALL"; echo "METRICS=Y"; } > "$pf"
  say "Parfile preview [$pf]:"; sed -n '1,200p' "$pf"
  read -r -p "Proceed with IMPDP SCHEMAS? (y/N): " go; [[ "$go" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  dp_run impdp "$ez" "$pf" "schemas"
}
ddl_execute_on_target(){
  db_connection_validation
  local default_dir="${DDL_DIR}"
  say "Default DDL directory: $default_dir"
  read -r -p "Use this directory? (Y/n): " yn
  local dir="${default_dir}"
  if [[ "$yn" =~ ^[Nn]$ ]]; then read -r -p "Enter directory containing .sql to run: " dir; fi
  [[ -d "$dir" ]] || { warn "Directory not found: $dir"; return; }
  say "Files:"; ls -1 "$dir" | sed 's/^/  - /'
  read -r -p "Enter filename to execute: " fname
  local fpath="${dir}/${fname}"
  [[ -f "$fpath" ]] || { warn "File not found: $fpath"; return; }
  say "About to run on TARGET: $fpath"; read -r -p "Confirm? (y/N): " go; [[ "$go" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  local conn="${SYS_USER}/${SYS_PASSWORD}@${TGT_EZCONNECT} as sysdba"
  local client_log="${LOG_DIR}/ddl_exec_${RUN_ID}.log"
  set +e; sqlplus -s "$conn" @"$fpath" >"$client_log" 2>&1; local rc=$?; set -e
  if [[ $rc -ne 0 ]] || grep -qi "ORA-" "$client_log"; then err "DDL execution failed. See $client_log"; else ok "DDL executed. See $client_log"; fi
  dp_emit_html_and_email "ddl_exec" "$(basename "$fpath")" "$fpath" "$client_log"; press_enter
}
collect_schema_inventory(){
  local ez="$1" side="$2" outdir="$3" schemas_csv="$4"
  mkdir -p "$outdir"
  local inv="${outdir}/${side}_inventory_${RUN_ID}.csv"
  local inv_rows="${outdir}/${side}_rowcounts_${RUN_ID}.csv"
  local inv_invalid="${outdir}/${side}_invalid_${RUN_ID}.csv"
  local inv_roles="${outdir}/${side}_roles_${RUN_ID}.csv"
  local inv_role_grants="${outdir}/${side}_role_grants_${RUN_ID}.csv"
  local inv_sysprivs="${outdir}/${side}_sysprivs_${RUN_ID}.csv"
  debug "Collect inventory (${side}) -> ${outdir}"
  run_sql_spool_local "$ez" "inv_objs_${side}" "$inv" "
SELECT owner||','||object_type||','||COUNT(*)
  FROM dba_objects
 WHERE owner IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)
 GROUP BY owner, object_type
 ORDER BY owner, object_type;
"
  run_sql_spool_local "$ez" "inv_invalid_${side}" "$inv_invalid" "
SELECT owner||','||object_type||','||object_name
  FROM dba_objects
 WHERE status='INVALID'
   AND owner IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)
 ORDER BY owner, object_type, object_name;
"
  if [[ "${EXACT_ROWCOUNT}" == "Y" ]]; then
    run_sql_spool_local "$ez" "inv_rows_${side}" "$inv_rows" "
SET SERVEROUTPUT ON
DECLARE v_cnt NUMBER; BEGIN
  FOR r IN (SELECT owner, table_name FROM dba_tables
             WHERE owner IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM '||DBMS_ASSERT.sql_object_name(r.owner||'.'||r.table_name) INTO v_cnt;
    dbms_output.put_line(r.owner||','||r.table_name||','||v_cnt);
  END LOOP;
END;
/
"
  else
    run_sql_spool_local "$ez" "inv_rows_${side}" "$inv_rows" "
SELECT owner||','||table_name||','||NVL(num_rows,-1)
  FROM dba_tables
 WHERE owner IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)
 ORDER BY owner, table_name;
"
  fi
  run_sql_spool_local "$ez" "inv_roles_${side}" "$inv_roles" "SELECT role FROM dba_roles WHERE oracle_maintained='N' ORDER BY role;"
  run_sql_spool_local "$ez" "inv_role_grants_${side}" "$inv_role_grants" "
SELECT grantee||','||granted_role FROM dba_role_privs
 WHERE grantee IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)
 ORDER BY grantee, granted_role;
"
  run_sql_spool_local "$ez" "inv_sysprivs_${side}" "$inv_sysprivs" "
SELECT grantee||','||privilege FROM dba_sys_privs
 WHERE grantee IN (SELECT REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) FROM dual CONNECT BY REGEXP_SUBSTR('${schemas_csv}','[^,]+',1,LEVEL) IS NOT NULL)
 ORDER BY grantee, privilege;
"
  ok "Inventory (${side}) collected in ${outdir}"
}
compare_schemas_offline(){
  say "Offline compare — no DB links, using jumper. You'll create two inventories then generate HTML."
  read -r -p "Schemas CSV (leave blank for all non-maintained users): " schemas_csv
  if [[ -z "$schemas_csv" ]]; then
    schemas_csv="$(run_sql_capture_all "$SRC_EZCONNECT" "SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM dba_users WHERE oracle_maintained='N';")"
  fi
  say "Schemas: ${schemas_csv}"
  local outdir="${CMP_DIR}/cmp_${RUN_ID}"; mkdir -p "$outdir"
  say "[1/3] Collect SOURCE side"; collect_schema_inventory "$SRC_EZCONNECT" "src" "$outdir" "$schemas_csv"
  say "[2/3] Collect TARGET side"; collect_schema_inventory "$TGT_EZCONNECT" "tgt" "$outdir" "$schemas_csv"
  say "[3/3] Building HTML report"; local html="${outdir}/schema_compare_${RUN_ID}.html"
  local src_ident tgt_ident
  src_ident="$(run_sql_capture_all "$SRC_EZCONNECT" "$(_db_ident_block)")"
  tgt_ident="$(run_sql_capture_all "$TGT_EZCONNECT" "$(_db_ident_block)")"
  {
    cat <<'H1'
<html><head><meta charset="utf-8"><title>Schema Compare</title>
<style>
body{font-family:Arial,Helvetica,sans-serif}
table{border-collapse:collapse;margin:8px 0;width:100%}
th,td{border:1px solid #ccc;padding:6px 8px;font-size:13px}
th{background:#f5f5f5}
pre{white-space:pre-wrap;background:#fafafa;border:1px solid #ddd;padding:8px}
h2{margin-top:1.2em}
.match{color:#0a0}
.nomatch{color:#c00}
</style></head><body>
<h1>Schema Compare Summary</h1>
H1
    echo "<h2>DB Identity</h2>"
    echo "<div style='display:flex;gap:16px'>"
    echo "<div style='flex:1'><h3>Source</h3><pre>$(echo "$src_ident" | sed 's/&/\&amp;/g; s/</\&lt;/g')</pre></div>"
    echo "<div style='flex:1'><h3>Target</h3><pre>$(echo "$tgt_ident" | sed 's/&/\&amp;/g; s/</\&lt;/g')</pre></div>"
    echo "</div>"
    echo "<h2>Object counts by type (side by side)</h2>"
    echo "<table><tr><th>Schema</th><th>Object Type</th><th>SOURCE Count</th><th>TARGET Count</th><th>Match?</th></tr>"
    declare -A SRC_MAP TGT_MAP
  } > "$html"
  while IFS=, read -r owner obj_type cnt; do SRC_MAP["$owner|$obj_type"]="$cnt"; done < "${outdir}/src_inventory_${RUN_ID}.csv"
  while IFS=, read -r owner obj_type cnt; do TGT_MAP["$owner|$obj_type"]="$cnt"; done < "${outdir}/tgt_inventory_${RUN_ID}.csv"
  {
    for key in "${!SRC_MAP[@]}" "${!TGT_MAP[@]}"; do echo "$key"; done | awk ' !seen[$0]++ ' | while read -r key; do
      owner="${key%%|*}"; obj_type="${key#*|}"; s="${SRC_MAP[$key]:-0}"; t="${TGT_MAP[$key]:-0}"; match_cls="match"; [[ "$s" != "$t" ]] && match_cls="nomatch"
      printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class=\"%s\">%s</td></tr>\n" "$owner" "$obj_type" "$s" "$t" "$match_cls" "$([[ "$s" == "$t" ]] && echo "Match" || echo "NO")"
    done
    echo "</table>"
    echo "<h2>Table row counts (side by side)</h2>"
    echo "<table><tr><th>Schema</th><th>Table</th><th>SOURCE Rows</th><th>TARGET Rows</th><th>Match?</th></tr>"
  } >> "$html"
  declare -A SRC_ROWS TGT_ROWS
  while IFS=, read -r owner tbl cnt; do SRC_ROWS["$owner|$tbl"]="$cnt"; done < "${outdir}/src_rowcounts_${RUN_ID}.csv"
  while IFS=, read -r owner tbl cnt; do TGT_ROWS["$owner|$tbl"]="$cnt"; done < "${outdir}/tgt_rowcounts_${RUN_ID}.csv"
  {
    for key in "${!SRC_ROWS[@]}" "${!TGT_ROWS[@]}"; do echo "$key"; done | awk ' !seen[$0]++ ' | while read -r key; do
      owner="${key%%|*}"; tbl="${key#*|}"; s="${SRC_ROWS[$key]:-0}"; t="${TGT_ROWS[$key]:-0}"; cls="match"; [[ "$s" != "$t" ]] && cls="nomatch"
      printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class=\"%s\">%s</td></tr>\n" "$owner" "$tbl" "$s" "$t" "$cls" "$([[ "$s" == "$t" ]] && echo "Match" || echo "NO")"
    done
    echo "</table>"
    echo "<h2>Invalid objects</h2><div style='display:flex;gap:16px'>"
    echo "<div style='flex:1'><h3>Source</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/src_invalid_${RUN_ID}.csv")</pre></div>"
    echo "<div style='flex:1'><h3>Target</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/tgt_invalid_${RUN_ID}.csv")</pre></div>"
    echo "</div>"
    echo "<h2>Roles, role grants, system privileges (summaries)</h2><div style='display:flex;gap:16px'>"
    echo "<div style='flex:1'><h3>Source roles</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/src_roles_${RUN_ID}.csv")</pre></div>"
    echo "<div style='flex:1'><h3>Target roles</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/tgt_roles_${RUN_ID}.csv")</pre></div>"
    echo "</div>"
    echo "<div style='display:flex;gap:16px'>"
    echo "<div style='flex:1'><h3>Source role grants</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/src_role_grants_${RUN_ID}.csv")</pre></div>"
    echo "<div style='flex:1'><h3>Target role grants</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/tgt_role_grants_${RUN_ID}.csv")</pre></div>"
    echo "</div>"
    echo "<div style='display:flex;gap:16px'>"
    echo "<div style='flex:1'><h3>Source sys privs</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/src_sysprivs_${RUN_ID}.csv")</pre></div>"
    echo "<div style='flex:1'><h3>Target sys privs</h3><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "${outdir}/tgt_sysprivs_${RUN_ID}.csv")</pre></div>"
    echo "</div>"
    echo "</body></html>"
  } >> "$html"
  ok "HTML report created: $html"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Schema Compare ${RUN_ID}" || true
  say "Report: $html"
  press_enter
}
menu_export(){
  while true; do
    cat <<EOF
[Export Menu]
  a) Full
  b) Schemas
  x) Back
EOF
    read -r -p "Select [a/b/x]: " ch
    case "$ch" in
      a|A) export_full "$SRC_EZCONNECT" ;;
      b|B) export_schemas "$SRC_EZCONNECT" ;;
      x|X) return ;;
      *) warn "Invalid choice";;
    esac
  done
}
menu_import(){
  while true; do
    cat <<EOF
[Import Menu]
  a) Full
  b) Schemas
  c) DDL Execution (Target)
  x) Back
EOF
    read -r -p "Select [a/b/c/x]: " ch
    case "$ch" in
      a|A) import_full "$TGT_EZCONNECT" ;;
      b|B) import_schemas "$TGT_EZCONNECT" ;;
      c|C) ddl_execute_on_target ;;
      x|X) return ;;
      *) warn "Invalid choice";;
    esac
  done
}
menu_ddl_extract(){
  _skip_users_in_list="$(_skip_users_in_list)"
  while true; do
    cat <<EOF
[DDL Extraction]
  1) System privileges -> users
  2) Privileges -> roles
  3) Role grants -> users (+ default role all)
  4) Public synonyms
  5) Private synonyms (non-maintained owners)
  6) Sequences (non-maintained owners)
  7) Roles (non-maintained)
  8) Profiles
  9) Tablespaces
  10) Directories
  11) DB Links (non-maintained owners)
  12) All DDLs for all non-maintained users (common object types)
  x) Back
EOF
    read -r -p "Choose: " ch
    case "$ch" in
      1) ddl_sysprivs_to_users ;;
      2) ddl_privs_to_roles ;;
      3) ddl_role_grants_to_users ;;
      4) ddl_public_synonyms ;;
      5) ddl_private_synonyms ;;
      6) ddl_sequences_all_users ;;
      7) ddl_roles ;;
      8) ddl_profiles ;;
      9) ddl_tablespaces ;;
      10) ddl_directories ;;
      11) ddl_db_links ;;
      12) ddl_all_users_objects ;;
      x|X) return ;;
      *) warn "Invalid choice";;
    esac
  done
}
main_menu(){
  while true; do
    cat <<EOF
== ${SCRIPT_NAME} (v5.0) ==
Workdir: ${WORK_BASE}
Logdir : ${LOG_DIR}
DEBUG  : ${DEBUG}
  1) Export
  2) Validate DB connections
  3) Import
  4) DDL Extraction
  5) Compare Schemas (offline, no dblink)
  6) Toggle DEBUG on/off
  x) Exit
EOF
    read -r -p "Select: " m
    case "$m" in
      1) menu_export ;;
      2) db_connection_validation ;;
      3) menu_import ;;
      4) menu_ddl_extract ;;
      5) compare_schemas_offline ;;
      6) toggle_debug ;;
      x|X) exit 0 ;;
      *) warn "Invalid choice";;
    esac
  done
}
main_menu
