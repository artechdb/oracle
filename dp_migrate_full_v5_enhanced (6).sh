#!/usr/bin/env bash
# dp_migrate.sh (v5 Enhanced) - Oracle 19c Data Pump migration & compare toolkit
# v5 enhancements:
# ================
# SECURITY IMPROVEMENTS:
# - Enhanced password masking for all sensitive data including encryption passwords
# - Secure file permissions for logs and parfiles (600)
# - Password validation and strength checking
# - Secure cleanup of sensitive temporary files
# - Audit trail for all critical operations
#
# NEW FEATURES:
# - Pre-upgrade version compatibility validation
# - Character set validation between source and target
# - Tablespace space pre-checks
# - Enhanced Data Pump error handling with common error detection
# - Restore point creation for rollback capability
# - Invalid objects check before export
# - Post-import statistics gathering
# - Enhanced monitoring with progress tracking
# - Network bandwidth optimization support
# - Retry logic for failed operations
#
# Based on v4u with all original functionality preserved

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
AUDIT_DIR="${AUDIT_DIR:-${WORK_DIR}/audit}"

mkdir -p "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$DDL_DIR" "$COMPARE_DIR" "$AUDIT_DIR"

# Secure permissions for sensitive directories
chmod 700 "$WORK_DIR" "$LOG_DIR" "$PAR_DIR" "$AUDIT_DIR" 2>/dev/null || true

#------------------------ Pretty print & debug helpers -------------------------
ce()   { printf "%b\n" "$*"; }
ok()   { ce "\e[32m✔ $*\e[0m"; }
warn() { ce "\e[33m⚠ $*\e[0m"; }
err()  { ce "\e[31m✘ $*\e[0m"; }
info() { ce "\e[34mℹ $*\e[0m"; }

DEBUG="${DEBUG:-Y}"
debug() { if [[ "${DEBUG^^}" == "Y" ]]; then ce "\e[36m[DEBUG]\e[0m $*"; fi; }

#------------------------ Audit Trail -----------------------------------------
audit_log() {
    local action="$1"
    local details="${2:-}"
    local audit_file="${AUDIT_DIR}/audit_${RUN_ID}.log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${USER:-unknown}"
    local host="${HOSTNAME:-unknown}"
    
    echo "${timestamp}|${user}@${host}|${action}|${details}" >> "$audit_file"
    debug "AUDIT: ${action} - ${details}"
}

#------------------------ Load Config -----------------------------------------
[[ -f "$CONFIG_FILE" ]] || { err "Config file not found: $CONFIG_FILE"; exit 1; }

# Check config file permissions (should not be world-readable)
if [[ $(stat -c %a "$CONFIG_FILE" 2>/dev/null || stat -f %A "$CONFIG_FILE" 2>/dev/null) =~ [0-9][0-9][4-7] ]]; then
    warn "Config file $CONFIG_FILE is world-readable. Consider: chmod 600 $CONFIG_FILE"
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

audit_log "CONFIG_LOADED" "Config file: $CONFIG_FILE"

need_vars=( SRC_EZCONNECT TGT_EZCONNECT SYS_PASSWORD NAS_PATH DUMPFILE_PREFIX )
for v in "${need_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { err "Missing required config variable: $v"; exit 1; }
done

#------------------------ Defaults / Tunables ---------------------------------
PARALLEL="${PARALLEL:-4}"
COMPRESSION="${COMPRESSION:-ALL}"  # ALL, DATA_ONLY, METADATA_ONLY, NONE
COMPRESSION_ALGORITHM="${COMPRESSION_ALGORITHM:-MEDIUM}"  # LOW, MEDIUM, HIGH
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
NETWORK_LINK="${NETWORK_LINK:-}"  # For network-based import without dump files

SCHEMAS_LIST_EXP="${SCHEMAS_LIST_EXP:-}"
SCHEMAS_LIST_IMP="${SCHEMAS_LIST_IMP:-}"

SKIP_SCHEMAS="${SKIP_SCHEMAS:-}"
DDL_OBJECT_TYPES="${DDL_OBJECT_TYPES:-TABLE,INDEX,VIEW,SEQUENCE,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE_BODY,MATERIALIZED_VIEW,TYPE,SYNONYM}"
SKIP_TABLESPACES="${SKIP_TABLESPACES:-SYSTEM,SYSAUX,TEMP,UNDOTBS1,UNDOTBS2}"

DRY_RUN_ONLY="${DRY_RUN_ONLY:-N}"

REPORT_EMAILS="${REPORT_EMAILS:-}"
MAIL_ENABLED="${MAIL_ENABLED:-Y}"
MAIL_FROM="${MAIL_FROM:-noreply@localhost}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[Oracle Compare]}"

COMPARE_INCLUDE_TYPES="${COMPARE_INCLUDE_TYPES:-}"
COMPARE_EXCLUDE_TYPES="${COMPARE_EXCLUDE_TYPES:-}"
COMPARE_DEEP_INCLUDE_TYPES="${COMPARE_DEEP_INCLUDE_TYPES:-TABLE,INDEX,VIEW,SEQUENCE,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE BODY,MATERIALIZED VIEW,SYNONYM,TYPE}"
COMPARE_DEEP_EXCLUDE_TYPES="${COMPARE_DEEP_EXCLUDE_TYPES:-}"
EXACT_ROWCOUNT="${EXACT_ROWCOUNT:-N}"

# New tunables for v5
DP_TIMEOUT="${DP_TIMEOUT:-43200}"  # 12 hours timeout for Data Pump jobs
MIN_FREE_TABLESPACE_GB="${MIN_FREE_TABLESPACE_GB:-10}"  # Minimum free space required
CREATE_RESTORE_POINT="${CREATE_RESTORE_POINT:-N}"  # Create restore point before import
GATHER_STATS_AFTER_IMPORT="${GATHER_STATS_AFTER_IMPORT:-Y}"  # Gather stats after import
CHECK_INVALID_OBJECTS="${CHECK_INVALID_OBJECTS:-Y}"  # Check for invalid objects before export
VALIDATE_CHARSET="${VALIDATE_CHARSET:-Y}"  # Validate character set compatibility
MAX_RETRY_ATTEMPTS="${MAX_RETRY_ATTEMPTS:-3}"  # Number of retry attempts for failed operations
RETRY_DELAY="${RETRY_DELAY:-60}"  # Delay in seconds between retries

#------------------------ Pre-flight checks -----------------------------------
for b in sqlplus expdp impdp; do
  command -v "$b" >/dev/null 2>&1 || { err "Missing required binary: $b"; exit 1; }
done
[[ -d "$NAS_PATH" ]] || { err "NAS mount path not found on this host: $NAS_PATH"; exit 1; }

ok "Using config: $CONFIG_FILE"
ok "Work: $WORK_DIR | Logs: $LOG_DIR | Parfiles: $PAR_DIR | DDLs: $DDL_DIR | Compare: $COMPARE_DIR"
info "Audit trail: $AUDIT_DIR"

#------------------------ ENHANCED Security Utility helpers -------------------
# Enhanced password masking - masks all sensitive information
mask_pwd() {
    sed 's#[^/"]\{1,\}@#***@#g' \
    | sed 's#sys/[^@]*@#sys/****@#g' \
    | sed 's#ENCRYPTION_PASSWORD=[^ ]*#ENCRYPTION_PASSWORD=****#g' \
    | sed 's#encryption_password=[^ ]*#encryption_password=****#g' \
    | sed 's#PASSWORD=[^ ]*#PASSWORD=****#g' \
    | sed 's#password=[^ ]*#password=****#g' \
    | sed "s#${SYS_PASSWORD}#****#g" 2>/dev/null \
    | sed "s#${ENCRYPTION_PASSWORD}#****#g" 2>/dev/null
}

# Secure file creation with restricted permissions
secure_create_file() {
    local filepath="$1"
    touch "$filepath"
    chmod 600 "$filepath"
}

