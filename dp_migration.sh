#!/usr/bin/env bash
# dp_migrate.sh (v4ax) - Oracle 19c Data Pump migration, DDL, and Compare toolkit
# NOTE: This is a consolidated script with EXP/IMP menus, DDL extract, DDL execution,
#       LOCAL compare (no dblinks), dynamic DDL SPOOL headers, and inline email of HTML logs.

set -euo pipefail

CONFIG_FILE="${1:-dp_migrate.conf}"
SCRIPT_NAME="$(basename "$0")"
RUN_ID="$(date +%Y%m%d_%H%M%S)"

WORK_DIR="${WORK_DIR:-/tmp/dp_migrate_${RUN_ID}}"
LOG_DIR="${LOG_DIR:-${WORK_DIR}/logs}"
PAR_DIR="${PAR_DIR:-${WORK_DIR}/parfiles}"
DDL_DIR="${DDL_DIR:-${WORK_DIR}/ddls}"
COMPARE_DIR="${COMPARE_DIR:-${WORK_DIR}/compare}"
COMMON_DIR_NAME="${COMMON_DIR_NAME:-DP_DIR}"
LOCAL_COMPARE_DIR="${LOCAL_COMPARE_DIR:-/tmp/dp_compare}"

mkdir -p "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$DDL_DIR" "$COMPARE_DIR" "$LOCAL_COMPARE_DIR"

ce(){ printf "%b\n" "$*"; }
ok(){ ce "\e[32m✔ $*\e[0m"; }
warn(){ ce "\e[33m! $*\e[0m"; }
err(){ ce "\e[31m✘ $*\e[0m"; }
DEBUG="${DEBUG:-Y}"
debug(){ [[ "${DEBUG^^}" == "Y" ]] && ce "\e[36m[DEBUG]\e[0m $*" >&2 || true; }

say_to_user(){ if [[ -w /dev/tty ]]; then cat >/dev/tty; else cat 1>&2; fi; }
toggle_debug(){ if [[ "${DEBUG^^}" == "Y" ]]; then DEBUG="N"; ok "DEBUG OFF"; else DEBUG="Y"; ok "DEBUG ON"; fi; ce "DEBUG=${DEBUG}"; }

[[ -f "$CONFIG_FILE" ]] || { err "Missing conf: $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

need_vars=( SYS_USER SYS_PASSWORD SRC_EZCONNECT TGT_EZCONNECT DUMPFILE_PREFIX )
for v in "${need_vars[@]}"; do [[ -n "${!v:-}" ]] || { err "Missing config var: $v"; exit 1; }; done

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
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[Oracle DP]}"
MAIL_METHOD="${MAIL_METHOD:-auto}"

COMPARE_ENGINE="${COMPARE_ENGINE:-LOCAL}"
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"

EXPORT_DIR_PATH="${EXPORT_DIR_PATH:-${NAS_PATH:-}}"
IMPORT_DIR_PATH="${IMPORT_DIR_PATH:-}"
NAS_PATH="${NAS_PATH:-}"

for b in sqlplus expdp impdp; do command -v "$b" >/dev/null 2>&1 || { err "Missing binary: $b"; exit 1; }; done

mask_pwd(){ sed 's#[^/"]\{1,\}@#***@#g' | sed "s#${SYS_USER}/[^@]*@#${SYS_USER}/****@#g"; }
basename_safe(){ local x="${1:-}"; x="${x##*/}"; printf "%s" "$x"; }

parfile_dir_for_mode(){
  local mode="${1}" preferred=""; case "${mode}" in expdp) preferred="${EXPORT_DIR_PATH:-}";; impdp) preferred="${IMPORT_DIR_PATH:-}";; esac
  if [[ -n "$preferred" && -d "$preferred" && -w "$preferred" ]]; then echo "$preferred"; else echo "$PAR_DIR"; fi
}

run_sql(){
  local ez="$1"; shift; local tag="${1:-sql}"; shift || true; local sql="$*"
  local conn="${SYS_USER; local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql ${tag} on ${ez}"; sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${sql}
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then err "SQL error: ${tag}"; tail -n 80 "$logf" | mask_pwd; exit 1; fi
  ok "SQL ok: ${tag}"
}

run_sql_try(){
  local ez="$1"; shift; local tag="${1:-sqltry}"; shift || true; local sql="$*"
  local conn="${SYS_USER; local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_try ${tag} on ${ez}"; sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${sql}
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then warn "SQL (non-fatal) error on ${tag}"; tail -n 60 "$logf" | mask_pwd; return 1; fi
  ok "SQL ok (non-fatal): ${tag}"; return 0
}

run_sql_spool_local(){
  local ez="$1"; shift; local tag="$1"; shift; local out="$1"; shift; local body="$*"
  local conn="${SYS_USER; local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "spool_local ${tag} -> ${out}"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGESIZE 0 LINESIZE 4000 LONG 1000000 LONGCHUNKSIZE 1000000 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
SPOOL $out
${body}
SPOOL OFF
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then err "SQL error: ${tag}"; tail -n 80 "$logf" | mask_pwd; exit 1; fi
  ok "Spool ok: $out"
}

run_sql_capture(){
  local ez="$1"
  local body="$2"
  local conn="${SYS_USER
  local tmp="${LOG_DIR}/.capture_${RUN_ID}_$$.out"

  # Do not let set -e abort the script if sqlplus fails here.
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

  # If any ORA- appears, treat as empty result but do not abort caller.
  if grep -qi "ORA-" "$tmp"; then
    rc=1
  fi

  if [[ $rc -ne 0 ]]; then
    echo ""
    rm -f "$tmp"
    return 0
  fi

  awk 'NF{last=$0} END{print last}' "$tmp"
  rm -f "$tmp"
  return 0
}
/${SYS_PASSWORD}@${ez} as sysdba"
  local out rc
  out="$(sqlplus -s "$conn" <<SQL 2>&1
SET PAGES 0 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMSPOOL ON LINES 32767
SET LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${body}
/
EXIT
SQL
)" && rc=$? || rc=$?
  if [[ $rc -ne 0 || "$out" =~ ORA- ]]; then echo ""; return 1; fi
  echo "$out" | awk 'NF{last=$0} END{print last}'
  return 0
}

detect_mail_stack(){
  local forced="${MAIL_METHOD:-auto}"
  case "$forced" in
    sendmail) command -v sendmail >/dev/null && { echo sendmail; return; } ;;
    mailutils) (mail --version 2>/dev/null | grep -qi "mailutils") && { echo mailutils; return; } ;;
    bsdmail) (mail -V 2>/dev/null | grep -qi "bsd") && { echo bsdmail; return; } ;;
    mailx) command -v mailx >/dev/null && { echo mailx; return; } ;;
  esac
  command -v sendmail >/dev/null 2>&1 && { echo sendmail; return; }
  mail --version 2>/dev/null | grep -qi "mailutils" && { echo mailutils; return; }
  mail -V 2>/dev/null | grep -qi "bsd" && { echo bsdmail; return; }
  command -v mailx >/dev/null 2>&1 && { echo mailx; return; }
  echo none
}

email_inline_html(){
  local file="$1" subject="$2"
  [[ "${MAIL_ENABLED^^}" != "Y" ]] && { warn "MAIL_ENABLED!=Y"; return 0; }
  [[ -z "${REPORT_EMAILS}" ]] && { warn "REPORT_EMAILS empty"; return 0; }
  [[ ! -f "$file" ]] && { warn "email file missing: $file"; return 1; }
  local method; method="$(detect_mail_stack)"; debug "Email via $method -> $REPORT_EMAILS"
  case "$method" in
    sendmail)
      { echo "From: ${MAIL_FROM}"; echo "To: ${REPORT_EMAILS}"; echo "Subject: ${subject}"
        echo "MIME-Version: 1.0"; echo "Content-Type: text/html; charset=UTF-8"; echo; cat "$file"; } | sendmail -t || return 1;;
    mailutils) mail -a "From: ${MAIL_FROM}" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" ${REPORT_EMAILS} < "$file" || return 1;;
    bsdmail) mail -a "From: ${MAIL_FROM}" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" ${REPORT_EMAILS} < "$file" || return 1;;
    mailx) mailx -r "$MAIL_FROM" -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" ${REPORT_EMAILS} < "$file" || return 1;;
    none) warn "No mailer found"; return 1;;
  esac
  ok "Email sent to ${REPORT_EMAILS}"
}

