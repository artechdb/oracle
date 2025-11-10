#!/usr/bin/env bash
# =============================================================================
# dp_migrate.sh (v4as) - Oracle 19c Data Pump migration & compare toolkit
# =============================================================================
# Fixes in v4as:
# - Resolved "version: unbound variable" by removing any risky 'version:' usage
#   under 'set -u' and printing tool version safely.
# - Added DEBUG tracing for compare schema functions (start/end and each step).
# - Retains inline-HTML email after expdp/impdp runs, DDL extraction suite,
#   robust parfile placement, and local (jumper) compare with rich HTML header.
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
COMMON_DIR_NAME="${COMMON_DIR_NAME:-DP_DIR}"
LOCAL_COMPARE_DIR="${LOCAL_COMPARE_DIR:-/tmp/dp_compare}"

mkdir -p "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$DDL_DIR" "$COMPARE_DIR" "$LOCAL_COMPARE_DIR"

# ------------------------ Pretty print & debug helpers -------------------------
ce()   { printf "%b\n" "$*"; }
ok()   { ce "\e[32m✔ $*\e[0m"; }
warn() { ce "\e[33m! $*\e[0m"; }
err()  { ce "\e[31m✘ $*\e[0m"; }
DEBUG="${DEBUG:-Y}"
debug() { if [[ "${DEBUG^^}" == "Y" ]]; then ce "\e[36m[DEBUG]\e[0m $*" >&2; fi; }

say_to_user() { if [[ -w /dev/tty ]]; then cat >/dev/tty; else cat 1>&2; fi; }

toggle_debug() {
  if [[ "${DEBUG^^}" == "Y" ]]; then DEBUG="N"; ok "DEBUG turned OFF"; else DEBUG="Y"; ok "DEBUG turned ON"; fi
  ce "Current DEBUG=${DEBUG}"
}

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
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[Oracle DP]}"
MAIL_METHOD="${MAIL_METHOD:-auto}"

COMPARE_ENGINE="${COMPARE_ENGINE:-LOCAL}"  # EXTERNAL | FILE | LOCAL
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"

EXPORT_DIR_PATH="${EXPORT_DIR_PATH:-${NAS_PATH:-}}"
IMPORT_DIR_PATH="${IMPORT_DIR_PATH:-}"
NAS_PATH="${NAS_PATH:-}"

ok "Using config: $CONFIG_FILE"
ok "Work: $WORK_DIR | Logs: $LOG_DIR | Parfiles(default): $PAR_DIR | DDLs: $DDL_DIR | Compare: $COMPARE_DIR"

# ---------------------------- Pre-flight checks --------------------------------
for b in sqlplus expdp impdp; do
  if ! command -v "$b" >/dev/null 2>&1; then err "Missing required binary: $b"; exit 1; fi
done

mask_pwd() { sed 's#[^/"]\{1,\}@#***@#g' | sed 's#sys/[^@]*@#sys/****@#g'; }

basename_safe() { local x="${1:-}"; x="${x##*/}"; printf "%s" "$x"; }
reject_if_pathlike() { local x="${1:-}"; if [[ "$x" == *"/"* ]]; then warn "Path component detected and removed: [$x]"; x="${x##*/}"; fi; printf "%s" "$x"; }

parfile_dir_for_mode() {
  local mode="${1}" preferred=""
  case "${mode}" in expdp) preferred="${EXPORT_DIR_PATH:-}";; impdp) preferred="${IMPORT_DIR_PATH:-}";; esac
  if [[ -n "$preferred" && -d "$preferred" && -w "$preferred" ]]; then echo "$preferred"; else
    [[ -n "$preferred" && ! -d "$preferred" ]] && warn "Parfile dir [$preferred] missing; using $PAR_DIR"
    [[ -n "$preferred" && -d "$preferred" && ! -w "$preferred" ]] && warn "Parfile dir [$preferred] not writable; using $PAR_DIR"
    echo "$PAR_DIR"
  fi
}

# ------------------------------- SQL helpers ----------------------------------
run_sql() {
  local ez="$1"; shift
  local tag="${1:-sql}"; shift || true
  local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql(tag=${tag}) on ${ez} -> $logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
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

run_sql_try() {
  local ez="$1"; shift
  local tag="${1:-sqltry}"; shift || true
  local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_try(tag=${tag}) on ${ez} -> $logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF LONG 1000000 LONGCHUNKSIZE 1000000
SET DEFINE OFF
${sql}
EXIT
SQL
  if grep -qi "ORA-" "$logf"; then
    warn "SQL (non-fatal) error on ${tag} — see $logf"
    tail -n 60 "$logf" | mask_pwd | sed 's/^/  /'
    return 1
  fi
  ok "SQL ok (non-fatal): ${tag}"
  return 0
}

run_sql_spool_local() {
  local ez="$1"; shift
  local tag="$1"; shift
  local out="$1"; shift
  local body="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  debug "run_sql_spool_local(tag=${tag}) -> spool $out ; log=$logf"
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
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
    tail -n 120 "$logf" | mask_pwd | sed 's/^/  /'
    exit 1
  fi
  ok "Spool ok: $out"
}

run_sql_capture() {
  local ez="$1" body="$2"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
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

# ------------------------------- Mail helpers ---------------------------------
detect_mail_stack() {
  local forced="${MAIL_METHOD:-auto}"
  case "${forced}" in
    sendmail) command -v sendmail >/dev/null && { echo sendmail; return; } ;;
    mailutils) (mail --version 2>/dev/null | grep -qi "mailutils") && { echo mailutils; return; } ;;
    bsdmail)   (mail -V 2>/dev/null | grep -qi "bsd") && { echo bsdmail; return; } ;;
    mailx)     command -v mailx >/dev/null && { echo mailx; return; } ;;
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
  debug "Email stack: ${method}; subject=${subject}; to=${REPORT_EMAILS}; file=${file}"
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
           -s "${subject}" ${REPORT_EMAILS} < "$file" || { warn "mail (mailutils) failed"; return 1; }
      ;;
    bsdmail)
      mail -a "From: ${MAIL_FROM}" \
           -a "MIME-Version: 1.0" \
           -a "Content-Type: text/html; charset=UTF-8" \
           -s "${subject}" ${REPORT_EMAILS} < "$file" || { warn "mail (bsd) failed"; return 1; }
      ;;
    mailx)
      if mailx -V 2>&1 | grep -qiE "heirloom|s-nail|nail"; then
        if mailx -a "Content-Type: text/html" -s test "$MAIL_FROM" </dev/null 2>&1 | grep -qi "unknown option"; then
          mailx -r "$MAIL_FROM" -s "${subject}" ${REPORT_EMAILS} < "$file" || { warn "mailx failed"; return 1; }
        else
          mailx -r "$MAIL_FROM" -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" ${REPORT_EMAILS} < "$file" || { warn "mailx failed"; return 1; }
        fi
      else
        mailx -s "${subject}" ${REPORT_EMAILS} < "$file" || { warn "mailx failed"; return 1; }
      fi
      ;;
    none) warn "No supported mailer found; skipping email."; return 1 ;;
  esac
  ok "Inline email sent to ${REPORT_EMAILS} via ${method}"
}

