#!/usr/bin/env bash
# dp_migrate.sh (v4ab) - Oracle 19c Data Pump migration & compare toolkit
# v4ab:
# - Integrates HTML compare + email (from v4aa)
# - Rewrites ddl_privs_to_roles() per screenshot, NO OVD_GLOBAL_USER refs
# - Rewrites ddl_sysprivs_to_users() to emit object GRANTs per screenshot, NO OVD refs

set -euo pipefail
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
ce()   { printf "%b\n" "$*"; }
ok()   { ce "\e[32m✔ $*\e[0m"; }
warn() { ce "\e[33m! $*\e[0m"; }
err()  { ce "\e[31m✘ $*\e[0m"; }
DEBUG="${DEBUG:-Y}"
debug() { if [[ "${DEBUG^^}" == "Y" ]]; then ce "\e[36m[DEBUG]\e[0m $*"; fi; }
[[ -f "$CONFIG_FILE" ]] || { err "Config file not found: $CONFIG_FILE"; exit 1; }
source "$CONFIG_FILE"
need_vars=( SRC_EZCONNECT TGT_EZCONNECT SYS_PASSWORD NAS_PATH DUMPFILE_PREFIX )
for v in "${need_vars[@]}"; do [[ -n "${!v:-}" ]] || { err "Missing required config variable: $v"; exit 1; }; done
PARALLEL="${PARALLEL:-4}"
COMPRESSION="${COMPRESSION:-METADATA_ONLY}"
TABLE_EXISTS_ACTION="${TABLE_EXISTS_ACTION:-APPEND}"
SCHEMAS_LIST_EXP="${SCHEMAS_LIST_EXP:-}"
SCHEMAS_LIST_IMP="${SCHEMAS_LIST_IMP:-}"
SKIP_SCHEMAS="${SKIP_SCHEMAS:-}"
DRY_RUN_ONLY="${DRY_RUN_ONLY:-N}"
REPORT_EMAILS="${REPORT_EMAILS:-}"
MAIL_ENABLED="${MAIL_ENABLED:-Y}"
MAIL_FROM="${MAIL_FROM:-noreply@localhost}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[Oracle Compare]}"
for b in sqlplus expdp impdp; do command -v "$b" >/dev/null 2>&1 || { err "Missing required binary: $b"; exit 1; }; done
[[ -d "$NAS_PATH" ]] || { err "NAS mount path not found on this host: $NAS_PATH"; exit 1; }
mask_pwd() { sed 's#[^/"]\{1,\}@#***@#g' | sed 's#sys/[^@]*@#sys/****@#g'; }
to_inlist_upper() {
  local csv="$1" out="" tok; IFS=',' read -r -a arr <<< "$csv"
  for tok in "${arr[@]}"; do tok="$(echo "$tok" | awk '{$1=$1;print}')"; [[ -z "$tok" ]] && continue; tok="${tok^^}"; out+="${out:+,}'${tok}'"; done
  printf "%s" "$out"
}
csv_to_inlist() {
  local csv="${1:-}" out="" tok; IFS=',' read -r -a arr <<< "$csv"
  for tok in "${arr[@]}"; do tok="$(echo "$tok" | awk '{$1=$1;print}')"; [[ -z "$tok" ]] && continue; tok="${tok^^}"; out+="${out:+,}'${tok}'"; done
  echo "$out"
}
run_sql() {
  local ez="$1"; shift; local tag="${1:-sql}"; shift || true; local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"; local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql(tag=$tag) on ${ez} -> $logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF
${sql}
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then err "SQL error: ${tag} (see $logf)"; tail -n 120 "$logf" | mask_pwd | sed 's/^/  /'; exit 1; fi
  ok "SQL ok: ${tag}"
}
find_mailer() { if command -v mailx >/dev/null 2>&1; then echo mailx; elif command -v mail >/dev/null 2>&1; then echo mail; elif command -v sendmail >/dev/null 2>&1; then echo sendmail; else echo ""; fi; }
email_file() {
  local file="$1" subject="$2"
  [[ "${MAIL_ENABLED^^}" != "Y" ]] && { warn "MAIL_ENABLED!=Y; skip email."; return 0; }
  [[ -z "${REPORT_EMAILS}" ]] && { warn "REPORT_EMAILS empty; skip email."; return 0; }
  local m; m="$(find_mailer)"; [[ -z "$m" ]] && { warn "No mailer found"; return 0; }
  case "$m" in
    mailx) mailx -a "From: ${MAIL_FROM}" -a "Content-Type: text/html" -a "$file" -s "${subject}" $REPORT_EMAILS < /dev/null || warn "mailx failed" ;;
    mail)  mail -s "${subject}" $REPORT_EMAILS < "$file" || warn "mail failed" ;;
    sendmail) { echo "From: ${MAIL_FROM}"; echo "To: ${REPORT_EMAILS}"; echo "Subject: ${subject}"; echo "MIME-Version: 1.0"; echo "Content-Type: text/html; charset=UTF-8"; echo; cat "$file"; } | sendmail -t || warn "sendmail failed" ;;
  esac
  ok "Email queued to ${REPORT_EMAILS}"
}
ensure_directory_object() {
  local ez="$1" host_tag="$2" dir_name="${3:-$COMMON_DIR_NAME}" dir_path="$NAS_PATH"
  run_sql "$ez" "create_dir_${host_tag}" "
BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY ${dir_name} AS ''${dir_path}''';
  BEGIN EXECUTE IMMEDIATE 'GRANT READ,WRITE ON DIRECTORY ${dir_name} TO PUBLIC'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"
}
validate_directory_on_db() {
  local ez="$1" tag="$2"; local logtag="dircheck_${tag}"
  run_sql "$ez" "$logtag" "
SET SERVEROUTPUT ON
DECLARE
  f UTL_FILE.FILE_TYPE; fname VARCHAR2(200) := '__dp_dir_test_${RUN_ID}.html';
BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'), fname, 'W', 32767);
  UTL_FILE.PUT_LINE(f, '<html><body>UTL_FILE write test</body></html>');
  UTL_FILE.FCLOSE(f);
END;
/
"
}
ddl_spool() {
  local out="$1"; shift; local body="$*"
  local conn="sys/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"
  sqlplus -s "$conn" <<SQL >"$out" 2>"${out}.log"
SET LONG 1000000 LONGCHUNKSIZE 1000000 LINES 32767 PAGES 0 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'OID', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
END;
/
${body}
EXIT
SQL
  if grep -qi "ORA-" "${out}.log"; then err "DDL extract error in $(basename "$out")"; tail -n 50 "${out}.log" | mask_pwd | sed 's/^/  /'; return 1; fi
  ok "DDL file created: $out"
}
ddl_users() { local f="${DDL_DIR}/01_users_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('USER', username) FROM dba_users WHERE oracle_maintained='N' ORDER BY username;
"; }
ddl_profiles() { local f="${DDL_DIR}/02_profiles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('PROFILE', profile) FROM (SELECT DISTINCT profile FROM dba_profiles ORDER BY 1);
"; }
ddl_roles() { local f="${DDL_DIR}/03_roles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('ROLE', role) FROM dba_roles WHERE NVL(oracle_maintained,'N')='N' ORDER BY role;
"; }
# REWRITE #1
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
# REWRITE #2
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
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, 'PUBLIC') FROM dba_synonyms WHERE owner='PUBLIC' ORDER BY synonym_name;
"; }
ddl_private_synonyms_all_users() { local f="${DDL_DIR}/08_private_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, owner)
FROM dba_synonyms
WHERE owner <> 'PUBLIC' AND owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, synonym_name;
"; }
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
    AND temporary = 'N'
)
SELECT DBMS_METADATA.GET_DDL(object_type, object_name, owner)
FROM objs
ORDER BY owner, object_type, object_name;
"; }
ddl_tablespaces() {
  local f="${DDL_DIR}/10_tablespaces_${RUN_ID}.sql"
  local skip_clause; skip_clause="$(to_inlist_upper "SYSTEM,SYSAUX,TEMP,UNDOTBS1,UNDOTBS2")"
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
  WHERE default_role='YES' AND grantee IN (SELECT username FROM u)
  GROUP BY grantee
)
SELECT 'ALTER USER '||username||' DEFAULT ROLE '||NVL(roles,'ALL')||';' FROM u LEFT JOIN r USING (username) ORDER BY username;
"; }
ddl_directories() { local f="${DDL_DIR}/13_directories_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DIRECTORY', directory_name) FROM (SELECT DISTINCT directory_name FROM dba_directories ORDER BY 1);
"; }
ddl_db_links_by_owner() {
  read -rp "Enter owner for DB links (schema name): " owner; owner="${owner^^}"
  local f="${DDL_DIR}/14_db_links_${owner}_${RUN_ID}.sql"
  ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DB_LINK', db_link, owner)
FROM dba_db_links
WHERE owner = UPPER('${owner}')
ORDER BY db_link;
"
  warn "Note: DB link passwords may be masked/omitted."
}
snapshot_src_objects_csv() {
  local schema="${1^^}"; [[ -z "$schema" ]] && { warn "Schema empty"; return 1; }
  local fname="${schema}_src_${RUN_ID}.csv"
  run_sql "$SRC_EZCONNECT" "snap_src_csv_${schema}" "
SET SERVEROUTPUT ON
DECLARE f UTL_FILE.FILE_TYPE; BEGIN
  f := UTL_FILE.FOPEN(UPPER('${COMMON_DIR_NAME}'), '${fname}', 'W', 32767);
  FOR r IN (SELECT object_type, object_name, status FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%' ORDER BY object_type, object_name) LOOP
    UTL_FILE.PUT_LINE(f, r.object_type||'|'||r.object_name||'|'||r.status);
  END LOOP; UTL_FILE.FCLOSE(f);
END; /
"
}
create_src_external_on_target() {
  local schema="${1^^}"; local fname="${schema}_src_${RUN_ID}.csv"
  run_sql "$TGT_EZCONNECT" "drop_ext_${schema}" "BEGIN EXECUTE IMMEDIATE 'DROP TABLE src_obj_snap_ext PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
  run_sql "$TGT_EZCONNECT" "create_ext_${schema}" "
CREATE TABLE src_obj_snap_ext (
  object_type VARCHAR2(30), object_name VARCHAR2(128), status VARCHAR2(7)
) ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY ${COMMON_DIR_NAME}
  ACCESS PARAMETERS (RECORDS DELIMITED BY NEWLINE FIELDS TERMINATED BY '|' (object_type CHAR(30), object_name CHAR(128), status CHAR(7)))
  LOCATION ('${fname}')
) REJECT LIMIT UNLIMITED; /
"
}
compare_one_schema_sql_external() {
  local schema="${1^^}"; [[ -z "$schema" ]] && { warn "Schema empty"; return 1; }
  ensure_directory_object "$SRC_EZCONNECT" "src"; ensure_directory_object "$TGT_EZCONNECT" "tgt"
  validate_directory_on_db "$SRC_EZCONNECT" "src"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
  snapshot_src_objects_csv "$schema"; create_src_external_on_target "$schema"
  local html="${COMPARE_DIR}/compare_${schema}_${RUN_ID}.html"
  local conn="sys/${SYS_PASSWORD}@${TGT_EZCONNECT} as sysdba"
  sqlplus -s "$conn" <<SQL >"$html" 2>"${html}.log"
SET MARKUP HTML ON SPOOL ON ENTMAP OFF
SPOOL $html
PROMPT <h2>Schema Compare Report: ${schema}</h2>
PROMPT <p>Run ID: ${RUN_ID} | Source: ${SRC_EZCONNECT} | Target: ${TGT_EZCONNECT}</p>
PROMPT <h3>Delta (SOURCE CSV vs TARGET)</h3>
WITH src AS (SELECT object_type, object_name, status FROM src_obj_snap_ext),
tgt AS (SELECT object_type, object_name, status FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'),
j AS (
  SELECT COALESCE(src.object_type, tgt.object_type) AS object_type,
         COALESCE(src.object_name, tgt.object_name) AS object_name,
         src.status AS src_status, tgt.status AS tgt_status,
         CASE
           WHEN src.object_name IS NOT NULL AND tgt.object_name IS NULL THEN 'ONLY_IN_SOURCE'
           WHEN src.object_name IS NULL AND tgt.object_name IS NOT NULL THEN 'ONLY_IN_TARGET'
           WHEN src.status IS NOT NULL AND tgt.status IS NOT NULL AND src.status <> tgt.status THEN 'STATUS_DIFFERS'
           ELSE 'SAME' END AS delta_kind
  FROM src FULL OUTER JOIN tgt ON src.object_type=tgt.object_type AND src.object_name=tgt.object_name
)
SELECT object_type, object_name, src_status, tgt_status, delta_kind FROM j WHERE delta_kind <> 'SAME'
ORDER BY delta_kind, object_type, object_name;
PROMPT <h3>Summary</h3>
WITH src_cnt AS (SELECT COUNT(*) cnt FROM src_obj_snap_ext),
tgt_cnt AS (SELECT COUNT(*) cnt FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'),
j AS (
  SELECT CASE
           WHEN src.object_name IS NOT NULL AND tgt.object_name IS NULL THEN 'ONLY_IN_SOURCE'
           WHEN src.object_name IS NULL AND tgt.object_name IS NOT NULL THEN 'ONLY_IN_TARGET'
           WHEN src.status IS NOT NULL AND tgt.status IS NOT NULL AND src.status <> tgt.status THEN 'STATUS_DIFFERS'
           ELSE 'SAME' END AS delta_kind
  FROM src_obj_snap_ext src FULL OUTER JOIN
       (SELECT object_type, object_name, status FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%') tgt
  ON src.object_type=tgt.object_type AND src.object_name=tgt.object_name
)
SELECT * FROM (
  SELECT 'Source total objects' AS metric, (SELECT cnt FROM src_cnt) AS value FROM dual
  UNION ALL SELECT 'Target total objects', (SELECT cnt FROM tgt_cnt) FROM dual
  UNION ALL SELECT 'DDL only in source', NVL(COUNT(CASE WHEN delta_kind='ONLY_IN_SOURCE' THEN 1 END),0) FROM j
  UNION ALL SELECT 'DDL only in target', NVL(COUNT(CASE WHEN delta_kind='ONLY_IN_TARGET' THEN 1 END),0) FROM j
  UNION ALL SELECT 'Status differs', NVL(COUNT(CASE WHEN delta_kind='STATUS_DIFFERS' THEN 1 END),0) FROM j
); 
PROMPT <h3>Invalid Objects on Target</h3>
SELECT object_type, COUNT(*) AS invalid_count FROM dba_objects WHERE owner=UPPER('${schema}') AND status='INVALID' GROUP BY object_type ORDER BY object_type;
SPOOL OFF
EXIT
SQL
  local subj="${MAIL_SUBJECT_PREFIX} Schema Compare - ${schema} - ${RUN_ID}"; email_file "$html" "$subj"
  run_sql "$TGT_EZCONNECT" "drop_ext_post_${schema}" "BEGIN EXECUTE IMMEDIATE 'DROP TABLE src_obj_snap_ext PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
}
get_nonmaintained_schemas() {
  local pred=""; if [[ -n "$SKIP_SCHEMAS" ]]; then IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done; fi
  run_sql "$SRC_EZCONNECT" "list_nonmaint_users_${RUN_ID}" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS (SELECT username FROM dba_users WHERE oracle_maintained='N'${pred})
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base; /
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/list_nonmaint_users_${RUN_ID}.log"
}
compare_many_sql_external() {
  local list_input="$1"; local schemas_list=""
  if [[ -n "$list_input" ]]; then schemas_list="$list_input"; else schemas_list="$(get_nonmaintained_schemas)"; [[ -z "$schemas_list" ]] && { warn "No non-maintained schemas found on source."; return 0; }; fi
  local index="${COMPARE_DIR}/compare_index_${RUN_ID}.html"
  { echo "<html><head><meta charset='utf-8'><title>Schema Compare Index ${RUN_ID}</title><style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px}</style></head><body><h2>Schema Compare Index</h2><p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}</p><table><tr><th>#</th><th>Schema</th><th>Report</th></tr>"; } > "$index"
  local i=0; IFS=',' read -r -a arr <<< "$schemas_list"
  for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; i=$((i+1)); compare_one_schema_sql_external "$s"; local f="compare_${s^^}_${RUN_ID}.html"; echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"; done
  echo "</table></body></html>" >> "$index"; email_file "$index" "${MAIL_SUBJECT_PREFIX} Compare Index - ${RUN_ID}"
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

======== Oracle 19c Migration & DDL (${SCRIPT_NAME} v4ab) ========
Source: ${SRC_EZCONNECT}
Target: ${TGT_EZCONNECT}
NAS:    ${NAS_PATH}
DDL out: ${DDL_DIR}
Compare out: ${COMPARE_DIR}
=============================================================

1) Precheck & create DIRECTORY on source and target
2) Export (Data Pump)           -> [use your existing exp menus if needed]
3) Import (Data Pump)           -> [use your existing imp menus if needed]
4) Monitor/Status               -> DBA_DATAPUMP_JOBS + tail logs
5) Drop DIRECTORY objects       -> cleanup
6) DDL Extraction (Source DB)   -> sub menu
7) Compare Objects (NO DB LINK) -> sub menu (HTML + email)
8) Quit
EOS
    read -rp "Choose: " choice
    case "$choice" in
      1) ensure_directory_object "$SRC_EZCONNECT" "src"; ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$SRC_EZCONNECT" "src"; validate_directory_on_db "$TGT_EZCONNECT" "tgt";;
      2) echo "Export submenu omitted in this cut (kept small).";;
      3) echo "Import submenu omitted in this cut (kept small).";;
      4) echo "Check logs in $LOG_DIR and data pump jobs via separate queries.";;
      5) read -rp "Drop DIRECTORY ${COMMON_DIR_NAME} on (src/tgt/both)? " side
         case "${side,,}" in
           src) run_sql "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
           tgt) run_sql "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
           both) run_sql "$SRC_EZCONNECT" "drop_dir_src_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
                 run_sql "$TGT_EZCONNECT" "drop_dir_tgt_${RUN_ID}" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
           *) warn "No action";;
         esac ;;
      6) ddl_menu_wrapper ;;
      7) compare_schema_menu ;;
      8) exit 0 ;;
      *) warn "Invalid choice.";;
    esac
  done
}
main_menu