emit_simple_html_and_email(){
  local title="$1" body_file="$2" out_html="$3" subject="$4"
  { echo "<html><head><meta charset='utf-8'><title>${title}</title>"
    echo "<style>body{font-family:Arial} pre{white-space:pre-wrap;border:1px solid #ddd;padding:10px;background:#fafafa}</style>"
    echo "</head><body><h2>${title}</h2><pre>"
    if [[ -f "$body_file" ]]; then sed 's/&/\&amp;/g;s/</\&lt;/g' "$body_file"; else echo "(missing: $body_file)"; fi
    echo "</pre></body></html>"
  } > "$out_html"
  email_inline_html "$out_html" "$subject" || true
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
  # Populate placeholders
  sed -i "s/__TITLE__/${tool^^} ${tag} ${RUN_ID}/g" "$html"
  sed -i "s/__HEADER__/${tool^^} job completed/g" "$html"
  sed -i "s/__RUNID__/${RUN_ID}/g" "$html"
  sed -i "s/__TOOL__/${tool}/g" "$html"
  sed -i "s/__TAG__/${tag}/g" "$html"

  # Insert parfile content (mask encryption password and HTML-escape)
  local par_tmp="${LOG_DIR}/.tmp_par_${RUN_ID}.txt"
  if [[ -f "$pf" ]]; then
    sed -E 's/(encryption_password=).*/\1*****/I' "$pf" | sed 's/&/\&amp;/g;s/</\&lt;/g' > "$par_tmp"
  else
    echo "(parfile not found: $pf)" > "$par_tmp"
  fi
  perl -0777 -pe "s/__PARFILE__/`sed -e 's/[\\\\&]/\\\\&/g' \"$par_tmp\"`/g" -i "$html" 2>/dev/null || \
  sed -i "s|__PARFILE__|$(sed -e 's/[\/&]/\\&/g' \"$par_tmp\")|g" "$html"

  # Insert client log content (HTML-escape)
  local log_tmp="${LOG_DIR}/.tmp_log_${RUN_ID}.txt"
  if [[ -f "$client_log" ]]; then
    sed 's/&/\&amp;/g;s/</\&lt;/g' "$client_log" > "$log_tmp"
  else
    echo "(client log not found: $client_log)" > "$log_tmp"
  fi
  perl -0777 -pe "s/__CLIENTLOG__/`sed -e 's/[\\\\&]/\\\\&/g' \"$log_tmp\"`/g" -i "$html" 2>/dev/null || \
  sed -i "s|__CLIENTLOG__|$(sed -e 's/[\/&]/\\&/g' \"$log_tmp\")|g" "$html"

  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} ${tool^^} ${tag} ${RUN_ID}" || true
}