# Validate password strength (basic check)
validate_password_strength() {
    local pwd="$1"
    local min_length=8
    
    if [[ ${#pwd} -lt $min_length ]]; then
        warn "Password is shorter than recommended minimum of $min_length characters"
        return 1
    fi
    
    # Check for complexity (at least one letter and one number)
    if [[ ! "$pwd" =~ [A-Za-z] ]] || [[ ! "$pwd" =~ [0-9] ]]; then
        warn "Password should contain both letters and numbers for better security"
        return 1
    fi
    
    return 0
}

# Secure cleanup of sensitive files
secure_cleanup() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Overwrite with random data before deletion (basic secure delete)
        dd if=/dev/urandom of="$file" bs=1k count=$(stat -c%s "$file" 2>/dev/null | awk '{print int($1/1024)+1}' || echo 1) conv=notrunc 2>/dev/null || true
        rm -f "$file"
        debug "Securely deleted: $file"
    fi
}

# Validate password on startup
if [[ -n "${ENCRYPTION_PASSWORD}" ]]; then
    if ! validate_password_strength "$ENCRYPTION_PASSWORD"; then
        warn "Encryption password does not meet recommended complexity requirements"
        read -rp "Continue anyway? (y/n): " cont
        [[ "${cont,,}" != "y" ]] && { audit_log "ABORTED" "Weak encryption password"; exit 1; }
    fi
fi

#------------------------ Original Utility helpers (preserved) ----------------
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

#------------------------ Enhanced SQL execution with security ----------------
run_sql() {
  local ez="$1"; shift
  local tag="${1:-sql}"; shift || true
  local sql="$*"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  
  # Secure log file permissions
  secure_create_file "$logf"
  
  debug "run_sql(tag=$tag) on ${ez} -> $logf"
  audit_log "SQL_EXECUTE" "Tag: $tag, Target: $ez"
  
  sqlplus -s "$conn" <<SQL >"$logf" 2>&1
SET PAGES 0 FEEDBACK OFF LINES 32767 VERIFY OFF HEADING OFF ECHO OFF
${sql}
EXIT
SQL
  
  if grep -qi "ORA-" "$logf"; then
    err "SQL error: ${tag} (see $logf)"
    tail -n 120 "$logf" | mask_pwd | sed 's/^/  /'
    audit_log "SQL_ERROR" "Tag: $tag, Target: $ez"
    exit 1
  fi
  ok "SQL ok: ${tag}"
  audit_log "SQL_SUCCESS" "Tag: $tag, Target: $ez"
}

print_log() {
  local tag="$1"
  local logf="${LOG_DIR}/${tag}_${RUN_ID}.log"
  [[ -f "$logf" ]] && { echo "----- ${tag} -----"; cat "$logf" | mask_pwd; echo "----- end (${tag}) -----"; } || true
}

#------------------------ NEW: Version Compatibility Validation ---------------
validate_version_compatibility() {
    info "Validating database version compatibility..."
    
    local src_ver_file="${LOG_DIR}/src_version_${RUN_ID}.log"
    local tgt_ver_file="${LOG_DIR}/tgt_version_${RUN_ID}.log"
    
    run_sql "$SRC_EZCONNECT" "get_src_ver" "SELECT version FROM v\$instance;"
    run_sql "$TGT_EZCONNECT" "get_tgt_ver" "SELECT version FROM v\$instance;"
    
    local src_ver=$(awk 'NF{print $1; exit}' "$src_ver_file")
    local tgt_ver=$(awk 'NF{print $1; exit}' "$tgt_ver_file")
    
    info "Source database version: $src_ver"
    info "Target database version: $tgt_ver"
    
    # Extract major version numbers
    local tgt_major=$(echo "$tgt_ver" | cut -d'.' -f1)
    local src_major=$(echo "$src_ver" | cut -d'.' -f1)
    
    # Ensure target is 19c
    if [[ "$tgt_major" != "19" ]]; then
        err "Target database is not Oracle 19c (found: $tgt_ver)"
        audit_log "VERSION_CHECK_FAILED" "Target not 19c: $tgt_ver"
        exit 1
    fi
    
    # Ensure source is same or lower version (19c, 18c, 12c, 11g)
    if [[ "$src_major" -gt "$tgt_major" ]]; then
        err "Source database version ($src_ver) is higher than target ($tgt_ver)"
        err "Downgrade migrations are not supported"
        audit_log "VERSION_CHECK_FAILED" "Source newer than target"
        exit 1
    fi
    
    # Warn about specific version considerations
    if [[ "$src_major" == "11" ]]; then
        warn "Migrating from Oracle 11g to 19c"
        warn "This is a major version upgrade. Review desupported features."
        warn "See: https://docs.oracle.com/en/database/oracle/oracle-database/19/upgrd/"
    fi
    
    ok "Version compatibility check passed"
    audit_log "VERSION_CHECK_PASSED" "Source: $src_ver, Target: $tgt_ver"
}

#------------------------ NEW: Character Set Validation -----------------------
validate_charset() {
    info "Validating character set compatibility..."
    
    run_sql "$SRC_EZCONNECT" "src_charset" "
SELECT 'NLS_CHARACTERSET='||value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET'
UNION ALL
SELECT 'NLS_NCHAR_CHARACTERSET='||value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';
/"
    
    run_sql "$TGT_EZCONNECT" "tgt_charset" "
SELECT 'NLS_CHARACTERSET='||value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET'
UNION ALL
SELECT 'NLS_NCHAR_CHARACTERSET='||value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';
/"
    
    local src_cs=$(grep "NLS_CHARACTERSET=" "${LOG_DIR}/src_charset_${RUN_ID}.log" | cut -d'=' -f2)
    local tgt_cs=$(grep "NLS_CHARACTERSET=" "${LOG_DIR}/tgt_charset_${RUN_ID}.log" | cut -d'=' -f2)
    local src_ncs=$(grep "NLS_NCHAR_CHARACTERSET=" "${LOG_DIR}/src_charset_${RUN_ID}.log" | cut -d'=' -f2)
    local tgt_ncs=$(grep "NLS_NCHAR_CHARACTERSET=" "${LOG_DIR}/tgt_charset_${RUN_ID}.log" | cut -d'=' -f2)
    
    info "Source: NLS_CHARACTERSET=$src_cs, NLS_NCHAR_CHARACTERSET=$src_ncs"
    info "Target: NLS_CHARACTERSET=$tgt_cs, NLS_NCHAR_CHARACTERSET=$tgt_ncs"
    
    if [[ "$src_cs" != "$tgt_cs" ]]; then
        warn "Character set mismatch detected!"
        warn "  Source NLS_CHARACTERSET: $src_cs"
        warn "  Target NLS_CHARACTERSET: $tgt_cs"
        warn "This may cause data corruption or conversion issues."
        audit_log "CHARSET_MISMATCH" "Source: $src_cs, Target: $tgt_cs"
        
        read -rp "Do you want to continue anyway? (yes/no): " cont
        if [[ "${cont,,}" != "yes" ]]; then
            audit_log "ABORTED" "Character set mismatch - user declined to continue"
            exit 1
        fi
        audit_log "CHARSET_MISMATCH_ACCEPTED" "User chose to continue despite mismatch"
    fi
    
    if [[ "$src_ncs" != "$tgt_ncs" ]]; then
        warn "National character set mismatch: Source=$src_ncs, Target=$tgt_ncs"
    fi
    
    ok "Character set validation completed"
    audit_log "CHARSET_CHECK_COMPLETED" "Source: $src_cs/$src_ncs, Target: $tgt_cs/$tgt_ncs"
}

#------------------------ NEW: Tablespace Space Check -------------------------
check_tablespace_space() {
    local ez="$1"
    local side="$2"
    local min_free_gb="${MIN_FREE_TABLESPACE_GB}"
    
    info "Checking tablespace free space on $side (minimum required: ${min_free_gb}GB)..."
    
    run_sql "$ez" "tbs_check_${side}" "
SET LINES 200 PAGES 1000
COL tablespace_name FOR A30
COL free_gb FOR 999,999.99
COL used_gb FOR 999,999.99
COL total_gb FOR 999,999.99
COL pct_used FOR 999.99

SELECT 
    tablespace_name,
    ROUND(SUM(bytes)/1024/1024/1024,2) AS free_gb
FROM dba_free_space
GROUP BY tablespace_name
HAVING ROUND(SUM(bytes)/1024/1024/1024,2) < ${min_free_gb}
ORDER BY 2;
/"
    
    local low_space_tbs=$(awk 'NF && !/^-/ && !/tablespace_name/ && !/^$/ {print $1}' "${LOG_DIR}/tbs_check_${side}_${RUN_ID}.log")
    
    if [[ -n "$low_space_tbs" ]]; then
        warn "Tablespaces with less than ${min_free_gb}GB free space on $side:"
        echo "$low_space_tbs" | while read -r tbs; do
            warn "  - $tbs"
        done
        
        read -rp "Continue anyway? (yes/no): " cont
        if [[ "${cont,,}" != "yes" ]]; then
            audit_log "ABORTED" "Insufficient tablespace space on $side"
            exit 1
        fi
        audit_log "LOW_SPACE_ACCEPTED" "$side - user chose to continue"
    else
        ok "All tablespaces have sufficient free space on $side"
    fi
    
    audit_log "TABLESPACE_CHECK_COMPLETED" "$side"
}

#------------------------ NEW: Check Invalid Objects --------------------------
check_invalid_objects_before_export() {
    local ez="$1"
    local schema="${2:-}"
    
    info "Checking for invalid objects before export..."
    
    local where_clause=""
    if [[ -n "$schema" ]]; then
        where_clause="AND owner = UPPER('${schema}')"
    fi
    
    run_sql "$ez" "invalid_objects_check" "
SET LINES 200 PAGES 1000
COL owner FOR A30
COL object_name FOR A40
COL object_type FOR A20

SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE status = 'INVALID'
  AND temporary = 'N'
  AND object_name NOT LIKE 'BIN\$%'
  ${where_clause}
ORDER BY owner, object_type, object_name;
/"
    
    local invalid_count=$(awk 'NF && !/^-/ && !/OWNER/ && !/^$/ && $4=="INVALID" {count++} END {print count+0}' "${LOG_DIR}/invalid_objects_check_${RUN_ID}.log")
    
    if [[ $invalid_count -gt 0 ]]; then
        warn "Found $invalid_count invalid object(s) in source database"
        warn "Consider recompiling invalid objects before export:"
        info "  SQL> @?/rdbms/admin/utlrp.sql"
        
        read -rp "Continue with export anyway? (yes/no): " cont
        if [[ "${cont,,}" != "yes" ]]; then
            audit_log "ABORTED" "Invalid objects found - user declined to continue"
            exit 1
        fi
        audit_log "INVALID_OBJECTS_ACCEPTED" "Count: $invalid_count"
    else
        ok "No invalid objects found"
    fi
    
    audit_log "INVALID_OBJECTS_CHECK_COMPLETED" "Count: $invalid_count"
}

#------------------------ NEW: Create Restore Point ---------------------------
create_restore_point() {
    local ez="$1"
    local rp_name="BEFORE_IMP_${RUN_ID}"
    
    info "Creating restore point: $rp_name"
    
    # Check if flashback is enabled
    run_sql "$ez" "check_flashback" "SELECT flashback_on FROM v\$database;"
    
    local flashback_status=$(awk 'NF{print $1; exit}' "${LOG_DIR}/check_flashback_${RUN_ID}.log")
    
    if [[ "$flashback_status" != "YES" ]]; then
        warn "Flashback database is not enabled on target"
        warn "Cannot create guaranteed restore point"
        info "To enable: ALTER DATABASE FLASHBACK ON;"
        
        read -rp "Continue without restore point? (yes/no): " cont
        if [[ "${cont,,}" != "yes" ]]; then
            audit_log "ABORTED" "Flashback not enabled - user declined to continue"
            exit 1
        fi
        audit_log "RESTORE_POINT_SKIPPED" "Flashback not enabled"
        return 0
    fi
    
    # Create guaranteed restore point
    run_sql "$ez" "create_restore_point" "CREATE RESTORE POINT ${rp_name} GUARANTEE FLASHBACK DATABASE;"
    
    ok "Restore point created: $rp_name"
    info "To rollback: FLASHBACK DATABASE TO RESTORE POINT ${rp_name};"
    audit_log "RESTORE_POINT_CREATED" "$rp_name"
}

#------------------------ NEW: Gather Schema Statistics -----------------------
gather_schema_stats() {
    local schema="$1"
    
    info "Gathering statistics for schema: $schema"
    audit_log "STATS_GATHER_START" "Schema: $schema"
    
    run_sql "$TGT_EZCONNECT" "gather_stats_${schema}" "
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname => UPPER('${schema}'),
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO',
        degree => ${PARALLEL},
        cascade => TRUE,
        options => 'GATHER'
    );
END;
/"
    
    ok "Statistics gathered for schema: $schema"
    audit_log "STATS_GATHER_COMPLETED" "Schema: $schema"
}

#------------------------ ENHANCED Data Pump Runner with Timeout & Monitoring ---
dp_run() {
  local tool="$1" ez="$2" pf="$3" tag="$4"
  local client_log="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.client.log"
  local monitor_log="${LOG_DIR}/${tool}_${tag}_${RUN_ID}.monitor.log"
  local conn="sys/${SYS_PASSWORD}@${ez} as sysdba"
  
  # Secure log file permissions
  secure_create_file "$client_log"
  secure_create_file "$monitor_log"
  
  debug "dp_run(${tool}) tag=${tag} parfile=${pf} ez=${ez}"
  audit_log "DP_START" "Tool: $tool, Tag: $tag, Target: $ez"
  
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
      cat "$pf" | mask_pwd
    else
      echo "<parfile not found>"
    fi
    echo "---------------------------"
  } > "$client_log" 2>&1

  # Background monitoring process for common Data Pump errors
  (
    while sleep 30; do
      if [[ -f "$client_log" ]]; then
        # Check for common critical errors
        if grep -qi "ORA-39002\|ORA-39013\|ORA-31693\|ORA-00942\|ORA-01555\|ORA-04031" "$client_log"; then
          echo "[$(date)] WARNING: Critical Data Pump error detected in $client_log" >> "$monitor_log"
          
          # Check specific errors and provide guidance
          if grep -qi "ORA-39002" "$client_log"; then
            echo "[$(date)] ERROR: Invalid operation (ORA-39002) - Check job state" >> "$monitor_log"
          fi
          if grep -qi "ORA-39013" "$client_log"; then
            echo "[$(date)] ERROR: Invalid parameter (ORA-39013) - Check parfile" >> "$monitor_log"
          fi
          if grep -qi "ORA-31693" "$client_log"; then
            echo "[$(date)] ERROR: Table data object failed to load (ORA-31693)" >> "$monitor_log"
          fi
          if grep -qi "ORA-01555" "$client_log"; then
            echo "[$(date)] ERROR: Snapshot too old - Consider FLASHBACK_SCN parameter" >> "$monitor_log"
          fi
          if grep -qi "ORA-04031" "$client_log"; then
            echo "[$(date)] ERROR: Out of shared pool memory" >> "$monitor_log"
          fi
        fi
        
        # Monitor job progress if available
        if [[ "$tool" == "expdp" || "$tool" == "impdp" ]]; then
          # Extract job name if possible
          local job_name=$(grep -oP 'Job "\K[^"]+' "$client_log" | tail -1)
          if [[ -n "$job_name" ]]; then
            echo "[$(date)] Monitoring job: $job_name" >> "$monitor_log"
          fi
        fi
      fi
    done
  ) &
  local monitor_pid=$!

  # Run Data Pump with timeout
  set +e
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    ( set -o pipefail; timeout "$DP_TIMEOUT" $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} )
    rc=$?
    if [[ $rc -eq 124 ]]; then
      err "[${tool}] TIMEOUT after ${DP_TIMEOUT} seconds"
      audit_log "DP_TIMEOUT" "Tool: $tool, Tag: $tag"
      kill $monitor_pid 2>/dev/null || true
      exit 124
    fi
  else
    ( set -o pipefail; $tool "$conn" parfile="$pf" 2>&1 | tee -a "$client_log"; exit ${PIPESTATUS[0]} )
    rc=$?
  fi
  set -e
  
  # Stop monitoring
  kill $monitor_pid 2>/dev/null || true
  
  # Display monitoring log if it has content
  if [[ -s "$monitor_log" ]]; then
    warn "Monitoring log has warnings:"
    cat "$monitor_log" | sed 's/^/  /'
  fi
  
  if [[ $rc -ne 0 ]]; then
    err "[${tool}] FAILED (rc=$rc) — see ${client_log}"
    audit_log "DP_FAILED" "Tool: $tool, Tag: $tag, RC: $rc"
    
    # Show tail of log for quick diagnosis
    echo ""
    warn "Last 50 lines of log:"
    tail -n 50 "$client_log" | mask_pwd | sed 's/^/  /'
    
    exit $rc
  else
    ok "[${tool}] SUCCESS — see ${client_log}"
    audit_log "DP_SUCCESS" "Tool: $tool, Tag: $tag"
  fi
}

#------------------------ NEW: Retry Wrapper for Operations ------------------
retry_operation() {
    local operation_name="$1"
    shift
    local cmd=("$@")
    
    local attempt=1
    local max_attempts="$MAX_RETRY_ATTEMPTS"
    
    while [[ $attempt -le $max_attempts ]]; do
        info "Attempt $attempt of $max_attempts for: $operation_name"
        
        if "${cmd[@]}"; then
            ok "$operation_name succeeded on attempt $attempt"
            audit_log "RETRY_SUCCESS" "Operation: $operation_name, Attempt: $attempt"
            return 0
        else
            local rc=$?
            warn "$operation_name failed on attempt $attempt (rc=$rc)"
            audit_log "RETRY_FAILED" "Operation: $operation_name, Attempt: $attempt, RC: $rc"
            
            if [[ $attempt -lt $max_attempts ]]; then
                info "Waiting $RETRY_DELAY seconds before retry..."
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    err "$operation_name failed after $max_attempts attempts"
    audit_log "RETRY_EXHAUSTED" "Operation: $operation_name"
    return 1
}

#------------------------ NEW: Monitor Data Pump Job Progress -----------------
monitor_datapump_job() {
    local ez="$1"
    local job_name="$2"
    local interval="${3:-60}"
    
    info "Monitoring Data Pump job: $job_name (refresh every ${interval}s)"
    info "Press Ctrl+C to stop monitoring (job will continue)"
    
    while true; do
        run_sql "$ez" "monitor_job_${job_name}" "
SET LINES 200 PAGES 1000
COL job_name FOR A30
COL state FOR A12
COL operation FOR A10

SELECT 
    TO_CHAR(SYSDATE, 'HH24:MI:SS') AS current_time,
    job_name,
    state,
    operation,
    job_mode,
    degree,
    attached_sessions
FROM dba_datapump_jobs
WHERE job_name LIKE '%${job_name}%'
ORDER BY 1;

-- Get progress info
SELECT 
    TO_CHAR(SYSDATE, 'HH24:MI:SS') AS current_time,
    opname,
    ROUND(sofar/totalwork*100, 2) AS pct_complete,
    time_remaining,
    elapsed_seconds
FROM v\$session_longops
WHERE opname LIKE '%${job_name}%'
AND totalwork > 0
ORDER BY 1 DESC;
/"
        
        print_log "monitor_job_${job_name}"
        
        sleep "$interval"
    done
}

#------------------------ Email & HTML helpers ---------------------------------
mail_send_html() {
  local subj="$1" html="$2" recipients_csv="$3"
  debug "mail_send_html(subj=${subj}) -> recipients=${recipients_csv} file=${html}"
  [[ "${MAIL_ENABLED^^}" == "Y" && -n "$recipients_csv" && -s "$html" ]] || {
    warn "Mail disabled or no recipients / html file missing. Saved: $html"
    return 0
  }
  local to_csv="${recipients_csv// /}" to_space
  IFS=',' read -r -a _arr <<< "$to_csv"
  to_space="${_arr[*]}"
  if command -v /usr/sbin/sendmail >/dev/null 2>&1; then
    {
      printf "From: %s\n" "$MAIL_FROM"
      printf "To: %s\n" "$to_csv"
      printf "Subject: %s\n" "$subj"
      printf "MIME-Version: 1.0\n"
      printf "Content-Type: text/html; charset=UTF-8\n"
      printf "Content-Transfer-Encoding: 8bit\n\n"
      cat "$html"
    } | /usr/sbin/sendmail -t
    ok "Mailed HTML report to: $to_csv"
  elif command -v mailx >/dev/null 2>&1; then
    if mailx -V 2>/dev/null | grep -qi 'heirloom\|s-nail\|mailutils'; then
      mailx -a "Content-Type: text/html; charset=UTF-8" -r "$MAIL_FROM" -s "$subj" $to_space < "$html"
    else
      mailx -s "$subj" $to_space < "$html"
    fi
    ok "Mailed HTML report to: $to_csv (via mailx)"
  else
    warn "No sendmail/mailx found. Report saved at: $html"
  fi
}