dp_emit_html_and_email() {
  local tool="$1" tag="$2" pf="$3" client_log="$4"
  local html="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.html"
  {
    echo "<html><head><meta charset='utf-8'><title>${tool^^} ${tag} ${RUN_ID}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} pre{white-space:pre-wrap; border:1px solid #ddd; padding:10px; background:#fafafa} .box{border:1px solid #ccc; padding:10px; margin:8px 0}</style>"
    echo "</head><body>"
    echo "<h2>${tool^^} job completed</h2>"
    echo "<p><b>Run:</b> ${RUN_ID}<br/><b>Tool:</b> ${tool}<br/><b>Tag:</b> ${tag}</p>"
    echo "<div class='box'><h3>Parfile</h3><pre>"
    if [[ -f "$pf" ]]; then sed -E 's/(encryption_password=).*/\1*****/I' "$pf" | sed 's/&/\&amp;/g;s/</\&lt;/g'; else echo "(parfile not found at $pf)"; fi
    echo "</pre></div>"
    echo "<div class='box'><h3>Client Log</h3><pre>"
    if [[ -f "$client_log" ]]; then sed 's/&/\&amp;/g;s/</\&lt;/g' "$client_log"; else echo "(client log not found at $client_log)"; fi
    echo "</pre></div>"
    local server_log=""
    if [[ -f "$pf" ]]; then server_log="$(awk -F= 'tolower($1)=="logfile"{print $2}' "$pf" | head -1)"; fi
    [[ -n "$server_log" ]] && echo "<p><i>Server log (on DB host Oracle DIRECTORY):</i> ${server_log}</p>"
    echo "</body></html>"
  } > "$html"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} ${tool^^} ${tag} ${RUN_ID}"
  ok "HTML emailed: ${html}"
}