create_or_replace_directory(){
  local ez="$1" dir_name="$2" dir_path="$3" host_tag="$4"
  [[ -z "$dir_path" ]] && { warn "empty dir_path"; return 1; }
  dir_name="$(echo "$dir_name" | tr '[:lower:]' '[:upper:]')"
  debug "create/replace DIRECTORY ${dir_name}='${dir_path}' on ${host_tag}"
  run_sql_try "$ez" "create_dir_${host_tag}_${dir_name}" "
BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY ${dir_name} AS ''${dir_path}''';
  BEGIN EXECUTE IMMEDIATE 'GRANT READ,WRITE ON DIRECTORY ${dir_name} TO PUBLIC'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"
}

validate_directory_on_db_try(){
  local ez="$1" tag="$2" dir_name="${3:-$COMMON_DIR_NAME}"; dir_name="$(echo "$dir_name" | tr '[:lower:]' '[:upper:]')"
  run_sql_try "$ez" "dircheck_${tag}" "
SET SERVEROUTPUT ON
DECLARE v_cnt PLS_INTEGER:=0; v_path VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM all_directories WHERE directory_name=UPPER('${dir_name}');
  IF v_cnt=0 THEN DBMS_OUTPUT.PUT_LINE('DIRECTORY_MISSING'); ELSE
    SELECT directory_path INTO v_path FROM all_directories WHERE directory_name=UPPER('${dir_name}');
    DBMS_OUTPUT.PUT_LINE('DIRECTORY_OK '||v_path);
  END IF;
END;
/
"
}

_db_ident_block(){ cat <<'SQL'
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 400
WITH ver AS (SELECT MAX(banner) banner FROM v$version WHERE banner LIKE 'Oracle Database%'),
name AS (SELECT name db_name, dbid FROM v$database),
patch AS (SELECT NVL(MAX(version||' '||REGEXP_REPLACE(description,' Patch','')),'N/A') last_patch FROM dba_registry_sqlpatch WHERE action='APPLY' AND status='SUCCESS'),
nls AS (SELECT LISTAGG(parameter||'='||value, ', ') WITHIN GROUP (ORDER BY parameter) nls FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET'))
SELECT 'DB_NAME='||name.db_name||' DBID='||name.dbid||CHR(10)||'VERSION='||ver.banner||CHR(10)||'PATCH='||patch.last_patch||CHR(10)||'CHARSETS='||nls.nls FROM name,ver,patch,nls;
SQL
}

show_db_identity(){ local ez="$1" which="$2"; local info; info="$(run_sql_capture "$ez" "$(_db_ident_block)")"; echo "---- ${which} ----" | say_to_user; if [[ -z "${info// }" ]]; then echo "(connection ok, but identity query returned no rows)" | say_to_user; else echo "$info" | say_to_user; fi; }
db_connection_validation(){ ok "Validating connections…"; show_db_identity "$SRC_EZCONNECT" "SOURCE"; show_db_identity "$TGT_EZCONNECT" "TARGET"; ok "Validation step finished."; }
VALIDATED_ONCE="${VALIDATED_ONCE:-N}"
ensure_connections_ready(){ [[ "$VALIDATED_ONCE" == "Y" ]] || { db_connection_validation; VALIDATED_ONCE="Y"; }; }

dp_run(){
  local tool="$1" ez="$2" pf="$3" tag="$4"; local client_log="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.client.log"
  local conn="\"${SYS_USER}/${SYS_PASSWORD}@${ez} as sysdba\""; debug "dp_run ${tool} tag=${tag} par=${pf}"
  { echo "date: $(date)"; echo "tool: $tool"; echo "bin: $(command -v $tool || true)"; echo "ver: $($tool -V 2>/dev/null | head -1 || true)"; echo "parfile: $pf"; } > "$client_log" 2>&1
  set +e
  ( set -o pipefail; $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} ); local rc=$?
  set -e
  [[ $rc -eq 0 ]] || { err "$tool failed rc=$rc"; dp_emit_html_and_email "$tool" "$tag-FAILED" "$pf" "$client_log"; exit $rc; }
  ok "$tool ok"; dp_emit_html_and_email "$tool" "$tag" "$pf" "$client_log"
}

par_common(){
  local mode="$1" tag="$2" dir_name="$3"; local pf_dir; pf_dir="$(parfile_dir_for_mode "$mode")"; mkdir -p "$pf_dir" || true
  local pf="${pf_dir}/${tag}_${RUN_ID}.par"; local server_log="$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log")"
  { echo "directory=${dir_name}"; echo "logfile=${server_log}"; echo "logtime=all"; echo "parallel=${PARALLEL}"; } > "$pf"
  if [[ "$mode" == "expdp" ]]; then
    local dump_pat="$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}_%U.dmp")"
    { echo "dumpfile=${dump_pat}"; echo "compression=${COMPRESSION}"
      [[ -n "$FLASHBACK_SCN"  ]] && echo "flashback_scn=${FLASHBACK_SCN}"
      [[ -n "$FLASHBACK_TIME" ]] && echo "flashback_time=${FLASHBACK_TIME}"
      [[ -n "$INCLUDE"        ]] && echo "include=${INCLUDE}"
      [[ -n "$EXCLUDE"        ]] && echo "exclude=${EXCLUDE}"
      [[ "${ESTIMATE_ONLY^^}" == "Y" ]] && echo "estimate_only=Y"
      [[ -n "$ENCRYPTION_PASSWORD" ]] && { echo "encryption=encrypt_password"; echo "encryption_password=${ENCRYPTION_PASSWORD}"; }
      [[ -n "$EXPDP_TRACE" ]] && echo "trace=${EXPDP_TRACE}"
    } >> "$pf"
  else
    { echo "table_exists_action=${TABLE_EXISTS_ACTION}"
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

par_common_imp_with_dump(){
  local tag="$1" dir_name="$2" dumpfiles="$3"; local pf_dir; pf_dir="$(parfile_dir_for_mode "impdp")"; mkdir -p "$pf_dir" || true
  local pf="${pf_dir}/${tag}_${RUN_ID}.par"
  { echo "directory=${dir_name}"; echo "dumpfile=${dumpfiles}"; echo "logfile=$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log")"
    echo "logtime=all"; echo "parallel=${PARALLEL}"; echo "table_exists_action=${TABLE_EXISTS_ACTION}"
    [[ -n "$REMAP_SCHEMA"     ]] && echo "remap_schema=${REMAP_SCHEMA}"
    [[ -n "$REMAP_TABLESPACE" ]] && echo "remap_tablespace=${REMAP_TABLESPACE}"
    [[ -n "$INCLUDE"          ]] && echo "include=${INCLUDE}"
    [[ -n "$EXCLUDE"          ]] && echo "exclude=${EXCLUDE}"
    [[ -n "$ENCRYPTION_PASSWORD" ]] && echo "encryption_password=${ENCRYPTION_PASSWORD}"
    [[ -n "$IMPDP_TRACE" ]] && echo "trace=${IMPDP_TRACE}"
  } > "$pf"; echo "$pf"
}

show_and_confirm_parfile(){
  local pf="$1" tool="${2:-}"
  { echo "----- PARFILE: ${pf} -----"; sed -E 's/(encryption_password=).*/\1*****/I' "$pf"; echo "---------------------------"; } | say_to_user
  local ans; read -rp "Proceed with ${tool:-the job}? [Y/N/X]: " ans; case "${ans^^}" in Y) return 0;; N) return 1;; X) exit 0;; *) return 1;; esac
}

# -------------------- DDL extraction with dynamic SPOOL header ----------------
ddl_spool(){
  local out="$1"; shift; local label="${1:-}"; shift || true; local body="$*"
  [[ -z "$label" ]] && label="$(basename "${out%.sql}" | sed 's/^[0-9]\+_//')"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"; debug "DDL -> ${out} label=${label}"
  sqlplus -s "$conn" <<SQL >"$out" 2>"${out}.log"
SET TERMOUT ON ECHO ON FEEDBACK ON LINES 32767 PAGES 0 SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE ON
COLUMN V_DBNAME NEW_VALUE V_DBNAME
COLUMN V_TS     NEW_VALUE V_TS
SELECT name V_DBNAME FROM v\$database;
SELECT TO_CHAR(SYSDATE,'YYYYMMDD_HH24MISS') V_TS FROM dual;
DEFINE V_SCRIPT='${label}'
SPOOL &&V_DBNAME._&&V_SCRIPT._&&V_TS..log
SET DEFINE OFF
SET LONG 1000000 LONGCHUNKSIZE 1000000
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
SPOOL OFF
EXIT
SQL
  if grep -qi "ORA-" "${out}.log"; then err "DDL extract error: $(basename "$out")"; tail -n 60 "${out}.log" | mask_pwd; return 1; fi
  ok "DDL file: $out"
}

to_inlist_upper(){ local csv="$1" out="" tok; IFS=',' read -r -a arr <<< "$csv"; for tok in "${arr[@]}"; do tok="$(echo "$tok"|awk '{$1=$1;print}')"; [[ -z "$tok" ]] && continue; tok="${tok^^}"; out+="${out:+,}'${tok}'"; done; printf "%s" "$out"; }

ddl_users(){ local f="${DDL_DIR}/01_users_${RUN_ID}.sql"; ddl_spool "$f" "users" "
SELECT DBMS_METADATA.GET_DDL('USER', username) FROM dba_users WHERE oracle_maintained='N' ORDER BY username;"; }
ddl_profiles(){ local f="${DDL_DIR}/02_profiles_${RUN_ID}.sql"; ddl_spool "$f" "profiles" "
SELECT DBMS_METADATA.GET_DDL('PROFILE', profile) FROM (SELECT DISTINCT profile FROM dba_profiles ORDER BY 1);"; }
ddl_roles(){ local f="${DDL_DIR}/03_roles_${RUN_ID}.sql"; ddl_spool "$f" "roles" "
SELECT DBMS_METADATA.GET_DDL('ROLE', role) FROM dba_roles WHERE NVL(oracle_maintained,'N')='N' ORDER BY role;"; }
ddl_privs_to_roles(){ local f="${DDL_DIR}/04_sys_and_role_grants_${RUN_ID}.sql"; ddl_spool "$f" "privs_to_roles" "
SELECT 'GRANT '||privilege||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';' FROM dba_sys_privs
WHERE grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y') AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
UNION ALL
SELECT 'GRANT '||granted_role||' TO '||grantee||CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END||';' FROM dba_role_privs
WHERE grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y') AND granted_role NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y')
ORDER BY 1;"; }
ddl_sysprivs_to_users(){ local f="${DDL_DIR}/05_user_obj_privs_${RUN_ID}.sql"; ddl_spool "$f" "obj_privs_to_users" "
WITH src AS (SELECT grantee, owner, table_name, privilege, grantable, grantor FROM dba_tab_privs
             WHERE grantee <> 'PUBLIC' AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained='Y')
               AND grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained='Y') AND grantee NOT LIKE 'C##%')
SELECT 'GRANT '||privilege||' ON '||owner||'.\"'||table_name||'\" TO '||grantee||DECODE(grantable,'YES',' WITH GRANT OPTION','')||';'
FROM src ORDER BY grantee, owner, table_name, privilege;"; }
ddl_sequences_all_users(){ local f="${DDL_DIR}/06_sequences_${RUN_ID}.sql"; ddl_spool "$f" "sequences" "
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', sequence_name, owner) FROM dba_sequences
WHERE owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N') ORDER BY owner, sequence_name;"; }
ddl_public_synonyms(){ local f="${DDL_DIR}/07_public_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "public_synonyms" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, 'PUBLIC') FROM dba_synonyms WHERE owner='PUBLIC' ORDER BY synonym_name;"; }
ddl_private_synonyms_all_users(){ local f="${DDL_DIR}/08_private_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "private_synonyms" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, owner) FROM dba_synonyms WHERE owner<>'PUBLIC'
AND owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N') ORDER BY owner, synonym_name;"; }
ddl_all_ddls_all_users(){
  local f="${DDL_DIR}/09_all_ddls_${RUN_ID}.sql"; local types_clause; types_clause="$(to_inlist_upper "TABLE,INDEX,VIEW,SEQUENCE,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE_BODY,MATERIALIZED_VIEW,TYPE,SYNONYM")"
  ddl_spool "$f" "all_user_ddls" "
WITH owners AS (SELECT username AS owner FROM dba_users WHERE oracle_maintained='N'),
objs AS (SELECT owner, object_type, object_name FROM dba_objects
         WHERE owner IN (SELECT owner FROM owners) AND object_type IN (${types_clause}) AND object_name NOT LIKE 'BIN$%%' AND temporary='N')
SELECT DBMS_METADATA.GET_DDL(object_type, object_name, owner) FROM objs ORDER BY owner, object_type, object_name;"; }
ddl_tablespaces(){
  local f="${DDL_DIR}/10_tablespaces_${RUN_ID}.sql"; local skip; skip="$(to_inlist_upper "$SKIP_TABLESPACES")"
  ddl_spool "$f" "tablespaces" "SELECT DBMS_METADATA.GET_DDL('TABLESPACE', tablespace_name) FROM dba_tablespaces WHERE UPPER(tablespace_name) NOT IN (${skip}) ORDER BY tablespace_name;"; }
ddl_role_grants_to_users(){
  local f="${DDL_DIR}/11_role_grants_to_users_${RUN_ID}.sql"; ddl_spool "$f" "default_roles" "
WITH u AS (SELECT username FROM dba_users WHERE oracle_maintained='N'),
def AS (SELECT grantee AS username, LISTAGG(granted_role, ',') WITHIN GROUP (ORDER BY granted_role) AS roles, COUNT(*) AS cnt
        FROM dba_role_privs WHERE default_role='YES' GROUP BY grantee)
SELECT CASE WHEN NVL(def.cnt,0) > 0 THEN 'ALTER USER '||u.username||' DEFAULT ROLE '||def.roles||';' ELSE 'ALTER USER '||u.username||' DEFAULT ROLE ALL;' END
FROM u LEFT JOIN def ON def.username=u.username ORDER BY u.username;"; }
ddl_directories(){ local f="${DDL_DIR}/13_directories_${RUN_ID}.sql"; ddl_spool "$f" "directories" "SELECT DBMS_METADATA.GET_DDL('DIRECTORY', directory_name) FROM (SELECT DISTINCT directory_name FROM dba_directories ORDER BY 1);"; }
ddl_db_links_by_owner(){
  read -rp "Enter DB LINK OWNER (schema): " owner; owner="${owner^^}"; local f="${DDL_DIR}/14_db_links_${owner}_${RUN_ID}.sql"
  ddl_spool "$f" "dblinks_${owner}" "SELECT DBMS_METADATA.GET_DDL('DB_LINK', db_link, owner) FROM dba_db_links WHERE owner=UPPER('${owner}') ORDER BY db_link;"
  warn "Note: DB link passwords may be masked."
}

ddl_menu_wrapper(){
  ensure_connections_ready
  while true; do
    cat <<'EOS' | say_to_user
DDL Extraction (Source DB):
  1) USERS
  2) PROFILES
  3) ROLES
  4) PRIVS -> ROLES (sys+role grants)
  5) OBJECT PRIVS -> USERS
  6) SEQUENCES (all users)
  7) PUBLIC SYNONYMS
  8) PRIVATE SYNONYMS (all users)
  9) ALL OBJECT DDLs (all users) [heavy]
 10) TABLESPACE DDLs
 11) DEFAULT ROLES per USER
 12) DIRECTORY OBJECTS
 13) DB LINKS by OWNER
  B) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "${c^^}" in
      1) ddl_users ;; 2) ddl_profiles ;; 3) ddl_roles ;; 4) ddl_privs_to_roles ;;
      5) ddl_sysprivs_to_users ;; 6) ddl_sequences_all_users ;; 7) ddl_public_synonyms ;;
      8) ddl_private_synonyms_all_users ;; 9) ddl_all_ddls_all_users ;; 10) ddl_tablespaces ;;
      11) ddl_role_grants_to_users ;; 12) ddl_directories ;; 13) ddl_db_links_by_owner ;;
      B) break ;; X) exit 0 ;; * ) warn "Invalid choice" ;;
    esac
  done
}

choose_content_option(){
  while true; do
    cat <<'EOS' | say_to_user
Choose Content:
  a) METADATA_ONLY
  b) ALL
  x) Exit
EOS
    read -rp "Select [a/b/x]: " choice
    case "${choice,,}" in a) echo "METADATA_ONLY"; return;; b) echo "ALL"; return;; x) exit 0;; *) warn "Invalid";; esac
  done
}

get_nonmaintained_schemas(){
  local pred=""; if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"; for s in "${arr[@]}"; do s="$(echo "$s"|awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql_capture "$SRC_EZCONNECT" "WITH base AS (SELECT username FROM dba_users WHERE oracle_maintained='N'${pred}) SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base"
}
get_nonmaintained_schemas_tgt(){
  local pred=""; if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"; for s in "${arr[@]}"; do s="$(echo "$s"|awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql_capture "$TGT_EZCONNECT" "WITH base AS (SELECT username FROM dba_users WHERE oracle_maintained='N'${pred}) SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base"
}

confirm_edit_value(){
  local label="$1" val="${2:-}" ans=""
  while true; do
    if [[ -z "${val// }" ]]; then echo "${label} is empty." | say_to_user; read -rp "Enter ${label}: " val; continue; fi
    echo "${label}: ${val}" | say_to_user; read -rp "Use this value? [Y/N]: " ans
    case "${ans^^}" in Y) echo "$val"; return;; N) read -rp "Enter new ${label}: " val;; *) echo "Please answer Y or N." | say_to_user;; esac
  done
}

precheck_export_directory(){
  local def_name="${COMMON_DIR_NAME:-DP_DIR}"; ensure_connections_ready
  while true; do
    read -rp "Export DIRECTORY name on SOURCE [${def_name}]: " dname; local dir_name="$(echo "${dname:-$def_name}"|tr '[:lower:]' '[:upper:]')"
    local default_path="${EXPORT_DIR_PATH:-${NAS_PATH:-}}"; local dir_path=""
    if [[ -z "$default_path" ]]; then read -rp "Enter SOURCE OS path for dumpfiles: " dir_path; else
      echo "Default export path: ${default_path}" | say_to_user; read -rp "Use default? [Y/N]: " ans; [[ "${ans^^}" == "Y" ]] && dir_path="$default_path" || read -rp "Enter export path: " dir_path
    fi
    [[ -z "$dir_path" ]] && { warn "Export path cannot be empty."; } || {
      create_or_replace_directory "$SRC_EZCONNECT" "$dir_name" "$dir_path" "src"
      if validate_directory_on_db_try "$SRC_EZCONNECT" "src" "$dir_name"; then ok "SOURCE export DIRECTORY ready"; EXPORT_DIR_NAME="$dir_name"; EXPORT_DIR_PATH="$dir_path"; return 0; fi
      warn "Failed to validate export DIRECTORY on source."
    }
    read -rp "Retry? [Y=retry / B=back / X=exit]: " r; case "${r^^}" in Y) continue;; B) return 1;; X) exit 0;; *) return 1;; esac
  done
}

precheck_import_directory(){
  local def_name="${COMMON_DIR_NAME:-DP_DIR}"; ensure_connections_ready
  while true; do
    read -rp "Import DIRECTORY name on TARGET [${def_name}]: " dname; local dir_name="$(echo "${dname:-$def_name}"|tr '[:lower:]' '[:upper:]')"
    read -rp "Enter TARGET OS path for dumpfiles: " dir_path; [[ -z "$dir_path" ]] && { warn "Import path cannot be empty."; }
    if [[ -n "$dir_path" ]]; then
      create_or_replace_directory "$TGT_EZCONNECT" "$dir_name" "$dir_path" "tgt"
      if validate_directory_on_db_try "$TGT_EZCONNECT" "tgt" "$dir_name"; then ok "TARGET import DIRECTORY ready"; IMPORT_DIR_NAME="$dir_name"; IMPORT_DIR_PATH="$dir_path"; return 0; fi
      warn "Failed to validate import DIRECTORY on target."
    fi
    read -rp "Retry? [Y=retry / B=back / X=exit]: " r; case "${r^^}" in Y) continue;; B) return 1;; X) exit 0;; *) return 1;; esac
  done
}

prompt_export_dump_location(){
  ensure_connections_ready
  if [[ -n "${EXPORT_DIR_NAME:-}" && -n "${EXPORT_DIR_PATH:-}" ]]; then
    echo "Use SOURCE DIRECTORY ${EXPORT_DIR_NAME} -> ${EXPORT_DIR_PATH} ?" | say_to_user; read -rp "[Y=accept / N=change / X=exit]: " ans
    case "${ans^^}" in Y) return 0;; N) ;; X) exit 0;; esac
  fi
  precheck_export_directory
}
prompt_import_dump_location(){
  ensure_connections_ready
  if [[ -n "${IMPORT_DIR_NAME:-}" && -n "${IMPORT_DIR_PATH:-}" ]]; then
    echo "Use TARGET DIRECTORY ${IMPORT_DIR_NAME} -> ${IMPORT_DIR_PATH} ?" | say_to_user; read -rp "[Y=accept / N=change / X=exit]: " ans
    case "${ans^^}" in Y) : ;; N) precheck_import_directory || { warn "Cancelled."; return 1; } ;; X) exit 0 ;; esac
  else
    precheck_import_directory || { warn "Cancelled."; return 1; }
  fi
  echo "Enter dumpfile pattern/list (e.g., dump%U.dmp or f1.dmp,f2.dmp) — filenames only:" | say_to_user
  read -rp "Dumpfile(s): " IMPORT_DUMPFILE_PATTERN; [[ -z "$IMPORT_DUMPFILE_PATTERN" ]] && { warn "Dumpfile pattern cannot be empty."; return 1; }
  return 0
}

choose_content_option_imp(){ choose_content_option; }

# ------------------------------ EXPORT MENUS ----------------------------------
exp_full_menu(){
  ensure_connections_ready; prompt_export_dump_location || return 1
  local content; content="$(choose_content_option)"; local tag="exp_full_${content,,}"
  local pf; pf="$(par_common "expdp" "$tag" "$EXPORT_DIR_NAME")"; { echo "full=Y"; echo "content=${content}"; } >> "$pf"
  show_and_confirm_parfile "$pf" "EXPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "expdp" "$SRC_EZCONNECT" "$pf" "$tag"
}
exp_schemas_menu(){
  ensure_connections_ready; prompt_export_dump_location || return 1
  local pick=""; while true; do
    cat <<'EOS' | say_to_user
Export Schemas:
  a) All non-Oracle-maintained accounts
  b) User / conf list (SCHEMAS_LIST_EXP)
  x) Back/Exit
EOS
    read -rp "Select [a/b/x]: " pick
    case "${pick,,}" in
      a) local list; list="$(get_nonmaintained_schemas)"; list="$(confirm_edit_value "Schemas for export" "${list}")"
         local content; content="$(choose_content_option)"; local tag="exp_schemas_${content,,}"
         local pf; pf="$(par_common "expdp" "$tag" "$EXPORT_DIR_NAME")"; { echo "schemas=${list}"; echo "content=${content}"; } >> "$pf"
         show_and_confirm_parfile "$pf" "EXPDP" || { warn "Cancelled."; return 1; }
         [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
         dp_run "expdp" "$SRC_EZCONNECT" "$pf" "$tag";;
      b) local list="${SCHEMAS_LIST_EXP:-}"; list="$(confirm_edit_value "Schemas for export" "${list}")"
         local content; content="$(choose_content_option)"; local tag="exp_schemas_${content,,}"
         local pf; pf="$(par_common "expdp" "$tag" "$EXPORT_DIR_NAME")"; { echo "schemas=${list}"; echo "content=${content}"; } >> "$pf"
         show_and_confirm_parfile "$pf" "EXPDP" || { warn "Cancelled."; return 1; }
         [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
         dp_run "expdp" "$SRC_EZCONNECT" "$pf" "$tag";;
      x) return 0;;
      *) warn "Invalid choice";;
    esac
  done
}
exp_tablespaces(){
  ensure_connections_ready; prompt_export_dump_location || return 1
  read -rp "Enter TABLESPACES (comma-separated): " tbs; [[ -z "$tbs" ]] && { warn "Empty."; return 1; }
  local tag="exp_tbs"; local pf; pf="$(par_common "expdp" "$tag" "$EXPORT_DIR_NAME")"
  { echo "transport_tablespaces=${tbs}"; echo "transport_full_check=Y"; } >> "$pf"
  show_and_confirm_parfile "$pf" "EXPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "expdp" "$SRC_EZCONNECT" "$pf" "$tag"
}
exp_tables(){
  ensure_connections_ready; prompt_export_dump_location || return 1
  read -rp "Enter TABLES (schema.table, comma-separated): " tables; [[ -z "$tables" ]] && { warn "Empty."; return 1; }
  local content; content="$(choose_content_option)"; local tag="exp_tables_${content,,}"
  local pf; pf="$(par_common "expdp" "$tag" "$EXPORT_DIR_NAME")"; { echo "tables=${tables}"; echo "content=${content}"; } >> "$pf"
  show_and_confirm_parfile "$pf" "EXPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "expdp" "$SRC_EZCONNECT" "$pf" "$tag"
}
export_menu(){
  ensure_connections_ready
  while true; do
    cat <<'EOS' | say_to_user
Export Menu (Source DB):
  1) FULL export
  2) SCHEMAS export
  3) TRANSPORT TABLESPACES export
  4) TABLES export
  B) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "${c^^}" in 1) exp_full_menu ;; 2) exp_schemas_menu ;; 3) exp_tablespaces ;; 4) exp_tables ;; B) break ;; X) exit 0 ;; * ) warn "Invalid";; esac
  done
}

# ------------------------------ IMPORT MENUS ----------------------------------
prompt_import_dump_location_wrapper(){ prompt_import_dump_location; }

imp_full_menu(){
  ensure_connections_ready; prompt_import_dump_location_wrapper || return 1
  local content; content="$(choose_content_option_imp)"; local tag="imp_full_${content,,}"
  local pf; pf="$(par_common_imp_with_dump "$tag" "$IMPORT_DIR_NAME" "$IMPORT_DUMPFILE_PATTERN")"; { echo "full=Y"; echo "content=${content}"; } >> "$pf"
  show_and_confirm_parfile "$pf" "IMPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "impdp" "$TGT_EZCONNECT" "$pf" "$tag"
}
imp_schemas_menu(){
  ensure_connections_ready; prompt_import_dump_location_wrapper || return 1
  while true; do
    cat <<'EOS' | say_to_user
Import Schemas:
  a) All non-Oracle-maintained accounts (on TARGET)
  b) User / conf list (SCHEMAS_LIST_IMP)
  x) Back/Exit
EOS
    read -rp "Select [a/b/x]: " pick
    case "${pick,,}" in
      a) local list; list="$(get_nonmaintained_schemas_tgt)"; list="$(confirm_edit_value "Schemas to import" "${list}")"
         local content; content="$(choose_content_option_imp)"; local tag="imp_schemas_${content,,}"
         local pf; pf="$(par_common_imp_with_dump "$tag" "$IMPORT_DIR_NAME" "$IMPORT_DUMPFILE_PATTERN")"; { echo "schemas=${list}"; echo "content=${content}"; } >> "$pf"
         show_and_confirm_parfile "$pf" "IMPDP" || { warn "Cancelled."; return 1; }
         [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
         dp_run "impdp" "$TGT_EZCONNECT" "$pf" "$tag";;
      b) local list="${SCHEMAS_LIST_IMP:-}"; list="$(confirm_edit_value "Schemas to import" "${list}")"
         local content; content="$(choose_content_option_imp)"; local tag="imp_schemas_${content,,}"
         local pf; pf="$(par_common_imp_with_dump "$tag" "$IMPORT_DIR_NAME" "$IMPORT_DUMPFILE_PATTERN")"; { echo "schemas=${list}"; echo "content=${content}"; } >> "$pf"
         show_and_confirm_parfile "$pf" "IMPDP" || { warn "Cancelled."; return 1; }
         [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
         dp_run "impdp" "$TGT_EZCONNECT" "$pf" "$tag";;
      x) return 0;;
      *) warn "Invalid";;
    esac
  done
}
imp_tablespaces(){
  ensure_connections_ready; prompt_import_dump_location_wrapper || return 1
  read -rp "Enter TRANSPORT TABLESPACES to import: " tbs; [[ -z "$tbs" ]] && { warn "Empty."; return 1; }
  local tag="imp_tbs"; local pf; pf="$(par_common_imp_with_dump "$tag" "$IMPORT_DIR_NAME" "$IMPORT_DUMPFILE_PATTERN")"
  { echo "transport_datafiles=<enter_datafiles_on_target>"; echo "transport_tablespaces=${tbs}"; echo "transport_full_check=Y"; } >> "$pf"
  show_and_confirm_parfile "$pf" "IMPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "impdp" "$TGT_EZCONNECT" "$pf" "$tag"
}
imp_tables(){
  ensure_connections_ready; prompt_import_dump_location_wrapper || return 1
  read -rp "Enter TABLES to import (schema.table, comma-separated): " tables; [[ -z "$tables" ]] && { warn "Empty."; return 1; }
  local content; content="$(choose_content_option_imp)"; local tag="imp_tables_${content,,}"
  local pf; pf="$(par_common_imp_with_dump "$tag" "$IMPORT_DIR_NAME" "$IMPORT_DUMPFILE_PATTERN")"; { echo "tables=${tables}"; echo "content=${content}"; } >> "$pf"
  show_and_confirm_parfile "$pf" "IMPDP" || { warn "Cancelled."; return 1; }
  [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && { ok "DRY_RUN_ONLY=Y"; return 0; }
  dp_run "impdp" "$TGT_EZCONNECT" "$pf" "$tag"
}

import_cleanup_menu(){
  ensure_connections_ready
  while true; do
    cat <<'EOS' | say_to_user
Import Cleanup Helpers (Target DB) - DANGEROUS:
  1) Drop all users CASCADE (exclude Oracle-maintained)
  2) Drop all objects of all non-Oracle-maintained users
  3) Drop users CASCADE listed in SCHEMAS_LIST_IMP
  4) Drop all objects of users listed in SCHEMAS_LIST_IMP
  B) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "${c}" in
      1) run_sql "$TGT_EZCONNECT" "drop_users_nonmaint" "
DECLARE CURSOR c IS SELECT username FROM dba_users WHERE oracle_maintained='N';
BEGIN FOR r IN c LOOP BEGIN EXECUTE IMMEDIATE 'DROP USER '||r.username||' CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END; END LOOP; END; /";;
      2) run_sql "$TGT_EZCONNECT" "drop_objs_nonmaint" "
DECLARE CURSOR c IS SELECT owner,object_name,object_type FROM dba_objects WHERE owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N');
BEGIN FOR r IN c LOOP BEGIN
  IF r.object_type IN ('TABLE','VIEW','MATERIALIZED VIEW') THEN EXECUTE IMMEDIATE 'DROP '||r.object_type||' '||r.owner||'.\"'||r.object_name||'\" CASCADE CONSTRAINTS';
  ELSE EXECUTE IMMEDIATE 'DROP '||r.object_type||' '||r.owner||'.\"'||r.object_name||'\"'; END IF;
EXCEPTION WHEN OTHERS THEN NULL; END; END LOOP; END; /";;
      3) local list="${SCHEMAS_LIST_IMP:-}"; list="$(confirm_edit_value "Schemas to DROP CASCADE" "$list")"
         run_sql "$TGT_EZCONNECT" "drop_users_list" "
DECLARE v_list VARCHAR2(32767):='$(echo "$list"|tr -d '\"')';
BEGIN FOR r IN (SELECT REGEXP_SUBSTR(v_list,'[^,]+',1,LEVEL) AS u FROM dual CONNECT BY LEVEL<=REGEXP_COUNT(v_list,',')+1) LOOP
  BEGIN EXECUTE IMMEDIATE 'DROP USER '||RTRIM(LTRIM(r.u))||' CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END; END LOOP; END; /";;
      4) local list="${SCHEMAS_LIST_IMP:-}"; list="$(confirm_edit_value "Schemas to DROP OBJECTS" "$list")"
         run_sql "$TGT_EZCONNECT" "drop_objs_list" "
DECLARE v_list VARCHAR2(32767):='$(echo "$list"|tr -d '\"')';
BEGIN FOR u IN (SELECT UPPER(RTRIM(LTRIM(REGEXP_SUBSTR(v_list,'[^,]+',1,LEVEL)))) AS owner FROM dual CONNECT BY LEVEL<=REGEXP_COUNT(v_list,',')+1) LOOP
  FOR r IN (SELECT object_name, object_type FROM dba_objects WHERE owner=u.owner) LOOP
    BEGIN
      IF r.object_type IN ('TABLE','VIEW','MATERIALIZED VIEW') THEN EXECUTE IMMEDIATE 'DROP '||r.object_type||' '||u.owner||'.\"'||r.object_name||'\" CASCADE CONSTRAINTS';
      ELSE EXECUTE IMMEDIATE 'DROP '||r.object_type||' '||u.owner||'.\"'||r.object_name||'\"'; END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END; END LOOP; END LOOP; END; /";;
      B|b) return ;; X|x) exit 0 ;; *) warn "Invalid";;
    esac
  done
}

ddl_exec_on_target_loop(){
  ensure_connections_ready; show_db_identity "$TGT_EZCONNECT" "TARGET (confirmation)"
  local default_dir="$DDL_DIR" choice dir; echo "Default DDL directory: $default_dir" | say_to_user
  read -rp "Use this directory? [Y/N/X]: " choice; case "${choice^^}" in Y) dir="$default_dir";; N) read -rp "Enter path: " dir;; X) return 0;; *) dir="$default_dir";; esac
  [[ -d "$dir" ]] || { warn "Dir not found: $dir"; return 1; }
  while true; do
    echo "Files under: $dir" | say_to_user; (ls -1 "$dir"/*.sql 2>/dev/null || true) | sed 's/^/  - /' | say_to_user
    local fbase file ans; read -rp "Enter filename (.sql) to execute [B=back X=exit]: " fbase
    case "${fbase^^}" in B) return 0;; X) exit 0;; esac
    file="${dir%/}/$fbase"; [[ -f "$file" ]] || { warn "File not found: $file"; continue; }
    echo "Execute on TARGET as ${SYS_USER}: $file" | say_to_user; read -rp "Proceed? [Y/N]: " ans; [[ "${ans^^}" == "Y" ]] || { warn "Cancelled."; continue; }
    local exec_log="${LOG_DIR}/ddl_exec_$(basename "${fbase%.sql}")_${RUN_ID}.log"; local conn="${SYS_USER}/${SYS_PASSWORD}@${TGT_EZCONNECT} as sysdba"
    set +e; sqlplus -s "$conn" @"$file" > "$exec_log" 2>&1; local rc=$?; set -e
    if [[ $rc -ne 0 || "$(grep -ci 'ORA-' "$exec_log" || true)" -gt 0 ]]; then warn "Finished with errors (rc=$rc): $exec_log"; else ok "Success: $exec_log"; fi
    local html="${LOG_DIR}/ddl_exec_$(basename "${fbase%.sql}")_${RUN_ID}.html"
    emit_simple_html_and_email "DDL Execution on TARGET — $(basename "$file")" "$exec_log" "$html" "${MAIL_SUBJECT_PREFIX} DDL Exec ${RUN_ID}"
    read -rp "Run another from ${dir}? [Y/B/X]: " ans; case "${ans^^}" in Y) continue;; B) return 0;; X) exit 0;; *) continue;; esac
  done
}

# ------------------------------ Compare (LOCAL) -------------------------------
# Collect per-DB facts into CSVs and build an HTML side-by-side report.

compare_ident_block_csv(){
  local ez="$1" side="$2" out="$3"
  run_sql_spool_local "$ez" "cmp_ident_${side}" "$out" "
SET HEADING OFF FEEDBACK OFF
WITH ver AS (SELECT MAX(banner) banner FROM v\$version WHERE banner LIKE 'Oracle Database%'),
name AS (SELECT name db_name, dbid FROM v\$database),
patch AS (SELECT NVL(MAX(version||' '||REGEXP_REPLACE(description,' Patch','')),'N/A') last_patch FROM dba_registry_sqlpatch WHERE action='APPLY' AND status='SUCCESS'),
nls AS (SELECT LISTAGG(parameter||'='||value, ',') WITHIN GROUP (ORDER BY parameter) nls FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET'))
SELECT name.db_name||','||name.dbid||','||ver.banner||','||patch.last_patch||','||nls.nls FROM name,ver,patch,nls;"
}

compare_schema_collect_for_db(){
  local ez="$1" side="$2" schema="$3" outdir="$4"; mkdir -p "$outdir"
  local s="${schema^^}"
  # object counts by type
  run_sql_spool_local "$ez" "cmp_objcnt_${side}_${s}" "${outdir}/${side}_${s}_objcnt.csv" "
SET HEADING OFF FEEDBACK OFF
SELECT object_type||','||COUNT(*) FROM dba_objects WHERE owner='${s}' GROUP BY object_type ORDER BY object_type;"
  # invalid objects
  run_sql_spool_local "$ez" "cmp_invalid_${side}_${s}" "${outdir}/${side}_${s}_invalid.csv" "
SET HEADING OFF FEEDBACK OFF
SELECT object_type||','||object_name FROM dba_objects WHERE owner='${s}' AND status<>'VALID' ORDER BY object_type, object_name;"
  # row counts
  if [[ "${EXACT_ROWCOUNT^^}" == "Y" ]]; then
run_sql_spool_local "$ez" "cmp_rows_exact_${side}_${s}" "${outdir}/${side}_${s}_rows.csv" "
SET HEADING OFF FEEDBACK OFF SERVEROUTPUT ON
DECLARE
  v_cnt NUMBER;
BEGIN
  FOR r IN (SELECT table_name FROM dba_tables WHERE owner='${s}') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ${s}.\"'||r.table_name||'\"' INTO v_cnt;
      DBMS_OUTPUT.PUT_LINE(r.table_name||','||v_cnt);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(r.table_name||',-1');
    END;
  END LOOP;
END;
/"
  else
run_sql_spool_local "$ez" "cmp_rows_est_${side}_${s}" "${outdir}/${side}_${s}_rows.csv" "
SET HEADING OFF FEEDBACK OFF
SELECT table_name||','||NVL(num_rows,-1) FROM dba_tables WHERE owner='${s}' ORDER BY table_name;"
  fi
}

compare_roles_collect_for_db(){
  local ez="$1" side="$2" outdir="$3"; mkdir -p "$outdir"
  run_sql_spool_local "$ez" "cmp_roles_${side}" "${outdir}/${side}_roles.csv" "SET HEADING OFF FEEDBACK OFF
SELECT role FROM dba_roles WHERE NVL(oracle_maintained,'N')='N' ORDER BY role;"
  run_sql_spool_local "$ez" "cmp_role_grants_${side}" "${outdir}/${side}_role_grants.csv" "SET HEADING OFF FEEDBACK OFF
SELECT grantee||','||granted_role FROM dba_role_privs WHERE grantee IN (SELECT username FROM dba_users WHERE oracle_maintained='N') ORDER BY grantee, granted_role;"
  run_sql_spool_local "$ez" "cmp_sys_privs_${side}" "${outdir}/${side}_sys_privs.csv" "SET HEADING OFF FEEDBACK OFF
SELECT grantee||','||privilege FROM dba_sys_privs WHERE grantee IN (SELECT username FROM dba_users WHERE oracle_maintained='N') ORDER BY grantee, privilege;"
}

html_escape(){ sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

compare_build_html(){
  local runroot="$1" html="$2" schemas_csv="$3"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:4px 8px} .sec{margin:16px 0}</style>"
    echo "</head><body><h2>Schema Compare — Run ${RUN_ID}</h2>"
    # DB identity
    if [[ -f "${runroot}/src_identity.csv" && -f "${runroot}/tgt_identity.csv" ]]; then
      IFS=',' read -r S_DB S_DBID S_VER S_PATCH S_NLS < "${runroot}/src_identity.csv"
      IFS=',' read -r T_DB T_DBID T_VER T_PATCH T_NLS < "${runroot}/tgt_identity.csv"
      echo "<div class='sec'><h3>Databases</h3>"
      echo "<table><tr><th></th><th>Source</th><th>Target</th></tr>"
      echo "<tr><td>DB Name</td><td>${S_DB}</td><td>${T_DB}</td></tr>"
      echo "<tr><td>DBID</td><td>${S_DBID}</td><td>${T_DBID}</td></tr>"
      echo "<tr><td>Version</td><td>$(echo "$S_VER" | html_escape)</td><td>$(echo "$T_VER" | html_escape)</td></tr>"
      echo "<tr><td>Last Patch</td><td>$(echo "$S_PATCH" | html_escape)</td><td>$(echo "$T_PATCH" | html_escape)</td></tr>"
      echo "<tr><td>Charsets</td><td>$(echo "$S_NLS" | html_escape)</td><td>$(echo "$T_NLS" | html_escape)</td></tr>"
      echo "</table></div>"
    fi

    echo "<div class='sec'><h3>Schemas Compared</h3><p>$(cat "$schemas_csv")</p></div>"

    # For each schema: object counts, invalids, rowcounts
    for s in $(tr ',' ' ' < "$schemas_csv"); do
      local S_OBJ="${runroot}/src_${s}_objcnt.csv"
      local T_OBJ="${runroot}/tgt_${s}_objcnt.csv"
      local S_INV="${runroot}/src_${s}_invalid.csv"
      local T_INV="${runroot}/tgt_${s}_invalid.csv"
      local S_ROW="${runroot}/src_${s}_rows.csv"
      local T_ROW="${runroot}/tgt_${s}_rows.csv"
      echo "<div class='sec'><h3>Schema: ${s}</h3>"

      # Object counts by type (side-by-side)
      echo "<h4>Object counts by type</h4>"
      echo "<table><tr><th>Object Type</th><th>Source</th><th>Target</th><th>Match?</th></tr>"
      # join object counts
      awk -F, 'FNR==NR{a[$1]=$2;next}{t=$1; sv=a[t]+0; tv=$2+0; m=(sv==tv)?"YES":"NO"; printf "<tr><td>%s</td><td>%d</td><td>%d</td><td>%s</td></tr>\n", t, sv, tv, m}' \
        "${S_OBJ:-/dev/null}" "${T_OBJ:-/dev/null}"
      echo "</table>"

      # Invalids summary
      echo "<h4>Invalid objects</h4>"
      local sc=$(wc -l < "${S_INV}" 2>/dev/null || echo 0); local tc=$(wc -l < "${T_INV}" 2>/dev/null || echo 0)
      echo "<p>Source invalid: ${sc} | Target invalid: ${tc} | Match? $([[ "$sc" == "$tc" ]] && echo YES || echo NO)</p>"
      [[ -s "$S_INV" ]] && { echo "<details><summary>Source invalid list</summary><pre>"; html_escape < "$S_INV"; echo "</pre></details>"; }
      [[ -s "$T_INV" ]] && { echo "<details><summary>Target invalid list</summary><pre>"; html_escape < "$T_INV"; echo "</pre></details>"; }

      # Row counts side by side
      echo "<h4>Table row counts</h4>"
      echo "<table><tr><th>Table</th><th>Source</th><th>Target</th><th>Δ</th></tr>"
      awk -F, 'FNR==NR{a[$1]=$2;next}{t=$1; sv=a[t]; if(sv=="")sv=0; tv=$2+0; dv=(tv - sv); printf "<tr><td>%s</td><td>%s</td><td>%d</td><td>%+d</td></tr>\n", t, sv, tv, dv}' \
        "${S_ROW:-/dev/null}" "${T_ROW:-/dev/null}"
      echo "</table></div>"
    done

    # Roles / grants summary (counts & simple diffs)
    echo "<div class='sec'><h3>Security Summary</h3>"
    if [[ -f "${runroot}/src_roles.csv" && -f "${runroot}/tgt_roles.csv" ]]; then
      echo "<h4>Roles (non-maintained)</h4><table><tr><th>Role</th><th>Present In</th></tr>"
      awk 'FNR==NR{a[$0]=1; next} {b[$0]=1} END{for(r in a){if(!(r in b))print r"||Source-only"} for(r in b){if(!(r in a))print r"||Target-only"}}' \
        "${runroot}/src_roles.csv" "${runroot}/tgt_roles.csv" | awk -F'||' '{printf "<tr><td>%s</td><td>%s</td></tr>\n",$1,$2}'
      echo "</table>"
    fi
    echo "</div>"

    echo "</body></html>"
  } > "$html"
}

compare_local_main(){
  ensure_connections_ready
  # pick schema list
  read -rp "Enter schemas to compare (comma-separated) or leave blank for ALL non-maintained from SOURCE: " list
  if [[ -z "${list// }" ]]; then list="$(get_nonmaintained_schemas)"; fi
  list="$(echo "$list" | tr '[:lower:]' '[:upper:]' | sed 's/ //g')"
  local runroot="${COMPARE_DIR}/run_${RUN_ID}"; mkdir -p "$runroot"
  echo "$list" > "${runroot}/schemas.csv"

  # identities
  compare_ident_block_csv "$SRC_EZCONNECT" "src" "${runroot}/src_identity.csv"
  compare_ident_block_csv "$TGT_EZCONNECT" "tgt" "${runroot}/tgt_identity.csv"

  # roles/system grants (global)
  compare_roles_collect_for_db "$SRC_EZCONNECT" "src" "$runroot"
  compare_roles_collect_for_db "$TGT_EZCONNECT" "tgt" "$runroot"

  # per schema
  IFS=',' read -r -a arr <<< "$list"
  for s in "${arr[@]}"; do
    s="$(echo "$s"|awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue
    compare_schema_collect_for_db "$SRC_EZCONNECT" "src" "$s" "$runroot"
    compare_schema_collect_for_db "$TGT_EZCONNECT" "tgt" "$s" "$runroot"
  done

  # build HTML report + email
  local html="${runroot}/compare_${RUN_ID}.html"
  compare_build_html "$runroot" "$html" "${runroot}/schemas.csv"
  ok "Compare HTML: $html"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Compare ${RUN_ID}" || true
}

# ------------------------------ Monitor / Jobs --------------------------------
show_jobs(){
  ensure_connections_ready
  ce "Logs: $LOG_DIR"
  read -rp "Show DBA_DATAPUMP_JOBS on which DB? (src/tgt/b=back/x=exit): " side
  case "${side,,}" in
    src) run_sql "$SRC_EZCONNECT" "jobs_src_${RUN_ID}" "SET LINES 220 PAGES 200
COL owner_name FOR A20
COL job_name FOR A30
COL state FOR A12
SELECT owner_name, job_name, state, operation, job_mode, degree, attached_sessions FROM dba_datapump_jobs ORDER BY 1,2; /" ;;
    tgt) run_sql "$TGT_EZCONNECT" "jobs_tgt_${RUN_ID}" "SET LINES 220 PAGES 200
COL owner_name FOR A20
COL job_name FOR A30
COL state FOR A12
SELECT owner_name, job_name, state, operation, job_mode, degree, attached_sessions FROM dba_datapump_jobs ORDER BY 1,2; /" ;;
    b) return ;;
    x) exit 0 ;;
    *) warn "Unknown choice";;
  esac
  for f in "$LOG_DIR"/*.log; do [[ -f "$f" ]] || continue; echo "---- $(basename "$f") (tail -n 20) ----"; tail -n 20 "$f"; done
}

cleanup_dirs(){
  ensure_connections_ready; read -rp "Drop DIRECTORY ${COMMON_DIR_NAME} on (src/tgt/both/b=back/x=exit)? " side
  case "${side,,}" in
    src) run_sql_try "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" || true ;;
    tgt) run_sql_try "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" || true ;;
    both) run_sql_try "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" || true
          run_sql_try "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" || true ;;
    b) return ;;
    x) exit 0 ;;
    *) warn "No action";;
  esac
}

# ------------------------------ Menus -----------------------------------------
export_menu(){
  ensure_connections_ready
  while true; do
    cat <<'EOS' | say_to_user
Export Menu (Source DB):
  1) FULL export
  2) SCHEMAS export
  3) TRANSPORT TABLESPACES export
  4) TABLES export
  B) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "${c^^}" in
      1) exp_full_menu ;; 2) exp_schemas_menu ;; 3) exp_tablespaces ;; 4) exp_tables ;;
      B) break ;; X) exit 0 ;; * ) warn "Invalid" ;;
    esac
  done
}

import_menu(){
  ensure_connections_ready
  while true; do
    cat <<'EOS' | say_to_user
Import Menu:
  1) FULL (metadata_only / all)
  2) SCHEMAS (non-maintained or user list)
  3) TABLESPACES (transport)
  4) TABLES
  5) Cleanup helpers (drop users/objects)  [DANGEROUS]
  6) DDL Execution (Target DB)
  7) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) imp_full_menu ;;
      2) imp_schemas_menu ;;
      3) imp_tablespaces ;;
      4) imp_tables ;;
      5) import_cleanup_menu ;;
      6) ddl_exec_on_target_loop ;;
      7) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

ddl_menu(){
  ddl_menu_wrapper
}

compare_schema_menu(){
  compare_local_main
}

main_menu(){
  while true; do
    cat <<EOS | say_to_user

======== Oracle 19c Migration & DDL (${SCRIPT_NAME} v4ax) ========
SYS_USER: ${SYS_USER}
Source:  ${SRC_EZCONNECT}
Target:  ${TGT_EZCONNECT}
PARALLEL=${PARALLEL}  COMPRESSION=${COMPRESSION}  TABLE_EXISTS_ACTION=${TABLE_EXISTS_ACTION}
DDL out: ${DDL_DIR}  Compare out: ${COMPARE_DIR}
=============================================================

1) Toggle DEBUG on/off (current: ${DEBUG})
2) Validate DB connections (identity/charsets)
3) Precheck Export DIRECTORY (SOURCE)
4) Precheck Import DIRECTORY (TARGET)
5) Export (EXPDP)           -> sub menu
6) Import (IMPDP & DDL)     -> sub menu
7) DDL Extraction (Source)  -> sub menu
8) Compare Schemas (LOCAL)  -> run compare
9) Monitor/Status (jobs + logs tail)
A) Drop DIRECTORY objects (cleanup)
X) Exit
EOS
    read -rp "Choose: " choice
    case "${choice^^}" in
      1) toggle_debug ;;
      2) db_connection_validation ;;
      3) precheck_export_directory || true ;;
      4) precheck_import_directory || true ;;
      5) export_menu ;;
      6) import_menu ;;
      7) ddl_menu ;;
      8) compare_schema_menu ;;
      9) show_jobs ;;
      A) cleanup_dirs ;;
      X) exit 0 ;;
      *) warn "Invalid choice." ;;
    esac
  done
}

main_menu