html_begin() {
  cat <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>${1}</title>
<style>
body{font:14px/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:20px;color:#1d2433;background:#f9fafb}
.container{max-width:1200px;margin:0 auto;background:white;padding:30px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.1)}
h1{font-size:24px;color:#0f172a;border-bottom:3px solid #3b82f6;padding-bottom:10px;margin-bottom:20px}
h2{font-size:20px;color:#1e293b;background:#f1f5f9;padding:8px 12px;border-left:4px solid #3b82f6;margin-top:25px;margin-bottom:15px}
h3{font-size:16px;color:#334155;margin-top:20px;margin-bottom:10px}
.meta{background:#f8fafc;padding:15px;border-radius:6px;margin-bottom:20px;font-size:13px;color:#64748b}
.meta-row{display:flex;justify-content:space-between;margin-bottom:8px}
.meta-label{font-weight:600;color:#475569}
table{border-collapse:collapse;width:100%;margin:15px 0;font-size:13px;box-shadow:0 1px 2px rgba(0,0,0,0.05)}
th{background:#f1f5f9;padding:10px 12px;text-align:left;font-weight:600;color:#0f172a;border-bottom:2px solid #cbd5e1}
td{border:1px solid #e2e8f0;padding:8px 12px;color:#334155}
tr:hover{background:#f8fafc}
code,pre{background:#f1f5f9;padding:4px 8px;border-radius:4px;font-family:monospace;font-size:12px}
pre{padding:12px;overflow-x:auto;border:1px solid #e2e8f0}
.badge{display:inline-block;padding:3px 8px;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase}
.badge-success{background:#d1fae5;color:#065f46}
.badge-warning{background:#fef3c7;color:#92400e}
.badge-error{background:#fee2e2;color:#991b1b}
.badge-info{background:#dbeafe;color:#1e40af}
.summary-box{background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:15px;margin:15px 0}
.summary-row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #e2e8f0}
.summary-row:last-child{border-bottom:none}
.summary-label{font-weight:500;color:#475569}
.summary-value{font-weight:600;color:#0f172a;font-size:16px}
.stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0}
.stat-card{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}
.stat-card.success{background:linear-gradient(135deg,#10b981 0%,#059669 100%)}
.stat-card.warning{background:linear-gradient(135deg,#f59e0b 0%,#d97706 100%)}
.stat-card.error{background:linear-gradient(135deg,#ef4444 0%,#dc2626 100%)}
.stat-label{font-size:12px;opacity:0.9;margin-bottom:5px;text-transform:uppercase}
.stat-value{font-size:32px;font-weight:700}
.section{margin-top:30px;margin-bottom:30px}
.delta-item{padding:8px;margin:5px 0;border-left:3px solid #3b82f6;background:#f8fafc;font-family:monospace;font-size:12px}
.delta-item.missing{border-left-color:#ef4444;background:#fef2f2}
.delta-item.extra{border-left-color:#f59e0b;background:#fffbeb}
.delta-item.diff{border-left-color:#8b5cf6;background:#faf5ff}
.footer{margin-top:40px;padding-top:20px;border-top:1px solid #e2e8f0;text-align:center;font-size:12px;color:#94a3b8}
.ok{color:#16a34a;font-weight:600}
.warn{color:#f59e0b;font-weight:600}
.bad{color:#ef4444;font-weight:600}
.timestamp{color:#94a3b8;font-size:12px}
ul{list-style:none;padding-left:0}
li{padding:6px 0;border-bottom:1px solid #f1f5f9}
li:before{content:"▸";color:#3b82f6;font-weight:bold;margin-right:8px}
</style></head><body>
<div class="container">
EOF
}
html_end(){ echo "</div></body></html>"; }

#------------------------ DDL prolog (plain quoted transforms) -----------------
ddl_sql_prolog='
SET LONG 1000000 LONGCHUNKSIZE 1000000 LINES 32767 PAGES 0 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''STORAGE'',           FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''SEGMENT_ATTRIBUTES'', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''CONSTRAINTS'',        TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''REF_CONSTRAINTS'',    TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''OID'',                FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''SQLTERMINATOR'',      TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''PRETTY'',             TRUE);
END;
/
'

#------------------------ DDL spooler (unquoted here-doc) ----------------------
ddl_spool() {
  local out="$1"; shift
  local body="$*"
  local conn="sys/${SYS_PASSWORD}@${SRC_EZCONNECT} as sysdba"

  warn "[DEBUG] Starting DDL extract → $(basename "$out")"
  warn "[DEBUG] SQL file: $out"
  warn "[DEBUG] Executing against: $SRC_EZCONNECT"

  sqlplus -s "$conn" <<SQL >"$out" 2>"${out}.log"
${ddl_sql_prolog}
${body}
EXIT
SQL

  if grep -qi "ORA-" "${out}.log"; then
    err "DDL extract error in $(basename "$out")"
    tail -n 50 "${out}.log" | mask_pwd | sed 's/^/  /'
    return 1
  fi

  if [[ ! -s "$out" ]]; then
    warn "[DEBUG] No content generated for $(basename "$out")"
  else
    local count
    count=$(wc -l < "$out")
    ok "[DEBUG] DDL file created: $out ($count lines)"
  fi
}

#------------------------ DDL extractors --------------------------------------
ddl_users() { debug "DDL -> USERS"; local f="${DDL_DIR}/01_users_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('USER', username)
FROM dba_users
WHERE oracle_maintained = 'N'
ORDER BY username;
"; }

ddl_profiles() { debug "DDL -> PROFILES"; local f="${DDL_DIR}/02_profiles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('PROFILE', profile)
FROM (SELECT DISTINCT profile FROM dba_profiles ORDER BY 1);
"; }

ddl_roles() { debug "DDL -> ROLES"; local f="${DDL_DIR}/03_roles_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('ROLE', role)
FROM dba_roles
WHERE NVL(oracle_maintained, 'N') = 'N'
ORDER BY role;
"; }

# --- rewrite: system & role grants (per screenshot) ---
ddl_privs_to_roles() {
  local f="${DDL_DIR}/04_sys_and_role_grants_${RUN_ID}.sql"
  ddl_spool "$f" "
/* System & role grants (exclusions per screenshot) */

-- System privileges granted to users/roles
WITH ignore_exists AS (
  SELECT COUNT(*) AS cnt
  FROM all_objects
  WHERE owner = 'OVD_GLOBAL_USER'
    AND object_name = 'IGNORE_USERS'
    AND object_type IN ('TABLE','VIEW')
),
ignore_list AS (
  SELECT username FROM ovd_global_user.ignore_users
  WHERE (SELECT cnt FROM ignore_exists) > 0
)
SELECT
  'GRANT ' || privilege ||
  ' TO '   || grantee ||
  CASE WHEN admin_option = 'YES' THEN ' WITH ADMIN OPTION' ELSE '' END ||
  ';' AS ddl_line
FROM dba_sys_privs
WHERE (SELECT cnt FROM ignore_exists) = 0
      OR grantee NOT IN (SELECT username FROM ignore_list)
AND   grantee NOT IN (
        'GGADMIN','SCHEDULER_ADMIN',
        'DATAPUMP_IMP_FULL_DATABASE','DATAPUMP_EXP_FULL_DATABASE',
        'CONNECT','RESOURCE','DBA'
      )

UNION ALL

-- Role grants (role -> grantee)
SELECT
  'GRANT ' || granted_role ||
  ' TO '   || grantee ||
  CASE WHEN admin_option = 'YES' THEN ' WITH ADMIN OPTION' ELSE '' END ||
  ';' AS ddl_line
FROM dba_role_privs
WHERE ( (SELECT cnt FROM ignore_exists) = 0
        OR grantee     NOT IN (SELECT username FROM ignore_list) )
  AND grantee NOT IN (
        'SCHEDULER_ADMIN',
        'DATAPUMP_IMP_FULL_DATABASE','DATAPUMP_EXP_FULL_DATABASE',
        'CONNECT','RESOURCE','DBA'
      )
  AND ( (SELECT cnt FROM ignore_exists) = 0
        OR granted_role NOT IN (SELECT username FROM ignore_list) )
ORDER BY 1;
"
}


# --- rewrite: object grants to users (per screenshot) ---
ddl_sysprivs_to_users() {
  local f="${DDL_DIR}/05_user_obj_privs_${RUN_ID}.sql"
  ddl_spool "$f" "
/* Object privilege grants to users (excludes PUBLIC, Oracle-maintained, common users, and directories) */
WITH src AS (
  SELECT
    grantee,
    owner,
    table_name,
    privilege,
    grantable,
    grantor
  FROM dba_tab_privs
  WHERE grantee <> 'PUBLIC'
    -- limit owners like the screenshot; adjust if you want wider coverage
    AND owner IN ('SYSTEM','SYS')
    -- exclude any custom ignore list/view if present; if view not present, condition is skipped
    AND (
          NOT EXISTS (
            SELECT 1 FROM all_objects
            WHERE owner = 'OVD_GLOBAL_USER'
              AND object_name = 'IGNORE_USERS'
              AND object_type IN ('TABLE','VIEW')
          )
          OR grantee NOT IN (SELECT username FROM ovd_global_user.ignore_users)
        )
    -- exclude Oracle-maintained roles and users
    AND grantee NOT IN (SELECT role     FROM dba_roles WHERE oracle_maintained = 'Y')
    AND grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained = 'Y')
    -- exclude common users (C##...)
    AND grantee NOT LIKE 'C##%'
    -- exclude specific roles
    AND grantee NOT IN ('HS_ADMIN_SELECT_ROLE')
    -- exclude directory object grants (handled separately)
    AND table_name NOT IN (SELECT directory_name FROM dba_directories)
    -- optional exclusions (as in screenshot)
    AND grantor NOT IN ('QUEST','SPOTLIGHT','SPOTLIGHT1')
    AND grantee NOT LIKE 'QUEST%'
)
SELECT
  'GRANT ' || privilege ||
  ' ON '   || owner || '.' || '\"' || table_name || '\"' ||
  ' TO '   || grantee ||
  DECODE(grantable, 'YES', ' WITH GRANT OPTION', '') ||
  ' /* grantor ' || grantor || ' */;'
FROM src
ORDER BY grantee, owner, table_name, privilege;
"
}


ddl_sequences_all_users() { debug "DDL -> SEQUENCES"; local f="${DDL_DIR}/06_sequences_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', sequence_name, owner)
FROM dba_sequences
WHERE owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, sequence_name;
"; }

ddl_public_synonyms() { debug "DDL -> PUBLIC SYNONYMS"; local f="${DDL_DIR}/07_public_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, 'PUBLIC')
FROM dba_synonyms
WHERE owner = 'PUBLIC'
ORDER BY synonym_name;
"; }

ddl_private_synonyms_all_users() { debug "DDL -> PRIVATE SYNONYMS"; local f="${DDL_DIR}/08_private_synonyms_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('SYNONYM', synonym_name, owner)
FROM dba_synonyms
WHERE owner <> 'PUBLIC'
  AND owner IN (SELECT username FROM dba_users WHERE oracle_maintained='N')
ORDER BY owner, synonym_name;
"; }

ddl_all_ddls_all_users() {
  debug "DDL -> ALL OBJECT DDLs (heavy)"
  local f="${DDL_DIR}/09_all_ddls_${RUN_ID}.sql"
  local types_clause; types_clause="$(to_inlist_upper "$DDL_OBJECT_TYPES")"
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
  debug "DDL -> TABLESPACES"
  local f="${DDL_DIR}/10_tablespaces_${RUN_ID}.sql"
  local skip_clause; skip_clause="$(to_inlist_upper "$SKIP_TABLESPACES")"
  ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('TABLESPACE', tablespace_name)
FROM dba_tablespaces
WHERE UPPER(tablespace_name) NOT IN (${skip_clause})
ORDER BY tablespace_name;
"; }

ddl_role_grants_to_users() { debug "DDL -> ROLE GRANTS -> USERS"; local f="${DDL_DIR}/11_role_grants_to_users_${RUN_ID}.sql"; ddl_spool "$f" "
WITH u AS (SELECT username FROM dba_users WHERE oracle_maintained='N'),
r AS (
  SELECT grantee AS username, LISTAGG(role, ',') WITHIN GROUP (ORDER BY role) AS roles
  FROM dba_role_privs
  WHERE default_role = 'YES' AND grantee IN (SELECT username FROM u)
  GROUP BY grantee
)
SELECT 'ALTER USER '||username||' DEFAULT ROLE '||
       CASE WHEN roles IS NULL THEN 'ALL' ELSE roles END || ';'
FROM u LEFT JOIN r USING (username)
ORDER BY username;
"; }

ddl_directories() { debug "DDL -> DIRECTORY OBJECTS"; local f="${DDL_DIR}/13_directories_${RUN_ID}.sql"; ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DIRECTORY', directory_name)
FROM (SELECT DISTINCT directory_name FROM dba_directories ORDER BY 1);
"; }

ddl_db_links_by_owner() {
  read -rp "Enter owner for DB links (schema name): " owner
  debug "DDL -> DB LINKS for owner ${owner}"
  local f="${DDL_DIR}/14_db_links_${owner^^}_${RUN_ID}.sql"
  ddl_spool "$f" "
SELECT DBMS_METADATA.GET_DDL('DB_LINK', db_link, owner)
FROM dba_db_links
WHERE owner = UPPER('${owner}')
ORDER BY db_link;
"
  warn "Note: DB link passwords may be masked/omitted depending on version/security."
}

ddl_menu() {
  while true; do
    cat <<'EOS'
DDL Extraction (Source DB):
  1) USERS (exclude Oracle-maintained)
  2) PROFILES
  3) ROLES (exclude Oracle-maintained)
  4) PRIVILEGES -> ROLES
  5) SYSTEM/OBJECT PRIVILEGES -> USERS (exclude Oracle-maintained)
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
      B) debug "DDL menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

#------------------------ EXPDP / IMPDP (menus/actions) ------------------------
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
      1)
        debug "Export FULL -> metadata_only"
        ensure_directory_object "$SRC_EZCONNECT" "src"
        validate_directory_on_db "$SRC_EZCONNECT" "src"
        local pf; pf=$(par_common expdp "exp_full_meta")
        { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"
        debug "Running EXPDP (meta-only) with $pf"
        dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_meta"
        ;;
      2)
        debug "Export FULL -> full content"
        ensure_directory_object "$SRC_EZCONNECT" "src"
        validate_directory_on_db "$SRC_EZCONNECT" "src"
        local pf; pf=$(par_common expdp "exp_full_all")
        { echo "full=Y"; echo "content=ALL"; } >> "$pf"
        debug "Running EXPDP (full) with $pf"
        dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_full_all"
        ;;
      3) debug "Export FULL -> Back"; break ;;
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
      1)
        debug "Export SCHEMAS -> auto non-maintained"
        ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
        local schemas; schemas="$(get_nonmaintained_schemas)"
        schemas="$(confirm_edit_value "Schemas" "$schemas")"
        local pf; pf=$(par_common expdp "exp_schemas_auto")
        { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        debug "Running EXPDP (schemas auto) with $pf"
        dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_auto"
        ;;
      2)
        debug "Export SCHEMAS -> user/conf list"
        ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
        local init="${SCHEMAS_LIST_EXP:-}"; [[ -z "$init" ]] && read -rp "Enter schemas (comma-separated): " init
        local schemas; schemas="$(confirm_edit_value "Schemas" "$init")"
        local pf; pf=$(par_common expdp "exp_schemas_user")
        { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        debug "Running EXPDP (schemas user) with $pf"
        dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_schemas_user"
        ;;
      3) debug "Export SCHEMAS -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

exp_tablespaces() {
  debug "Export TABLESPACES -> transport"
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tablespaces (comma-separated): " tbs
  local pf; pf=$(par_common expdp "exp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  debug "Running EXPDP (transport tablespaces) with $pf"
  dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tbs"
}

exp_tables() {
  debug "Export TABLES"
  ensure_directory_object "$SRC_EZCONNECT" "src"; validate_directory_on_db "$SRC_EZCONNECT" "src"
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  local pf; pf=$(par_common expdp "exp_tables")
  echo "tables=${tabs}" >> "$pf"
  debug "Running EXPDP (tables) with $pf"
  dp_run expdp "$SRC_EZCONNECT" "$pf" "exp_tables"
}

#------------------------ IMPDP: Menus & actions -------------------------------
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
        debug "Import FULL -> metadata_only"
        ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
        local pf; pf=$(par_common impdp "imp_full_meta")
        { echo "full=Y"; echo "content=METADATA_ONLY"; } >> "$pf"
        debug "Running IMPDP (meta-only) with $pf"
        dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_meta"
        ;;
      2)
        debug "Import FULL -> full"
        ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
        local pf; pf=$(par_common impdp "imp_full_all")
        { echo "full=Y"; echo "content=ALL"; } >> "$pf"
        debug "Running IMPDP (full) with $pf"
        dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_full_all"
        ;;
      3) debug "Import FULL -> Back"; break ;;
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
        debug "Import SCHEMAS -> auto non-maintained"
        
        # Pre-import validations
        if [[ "${CREATE_RESTORE_POINT^^}" == "Y" ]]; then
          info "CREATE_RESTORE_POINT is enabled"
          read -rp "Create restore point before import? (yes/no): " create_rp
          if [[ "${create_rp,,}" == "yes" ]]; then
            create_restore_point "$TGT_EZCONNECT"
          fi
        fi
        
        ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
        local schemas; schemas="$(get_nonmaintained_schemas)"
        schemas="$(confirm_edit_value "Schemas" "$schemas")"
        local pf; pf=$(par_common impdp "imp_schemas_auto")
        { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        debug "Running IMPDP (schemas auto) with $pf"
        
        # Run import with retry logic for resilience
        if ! dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_auto"; then
          warn "Import failed. Check logs at: $LOG_DIR"
          read -rp "Retry import? (yes/no): " retry
          if [[ "${retry,,}" == "yes" ]]; then
            retry_operation "IMPDP schemas auto" dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_auto"
          fi
        fi
        
        # Post-import statistics gathering
        if [[ "${GATHER_STATS_AFTER_IMPORT^^}" == "Y" ]]; then
          info "Gathering statistics after import (GATHER_STATS_AFTER_IMPORT=Y)..."
          IFS=',' read -r -a schema_arr <<< "$schemas"
          for schema in "${schema_arr[@]}"; do
            schema="$(echo "$schema" | awk '{$1=$1;print}')"
            [[ -z "$schema" ]] && continue
            gather_schema_stats "$schema"
          done
          ok "Statistics gathering completed for all imported schemas"
        fi
        ;;
      2)
        debug "Import SCHEMAS -> user/conf list"
        
        # Pre-import validations
        if [[ "${CREATE_RESTORE_POINT^^}" == "Y" ]]; then
          info "CREATE_RESTORE_POINT is enabled"
          read -rp "Create restore point before import? (yes/no): " create_rp
          if [[ "${create_rp,,}" == "yes" ]]; then
            create_restore_point "$TGT_EZCONNECT"
          fi
        fi
        
        ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
        local base="${SCHEMAS_LIST_IMP:-${SCHEMAS_LIST_EXP:-}}"
        [[ -z "$base" ]] && read -rp "Enter schemas (comma-separated): " base
        local schemas; schemas="$(confirm_edit_value "Schemas" "$base")"
        local pf; pf=$(par_common impdp "imp_schemas_user")
        { echo "schemas=${schemas}"; echo "content=ALL"; } >> "$pf"
        debug "Running IMPDP (schemas user) with $pf"
        
        # Run import with retry logic
        if ! dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_user"; then
          warn "Import failed. Check logs at: $LOG_DIR"
          read -rp "Retry import? (yes/no): " retry
          if [[ "${retry,,}" == "yes" ]]; then
            retry_operation "IMPDP schemas user" dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_schemas_user"
          fi
        fi
        
        # Post-import statistics gathering
        if [[ "${GATHER_STATS_AFTER_IMPORT^^}" == "Y" ]]; then
          info "Gathering statistics after import (GATHER_STATS_AFTER_IMPORT=Y)..."
          IFS=',' read -r -a schema_arr <<< "$schemas"
          for schema in "${schema_arr[@]}"; do
            schema="$(echo "$schema" | awk '{$1=$1;print}')"
            [[ -z "$schema" ]] && continue
            gather_schema_stats "$schema"
          done
          ok "Statistics gathering completed for all imported schemas"
        fi
        ;;
      3) debug "Import SCHEMAS -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

imp_tablespaces() {
  debug "Import TABLESPACES -> transport"
  ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
  read -rp "Transported tablespaces (comma-separated): " tbs
  local pf; pf=$(par_common impdp "imp_tbs")
  echo "transport_tablespaces=${tbs}" >> "$pf"
  debug "Running IMPDP (transport tablespaces) with $pf"
  dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tbs"
}

imp_tables() {
  debug "Import TABLES"
  ensure_directory_object "$TGT_EZCONNECT" "tgt"; validate_directory_on_db "$TGT_EZCONNECT" "tgt"
  read -rp "Tables (SCHEMA.TAB,SCHEMA2.TAB2,...): " tabs
  local pf; pf=$(par_common impdp "imp_tables")
  echo "tables=${tabs}" >> "$pf"
  debug "Running IMPDP (tables) with $pf"
  dp_run impdp "$TGT_EZCONNECT" "$pf" "imp_tables"
}

#------------------------ IMPORT CLEANUP (Drop/Reset) --------------------------
schemas_skip_predicate() {
  local out="" item trimmed
  IFS=',' read -r -a arr <<< "${SKIP_SCHEMAS}"
  for item in "${arr[@]}"; do
    trimmed="$(echo "$item" | awk '{$1=$1;print}')"
    [[ -z "$trimmed" ]] && continue
    trimmed="${trimmed^^}"
    out+="  AND UPPER(username) NOT LIKE '${trimmed}'"
  done
  printf "%s" "$out"
}

get_nonmaintained_schemas() {
  local tmp_pred; tmp_pred="$(schemas_skip_predicate)"
  debug "get_nonmaintained_schemas() predicate: ${tmp_pred}"
  run_sql "$SRC_EZCONNECT" "list_nonmaint_users" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS (
  SELECT username
  FROM dba_users
  WHERE oracle_maintained='N'${tmp_pred}
)
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/list_nonmaint_users_${RUN_ID}.log"
}

get_nonmaintained_schemas_tgt() {
  local tmp_pred; tmp_pred="$(schemas_skip_predicate)"
  debug "get_nonmaintained_schemas_tgt() predicate: ${tmp_pred}"
  run_sql "$TGT_EZCONNECT" "tgt_nonmaint_users" "
SET PAGES 0 FEEDBACK OFF HEADING OFF
WITH base AS (
  SELECT username
  FROM dba_users
  WHERE oracle_maintained='N'${tmp_pred}
)
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) FROM base;
/
"
  awk 'NF{line=$0} END{print line}' "${LOG_DIR}/tgt_nonmaint_users_${RUN_ID}.log"
}

confirm_edit_value() {
  local label="$1" val="${2:-}" ans
  debug "confirm_edit_value(${label}) initial=${val}"
  echo "${label}: ${val}"
  read -rp "Use this value? (Y to accept, N to edit) [Y/N]: " ans
  if [[ "${ans^^}" == "N" ]]; then
    read -rp "Enter new ${label}: " val
  fi
  echo "$val"
}

report_user_list() {
  local tag="$1" inlist="${2:-}" q
  debug "report_user_list(tag=${tag}) inlist=${inlist}"
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
  debug "report_object_counts(tag=${tag}) inlist=${inlist}"
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
  debug "Cleanup -> drop_users_cascade_all_nonmaint()"
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
  debug "Cleanup -> drop_objects_all_nonmaint()"
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
  debug "Cleanup -> drop_users_cascade_listed()"
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
  debug "Cleanup -> drop_objects_listed()"
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
    FOR r IN (SELECT index_name object name FROM dba_indexes WHERE owner=p_owner AND table_owner=p_owner) LOOP exec_ddl('DROP INDEX '||p_owner||'.\"'||r.object_name||'\"'); END LOOP;
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
      1) debug "Cleanup menu -> Drop ALL users CASCADE"; drop_users_cascade_all_nonmaint ;;
      2) debug "Cleanup menu -> Drop ALL objects of ALL users"; drop_objects_all_nonmaint ;;
      3) debug "Cleanup menu -> Drop users CASCADE listed"; drop_users_cascade_listed ;;
      4) debug "Cleanup menu -> Drop ALL objects of listed users"; drop_objects_listed ;;
      5) debug "Cleanup menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

#------------------------ Compare (file-based DDL + rowcounts) -----------------
sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/_/g'
}

compare_type_predicate() {
  local inc="$COMPARE_INCLUDE_TYPES" exc="$COMPARE_EXCLUDE_TYPES" out=""
  if [[ -n "$inc" ]]; then
    local list; list="$(to_inlist_upper "$inc")"
    out+=" AND object_type IN (${list})"
  fi
  if [[ -n "$exc" ]]; then
    local list; list="$(to_inlist_upper "$exc")"
    out+=" AND object_type NOT IN (${list})"
  fi
  printf "%s" "$out"
}

compare_deep_type_predicate() {
  local inc="$COMPARE_DEEP_INCLUDE_TYPES" exc="$COMPARE_DEEP_EXCLUDE_TYPES" out=""
  if [[ -n "$inc" ]]; then
    local list; list="$(to_inlist_upper "$inc")"
    out+=" AND object_type IN (${list})"
  fi
  if [[ -n "$exc" ]]; then
    local list; list="$(to_inlist_upper "$exc")"
    out+=" AND object_type NOT IN (${list})"
  fi
  printf "%s" "$out"
}

snapshot_schema_objects() {
  local ez="$1" schema="${2^^}" side="$3"
  local types_pred; types_pred="$(compare_type_predicate)"
  local tag="cmp_snap_${side}_${schema}_${RUN_ID}"
  local out="${COMPARE_DIR}/${schema}_${side}.lst"
  debug "snapshot_schema_objects(${schema}) side=${side} -> ${out}"

  run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT object_type||'|'||object_name||'|'||status
FROM dba_objects
WHERE owner = UPPER('${schema}')
  AND temporary = 'N'
  AND object_name NOT LIKE 'BIN$%'
${types_pred}
ORDER BY object_type, object_name;
/
"
  awk 'NF{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
  ok "Snapshot ${schema}@${side} -> $(basename "$out") ($(wc -l < "$out") rows)"
}

dump_schema_ddls_to_file() {
  local ez="$1" schema="${2^^}" side="$3"
  local tag="cmp_pack_${side}_${schema}_${RUN_ID}"
  local out="${COMPARE_DIR}/${schema}_${side}.ddlpack"
  local types_pred; types_pred="$(compare_deep_type_predicate)"
  debug "dump_schema_ddls_to_file(${schema}) side=${side} -> ${out}"

  run_sql "$ez" "$tag" "
SET LONG 1000000 LONGCHUNKSIZE 1000000 LINES 32767 PAGES 0 TRIMSPOOL ON TRIMOUT ON FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE',           FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS',        TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS',    TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'OID',                FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR',      TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY',             TRUE);
END;
/
WITH objs AS (
  SELECT owner, object_type, object_name
  FROM dba_objects
  WHERE owner=UPPER('${schema}')
    AND temporary='N'
    AND object_name NOT LIKE 'BIN$%'
${types_pred}
)
SELECT '##OBJ '||owner||'|'||object_type||'|'||object_name||CHR(10)||
       DBMS_METADATA.GET_DDL(object_type, object_name, owner)||CHR(10)||
       '##END'
FROM objs
ORDER BY owner, object_type, object_name;
/
"
  cp "${LOG_DIR}/${tag}_${RUN_ID}.log" "$out"
  ok "DDL pack created: $out ($(wc -l < "$out") lines)"
}

unpack_ddlpack_to_tree() {
  local pack="$1" side="$2" schema="${3^^}"
  local base="${COMPARE_DIR}/tree_${side}/$(sanitize_name "$schema")"
  debug "unpack_ddlpack_to_tree(pack=$(basename "$pack")) -> ${base}"
  rm -rf "$base"
  mkdir -p "$base"

  awk -v BASE="$base" '
    BEGIN{file=""}
    /^##OBJ / {
      hdr=substr($0,8);
      split(hdr,a,"[|]"); owner=a[1]; type=a[2]; name=a[3];
      stype=tolower(type); gsub(/[^a-z0-9._-]/,"_",stype);
      sname=tolower(name); gsub(/[^a-z0-9._-]/,"_",sname);
      dir=BASE "/" stype;
      system("mkdir -p \"" dir "\"");
      file=dir "/" sname ".sql";
      next
    }
    /^##END$/ { file=""; next }
    { if(file!=""){ print $0 >> file } }
  ' "$pack"
  ok "Unpacked into: $base (files: $(find "$base" -type f | wc -l))"
}

snapshot_table_counts() {
  local ez="$1" schema="${2^^}" side="$3"
  local tag="cmp_tbl_${side}_${schema}_${RUN_ID}"
  local out="${COMPARE_DIR}/${schema}_${side}.tblcnt"
  debug "snapshot_table_counts(${schema}) side=${side} mode=$([[ "${EXACT_ROWCOUNT^^}" == "Y" ]] && echo EXACT || echo STATS) -> ${out}"

  if [[ "${EXACT_ROWCOUNT^^}" == "Y" ]]; then
    run_sql "$ez" "$tag" "
SET SERVEROUTPUT ON PAGES 0 FEEDBACK OFF HEADING OFF
DECLARE
  v_sql VARCHAR2(4000);
  v_cnt NUMBER;
BEGIN
  FOR t IN (SELECT table_name
              FROM dba_tables
             WHERE owner=UPPER('${schema}')
               AND temporary='N'
             ORDER BY table_name)
  LOOP
    BEGIN
      v_sql := 'SELECT COUNT(*) FROM '||DBMS_ASSERT.ENQUOTE_NAME('${schema}',FALSE)
               ||'.'||DBMS_ASSERT.ENQUOTE_NAME(t.table_name,FALSE);
      EXECUTE IMMEDIATE v_sql INTO v_cnt;
      DBMS_OUTPUT.PUT_LINE(t.table_name||'|'||v_cnt||'|EXACT');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(t.table_name||'|ERROR:'||REPLACE(SQLERRM,'|','/')||'|EXACT');
    END;
  END LOOP;
END;
/
"
    awk 'NF{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
  else
    run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT table_name||'|'||NVL(num_rows,-1)||'|STATS '||
       NVL(TO_CHAR(last_analyzed,'YYYY-MM-DD HH24:MI:SS'),'')
FROM dba_tables
WHERE owner=UPPER('${schema}')
  AND temporary='N'
ORDER BY table_name;
/
"
    awk 'NF{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
  fi
  ok "Rowcount snapshot ${schema}@${side} -> $(basename "$out") ($(wc -l < "$out") rows)"
}

generate_html_diff_pre() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

#------------------------ ENHANCED: Deep Compare with Row Counts (No DBLink) ---

deep_compare_schema_enhanced() {
    local schema="${1^^}"
    [[ -z "$schema" ]] && { warn "Schema is empty"; return 1; }
    
    info "Starting DEEP enhanced comparison for schema: ${schema}"
    info "This includes: Objects + Row Counts + Index Metadata + Constraints"
    audit_log "DEEP_COMPARE_START" "Schema: $schema"
    
    local report="${COMPARE_DIR}/${schema}_deep_enhanced_${RUN_ID}.txt"
    
    # Step 1: Object comparison
    info "[1/5] Comparing objects..."
    local src_objects=$(snapshot_schema_objects_enhanced "$SRC_EZCONNECT" "$schema" "src")
    local tgt_objects=$(snapshot_schema_objects_enhanced "$TGT_EZCONNECT" "$schema" "tgt")
    
    # Step 2: Table row counts
    info "[2/5] Comparing table row counts..."
    local src_rowcounts=$(get_table_rowcounts "$SRC_EZCONNECT" "$schema" "src" "$EXACT_ROWCOUNT")
    local tgt_rowcounts=$(get_table_rowcounts "$TGT_EZCONNECT" "$schema" "tgt" "$EXACT_ROWCOUNT")
    
    # Step 3: Index metadata
    info "[3/5] Comparing index metadata..."
    local src_indexes=$(get_index_metadata "$SRC_EZCONNECT" "$schema" "src")
    local tgt_indexes=$(get_index_metadata "$TGT_EZCONNECT" "$schema" "tgt")
    
    # Step 4: Constraint metadata
    info "[4/5] Comparing constraint metadata..."
    local src_constraints=$(get_constraint_metadata "$SRC_EZCONNECT" "$schema" "src")
    local tgt_constraints=$(get_constraint_metadata "$TGT_EZCONNECT" "$schema" "tgt")
    
    # Step 5: Generate comprehensive report
    info "[5/5] Generating comprehensive report..."
    
    {
        echo "================================================================================"
        echo "DEEP ENHANCED COMPARISON REPORT"
        echo "================================================================================"
        echo "Schema:       ${schema}"
        echo "Source DB:    ${SRC_EZCONNECT}"
        echo "Target DB:    ${TGT_EZCONNECT}"
        echo "Generated:    $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report ID:    ${RUN_ID}"
        echo "Row Count:    $([ "${EXACT_ROWCOUNT^^}" == "Y" ] && echo "EXACT (COUNT(*))" || echo "FROM STATISTICS")"
        echo "================================================================================"
        echo ""
        
        # Objects comparison
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║ SECTION 1: OBJECT COMPARISON                                              ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        local obj_delta="${COMPARE_DIR}/${schema}_obj_delta"
        local obj_counts=$(compare_delta_files "$src_objects" "$tgt_objects" "src" "tgt" "1,2" "$obj_delta")
        IFS='|' read -r obj_only_src obj_only_tgt obj_diff <<< "$obj_counts"
        
        printf "  Objects only in SOURCE : %6d\n" "${obj_only_src:-0}"
        printf "  Objects only in TARGET : %6d\n" "${obj_only_tgt:-0}"
        printf "  Objects with diffs     : %6d\n" "${obj_diff:-0}"
        echo ""
        
        # Row counts comparison
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║ SECTION 2: TABLE ROW COUNTS                                               ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Compare row counts
        local rc_src_sorted="${COMPARE_DIR}/${schema}_rc_src.sorted"
        local rc_tgt_sorted="${COMPARE_DIR}/${schema}_rc_tgt.sorted"
        sort -t'|' -k2,2 "$src_rowcounts" > "$rc_src_sorted" 2>/dev/null || touch "$rc_src_sorted"
        sort -t'|' -k2,2 "$tgt_rowcounts" > "$rc_tgt_sorted" 2>/dev/null || touch "$rc_tgt_sorted"
        
        # Join on table name and compare counts
        join -t'|' -1 2 -2 2 "$rc_src_sorted" "$rc_tgt_sorted" 2>/dev/null | \
        awk -F'|' '
        BEGIN {
            perfect=0; differ=0; 
            print "  TABLE_NAME                                          SOURCE       TARGET      DELTA"
            print "  --------------------------------------------------  -----------  -----------  -----------"
        }
        {
            table=$1; src_cnt=$3; tgt_cnt=$5;
            delta=tgt_cnt-src_cnt;
            if(delta==0) {
                perfect++;
            } else {
                differ++;
                if(differ<=30) {
                    printf "  %-50s  %11s  %11s  %+11d\n", table, src_cnt, tgt_cnt, delta
                }
            }
        }
        END {
            print ""
            printf "  Tables with matching row counts : %6d\n", perfect
            printf "  Tables with different row counts: %6d\n", differ
            if(differ>30) printf "  (showing first 30, see detail files for complete list)\n"
        }
        ' || echo "  No common tables found for comparison"
        echo ""
        
        # Index comparison
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║ SECTION 3: INDEX METADATA                                                 ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        local idx_delta="${COMPARE_DIR}/${schema}_idx_delta"
        local idx_counts=$(compare_delta_files "$src_indexes" "$tgt_indexes" "src" "tgt" "1,2" "$idx_delta")
        IFS='|' read -r idx_only_src idx_only_tgt idx_diff <<< "$idx_counts"
        
        printf "  Indexes only in SOURCE : %6d\n" "${idx_only_src:-0}"
        printf "  Indexes only in TARGET : %6d\n" "${idx_only_tgt:-0}"
        printf "  Indexes with diffs     : %6d\n" "${idx_diff:-0}"
        echo ""
        
        # Constraint comparison
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║ SECTION 4: CONSTRAINT METADATA                                            ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        local cons_delta="${COMPARE_DIR}/${schema}_cons_delta"
        local cons_counts=$(compare_delta_files "$src_constraints" "$tgt_constraints" "src" "tgt" "1,2" "$cons_delta")
        IFS='|' read -r cons_only_src cons_only_tgt cons_diff <<< "$cons_counts"
        
        printf "  Constraints only in SOURCE : %6d\n" "${cons_only_src:-0}"
        printf "  Constraints only in TARGET : %6d\n" "${cons_only_tgt:-0}"
        printf "  Constraints with diffs     : %6d\n" "${cons_diff:-0}"
        echo ""
        
        # Final summary
        echo "================================================================================"
        echo "DEEP COMPARISON SUMMARY"
        echo "================================================================================"
        
        local total_issues=$((obj_only_src + obj_only_tgt + obj_diff + idx_only_src + idx_only_tgt + idx_diff + cons_only_src + cons_only_tgt + cons_diff))
        
        # Check row count differences
        local rc_diffs=0
        if [[ -f "$rc_src_sorted" ]] && [[ -f "$rc_tgt_sorted" ]]; then
            rc_diffs=$(join -t'|' -1 2 -2 2 "$rc_src_sorted" "$rc_tgt_sorted" 2>/dev/null | \
                       awk -F'|' '$3!=$5{count++} END{print count+0}')
            total_issues=$((total_issues + rc_diffs))
        fi
        
        if [[ $total_issues -eq 0 ]]; then
            echo "✓ PERFECT MATCH: Schemas are completely identical"
            echo "  - All objects match"
            echo "  - All row counts match"
            echo "  - All indexes match"
            echo "  - All constraints match"
        else
            echo "⚠ DIFFERENCES FOUND: $total_issues total difference(s)"
            echo ""
            echo "Object Differences:"
            [[ ${obj_only_src:-0} -gt 0 ]] && echo "  ⚠ ${obj_only_src} objects missing in target"
            [[ ${obj_only_tgt:-0} -gt 0 ]] && echo "  ⚠ ${obj_only_tgt} extra objects in target"
            [[ ${obj_diff:-0} -gt 0 ]] && echo "  ⚠ ${obj_diff} objects with metadata differences"
            echo ""
            echo "Data Differences:"
            [[ ${rc_diffs:-0} -gt 0 ]] && echo "  ⚠ ${rc_diffs} tables with different row counts"
            echo ""
            echo "Index Differences:"
            [[ ${idx_only_src:-0} -gt 0 ]] && echo "  ⚠ ${idx_only_src} indexes missing in target"
            [[ ${idx_only_tgt:-0} -gt 0 ]] && echo "  ⚠ ${idx_only_tgt} extra indexes in target"
            [[ ${idx_diff:-0} -gt 0 ]] && echo "  ⚠ ${idx_diff} indexes with metadata differences"
            echo ""
            echo "Constraint Differences:"
            [[ ${cons_only_src:-0} -gt 0 ]] && echo "  ⚠ ${cons_only_src} constraints missing in target"
            [[ ${cons_only_tgt:-0} -gt 0 ]] && echo "  ⚠ ${cons_only_tgt} extra constraints in target"
            [[ ${cons_diff:-0} -gt 0 ]] && echo "  ⚠ ${cons_diff} constraints with metadata differences"
        fi
        echo ""
        echo "Detail Files:"
        echo "  Main report: $report"
        echo "  Objects:"
        echo "    - Only in source: ${obj_delta}_only_src.lst"
        echo "    - Only in target: ${obj_delta}_only_tgt.lst"
        echo "    - Different:      ${obj_delta}_different.lst"
        echo "  Row Counts:"
        echo "    - Source: $src_rowcounts"
        echo "    - Target: $tgt_rowcounts"
        echo "  Indexes:"
        echo "    - Only in source: ${idx_delta}_only_src.lst"
        echo "    - Only in target: ${idx_delta}_only_tgt.lst"
        echo "  Constraints:"
        echo "    - Only in source: ${cons_delta}_only_src.lst"
        echo "    - Only in target: ${cons_delta}_only_tgt.lst"
        echo "================================================================================"
        
    } | tee "$report"
    
    ok "Deep enhanced comparison complete: $report"
    audit_log "DEEP_COMPARE_COMPLETE" "Schema: $schema, Total differences: $total_issues"
    
    # Generate HTML report
    generate_deep_comparison_html_report "$schema" "$report" "$total_issues" \
        "$obj_only_src" "$obj_only_tgt" "$obj_diff" "$rc_diffs" \
        "$idx_only_src" "$idx_only_tgt" "$idx_diff" \
        "$cons_only_src" "$cons_only_tgt" "$cons_diff"
    
    # Send email if configured
    send_comparison_email "$schema" "deep"
}

#------------------------ ORIGINAL: Deep Compare (Kept for Compatibility) ------

deep_compare_schema() {
  local schema="${1^^}"
  [[ -z "$schema" ]] && { warn "Schema is empty"; return 1; }
  debug "deep_compare_schema(${schema}) using file-based DDL diffs"

  dump_schema_ddls_to_file "$SRC_EZCONNECT" "$schema" "src"
  dump_schema_ddls_to_file "$TGT_EZCONNECT" "$schema" "tgt"
  unpack_ddlpack_to_tree "${COMPARE_DIR}/${schema}_src.ddlpack" "src" "$schema"
  unpack_ddlpack_to_tree "${COMPARE_DIR}/${schema}_tgt.ddlpack" "tgt" "$schema"

  local tree_src="${COMPARE_DIR}/tree_src/$(sanitize_name "$schema")"
  local tree_tgt="${COMPARE_DIR}/tree_tgt/$(sanitize_name "$schema")"

  snapshot_table_counts "$SRC_EZCONNECT" "$schema" "src"
  snapshot_table_counts "$TGT_EZCONNECT" "$schema" "tgt"

  # Precompute invalids
  local inv_src="${COMPARE_DIR}/${schema}_invalid_src.lst"
  local inv_tgt="${COMPARE_DIR}/${schema}_invalid_tgt.lst"
  summary_invalid_by_type "$SRC_EZCONNECT" "$schema" "src" > "$inv_src"
  summary_invalid_by_type "$TGT_EZCONNECT" "$schema" "tgt" > "$inv_tgt"
  local inv_types="${COMPARE_DIR}/${schema}_invalid_types.lst"
  (cat "$inv_src" "$inv_tgt" 2>/dev/null || true) | awk -F'|' 'NF{print $1}' | sort -u > "$inv_types"

  local txt="${COMPARE_DIR}/${schema}_deep_${RUN_ID}.txt"
  local html="${COMPARE_DIR}/${schema}_deep_${RUN_ID}.html"

  local only_src="${COMPARE_DIR}/${schema}_only_src.lst"
  local only_tgt="${COMPARE_DIR}/${schema}_only_tgt.lst"
  local differ_files="${COMPARE_DIR}/${schema}_differ.lst"

  diff -rq "$tree_src" "$tree_tgt" > "${COMPARE_DIR}/${schema}_diff_raw.lst" || true
  awk '/^Only in / && /tree_src/ {sub(/^Only in /,""); gsub(/: /,"/"); print}' "${COMPARE_DIR}/${schema}_diff_raw.lst" > "$only_src" || true
  awk '/^Only in / && /tree_tgt/ {sub(/^Only in /,""); gsub(/: /,"/"); print}' "${COMPARE_DIR}/${schema}_diff_raw.lst" > "$only_tgt" || true
  awk '/^Files .* differ$/ {print}' "${COMPARE_DIR}/${schema}_diff_raw.lst" > "$differ_files" || true

  local tsrc="${COMPARE_DIR}/${schema}_src.tblcnt"
  local ttgt="${COMPARE_DIR}/${schema}_tgt.tblcnt"
  local tsrc_sorted="${COMPARE_DIR}/${schema}_src.tblcnt.sorted"
  local ttgt_sorted="${COMPARE_DIR}/${schema}_tgt.tblcnt.sorted"
  awk -F'|' '{print toupper($1)"|"$2"|"$3}' "$tsrc" | sort -t'|' -k1,1 > "$tsrc_sorted"
  awk -F'|' '{print toupper($1)"|"$2"|"$3}' "$ttgt" | sort -t'|' -k1,1 > "$ttgt_sorted"

  {
    echo "=== Deep Compare (DDL files + Rowcounts) ==="
    echo "Schema: ${schema}"
    echo "Generated: $(date)"
    echo
    # ---- Totals ----
    local src_total tgt_total
    src_total="$(summary_object_totals "$SRC_EZCONNECT" "$schema" "src")"
    tgt_total="$(summary_object_totals "$TGT_EZCONNECT" "$schema" "tgt")"
    echo "== Totals =="
    printf "  Source total objects: %s\n" "${src_total:-0}"
    printf "  Target total objects: %s\n" "${tgt_total:-0}"
    echo
    # ---- Invalid by type ----
    echo "== Invalid objects by type (Source) =="
    awk -F'|' '{printf "  %-24s %6d\n",$1,$2}' "$inv_src"
    echo
    echo "== Invalid objects by type (Target) =="
    awk -F'|' '{printf "  %-24s %6d\n",$1,$2}' "$inv_tgt"
    echo

    echo "== DDL Only in SOURCE =="
    sed 's#.*tree_src/##' "$only_src"
    echo
    echo "== DDL Only in TARGET =="
    sed 's#.*tree_tgt/##' "$only_tgt"
    echo
    echo "== DDL Differing files =="
    sed -E 's#^Files (.*tree_src/)([^ ]*) and (.*tree_tgt/)([^ ]*) differ#\2#g' "$differ_files"
    echo
    # ---- Difference Summary ----
    local ddl_only_src_cnt ddl_only_tgt_cnt ddl_diff_cnt rc_diff_cnt
    ddl_only_src_cnt="$(wc -l < "$only_src" 2>/dev/null || echo 0)"
    ddl_only_tgt_cnt="$(wc -l < "$only_tgt" 2>/dev/null || echo 0)"
    ddl_diff_cnt="$(wc -l < "$differ_files" 2>/dev/null || echo 0)"
    rc_diff_cnt="$(join -t'|' -j 1 "$tsrc_sorted" "$ttgt_sorted" | awk -F'|' '($2!=$5){c++} END{print c+0}')"
    echo "== Difference Summary =="
    printf "  DDL only in source: %s\n" "${ddl_only_src_cnt:-0}"
    printf "  DDL only in target: %s\n" "${ddl_only_tgt_cnt:-0}"
    printf "  DDL files differing: %s\n" "${ddl_diff_cnt:-0}"
    printf "  Tables with rowcount differences: %s\n" "${rc_diff_cnt:-0}"
    echo
    echo "== TABLE ROWCOUNTS: differences =="
    join -t'|' -j 1 "$tsrc_sorted" "$ttgt_sorted" \
      | awk -F'|' '{
          gsub(/["\\]/, "\\\\&", $1);
          if($2!=$5) printf "%-64s src=%s (%s)  tgt=%s (%s)\n",$1,$2,$3,$5,$6
        }'
  } > "${COMPARE_DIR}/${schema}_deep_${RUN_ID}.txt"
  ok "Deep text report: ${COMPARE_DIR}/${schema}_deep_${RUN_ID}.txt"

  {
    html_begin "Deep Compare ${schema}"
    echo "<h1>Deep Compare: <code>${schema}</code></h1>"
    echo "<div class=\"small\">Source: <code>${SRC_EZCONNECT}</code> &nbsp; Target: <code>${TGT_EZCONNECT}</code> &nbsp; Generated: $(date)</div>"
    echo "<div class=\"section\"><h2>Totals</h2>"
    echo "<table><thead><tr><th></th><th>Total Objects</th></tr></thead><tbody>"
    echo "<tr><td>Source</td><td>${src_total}</td></tr>"
    echo "<tr><td>Target</td><td>${tgt_total}</td></tr>"
    echo "</tbody></table></div>"

    echo "<div class=\"section\"><h2>Invalid objects by type</h2><table><thead><tr><th>Type</th><th>Source</th><th>Target</th></tr></thead><tbody>"
    while IFS= read -r T; do
      [[ -z "$T" ]] && continue
      s=$(awk -F'|' -v t="$T" '$1==t{print $2}' "$inv_src" | head -n1)
      g=$(awk -F'|' -v t="$T" '$1==t{print $2}' "$inv_tgt" | head -n1)
      s=${s:-0}; g=${g:-0}
      echo "<tr><td><code>$T</code></td><td>$s</td><td>$g</td></tr>"
    done < "$inv_types"
    echo "</tbody></table></div>"

    echo "<div class=\"section\"><h2>Difference Summary</h2><table><thead><tr><th>Metric</th><th>Count</th></tr></thead><tbody>"
    echo "<tr><td>DDL only in source</td><td>${ddl_only_src_cnt}</td></tr>"
    echo "<tr><td>DDL only in target</td><td>${ddl_only_tgt_cnt}</td></tr>"
    echo "<tr><td>DDL files differing</td><td>${ddl_diff_cnt}</td></tr>"
    echo "<tr><td>Tables with rowcount differences</td><td>${rc_diff_cnt}</td></tr>"
    echo "</tbody></table></div>"

    echo "<h2>DDL — Only in Source</h2><ul>"
    sed 's#.*tree_src/##' "$only_src" | awk '{gsub(/&/,"\\&amp;");gsub(/</,"\\&lt;");gsub(/>/,"\\&gt;");printf "<li><code>%s</code></li>\n",$0}'
    echo "</ul>"

    echo "<h2>DDL — Only in Target</h2><ul>"
    sed 's#.*tree_tgt/##' "$only_tgt" | awk '{gsub(/&/,"\\&amp;");gsub(/</,"\\&lt;");gsub(/>/,"\\&gt;");printf "<li><code>%s</code></li>\n",$0}'
    echo "</ul>"

    echo "<h2>DDL — Differing files</h2>"
    if [[ -s "$differ_files" ]]; then
      while IFS= read -r line; do
        src_file=$(echo "$line" | sed -E 's/^Files (.*) and (.*) differ/\1/')
        tgt_file=$(echo "$line" | sed -E 's/^Files (.*) and (.*) differ/\2/')
        rel=$(echo "$src_file" | sed 's#.*tree_src/##')
        echo "<h3><code>$rel</code></h3>"
        echo "<pre>"
        diff -u "$src_file" "$tgt_file" | generate_html_diff_pre || true
        echo "</pre>"
      done < "$differ_files"
    else
      echo "<p class=\"ok\">No differing DDL files.</p>"
    fi

    echo "<h2>Table Rowcount Differences</h2>"
    echo "<table><thead><tr><th>Table</th><th>Source Rows</th><th>Target Rows</th></tr></thead><tbody>"
    join -t'|' -j 1 "$tsrc_sorted" "$ttgt_sorted" \
      | awk -F'|' '{
          t=$1; gsub(/&/,"\\&amp;",t); gsub(/</,"\\&lt;",t); gsub(/>/,"\\&gt;",t);
          if ($2!=$5)
            printf "<tr><td><code>%s</code></td><td>%s <span class=\"small\">(%s)</span></td><td>%s <span class=\"small\">(%s)</span></td></tr>\n", t,$2,$3,$5,$6
        }'
    echo "</tbody></table>"
    html_end
  } > "${COMPARE_DIR}/${schema}_deep_${RUN_ID}.html"
  ok "Deep HTML report: ${COMPARE_DIR}/${schema}_deep_${RUN_ID}.html"

  if [[ -n "$REPORT_EMAILS" ]]; then
    local subject="${MAIL_SUBJECT_PREFIX} Deep Compare ${schema}"
    mail_send_html "$subject" "${COMPARE_DIR}/${schema}_deep_${RUN_ID}.html" "$REPORT_EMAILS"
  fi
}

#------------------------ ENHANCED: SQL-Based Delta Comparison (No DBLink) ----

# Enhanced snapshot with more metadata
snapshot_schema_objects_enhanced() {
    local ez="$1"
    local schema="${2^^}"
    local side="$3"
    local tag="cmp_snap_${side}_${schema}_${RUN_ID}"
    local out="${COMPARE_DIR}/${schema}_${side}_enhanced.lst"
    
    info "Capturing enhanced object snapshot for ${schema} on ${side}..."
    audit_log "COMPARE_SNAPSHOT_START" "Schema: $schema, Side: $side"
    
    # Get object metadata
    run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT 
    object_type||'|'||
    object_name||'|'||
    status||'|'||
    TO_CHAR(created, 'YYYY-MM-DD HH24:MI:SS')||'|'||
    TO_CHAR(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS')||'|'||
    temporary||'|'||
    generated||'|'||
    secondary
FROM dba_objects
WHERE owner = UPPER('${schema}')
  AND temporary = 'N'
  AND object_name NOT LIKE 'BIN\$%'
  AND object_type NOT IN ('LOB', 'INDEX PARTITION', 'TABLE PARTITION', 'LOB PARTITION')
ORDER BY object_type, object_name;
/"
    
    awk 'NF{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
    ok "Snapshot ${schema}@${side}: $(wc -l < "$out") objects captured"
    audit_log "COMPARE_SNAPSHOT_COMPLETE" "Schema: $schema, Side: $side, Count: $(wc -l < "$out")"
    echo "$out"
}

# Get table row counts
get_table_rowcounts() {
    local ez="$1"
    local schema="${2^^}"
    local side="$3"
    local exact="${4:-N}"
    local tag="cmp_rowcnt_${side}_${schema}_${RUN_ID}"
    local out="${COMPARE_DIR}/${schema}_${side}_rowcounts.lst"
    
    info "Getting table row counts for ${schema} on ${side} (exact=${exact})..."
    
    if [[ "${exact^^}" == "Y" ]]; then
        # Exact count using dynamic SQL (slower but accurate)
        run_sql "$ez" "$tag" "
SET SERVEROUTPUT ON SIZE UNLIMITED
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
DECLARE
    v_count NUMBER;
    v_sql VARCHAR2(1000);
BEGIN
    FOR r IN (
        SELECT table_name
        FROM dba_tables
        WHERE owner = UPPER('${schema}')
          AND temporary = 'N'
          AND nested = 'NO'
        ORDER BY table_name
    ) LOOP
        BEGIN
            v_sql := 'SELECT COUNT(*) FROM \"${schema}\".\"' || r.table_name || '\"';
            EXECUTE IMMEDIATE v_sql INTO v_count;
            DBMS_OUTPUT.PUT_LINE('TABLE|' || r.table_name || '|' || v_count);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('TABLE|' || r.table_name || '|ERROR:' || SQLERRM);
        END;
    END LOOP;
END;
/"
    else
        # Use statistics (faster but may be stale)
        run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT 
    'TABLE|'||table_name||'|'||NVL(num_rows, 0)
FROM dba_tables
WHERE owner = UPPER('${schema}')
  AND temporary = 'N'
  AND nested = 'NO'
ORDER BY table_name;
/"
    fi
    
    awk 'NF && /^TABLE\|/{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
    ok "Row counts ${schema}@${side}: $(wc -l < "$out") tables"
    echo "$out"
}

# Get index metadata for comparison
get_index_metadata() {
    local ez="$1"
    local schema="${2^^}"
    local side="$3"
    local tag="cmp_idx_${side}_${schema}_${RUN_ID}"
    local out="${COMPARE_DIR}/${schema}_${side}_indexes.lst"
    
    info "Getting index metadata for ${schema} on ${side}..."
    
    run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT 
    'INDEX|'||
    index_name||'|'||
    table_name||'|'||
    uniqueness||'|'||
    status||'|'||
    index_type||'|'||
    NVL(TO_CHAR(num_rows), 'NULL')
FROM dba_indexes
WHERE owner = UPPER('${schema}')
  AND index_type NOT IN ('LOB', 'DOMAIN')
ORDER BY index_name;
/"
    
    awk 'NF && /^INDEX\|/{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
    ok "Index metadata ${schema}@${side}: $(wc -l < "$out") indexes"
    echo "$out"
}

# Get constraint metadata
get_constraint_metadata() {
    local ez="$1"
    local schema="${2^^}"
    local side="$3"
    local tag="cmp_cons_${side}_${schema}_${RUN_ID}"
    local out="${COMPARE_DIR}/${schema}_${side}_constraints.lst"
    
    info "Getting constraint metadata for ${schema} on ${side}..."
    
    run_sql "$ez" "$tag" "
SET PAGES 0 FEEDBACK OFF HEADING OFF LINES 32767
SELECT 
    'CONSTRAINT|'||
    constraint_name||'|'||
    constraint_type||'|'||
    table_name||'|'||
    status||'|'||
    deferrable||'|'||
    deferred||'|'||
    validated||'|'||
    generated
FROM dba_constraints
WHERE owner = UPPER('${schema}')
  AND constraint_type IN ('P', 'U', 'R', 'C')
ORDER BY table_name, constraint_name;
/"
    
    awk 'NF && /^CONSTRAINT\|/{print $0}' "${LOG_DIR}/${tag}_${RUN_ID}.log" > "$out"
    ok "Constraint metadata ${schema}@${side}: $(wc -l < "$out") constraints"
    echo "$out"
}

# Compare two result files and generate delta report
compare_delta_files() {
    local file1="$1"
    local file2="$2"
    local label1="$3"
    local label2="$4"
    local key_fields="$5"  # e.g., "1,2" for fields 1 and 2
    local output_prefix="$6"
    
    # Create sorted key files
    local key1="${output_prefix}_key1.tmp"
    local key2="${output_prefix}_key2.tmp"
    
    if [[ "$key_fields" == "1,2" ]]; then
        awk -F'|' '{print $1"|"$2"|"$0}' "$file1" | sort -t'|' -k1,1 -k2,2 > "$key1"
        awk -F'|' '{print $1"|"$2"|"$0}' "$file2" | sort -t'|' -k1,1 -k2,2 > "$key2"
    else
        sort -t'|' "$file1" > "$key1"
        sort -t'|' "$file2" > "$key2"
    fi
    
    # Generate delta files
    local only_in_1="${output_prefix}_only_${label1}.lst"
    local only_in_2="${output_prefix}_only_${label2}.lst"
    local in_both="${output_prefix}_in_both.lst"
    local different="${output_prefix}_different.lst"
    
    # Only in file1 (source)
    comm -23 "$key1" "$key2" > "$only_in_1"
    
    # Only in file2 (target)
    comm -13 "$key1" "$key2" > "$only_in_2"
    
    # In both (common keys)
    comm -12 "$key1" "$key2" > "$in_both"
    
    # Find differences in common keys
    if [[ -s "$in_both" ]]; then
        # For objects in both, check if metadata differs
        join -t'|' -1 1,2 -2 1,2 "$key1" "$key2" 2>/dev/null | \
        awk -F'|' '{
            # Compare all fields after the key
            src=""; tgt="";
            # Extract source fields (starting at field 3 in key1 format)
            for(i=3; i<=NF/2+1; i++) src=src FS $i;
            # Extract target fields
            for(i=NF/2+2; i<=NF; i++) tgt=tgt FS $i;
            if(src != tgt) print $0;
        }' > "$different" || touch "$different"
    else
        touch "$different"
    fi
    
    # Cleanup temp files
    rm -f "$key1" "$key2" "$in_both"
    
    # Return counts
    local cnt_only_1=$(wc -l < "$only_in_1" 2>/dev/null || echo 0)
    local cnt_only_2=$(wc -l < "$only_in_2" 2>/dev/null || echo 0)
    local cnt_diff=$(wc -l < "$different" 2>/dev/null || echo 0)
    
    echo "${cnt_only_1}|${cnt_only_2}|${cnt_diff}"
}

#------------------------ HTML Report Generation for Comparisons --------------

generate_comparison_html_report() {
    local schema="$1"
    local text_report="$2"
    local src_file="$3"
    local tgt_file="$4"
    local delta_prefix="$5"
    local only_src="$6"
    local only_tgt="$7"
    local different="$8"
    
    local html_report="${COMPARE_DIR}/${schema}_enhanced_compare_${RUN_ID}.html"
    
    info "Generating HTML report: $html_report"
    
    # Get object counts
    local src_count=$(wc -l < "$src_file" 2>/dev/null || echo 0)
    local tgt_count=$(wc -l < "$tgt_file" 2>/dev/null || echo 0)
    local total_issues=$((only_src + only_tgt + different))
    
    {
        html_begin "Schema Comparison: ${schema}"
        
        cat <<'EOHTML'
<h1>📊 Schema Comparison Report</h1>

<div class="meta">
  <div class="meta-row">
    <span class="meta-label">Schema:</span>
    <span><code>SCHEMA_PLACEHOLDER</code></span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Source Database:</span>
    <span>SRC_EZCONNECT_PLACEHOLDER</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Target Database:</span>
    <span>TGT_EZCONNECT_PLACEHOLDER</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Generated:</span>
    <span class="timestamp">TIMESTAMP_PLACEHOLDER</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Report ID:</span>
    <span><code>RUN_ID_PLACEHOLDER</code></span>
  </div>
</div>

<div class="stat-grid">
  <div class="stat-card success">
    <div class="stat-label">Source Objects</div>
    <div class="stat-value">SRC_COUNT_PLACEHOLDER</div>
  </div>
  <div class="stat-card success">
    <div class="stat-label">Target Objects</div>
    <div class="stat-value">TGT_COUNT_PLACEHOLDER</div>
  </div>
  <div class="stat-card OVERALL_STATUS_CLASS">
    <div class="stat-label">Total Differences</div>
    <div class="stat-value">TOTAL_ISSUES_PLACEHOLDER</div>
  </div>
</div>

OVERALL_STATUS_MESSAGE

<div class="section">
  <h2>📈 Object Distribution</h2>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px">
    <div>
      <h3>Source Database</h3>
      <table>
        <thead>
          <tr><th>Object Type</th><th>Count</th></tr>
        </thead>
        <tbody>
SOURCE_TYPE_COUNTS
        </tbody>
      </table>
    </div>
    <div>
      <h3>Target Database</h3>
      <table>
        <thead>
          <tr><th>Object Type</th><th>Count</th></tr>
        </thead>
        <tbody>
TARGET_TYPE_COUNTS
        </tbody>
      </table>
    </div>
  </div>
</div>

<div class="section">
  <h2>🔍 Delta Analysis</h2>
  <div class="summary-box">
    <div class="summary-row">
      <span class="summary-label">Objects only in SOURCE:</span>
      <span class="summary-value ONLY_SRC_CLASS">ONLY_SRC_PLACEHOLDER</span>
    </div>
    <div class="summary-row">
      <span class="summary-label">Objects only in TARGET:</span>
      <span class="summary-value ONLY_TGT_CLASS">ONLY_TGT_PLACEHOLDER</span>
    </div>
    <div class="summary-row">
      <span class="summary-label">Objects with differences:</span>
      <span class="summary-value DIFF_CLASS">DIFF_PLACEHOLDER</span>
    </div>
  </div>
</div>

ONLY_SRC_SECTION

ONLY_TGT_SECTION

DIFF_SECTION

<div class="footer">
  <p>Generated by Oracle 19c Migration Toolkit v5 Enhanced</p>
  <p class="timestamp">FOOTER_TIMESTAMP</p>
</div>
EOHTML

        html_end
        
    } > "$html_report"
    
    # Now replace placeholders with actual values
    sed -i "s/SCHEMA_PLACEHOLDER/${schema}/g" "$html_report"
    sed -i "s/SRC_EZCONNECT_PLACEHOLDER/${SRC_EZCONNECT}/g" "$html_report"
    sed -i "s/TGT_EZCONNECT_PLACEHOLDER/${TGT_EZCONNECT}/g" "$html_report"
    sed -i "s/TIMESTAMP_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/g" "$html_report"
    sed -i "s/RUN_ID_PLACEHOLDER/${RUN_ID}/g" "$html_report"
    sed -i "s/SRC_COUNT_PLACEHOLDER/${src_count}/g" "$html_report"
    sed -i "s/TGT_COUNT_PLACEHOLDER/${tgt_count}/g" "$html_report"
    sed -i "s/TOTAL_ISSUES_PLACEHOLDER/${total_issues}/g" "$html_report"
    sed -i "s/ONLY_SRC_PLACEHOLDER/${only_src}/g" "$html_report"
    sed -i "s/ONLY_TGT_PLACEHOLDER/${only_tgt}/g" "$html_report"
    sed -i "s/DIFF_PLACEHOLDER/${different}/g" "$html_report"
    sed -i "s/FOOTER_TIMESTAMP/$(date '+%Y-%m-%d %H:%M:%S %Z')/g" "$html_report"
    
    # Set status classes
    if [[ $total_issues -eq 0 ]]; then
        sed -i "s/OVERALL_STATUS_CLASS/success/g" "$html_report"
        sed -i "s|OVERALL_STATUS_MESSAGE|<div class=\"summary-box\" style=\"background:#d1fae5;border-color:#10b981\"><p class=\"ok\" style=\"font-size:18px;margin:0\">✓ PERFECT MATCH: Schemas are identical</p></div>|g" "$html_report"
    else
        sed -i "s/OVERALL_STATUS_CLASS/warning/g" "$html_report"
        sed -i "s|OVERALL_STATUS_MESSAGE|<div class=\"summary-box\" style=\"background:#fef3c7;border-color:#f59e0b\"><p class=\"warn\" style=\"font-size:18px;margin:0\">⚠ DIFFERENCES FOUND: Review details below</p></div>|g" "$html_report"
    fi
    
    # Set individual classes
    [[ $only_src -eq 0 ]] && sed -i "s/ONLY_SRC_CLASS/ok/g" "$html_report" || sed -i "s/ONLY_SRC_CLASS/warn/g" "$html_report"
    [[ $only_tgt -eq 0 ]] && sed -i "s/ONLY_TGT_CLASS/ok/g" "$html_report" || sed -i "s/ONLY_TGT_CLASS/warn/g" "$html_report"
    [[ $different -eq 0 ]] && sed -i "s/DIFF_CLASS/ok/g" "$html_report" || sed -i "s/DIFF_CLASS/warn/g" "$html_report"
    
    # Generate object type counts tables
    local src_types=$(awk -F'|' '{count[$1]++} END {for (type in count) printf "<tr><td>%s</td><td>%d</td></tr>\n", type, count[type]}' "$src_file" | sort)
    local tgt_types=$(awk -F'|' '{count[$1]++} END {for (type in count) printf "<tr><td>%s</td><td>%d</td></tr>\n", type, count[type]}' "$tgt_file" | sort)
    
    # Use perl for multi-line replacement (sed has issues with newlines)
    perl -i -pe "s|SOURCE_TYPE_COUNTS|$src_types|s" "$html_report" 2>/dev/null || \
        sed -i "s|SOURCE_TYPE_COUNTS|<tr><td colspan='2'>Data processing error</td></tr>|g" "$html_report"
    perl -i -pe "s|TARGET_TYPE_COUNTS|$tgt_types|s" "$html_report" 2>/dev/null || \
        sed -i "s|TARGET_TYPE_COUNTS|<tr><td colspan='2'>Data processing error</td></tr>|g" "$html_report"
    
    # Generate detailed sections
    if [[ $only_src -gt 0 ]]; then
        local only_src_html="<div class=\"section\"><h2>⚠️ Objects Only in SOURCE ($only_src)</h2><div>"
        only_src_html+=$(awk -F'|' 'NR<=100 {printf "<div class=\"delta-item missing\"><strong>%s</strong> %s <span class=\"badge badge-error\">%s</span></div>\n", $1, $2, $3}' "${delta_prefix}_only_src.lst")
        [[ $only_src -gt 100 ]] && only_src_html+="<p><em>... and $((only_src - 100)) more objects (see text report for complete list)</em></p>"
        only_src_html+="</div></div>"
        sed -i "s|ONLY_SRC_SECTION|${only_src_html}|g" "$html_report"
    else
        sed -i "s|ONLY_SRC_SECTION||g" "$html_report"
    fi
    
    if [[ $only_tgt -gt 0 ]]; then
        local only_tgt_html="<div class=\"section\"><h2>ℹ️ Objects Only in TARGET ($only_tgt)</h2><div>"
        only_tgt_html+=$(awk -F'|' 'NR<=100 {printf "<div class=\"delta-item extra\"><strong>%s</strong> %s <span class=\"badge badge-warning\">%s</span></div>\n", $1, $2, $3}' "${delta_prefix}_only_tgt.lst")
        [[ $only_tgt -gt 100 ]] && only_tgt_html+="<p><em>... and $((only_tgt - 100)) more objects (see text report for complete list)</em></p>"
        only_tgt_html+="</div></div>"
        sed -i "s|ONLY_TGT_SECTION|${only_tgt_html}|g" "$html_report"
    else
        sed -i "s|ONLY_TGT_SECTION||g" "$html_report"
    fi
    
    if [[ $different -gt 0 ]]; then
        local diff_html="<div class=\"section\"><h2>🔄 Objects with Metadata Differences ($different)</h2><div>"
        diff_html+=$(awk -F'|' 'NR<=50 {printf "<div class=\"delta-item diff\"><strong>%s</strong> %s</div>\n", $1, $2}' "${delta_prefix}_different.lst")
        [[ $different -gt 50 ]] && diff_html+="<p><em>... and $((different - 50)) more objects (see text report for complete list)</em></p>"
        diff_html+="</div></div>"
        sed -i "s|DIFF_SECTION|${diff_html}|g" "$html_report"
    else
        sed -i "s|DIFF_SECTION||g" "$html_report"
    fi
    
    ok "HTML report generated: $html_report"
    audit_log "HTML_REPORT_GENERATED" "Schema: $schema, File: $html_report"
}

generate_deep_comparison_html_report() {
    local schema="$1"
    local text_report="$2"
    local total_issues="$3"
    local obj_only_src="$4"
    local obj_only_tgt="$5"
    local obj_diff="$6"
    local rc_diffs="$7"
    local idx_only_src="$8"
    local idx_only_tgt="$9"
    local idx_diff="${10}"
    local cons_only_src="${11}"
    local cons_only_tgt="${12}"
    local cons_diff="${13}"
    
    local html_report="${COMPARE_DIR}/${schema}_deep_enhanced_${RUN_ID}.html"
    
    info "Generating deep comparison HTML report: $html_report"
    
    {
        html_begin "Deep Schema Comparison: ${schema}"
        
        echo "<h1>🔬 Deep Schema Comparison Report</h1>"
        
        echo "<div class=\"meta\">"
        echo "  <div class=\"meta-row\"><span class=\"meta-label\">Schema:</span><span><code>${schema}</code></span></div>"
        echo "  <div class=\"meta-row\"><span class=\"meta-label\">Source:</span><span>${SRC_EZCONNECT}</span></div>"
        echo "  <div class=\"meta-row\"><span class=\"meta-label\">Target:</span><span>${TGT_EZCONNECT}</span></div>"
        echo "  <div class=\"meta-row\"><span class=\"meta-label\">Generated:</span><span class=\"timestamp\">$(date '+%Y-%m-%d %H:%M:%S')</span></div>"
        echo "  <div class=\"meta-row\"><span class=\"meta-label\">Row Count Method:</span><span>$([ "${EXACT_ROWCOUNT^^}" == "Y" ] && echo "EXACT (COUNT(*))" || echo "FROM STATISTICS")</span></div>"
        echo "</div>"
        
        # Overall status
        if [[ $total_issues -eq 0 ]]; then
            echo "<div class=\"summary-box\" style=\"background:#d1fae5;border-color:#10b981\">"
            echo "  <p class=\"ok\" style=\"font-size:18px;margin:0\">✓ PERFECT MATCH: Schemas are completely identical</p>"
            echo "  <ul style=\"margin-top:10px\">"
            echo "    <li>All objects match</li>"
            echo "    <li>All row counts match</li>"
            echo "    <li>All indexes match</li>"
            echo "    <li>All constraints match</li>"
            echo "  </ul>"
            echo "</div>"
        else
            echo "<div class=\"summary-box\" style=\"background:#fef3c7;border-color:#f59e0b\">"
            echo "  <p class=\"warn\" style=\"font-size:18px;margin:0\">⚠ DIFFERENCES FOUND: ${total_issues} total difference(s)</p>"
            echo "</div>"
        fi
        
        # Statistics grid
        echo "<div class=\"stat-grid\">"
        echo "  <div class=\"stat-card $([ $obj_only_src -eq 0 ] && echo 'success' || echo 'error')\">"
        echo "    <div class=\"stat-label\">Objects Missing in Target</div>"
        echo "    <div class=\"stat-value\">$obj_only_src</div>"
        echo "  </div>"
        echo "  <div class=\"stat-card $([ $obj_only_tgt -eq 0 ] && echo 'success' || echo 'warning')\">"
        echo "    <div class=\"stat-label\">Extra Objects in Target</div>"
        echo "    <div class=\"stat-value\">$obj_only_tgt</div>"
        echo "  </div>"
        echo "  <div class=\"stat-card $([ $rc_diffs -eq 0 ] && echo 'success' || echo 'error')\">"
        echo "    <div class=\"stat-label\">Row Count Differences</div>"
        echo "    <div class=\"stat-value\">$rc_diffs</div>"
        echo "  </div>"
        echo "  <div class=\"stat-card $([ $idx_diff -eq 0 ] && echo 'success' || echo 'warning')\">"
        echo "    <div class=\"stat-label\">Index Differences</div>"
        echo "    <div class=\"stat-value\">$((idx_only_src + idx_only_tgt + idx_diff))</div>"
        echo "  </div>"
        echo "</div>"
        
        # Detailed sections
        echo "<div class=\"section\">"
        echo "<h2>📦 Object Comparison</h2>"
        echo "<div class=\"summary-box\">"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Objects only in SOURCE:</span><span class=\"summary-value $([ $obj_only_src -eq 0 ] && echo 'ok' || echo 'bad')\">$obj_only_src</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Objects only in TARGET:</span><span class=\"summary-value $([ $obj_only_tgt -eq 0 ] && echo 'ok' || echo 'warn')\">$obj_only_tgt</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Objects with differences:</span><span class=\"summary-value $([ $obj_diff -eq 0 ] && echo 'ok' || echo 'warn')\">$obj_diff</span></div>"
        echo "</div>"
        echo "</div>"
        
        echo "<div class=\"section\">"
        echo "<h2>📊 Table Row Counts</h2>"
        echo "<div class=\"summary-box\">"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Tables with different counts:</span><span class=\"summary-value $([ $rc_diffs -eq 0 ] && echo 'ok' || echo 'bad')\">$rc_diffs</span></div>"
        echo "</div>"
        echo "</div>"
        
        echo "<div class=\"section\">"
        echo "<h2>🔑 Index Metadata</h2>"
        echo "<div class=\"summary-box\">"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Indexes only in SOURCE:</span><span class=\"summary-value $([ $idx_only_src -eq 0 ] && echo 'ok' || echo 'warn')\">$idx_only_src</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Indexes only in TARGET:</span><span class=\"summary-value $([ $idx_only_tgt -eq 0 ] && echo 'ok' || echo 'warn')\">$idx_only_tgt</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Indexes with differences:</span><span class=\"summary-value $([ $idx_diff -eq 0 ] && echo 'ok' || echo 'warn')\">$idx_diff</span></div>"
        echo "</div>"
        echo "</div>"
        
        echo "<div class=\"section\">"
        echo "<h2>🔗 Constraint Metadata</h2>"
        echo "<div class=\"summary-box\">"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Constraints only in SOURCE:</span><span class=\"summary-value $([ $cons_only_src -eq 0 ] && echo 'ok' || echo 'warn')\">$cons_only_src</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Constraints only in TARGET:</span><span class=\"summary-value $([ $cons_only_tgt -eq 0 ] && echo 'ok' || echo 'warn')\">$cons_only_tgt</span></div>"
        echo "  <div class=\"summary-row\"><span class=\"summary-label\">Constraints with differences:</span><span class=\"summary-value $([ $cons_diff -eq 0 ] && echo 'ok' || echo 'warn')\">$cons_diff</span></div>"
        echo "</div>"
        echo "</div>"
        
        echo "<div class=\"footer\">"
        echo "  <p>Generated by Oracle 19c Migration Toolkit v5 Enhanced</p>"
        echo "  <p class=\"timestamp\">$(date '+%Y-%m-%d %H:%M:%S %Z')</p>"
        echo "  <p><a href=\"$text_report\">View Text Report</a></p>"
        echo "</div>"
        
        html_end
        
    } > "$html_report"
    
    ok "Deep HTML report generated: $html_report"
    audit_log "HTML_DEEP_REPORT_GENERATED" "Schema: $schema, File: $html_report"
}

send_comparison_email() {
    local schema="$1"
    local type="${2:-shallow}"  # shallow or deep
    
    # Check if email is enabled and recipients configured
    if [[ "${MAIL_ENABLED^^}" != "Y" ]]; then
        debug "Email disabled (MAIL_ENABLED=$MAIL_ENABLED)"
        return 0
    fi
    
    if [[ -z "$REPORT_EMAILS" ]]; then
        debug "No email recipients configured (REPORT_EMAILS is empty)"
        return 0
    fi
    
    local html_report
    if [[ "$type" == "deep" ]]; then
        html_report="${COMPARE_DIR}/${schema}_deep_enhanced_${RUN_ID}.html"
    else
        html_report="${COMPARE_DIR}/${schema}_enhanced_compare_${RUN_ID}.html"
    fi
    
    if [[ ! -f "$html_report" ]]; then
        warn "HTML report not found: $html_report (skipping email)"
        return 0
    fi
    
    local subject="${MAIL_SUBJECT_PREFIX} Schema Comparison: ${schema} ($([ "$type" == "deep" ] && echo "Deep" || echo "Standard"))"
    
    info "Sending comparison report via email to: $REPORT_EMAILS"
    audit_log "EMAIL_SEND_START" "Schema: $schema, Recipients: $REPORT_EMAILS"
    
    mail_send_html "$subject" "$html_report" "$REPORT_EMAILS"
    
    audit_log "EMAIL_SEND_COMPLETE" "Schema: $schema, Type: $type"
}

#------------------------ ENHANCED: Compare One Schema (No DBLink) -------------

compare_one_schema() {
    local schema="${1^^}"
    [[ -z "$schema" ]] && { warn "Schema is empty"; return 1; }
    
    info "Starting enhanced comparison for schema: ${schema}"
    audit_log "COMPARE_START" "Schema: $schema, Type: Enhanced SQL (no dblink)"
    
    # Create comparison report file
    local report="${COMPARE_DIR}/${schema}_enhanced_compare_${RUN_ID}.txt"
    
    # Capture snapshots from both databases
    local src_file=$(snapshot_schema_objects_enhanced "$SRC_EZCONNECT" "$schema" "src")
    local tgt_file=$(snapshot_schema_objects_enhanced "$TGT_EZCONNECT" "$schema" "tgt")
    
    # Generate comparison report
    {
        echo "================================================================================"
        echo "ENHANCED SCHEMA COMPARISON REPORT (SQL Delta - No DBLink)"
        echo "================================================================================"
        echo "Schema:       ${schema}"
        echo "Source DB:    ${SRC_EZCONNECT}"
        echo "Target DB:    ${TGT_EZCONNECT}"
        echo "Generated:    $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report ID:    ${RUN_ID}"
        echo "================================================================================"
        echo ""
        
        # Overall statistics
        echo "=== OVERALL STATISTICS ==="
        echo ""
        local src_count=$(wc -l < "$src_file")
        local tgt_count=$(wc -l < "$tgt_file")
        printf "  %-30s : %8d objects\n" "Source total objects" "$src_count"
        printf "  %-30s : %8d objects\n" "Target total objects" "$tgt_count"
        printf "  %-30s : %8d objects\n" "Difference" "$((tgt_count - src_count))"
        echo ""
        
        # Object type breakdown
        echo "=== OBJECT COUNTS BY TYPE ==="
        echo ""
        echo "Source:"
        awk -F'|' '{count[$1]++} END {for (type in count) printf "  %-30s : %6d\n", type, count[type]}' "$src_file" | sort
        echo ""
        echo "Target:"
        awk -F'|' '{count[$1]++} END {for (type in count) printf "  %-30s : %6d\n", type, count[type]}' "$tgt_file" | sort
        echo ""
        
        # Status summary
        echo "=== OBJECT STATUS SUMMARY ==="
        echo ""
        echo "Source - Invalid Objects:"
        awk -F'|' '$3=="INVALID" {count[$1]++} END {if(length(count)==0) print "  None"; else for (type in count) printf "  %-30s : %6d\n", type, count[type]}' "$src_file" | sort
        echo ""
        echo "Target - Invalid Objects:"
        awk -F'|' '$3=="INVALID" {count[$1]++} END {if(length(count)==0) print "  None"; else for (type in count) printf "  %-30s : %6d\n", type, count[type]}' "$tgt_file" | sort
        echo ""
        
        # Perform delta analysis
        echo "=== DELTA ANALYSIS ==="
        echo ""
        local delta_prefix="${COMPARE_DIR}/${schema}_delta"
        local delta_counts=$(compare_delta_files "$src_file" "$tgt_file" "src" "tgt" "1,2" "$delta_prefix")
        
        IFS='|' read -r only_src only_tgt different <<< "$delta_counts"
        
        printf "  %-40s : %6d\n" "Objects only in SOURCE" "${only_src:-0}"
        printf "  %-40s : %6d\n" "Objects only in TARGET" "${only_tgt:-0}"
        printf "  %-40s : %6d\n" "Objects with metadata differences" "${different:-0}"
        echo ""
        
        # Detailed delta listings
        if [[ ${only_src:-0} -gt 0 ]]; then
            echo "=== OBJECTS ONLY IN SOURCE ==="
            echo ""
            awk -F'|' 'NR<=100 {printf "  %-25s %-50s %s\n", $1, $2, $3}' "${delta_prefix}_only_src.lst"
            if [[ ${only_src} -gt 100 ]]; then
                echo "  ... and $((only_src - 100)) more (see ${delta_prefix}_only_src.lst)"
            fi
            echo ""
        fi
        
        if [[ ${only_tgt:-0} -gt 0 ]]; then
            echo "=== OBJECTS ONLY IN TARGET ==="
            echo ""
            awk -F'|' 'NR<=100 {printf "  %-25s %-50s %s\n", $1, $2, $3}' "${delta_prefix}_only_tgt.lst"
            if [[ ${only_tgt} -gt 100 ]]; then
                echo "  ... and $((only_tgt - 100)) more (see ${delta_prefix}_only_tgt.lst)"
            fi
            echo ""
        fi
        
        if [[ ${different:-0} -gt 0 ]]; then
            echo "=== OBJECTS WITH STATUS DIFFERENCES ==="
            echo ""
            # Parse differences and show status changes
            awk -F'|' '
            {
                obj_type=$1; obj_name=$2; 
                # Source status is field 5, target status varies based on join
                src_status=$5;
                # Try to find target status (usually around position 11-13)
                for(i=10; i<=15; i++) {
                    if($i=="VALID" || $i=="INVALID") {
                        tgt_status=$i;
                        break;
                    }
                }
                if(src_status != tgt_status && NR<=50) {
                    printf "  %-25s %-40s SRC: %-10s TGT: %-10s\n", obj_type, obj_name, src_status, tgt_status
                }
            }
            ' "${delta_prefix}_different.lst"
            if [[ ${different} -gt 50 ]]; then
                echo "  ... and $((different - 50)) more (see ${delta_prefix}_different.lst)"
            fi
            echo ""
        fi
        
        echo "================================================================================"
        echo "COMPARISON SUMMARY"
        echo "================================================================================"
        if [[ ${only_src:-0} -eq 0 ]] && [[ ${only_tgt:-0} -eq 0 ]] && [[ ${different:-0} -eq 0 ]]; then
            echo "✓ PERFECT MATCH: Schemas are identical"
        else
            echo "⚠ DIFFERENCES FOUND:"
            [[ ${only_src:-0} -gt 0 ]] && echo "  - ${only_src} objects missing in target"
            [[ ${only_tgt:-0} -gt 0 ]] && echo "  - ${only_tgt} extra objects in target"
            [[ ${different:-0} -gt 0 ]] && echo "  - ${different} objects with metadata differences"
        fi
        echo ""
        echo "Detail files:"
        echo "  - Full report: $report"
        echo "  - Source snapshot: $src_file"
        echo "  - Target snapshot: $tgt_file"
        echo "  - Only in source: ${delta_prefix}_only_src.lst"
        echo "  - Only in target: ${delta_prefix}_only_tgt.lst"
        echo "  - Different: ${delta_prefix}_different.lst"
        echo "================================================================================"
        
    } | tee "$report"
    
    ok "Enhanced comparison complete: $report"
    audit_log "COMPARE_COMPLETE" "Schema: $schema, Delta: src_only=${only_src:-0}, tgt_only=${only_tgt:-0}, diff=${different:-0}"
    
    # Generate HTML report
    generate_comparison_html_report "$schema" "$report" "$src_file" "$tgt_file" "$delta_prefix" "${only_src:-0}" "${only_tgt:-0}" "${different:-0}"
    
    # Send email if configured
    send_comparison_email "$schema" "shallow"
}

#------------------------ Menus (Export/Import/Compare/Main) -------------------
show_jobs() {
  ce "Logs under $LOG_DIR and NAS path: $NAS_PATH"
  read -rp "Show DBA_DATAPUMP_JOBS on which DB? (src/tgt): " side
  case "${side,,}" in
    src) debug "Monitor -> jobs on source"; run_sql "$SRC_EZCONNECT" "jobs_src" "SET LINES 220 PAGES 200
COL owner_name FOR A20
COL job_name FOR A30
COL state FOR A12
SELECT owner_name, job_name, state, operation, job_mode, degree, attached_sessions
FROM dba_datapump_jobs ORDER BY 1,2; /" ;;
    tgt) debug "Monitor -> jobs on target"; run_sql "$TGT_EZCONNECT" "jobs_tgt" "SET LINES 220 PAGES 200
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
    src) debug "Drop DIRECTORY on source"; run_sql "$SRC_EZCONNECT" "drop_dir_src" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
    tgt) debug "Drop DIRECTORY on target"; run_sql "$TGT_EZCONNECT" "drop_dir_tgt" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /" ;;
    both) debug "Drop DIRECTORY on both"
      run_sql "$SRC_EZCONNECT" "drop_dir_src" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
      run_sql "$TGT_EZCONNECT" "drop_dir_tgt" "BEGIN EXECUTE IMMEDIATE 'DROP DIRECTORY ${COMMON_DIR_NAME}'; EXCEPTION WHEN OTHERS THEN NULL; END; /"
      ;;
    *) warn "No action";;
  esac
}

export_menu() {
  while true; do
    cat <<'EOS'
Export Menu:
  1) FULL database (submenu: metadata_only / full)
  2) SCHEMAS (submenu: all non-maintained / user|conf)
  3) TABLESPACES (transport)
  4) TABLES
  5) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) debug "Export menu -> FULL"; exp_full_menu ;;
      2) debug "Export menu -> SCHEMAS"; exp_schemas_menu ;;
      3) debug "Export menu -> TABLESPACES"; exp_tablespaces ;;
      4) debug "Export menu -> TABLES"; exp_tables ;;
      5) debug "Export menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

import_menu() {
  while true; do
    cat <<EOS
Import Menu  $( [[ "${DRY_RUN_ONLY^^}" == "Y" ]] && echo "[DRY_RUN_ONLY=Y active for Drop/Cleanup]" )
  1) FULL database (submenu: metadata_only / full)
  2) SCHEMAS (submenu: all non-maintained / user|conf)
  3) TABLESPACES (transport)
  4) TABLES
  5) Drop/Cleanup (DANGEROUS) -> submenu (with preview/dry-run)
  6) Back
EOS
    read -rp "Choose: " c
    case "$c" in
      1) debug "Import menu -> FULL"; imp_full_menu ;;
      2) debug "Import menu -> SCHEMAS"; imp_schemas_menu ;;
      3) debug "Import menu -> TABLESPACES"; imp_tablespaces ;;
      4) debug "Import menu -> TABLES"; imp_tables ;;
      5) debug "Import menu -> Cleanup"; import_cleanup_menu ;;
      6) debug "Import menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