# ----------------------- DIRECTORY helpers (NON-FATAL) ------------------------
create_or_replace_directory() {
  local ez="$1" dir_name="$2" dir_path="$3" host_tag="$4"
  [[ -z "$dir_path" ]] && { warn "create_or_replace_directory: dir_path is empty"; return 1; }
  dir_name="$(echo "$dir_name" | tr '[:lower:]' '[:upper:]')"
  debug "CREATE OR REPLACE DIRECTORY ${dir_name} AS '${dir_path}' on ${host_tag} (${ez})"
  run_sql_try "$ez" "create_dir_${host_tag}_${dir_name}" "
BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY ${dir_name} AS ''${dir_path}''';
  BEGIN EXECUTE IMMEDIATE 'GRANT READ,WRITE ON DIRECTORY ${dir_name} TO PUBLIC'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"
  return $?
}

validate_directory_on_db_try() {
  local ez="$1" tag="$2" dir_name="${3:-$COMMON_DIR_NAME}"
  dir_name="$(echo "$dir_name" | tr '[:lower:]' '[:upper:]')"
  local logtag="dircheck_${tag}"
  debug "VALIDATE DIRECTORY ${dir_name} on ${tag} (${ez})"
  run_sql_try "$ez" "$logtag" "
SET SERVEROUTPUT ON
DECLARE
  v_cnt  PLS_INTEGER := 0;
  v_path VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM all_directories
  WHERE directory_name = UPPER('${dir_name}');
  IF v_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('DIRECTORY_MISSING '||UPPER('${dir_name}'));
  ELSE
    SELECT directory_path INTO v_path
    FROM all_directories
    WHERE directory_name = UPPER('${dir_name}');
    DBMS_OUTPUT.PUT_LINE('DIRECTORY_OK '||UPPER('${dir_name}')||' '||v_path);
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('DIRECTORY_VALIDATE_ERROR '||SQLCODE||' '||SQLERRM);
END;
/
"
  return $?
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
    echo "tool_binary: $(command -v $tool || echo not found)"
    echo "tool_version: $($tool -V 2>/dev/null | head -1 || echo '(unknown)')"
    echo "---- parfile (${pf}) ----"
    if [[ -f "$pf" ]]; then sed -E 's/(encryption_password=).*/\1*****/I' "$pf"; else echo "<parfile not found>"; fi
  } > "$client_log" 2>&1

  set +e
  ( set -o pipefail; $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} )
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    err "[${tool}] FAILED (rc=$rc) — see ${client_log}"
    dp_emit_html_and_email "$tool" "$tag-FAILED" "$pf" "$client_log" || true
    exit $rc
  fi

  ok "[${tool}] SUCCESS — see ${client_log}"
  dp_emit_html_and_email "$tool" "$tag" "$pf" "$client_log" || true
}

par_common() {
  local mode="$1" tag="$2" dir_name="$3"
  local pf_dir; pf_dir="$(parfile_dir_for_mode "$mode")"
  mkdir -p "$pf_dir" || true
  local pf="${pf_dir}/${tag}_${RUN_ID}.par"
  debug "par_common(mode=${mode}, tag=${tag}, dir=${dir_name}) -> ${pf}"

  local server_log="$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log")"

  {
    echo "directory=${dir_name}"
    echo "logfile=${server_log}"
    echo "logtime=all"
    echo "parallel=${PARALLEL}"
  } > "$pf"

  if [[ "$mode" == "expdp" ]]; then
    local dump_pat="$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}_%U.dmp")"
    {
      echo "dumpfile=${dump_pat}"
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

show_and_confirm_parfile() {
  local pf="$1" tool="${2:-}"
  { echo "----- PARFILE: ${pf} -----"
    sed -E 's/(encryption_password=).*/\1*****/I' "$pf"
    echo "---------------------------"
  } | say_to_user
  local ans
  read -rp "Proceed with ${tool:-the job} using this parfile? [Y/N/X]: " ans
  case "${ans^^}" in Y) return 0 ;; N) return 1 ;; X) exit 0 ;; *) return 1 ;; esac
}

# -------------------- value confirmers & content picker ------------------------
confirm_edit_value() {
  local label="$1" val="${2:-}" ans=""
  while true; do
    if [[ -z "${val// }" ]]; then
      echo "${label} is currently empty." | say_to_user
      read -rp "Please enter ${label}: " val
      continue
    fi
    echo "${label}: ${val}" | say_to_user
    read -rp "Use this value? (Y to accept, N to edit) [Y/N]: " ans
    case "${ans^^}" in Y) echo "$val"; return 0 ;; N) read -rp "Enter new ${label}: " val ;; *) echo "Please answer Y or N." | say_to_user ;; esac
  done
}

choose_content_option() {
  while true; do
    cat <<'EOS' | say_to_user
Choose Export Content:
  a) METADATA_ONLY  (schema/metadata only)
  b) FULL (ALL)     (metadata + data)
  x) Exit
EOS
    local choice=""; read -rp "Select [a/b/x]: " choice
    case "${choice,,}" in
      a) echo "METADATA_ONLY"; echo "[INFO] CONTENT=METADATA_ONLY" | say_to_user; return 0 ;;
      b) echo "ALL";            echo "[INFO] CONTENT=ALL"            | say_to_user; return 0 ;;
      x) echo "[INFO] Exit chosen." | say_to_user; exit 0 ;;
      *) echo "Invalid choice. Please select a, b or x." | say_to_user ;;
    esac
  done
}

# ---------------- Precheck helpers: verify only on the DB that runs the job ---
precheck_export_directory() {
  local def_name="${COMMON_DIR_NAME:-DP_DIR}"
  while true; do
    read -rp "Export: DIRECTORY object name to use/create on SOURCE [${def_name}]: " dname
    local dir_name="$(echo "${dname:-$def_name}" | tr '[:lower:]' '[:upper:]')"
    local default_path="${EXPORT_DIR_PATH:-${NAS_PATH:-}}"
    local dir_path=""
    if [[ -z "$default_path" ]]; then
      echo "Enter absolute OS path on the SOURCE DB server for export dumpfiles (.dmp):" | say_to_user
      read -rp "Export path: " dir_path
    else
      echo "Default export path from conf: ${default_path}" | say_to_user
      read -rp "Use this export path? [Y to accept, N to enter a different path]: " ans
      if [[ "${ans^^}" == "N" ]]; then read -rp "Enter export path: " dir_path; else dir_path="$default_path"; fi
    fi
    if [[ -z "$dir_path" ]]; then warn "Export path cannot be empty."
    else
      create_or_replace_directory "$SRC_EZCONNECT" "$dir_name" "$dir_path" "src"
      if validate_directory_on_db_try "$SRC_EZCONNECT" "src" "$dir_name"; then
        ok "SOURCE export DIRECTORY ${dir_name} -> ${dir_path} is ready"
        EXPORT_DIR_NAME="$dir_name"; EXPORT_DIR_PATH="$dir_path"; return 0
      fi
      warn "[DEBUG] run_sql_try(tag_dircheck_src) failed to create/validate export DIRECTORY on source."
    fi
    read -rp "Retry export precheck? [Y=retry / B=back / X=exit]: " r
    case "${r^^}" in Y) continue ;; B) return 1 ;; X) exit 0 ;; *) return 1 ;; esac
  done
}

precheck_import_directory() {
  local def_name="${COMMON_DIR_NAME:-DP_DIR}"
  while true; do
    read -rp "Import: DIRECTORY object name to use/create on TARGET [${def_name}]: " dname
    local dir_name="$(echo "${dname:-$def_name}" | tr '[:lower:]' '[:upper:]')"
    echo "Enter absolute OS path on the TARGET DB server for import dumpfiles (.dmp):" | say_to_user
    read -rp "Import path: " dir_path
    [[ -z "$dir_path" ]] && { warn "Import path cannot be empty."; }
    if [[ -n "$dir_path" ]]; then
      create_or_replace_directory "$TGT_EZCONNECT" "$dir_name" "$dir_path" "tgt"
      if validate_directory_on_db_try "$TGT_EZCONNECT" "tgt" "$dir_name"; then
        ok "TARGET import DIRECTORY ${dir_name} -> ${dir_path} is ready"
        IMPORT_DIR_NAME="$dir_name"; IMPORT_DIR_PATH="$dir_path"; return 0
      fi
      warn "[DEBUG] run_sql_try(tag_dircheck_tgt) failed to create/validate import DIRECTORY on target."
    fi
    read -rp "Retry import precheck? [Y=retry / B=back / X=exit]: " r
    case "${r^^}" in Y) continue ;; B) return 1 ;; X) exit 0 ;; *) return 1 ;; esac
  done
}

# ------------------- Export/Import dump location prompts ----------------------
prompt_export_dump_location() {
  if [[ -n "${EXPORT_DIR_NAME:-}" && -n "${EXPORT_DIR_PATH:-}" ]]; then
    echo "Export using SOURCE DIRECTORY ${EXPORT_DIR_NAME} -> ${EXPORT_DIR_PATH}" | say_to_user
    read -rp "Use these? [Y to accept / N to change / X to exit]: " ans
    case "${ans^^}" in Y) return 0 ;; N) ;; X) exit 0 ;; esac
  fi
  precheck_export_directory
}

prompt_import_dump_location() {
  if [[ -n "${IMPORT_DIR_NAME:-}" && -n "${IMPORT_DIR_PATH:-}" ]]; then
    echo "Import using TARGET DIRECTORY ${IMPORT_DIR_NAME} -> ${IMPORT_DIR_PATH}" | say_to_user
    read -rp "Use these? [Y to accept / N to change / X to exit]: " ans
    case "${ans^^}" in Y) : ;; N) precheck_import_directory || { warn "Setup cancelled."; return 1; } ;; X) exit 0 ;; esac
  else
    precheck_import_directory || { warn "Setup cancelled."; return 1; }
  fi
  echo "Enter dumpfile pattern or list (impdp format; e.g., dumpfile%U.dmp or f1.dmp,f2.dmp)" | say_to_user
  echo "(Tip: just the filename pattern, not a path — DIRECTORY controls the path)" | say_to_user
  read -rp "Dumpfile(s): " IMPORT_DUMPFILE_PATTERN
  [[ -z "$IMPORT_DUMPFILE_PATTERN" ]] && { warn "Dumpfile pattern cannot be empty."; return 1; }
  return 0
}

# ------------------------------ EXPORT MENUS ----------------------------------
get_nonmaintained_schemas() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql_capture "$SRC_EZCONNECT" "
WITH base AS ( SELECT username FROM dba_users WHERE oracle_maintained='N'${pred} )
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base
"
}

get_nonmaintained_schemas_tgt() {
  local pred=""
  if [[ -n "$SKIP_SCHEMAS" ]]; then
    IFS=',' read -r -a arr <<< "$SKIP_SCHEMAS"
    for s in "${arr[@]}"; do s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue; pred+=" AND UPPER(username) NOT LIKE '${s^^}'"; done
  fi
  run_sql_capture "$TGT_EZCONNECT" "
WITH base AS ( SELECT username FROM dba_users WHERE oracle_maintained='N'${pred} )
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base
"
}

confirm_and_run_expdp() {
  local tag="$1" dir_name="$2"
  local pf; pf=$(par_common expdp "$tag" "$dir_name")
  if show_and_confirm_parfile "$pf" "expdp"; then dp_run expdp "$SRC_EZCONNECT" "$pf" "$tag"; else warn "Export cancelled."; fi
}

exp_full_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Export FULL (choose content):
  1) metadata_only  (CONTENT=METADATA_ONLY)
  2) full           (CONTENT=ALL)
  3) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) prompt_export_dump_location || { warn "Setup cancelled."; continue; }
         pf=$(par_common expdp "exp_full_meta" "$EXPORT_DIR_NAME")
         { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"
         show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_meta"
         ;;
      2) prompt_export_dump_location || { warn "Setup cancelled."; continue; }
         pf=$(par_common expdp "exp_full_all" "$EXPORT_DIR_NAME")
         { echo "full=Y"; echo "content=ALL"; } >> "$pf"
         show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_all"
         ;;
      3) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_schemas_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Export SCHEMAS:
  1) All accounts (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) User input or value from conf (SCHEMAS_LIST_EXP) with confirmation
  3) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1)
        prompt_export_dump_location || { warn "Setup cancelled."; continue; }
        schemas="$(get_nonmaintained_schemas)"
        schemas="$(confirm_edit_value "Schemas (comma-separated)" "$schemas")"
        content_choice="$(choose_content_option)"
        echo "[INFO] Final Schemas: ${schemas}" | say_to_user
        echo "[INFO] Final CONTENT: ${content_choice}" | say_to_user
        pf=$(par_common expdp "exp_schemas_auto" "$EXPORT_DIR_NAME")
        { echo "schemas=${schemas}"; echo "content=${content_choice}"; } >> "$pf"
        show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_auto"
        ;;
      2)
        prompt_export_dump_location || { warn "Setup cancelled."; continue; }
        init="${SCHEMAS_LIST_EXP:-}"
        [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init
        schemas="$(confirm_edit_value "Schemas (comma-separated)" "$init")"
        content_choice="$(choose_content_option)"
        echo "[INFO] Final Schemas: ${schemas}" | say_to_user
        echo "[INFO] Final CONTENT: ${content_choice}" | say_to_user
        pf=$(par_common expdp "exp_schemas_user" "$EXPORT_DIR_NAME")
        { echo "schemas=${schemas}"; echo "content=${content_choice}"; } >> "$pf"
        show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_user"
        ;;
      3) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_tablespaces() {
  prompt_export_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Tablespaces (comma-separated): " tbs
  pf=$(par_common expdp "exp_tbs" "$EXPORT_DIR_NAME")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tbs"
}

exp_tables() {
  prompt_export_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  pf=$(par_common expdp "exp_tables" "$EXPORT_DIR_NAME")
  echo "tables=${tabs}" >> "$pf"
  show_and_confirm_parfile "$pf" "expdp" && dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tables"
}

export_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Export Menu:
  1) FULL database (metadata_only / full)
  2) SCHEMAS      (all non-maintained / user|conf) with content selector
  3) TABLESPACES  (transport)
  4) TABLES
  5) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) exp_full_menu ;;
      2) exp_schemas_menu ;;
      3) exp_tablespaces ;;
      4) exp_tables ;;
      5) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

# ------------------------------ IMPORT HELPERS --------------------------------
par_common_imp_with_dump() {
  local tag="$1"
  local pf_dir; pf_dir="$(parfile_dir_for_mode impdp)"
  mkdir -p "$pf_dir" || true
  local pf="${pf_dir}/${tag}_${RUN_ID}.par"
  debug "Creating impdp parfile: ${pf}"
  local server_log="$(basename_safe "${DUMPFILE_PREFIX}_${tag}_${RUN_ID}.log")"
  local cleaned_pattern; cleaned_pattern="$(reject_if_pathlike "${IMPORT_DUMPFILE_PATTERN}")"
  {
    echo "directory=${IMPORT_DIR_NAME}"
    echo "dumpfile=${cleaned_pattern}"
    echo "logfile=${server_log}"
    echo "logtime=all"
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

imp_full_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Import FULL (choose content):
  1) metadata_only  (CONTENT=METADATA_ONLY)
  2) full           (CONTENT=ALL)
  3) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) prompt_import_dump_location || { warn "Setup cancelled."; continue; }
         pf=$(par_common_imp_with_dump "imp_full_meta"); { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"
         show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_meta"
         ;;
      2) prompt_import_dump_location || { warn "Setup cancelled."; continue; }
         pf=$(par_common_imp_with_dump "imp_full_all");  { echo "full=Y"; echo "content=ALL"; } >> "$pf"
         show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_all"
         ;;
      3) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_schemas_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Import SCHEMAS:
  1) All accounts (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) User input or value from conf (SCHEMAS_LIST_IMP / SCHEMAS_LIST_EXP) with confirmation
  3) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        schemas="$(get_nonmaintained_schemas_tgt)"
        schemas="$(confirm_edit_value "Schemas to import (comma-separated)" "$schemas")"
        echo "[INFO] Final Schemas to import: ${schemas}" | say_to_user
        pf=$(par_common_imp_with_dump "imp_schemas_auto"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_auto"
        ;;
      2)
        prompt_import_dump_location || { warn "Setup cancelled."; continue; }
        init="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"
        [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init
        schemas="$(confirm_edit_value "Schemas to import (comma-separated)" "$init")"
        echo "[INFO] Final Schemas to import: ${schemas}" | say_to_user
        pf=$(par_common_imp_with_dump "imp_schemas_user"); { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_user"
        ;;
      3) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_tablespaces() {
  prompt_import_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Transported tablespaces (comma-separated): " tbs
  pf=$(par_common_imp_with_dump "imp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tbs"
}

imp_tables() {
  prompt_import_dump_location || { warn "Setup cancelled."; return; }
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  pf=$(par_common_imp_with_dump "imp_tables")
  echo "tables=${tabs}" >> "$pf"
  show_and_confirm_parfile "$pf" "impdp" && dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tables"
}

import_cleanup_menu() {
  while true; do
    cat <<EOS | say_to_user
Import Cleanup (TARGET) - DANGEROUS  $( [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && echo "[DRY_RUN_ONLY=Y]" )
  1) Drop ALL users CASCADE (exclude Oracle-maintained; honors SKIP_SCHEMAS)
  2) Drop ALL objects of ALL users (exclude Oracle-maintained; honors SKIP_SCHEMAS) [users kept]
  3) Drop users CASCADE listed in imp schemas (SCHEMAS_LIST_IMP/SCHEMAS_LIST_EXP)
  4) Drop ALL objects of users listed in imp schemas [users kept]
  5) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) drop_users_cascade_all_nonmaint ;;
      2) drop_objects_all_nonmaint ;;
      3) drop_users_cascade_listed ;;
      4) drop_objects_listed ;;
      5) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

# ------------------------------ DDL Extraction (subset) -----------------------
ddl_spool() {
  local out="$1"; shift
  local body="$*"
  local conn="sys/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"
  debug "DDL spool -> ${out}"
  sqlplus -s "$conn" <<SQL >"$out" 2>"${out}.log"
SET LONG 1000000 LONGCHUNKSIZE 1000000 LINES 32767 PAGES 0 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
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
  for tok in "${arr[@]}"; do tok="$(echo "$tok" | awk '{$1=$1;print}')"; [[ -z "$tok" ]] && continue; tok="${tok^^}"; out+="${out:+,}'${tok}'"; done
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
    cat <<'EOS' | say_to_user
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

# ----------------------- COMPARE (LOCAL/Jumper) -------------------------------
ensure_local_dir() { mkdir -p "$1" || { echo "Cannot create $1"; exit 1; }; }
normalize_sorted() { local in="$1" out="$2"; if [[ -f "$in" ]]; then tr -d '\r' < "$in" | awk 'NF' | sort -u > "$out"; else : > "$out"; fi; }

emit_set_delta_html() {
  local title="$1" left_csv="$2" right_csv="$3" html="$4"
  local L R; L="$(mktemp)"; R="$(mktemp)"
  normalize_sorted "$left_csv"  "$L"; normalize_sorted "$right_csv" "$R"
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
  local L R; L="$(mktemp)"; R="$(mktemp)"
  normalize_sorted "$left_csv"  "$L"; normalize_sorted "$right_csv" "$R"
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

snapshot_objects_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_objects_local(${who}, ${schema}) -> ${out}"
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

snapshot_rowcounts_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_rowcounts_local(${who}, ${schema}) -> ${out} (exact=${EXACT_ROWCOUNT})"
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

snapshot_sys_privs_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_sys_privs_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_sysprivs_${schema}" "$out" "
SET COLSEP '|'
SELECT privilege||'|'||admin_option
FROM dba_sys_privs
WHERE grantee=UPPER('${schema}')
ORDER BY privilege;
"
}

snapshot_role_privs_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_role_privs_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_roleprivs_${schema}" "$out" "
SET COLSEP '|'
SELECT granted_role||'|'||admin_option||'|'||default_role
FROM dba_role_privs
WHERE grantee=UPPER('${schema}')
ORDER BY granted_role;
"
}

snapshot_tabprivs_on_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_tabprivs_on_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_tabprivs_on_${schema}" "$out" "
SET COLSEP '|'
SELECT owner||'|'||table_name||'|'||grantee||'|'||privilege||'|'||grantable||'|'||grantor
FROM dba_tab_privs
WHERE owner=UPPER('${schema}') AND grantee <> 'PUBLIC'
ORDER BY owner, table_name, grantee, privilege;
"
}

snapshot_tabprivs_to_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_tabprivs_to_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_tabprivs_to_${schema}" "$out" "
SET COLSEP '|'
SELECT owner||'|'||table_name||'|'||grantee||'|'||privilege||'|'||grantable||'|'||grantor
FROM dba_tab_privs
WHERE grantee=UPPER('${schema}')
ORDER BY owner, table_name, privilege;
"
}

snapshot_invalid_objects_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_invalid_objects_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_invalid_${schema}" "$out" "
SET COLSEP '|'
SELECT object_type||'|'||object_name
FROM dba_objects
WHERE owner=UPPER('${schema}') AND status<>'VALID' AND object_name NOT LIKE 'BIN$%'
ORDER BY object_type, object_name;
"
}

snapshot_unusable_indexes_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_unusable_indexes_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_unusable_idx_${schema}" "$out" "
SET COLSEP '|'
SELECT index_name||'|'||table_name
FROM dba_indexes
WHERE owner=UPPER('${schema}') AND status='UNUSABLE'
ORDER BY index_name;
"
}

snapshot_disabled_constraints_local() { local ez="$1" who="$2" schema="${3^^}" out="${4}"
  debug "snapshot_disabled_constraints_local(${who}, ${schema}) -> ${out}"
  run_sql_spool_local "$ez" "snap_${who}_disabled_cons_${schema}" "$out" "
SET COLSEP '|'
SELECT constraint_type||'|'||constraint_name||'|'||table_name
FROM dba_constraints
WHERE owner=UPPER('${schema}') AND status='DISABLED'
ORDER BY constraint_type, constraint_name;
"
}

cap_db_version()       { local ez="$1"; run_sql_capture "$ez" "SELECT banner FROM v\\$version WHERE banner LIKE 'Oracle Database%'"; }
cap_db_patchlevel()    { local ez="$1"; run_sql_capture "$ez" "SELECT NVL(MAX(version||' '||REGEXP_REPLACE(description,' Patch','')), 'N/A') FROM dba_registry_sqlpatch WHERE action='APPLY' AND status='SUCCESS'"; }
cap_db_charsets()      { local ez="$1"; run_sql_capture "$ez" "SELECT LISTAGG(parameter||'='||value, ', ') WITHIN GROUP (ORDER BY parameter) FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET')"; }
cap_total_objects()    { local ez="$1" schema="${2^^}"; run_sql_capture "$ez" "SELECT COUNT(*) FROM dba_objects WHERE owner=UPPER('${schema}') AND temporary='N' AND object_name NOT LIKE 'BIN$%'"; }
cap_invalid_objects()  { local ez="$1" schema="${2^^}"; run_sql_capture "$ez" "SELECT COUNT(*) FROM dba_objects WHERE owner=UPPER('${schema}') AND status<>'VALID'"; }

compare_one_schema_local() { local schema="${1^^}"
  debug "compare_one_schema_local: START schema=${schema}"
  ensure_local_dir "$LOCAL_COMPARE_DIR"
  local S="${LOCAL_COMPARE_DIR}"

  debug "Header capture: versions/patch/charsets/totals/invalids"
  local src_ver tgt_ver src_patch tgt_patch src_cs tgt_cs
  src_ver="$(cap_db_version "$SRC_EZCONNECT" || true)"; tgt_ver="$(cap_db_version "$TGT_EZCONNECT" || true)"
  src_patch="$(cap_db_patchlevel "$SRC_EZCONNECT" || true)"; tgt_patch="$(cap_db_patchlevel "$TGT_EZCONNECT" || true)"
  src_cs="$(cap_db_charsets "$SRC_EZCONNECT" || true)"; tgt_cs="$(cap_db_charsets "$TGT_EZCONNECT" || true)"
  local src_tot tgt_tot src_inv tgt_inv
  src_tot="$(cap_total_objects "$SRC_EZCONNECT" "$schema" || true)"; tgt_tot="$(cap_total_objects "$TGT_EZCONNECT" "$schema" || true)"
  src_inv="$(cap_invalid_objects "$SRC_EZCONNECT" "$schema" || true)"; tgt_inv="$(cap_invalid_objects "$TGT_EZCONNECT" "$schema" || true)"
  [[ -z "$src_tot" ]] && src_tot="0"; [[ -z "$tgt_tot" ]] && tgt_tot="0"
  [[ -z "$src_inv" ]] && src_inv="0"; [[ -z "$tgt_inv" ]] && tgt_inv="0"
  local tot_match inv_match
  tot_match=$([[ "$src_tot" == "$tgt_tot" ]] && echo "Match" || echo "NO MATCH")
  inv_match=$([[ "$src_inv" == "$tgt_inv" ]] && echo "Match" || echo "NO MATCH")
  debug "Header data: src_ver='${src_ver}', tgt_ver='${tgt_ver}', src_patch='${src_patch}', tgt_patch='${tgt_patch}', src_cs='${src_cs}', tgt_cs='${tgt_cs}', totals=${src_tot}/${tgt_tot}, invalids=${src_inv}/${tgt_inv}"

  debug "Snapshot: objects/rowcounts/privs (src & tgt)"
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

  debug "Snapshot: expert checks (invalid objects / unusable idx / disabled constraints)"
  snapshot_invalid_objects_local      "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_invalid_${RUN_ID}.csv"
  snapshot_invalid_objects_local      "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_invalid_${RUN_ID}.csv"
  snapshot_unusable_indexes_local     "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_unusable_idx_${RUN_ID}.csv"
  snapshot_unusable_indexes_local     "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_unusable_idx_${RUN_ID}.csv"
  snapshot_disabled_constraints_local "$SRC_EZCONNECT" "src" "$schema" "${S}/${schema}_src_disabled_cons_${RUN_ID}.csv"
  snapshot_disabled_constraints_local "$TGT_EZCONNECT" "tgt" "$schema" "${S}/${schema}_tgt_disabled_cons_${RUN_ID}.csv"

  local html="${COMPARE_DIR}/compare_local_${schema}_${RUN_ID}.html"
  ensure_local_dir "$COMPARE_DIR"
  debug "Writing HTML summary to ${html}"
  {
    echo "<html><head><meta charset='utf-8'><title>Schema Compare (LOCAL) ${schema}</title>"
    echo "<style>body{font-family:Arial,Helvetica,sans-serif} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px} pre{white-space:pre-wrap}</style>"
    echo "</head><body>"
    echo "<h2>Schema Compare (LOCAL/Jumper): ${schema}</h2>"
    echo "<p>Run: ${RUN_ID}<br/>Source: ${SRC_EZCONNECT}<br/>Target: ${TGT_EZCONNECT}<br/>Local: ${LOCAL_COMPARE_DIR}</p>"

    echo "<h3>Summary</h3>"
    echo "<table>"
    echo "<tr><th></th><th>Source</th><th>Target</th><th>Match</th></tr>"
    echo "<tr><td><b>DB Version</b></td><td>$(echo "$src_ver" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$(echo "$tgt_ver" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$( [[ "$src_ver" == "$tgt_ver" ]] && echo 'Match' || echo 'NO MATCH' )</td></tr>"
    echo "<tr><td><b>Patch Level</b></td><td>$(echo "$src_patch" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$(echo "$tgt_patch" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$( [[ "$src_patch" == "$tgt_patch" ]] && echo 'Match' || echo 'NO MATCH' )</td></tr>"
    echo "<tr><td><b>Character Sets</b></td><td>$(echo "$src_cs" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$(echo "$tgt_cs" | sed 's/&/\&amp;/g;s/</\&lt;/g')</td><td>$( [[ "$src_cs" == "$tgt_cs" ]] && echo 'Match' || echo 'NO MATCH' )</td></tr>"
    echo "<tr><td><b>Total Objects (${schema})</b></td><td>${src_tot}</td><td>${tgt_tot}</td><td>${tot_match}</td></tr>"
    echo "<tr><td><b>Invalid Objects (${schema})</b></td><td>${src_inv}</td><td>${tgt_inv}</td><td>${inv_match}</td></tr>"
    echo "</table>"
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

  emit_set_delta_html "Invalid Objects (type|name)" \
    "${S}/${schema}_src_invalid_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_invalid_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Disabled Constraints (type|name|table)" \
    "${S}/${schema}_src_disabled_cons_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_disabled_cons_${RUN_ID}.csv" \
    "$html"

  emit_set_delta_html "Unusable Indexes (index|table)" \
    "${S}/${schema}_src_unusable_idx_${RUN_ID}.csv" \
    "${S}/${schema}_tgt_unusable_idx_${RUN_ID}.csv" \
    "$html"

  echo "</body></html>" >> "$html"
  ok "HTML (LOCAL/Jumper): ${html}"
  email_inline_html "$html" "${MAIL_SUBJECT_PREFIX} Schema Compare LOCAL - ${schema} - ${RUN_ID}"
  debug "compare_one_schema_local: END schema=${schema}"
}

compare_many_local() {
  local list_input="${1:-}"
  debug "compare_many_local START (input='${list_input}')"
  local schemas_list=""
  if [[ -n "$list_input" ]]; then schemas_list="$list_input"
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
    s="$(echo "$s" | awk '{$1=$1;print}')"; [[ -z "$s" ]] && continue
    i=$((i+1)); debug "compare_many_local item ${i}: ${s}"
    compare_one_schema_local "$s"
    local f="compare_local_${s^^}_${RUN_ID}.html"
    echo "<tr><td>${i}</td><td>${s^^}</td><td><a href='${f}'>${f}</a></td></tr>" >> "$index"
  done
  echo "</table></body></html>" >> "$index"
  ok "Index HTML (LOCAL): ${index}"
  email_inline_html "$index" "${MAIL_SUBJECT_PREFIX} Compare LOCAL Index - ${RUN_ID}"
  debug "compare_many_local END"
}

# ------------------------------ Menus -----------------------------------------
export_import_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Data Pump:
  1) Export -> sub menu
  2) Import -> sub menu
  3) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) export_menu ;;
      2) import_menu ;;
      3) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

import_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Import Menu:
  1) FULL (metadata_only / full)
  2) SCHEMAS (auto/user list)
  3) TABLESPACES (transport)
  4) TABLES
  5) Cleanup helpers (drop users/objects)  [DANGEROUS]
  6) Back
  X) Exit
EOS
    read -rp "Choose: " c
    case "$c" in
      1) imp_full_menu ;;
      2) imp_schemas_menu ;;
      3) imp_tablespaces ;;
      4) imp_tables ;;
      5) import_cleanup_menu ;;
      6) break ;;
      X|x) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

compare_schema_menu() {
  while true; do
    cat <<'EOS' | say_to_user
Compare Objects (Source vs Target)
  Engine:
    A) EXTERNAL tables on TARGET (needs DIRECTORY/NAS)
    B) FILE mode (CSV + shell diff; needs DIRECTORY/NAS)
    C) LOCAL/JUMPER (CSV spooled locally; NO NAS, NO ext tables)
  Actions:
    1) One schema (HTML + email)
    2) Multiple schemas (ENTER = all non-maintained on source) [HTML + email]
    3) Back
    X) Exit
EOS
    read -rp "Choose engine [A/B/C] or action [1/2/3/X]: " eng
    eng="${eng^^}"
    case "$eng" in
      A)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back, X=exit]: " c
        case "${c^^}" in
          1) read -rp "Schema name: " s; compare_one_schema_sql_external "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_sql_external "${list:-}";;
          3) break ;;
          X) exit 0 ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      B)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back, X=exit]: " c
        case "${c^^}" in
          1) read -rp "Schema name: " s; compare_one_schema_file_mode "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_file_mode "${list:-}";;
          3) break ;;
          X) exit 0 ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      C)
        read -rp "Pick action [1=one schema, 2=multiple, 3=back, X=exit]: " c
        case "${c^^}" in
          1) read -rp "Schema name: " s; compare_one_schema_local "$s" ;;
          2) read -rp "Schema names (comma-separated) or ENTER for all: " list; compare_many_local "${list:-}";;
          3) break ;;
          X) exit 0 ;;
          *) warn "Invalid choice" ;;
        esac
        ;;
      1|2|3) warn "Pick engine first (A/B/C), then action." ;;
      X) exit 0 ;;
      *) warn "Unknown engine. Choose A, B, C or X." ;;
    esac
  done
}

show_jobs() {
  ce "Logs under $LOG_DIR"
  read -rp "Show DBA_DATAPUMP_JOBS on which DB? (src/tgt/b=back/x=exit): " side
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
    b) return ;;
    x) exit 0 ;;
    *) warn "Unknown choice";;
  esac
  for f in "$LOG_DIR"/*.log; do [[ -f "$f" ]] || continue; echo "---- $(basename "$f") (tail -n 20) ----"; tail -n 20 "$f"; done
}

cleanup_dirs() {
  read -rp "Drop DIRECTORY ${COMMON_DIR_NAME} on (src/tgt/both/b=back/x=exit)? " side
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

main_menu() {
  while true; do
    cat <<EOS | say_to_user

======== Oracle 19c Migration & DDL (${SCRIPT_NAME} v4as) ========
Source: ${SRC_EZCONNECT}
Target: ${TGT_EZCONNECT}
NAS:    ${NAS_PATH:-<not set>}
PARALLEL=${PARALLEL}  COMPRESSION=${COMPRESSION}  TABLE_EXISTS_ACTION=${TABLE_EXISTS_ACTION}
DDL out: ${DDL_DIR}
Compare out: ${COMPARE_DIR}
=============================================================

1) Toggle DEBUG on/off (current: ${DEBUG})
2) Precheck Export DIRECTORY (on SOURCE only)
3) Precheck Import DIRECTORY (on TARGET only)
4) Data Pump (EXP/IMP)         -> sub menu
5) Monitor/Status              -> DBA_DATAPUMP_JOBS + tail logs
6) Drop DIRECTORY objects      -> cleanup (non-fatal)
7) DDL Extraction (Source DB)  -> sub menu
8) Compare Objects             -> sub menu (EXTERNAL / FILE / LOCAL)
9) Back
X) Exit
EOS
    read -rp "Choose: " choice
    case "${choice^^}" in
      1) toggle_debug ;;
      2) precheck_export_directory  || true ;;
      3) precheck_import_directory  || true ;;
      4) export_import_menu ;;
      5) show_jobs ;;
      6) cleanup_dirs ;;
      7) ddl_menu_wrapper ;;
      8) compare_schema_menu ;;
      9) return ;;
      X) exit 0 ;;
      *) warn "Invalid choice.";;
    esac
  done
}

# Root loop
main_menu