compare_schema_menu() {
  while true; do
    cat <<'EOS'
Compare Objects (Source vs Target):
  === SQL-BASED COMPARISON (Recommended - No DBLink Required) ===
  1) SQL Compare: One schema (objects + status)
  2) SQL Compare: Multiple schemas
  3) SQL Deep Compare: One schema (objects + row counts + indexes + constraints)
  4) SQL Deep Compare: Multiple schemas
  
  === LEGACY DDL FILE-BASED COMPARISON ===
  5) DDL Compare: One schema (DDL file diff + row counts)
  6) DDL Compare: Multiple schemas
  
  7) Back to Main Menu
EOS
    read -rp "Choose: " c
    case "$c" in
      1) read -rp "Schema name: " s
         info "Using Enhanced SQL-Based Comparison (no dblink required)"
         compare_one_schema "$s" ;;
      2) read -rp "Schema names (comma-separated): " list
         info "Using Enhanced SQL-Based Comparison (no dblink required)"
         IFS=',' read -r -a arr <<< "$list"
         for s in "${arr[@]}"; do 
           s="$(echo "$s" | awk '{$1=$1;print}')"
           [[ -z "$s" ]] && continue
           compare_one_schema "$s"
         done ;;
      3) read -rp "Schema name: " s
         info "Using Enhanced SQL-Based Deep Comparison (no dblink required)"
         info "Includes: Objects + Row Counts + Indexes + Constraints"
         deep_compare_schema_enhanced "$s" ;;
      4) read -rp "Schema names (comma-separated): " list
         info "Using Enhanced SQL-Based Deep Comparison (no dblink required)"
         IFS=',' read -r -a arr <<< "$list"
         for s in "${arr[@]}"; do
           s="$(echo "$s" | awk '{$1=$1;print}')"
           [[ -z "$s" ]] && continue
           deep_compare_schema_enhanced "$s"
         done ;;
      5) read -rp "Schema name: " s
         warn "Using Legacy DDL File-Based Comparison"
         warn "This method extracts DDL to files and uses diff"
         deep_compare_schema "$s" ;;
      6) read -rp "Schema names (comma-separated): " list
         warn "Using Legacy DDL File-Based Comparison"
         IFS=',' read -r -a arr <<< "$list"
         for s in "${arr[@]}"; do
           s="$(echo "$s" | awk '{$1=$1;print}')"
           [[ -z "$s" ]] && continue
           deep_compare_schema "$s"
         done ;;
      7) debug "Compare menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

validation_menu() {
  while true; do
    cat <<'EOS'
Pre-Migration Validation Menu:
  1) Check database version compatibility
  2) Validate character set compatibility
  3) Check tablespace free space (source)
  4) Check tablespace free space (target)
  5) Check invalid objects before export
  6) Run ALL validations
  7) Back to main menu
EOS
    read -rp "Choose: " c
    case "$c" in
      1) debug "Validation -> Version compatibility"; validate_version_compatibility ;;
      2) debug "Validation -> Character set"; 
         if [[ "${VALIDATE_CHARSET^^}" == "Y" ]]; then validate_charset; else warn "VALIDATE_CHARSET is disabled"; fi ;;
      3) debug "Validation -> Tablespace (source)"; check_tablespace_space "$SRC_EZCONNECT" "source" ;;
      4) debug "Validation -> Tablespace (target)"; check_tablespace_space "$TGT_EZCONNECT" "target" ;;
      5) debug "Validation -> Invalid objects"; 
         if [[ "${CHECK_INVALID_OBJECTS^^}" == "Y" ]]; then 
           read -rp "Schema name (or leave empty for all): " s
           check_invalid_objects_before_export "$SRC_EZCONNECT" "$s"
         else 
           warn "CHECK_INVALID_OBJECTS is disabled"
         fi ;;
      6) debug "Validation -> ALL checks";
         ok "Running all validation checks..."
         validate_version_compatibility
         [[ "${VALIDATE_CHARSET^^}" == "Y" ]] && validate_charset
         check_tablespace_space "$SRC_EZCONNECT" "source"
         check_tablespace_space "$TGT_EZCONNECT" "target"
         [[ "${CHECK_INVALID_OBJECTS^^}" == "Y" ]] && check_invalid_objects_before_export "$SRC_EZCONNECT" ""
         ok "All validations completed!" ;;
      7) debug "Validation menu -> Back"; break ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

main_menu() {
  while true; do
    cat <<EOS

======== Oracle 19c Migration & DDL (v5 Enhanced) ========
Script:  ${SCRIPT_NAME}
Source:  ${SRC_EZCONNECT}
Target:  ${TGT_EZCONNECT}
NAS:     ${NAS_PATH}
Config:  PARALLEL=${PARALLEL} | COMPRESSION=${COMPRESSION} | TABLE_EXISTS_ACTION=${TABLE_EXISTS_ACTION}
Dirs:    DDL=${DDL_DIR} | Compare=${COMPARE_DIR} | Audit=${AUDIT_DIR}
===========================================================

 1) Pre-Migration Validations    -> version, charset, space, invalid objects
 2) Precheck & create DIRECTORY  -> on source and target
 3) Export (Data Pump)           -> sub menu
 4) Import (Data Pump)           -> sub menu
 5) Monitor/Status               -> DBA_DATAPUMP_JOBS + tail logs
 6) Drop DIRECTORY objects       -> cleanup
 7) DDL Extraction (Source DB)   -> sub menu
 8) Compare Objects (Src vs Tgt) -> sub menu
 9) View Audit Trail             -> security audit log
10) Quit
EOS
    read -rp "Choose: " choice
    case "$choice" in
      1) debug "Main -> Validation menu"; validation_menu ;;
      2) debug "Main -> Precheck & create DIRECTORY";
         ensure_directory_object "$SRC_EZCONNECT" "src"; ensure_directory_object "$TGT_EZCONNECT" "tgt";
         validate_directory_on_db "$SRC_EZCONNECT" "src"; validate_directory_on_db "$TGT_EZCONNECT" "tgt";
         ok "DIRECTORY ${COMMON_DIR_NAME} ready on both." ;;
      3) debug "Main -> Export menu"; export_menu ;;
      4) debug "Main -> Import menu"; import_menu ;;
      5) debug "Main -> Monitor/Status"; show_jobs ;;
      6) debug "Main -> Drop DIRECTORY objects"; cleanup_dirs ;;
      7) debug "Main -> DDL Extraction menu"; ddl_menu ;;
      8) debug "Main -> Compare menu"; compare_schema_menu ;;
      9) debug "Main -> View audit trail";
         if [[ -f "${AUDIT_DIR}/audit_${RUN_ID}.log" ]]; then
           info "Audit trail for RUN_ID: $RUN_ID"
           cat "${AUDIT_DIR}/audit_${RUN_ID}.log" | column -t -s'|' | sed 's/^/  /'
         else
           warn "No audit log found for this session"
         fi
         ;;
      10) ok "Cleaning up and exiting..."; 
          audit_log "SESSION_END" "Normal exit"
          ok "Audit trail saved: ${AUDIT_DIR}/audit_${RUN_ID}.log"
          exit 0 ;;
      *) warn "Invalid choice.";;
    esac
  done
}

# Trap for unexpected exits
trap 'audit_log "SESSION_INTERRUPTED" "Script terminated unexpectedly"' EXIT INT TERM

main_menu
