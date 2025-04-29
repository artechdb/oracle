#!/bin/bash

# Load functions
source ./functions_health_check.sh
source ./functions_health_check_advanced.sh

# Variables
EMAIL_TO="dba-team@example.com"
SUMMARY_HTML="/tmp/rac_health_summary.html"
ZIP_FILE="/tmp/rac_health_results_$(date +%Y%m%d).zip"

# Perform health checks (this part should loop over connections in real script)

generate_summary_html
package_html_reports "/tmp" "$SUMMARY_HTML"
send_health_report_email "$EMAIL_TO" "$SUMMARY_HTML" "$ZIP_FILE"

exit 0

##########################################
# Advanced Health Check Functions

REDO_SWITCH_THRESHOLD_PER_HOUR=50
TEMP_USAGE_THRESHOLD_MB=2048
SESSION_CPU_THRESHOLD=5000
CHILD_CURSOR_THRESHOLD=50
PARALLEL_SKEW_RATIO=2.0

# (functions like check_redo_log_switch_rate, check_temp_usage, etc. are here...)

package_html_reports() {
  local REPORT_DIR="$1"
  local SUMMARY_FILE="$2"
  local DATE_TAG
  DATE_TAG=$(date +%Y%m%d)
  local ZIP_NAME="rac_health_results_${DATE_TAG}.zip"

  echo "Packaging all reports into: $ZIP_NAME"

  if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "Summary HTML not found: $SUMMARY_FILE"
    return 1
  fi

  local REPORTS=("$SUMMARY_FILE" "$REPORT_DIR"/db_*.html)

  zip -j "/tmp/$ZIP_NAME" "${REPORTS[@]}" >/dev/null

  if [[ $? -eq 0 ]]; then
    echo "Report package created: /tmp/$ZIP_NAME"
  else
    echo "Failed to create report package"
    return 1
  fi
}

send_health_report_email() {
  local RECIPIENT="$1"
  local SUMMARY_HTML="$2"
  local ZIP_FILE="$3"
  local SUBJECT="RAC Health Check Report - $(date '+%Y-%m-%d %H:%M')"

  if [ ! -f "$SUMMARY_HTML" ]; then
    echo "Missing summary file: $SUMMARY_HTML"
    return 1
  fi

  if [ -s "$SUMMARY_HTML" ] && [ $(stat -c%s "$SUMMARY_HTML") -lt 1000000 ]; then
    {
      echo "To: $RECIPIENT"
      echo "Subject: $SUBJECT"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/html"
      echo
      cat "$SUMMARY_HTML"
    } | sendmail -t
    echo "Email sent with inline HTML summary to $RECIPIENT"
  elif [ -f "$ZIP_FILE" ]; then
    echo "Please find attached RAC Health Check ZIP." | mailx -s "$SUBJECT" -a "$ZIP_FILE" "$RECIPIENT"
    echo "Email sent with ZIP attachment to $RECIPIENT"
  else
    echo "No valid file found to send."
    return 1
  fi
}

#########
# functions_standby_rac.sh
# functions_standby_rac.sh

set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

exec_sqlplus() {
  local CONN="$1"
  local SQL="$2"
  sqlplus -s /nolog <<EOF
CONNECT $CONN
SET HEAD OFF FEEDBACK OFF PAGES 0 VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE;
$SQL
EXIT;
EOF
}

precheck_standby_environment() {
  log "Performing Pre-checks..."

  log "Checking connectivity to Primary Database..."
  if ! echo "exit" | sqlplus -s sys/$SYS_PASS@$PRIMARY_DB_CONN as sysdba >/dev/null; then
    log "ERROR: Cannot connect to Primary Database ($PRIMARY_DB_CONN). Exiting."
    exit 1
  fi

  log "Checking connectivity to Standby Node1 ($STANDBY_HOST1)..."
  if ! ping -c 2 "$STANDBY_HOST1" >/dev/null; then
    log "ERROR: Cannot ping Standby Node1 ($STANDBY_HOST1). Exiting."
    exit 1
  fi

  log "Checking connectivity to Standby Node2 ($STANDBY_HOST2)..."
  if ! ping -c 2 "$STANDBY_HOST2" >/dev/null; then
    log "ERROR: Cannot ping Standby Node2 ($STANDBY_HOST2). Exiting."
    exit 1
  fi

  log "Checking ORACLE_HOME exists..."
  if [ ! -d "$ORACLE_HOME" ]; then
    log "ERROR: ORACLE_HOME ($ORACLE_HOME) does not exist. Exiting."
    exit 1
  fi

  log "Pre-checks completed successfully."
}

create_required_directories_standby() {
  local HOST1="$1"
  local HOST2="$2"
  local DBNAME="$3"

  log "Creating adump directory on $HOST1"
  ssh oracle@"$HOST1" bash <<EOF
mkdir -p /u01/app/oracle/admin/${DBNAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${DBNAME}/adump
EOF

  log "Creating adump directory on $HOST2"
  ssh oracle@"$HOST2" bash <<EOF
mkdir -p /u01/app/oracle/admin/${DBNAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${DBNAME}/adump
EOF

  log "Adump directories created on both nodes."
}

create_all_logs_from_primary_info() {
  local PRIMARY_CONN="$1"
  local STANDBY_SID="$2"
  local ASM_DISKGROUP="$3"

  export ORACLE_SID="$STANDBY_SID"

  log "Fetching redo size from Primary Database."
  local REDO_SIZE_MB=$(exec_sqlplus "$PRIMARY_CONN" "SELECT bytes/1024/1024 FROM v\$log WHERE rownum = 1;" | xargs)

  log "Fetching redo group counts per thread from Primary."
  local THREAD_COUNTS=$(exec_sqlplus "$PRIMARY_CONN" "SELECT thread#||':'||COUNT(group#) FROM v\$log GROUP BY thread#;" | xargs)

  for entry in $THREAD_COUNTS; do
    local thread=$(echo "$entry" | cut -d':' -f1)
    local redo_count=$(echo "$entry" | cut -d':' -f2)

    log "Creating Redo Logs for Thread $thread"
    for ((i=1; i<=redo_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD LOGFILE THREAD $thread ('$ASM_DISKGROUP/$STANDBY_SID/ONLINELOG/redo_t${thread}_g${i}.log') SIZE ${REDO_SIZE_MB}M;
EXIT;
EOF
    done

    log "Creating Standby Redo Logs for Thread $thread"
    standby_count=$((redo_count + 1))
    for ((i=1; i<=standby_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD STANDBY LOGFILE THREAD $thread ('$ASM_DISKGROUP/$STANDBY_SID/STANDBYLOG/standby_t${thread}_g${i}.log') SIZE ${REDO_SIZE_MB}M;
EXIT;
EOF
    done
  done

  log "Redo and Standby Redo Logs created successfully."
}

############
# standby_create_driver.sh

#!/bin/bash

set -euo pipefail

# Load configuration and functions
source ./standby_create.conf
source ./functions_standby_rac.sh

log "Starting Standby RAC Creation Process"

# Step 1: Perform pre-checks
precheck_standby_environment

# Step 2: Create required adump directories
create_required_directories_standby "$STANDBY_HOST1" "$STANDBY_HOST2" "$STANDBY_DB_UNIQUE_NAME"

# Step 3: (Manual Step) Perform RMAN DUPLICATE FOR STANDBY from active database
log "Please ensure RMAN DUPLICATE FOR STANDBY is completed manually."
echo "Example Command:"
echo "rman target sys/\$SYS_PASS@\$PRIMARY_DB_CONN auxiliary sys/\$SYS_PASS@\$STANDBY_DB_NAME"
echo "DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE DORECOVER NOFILENAMECHECK;"
echo "(Note: Adjust for your environment)"

read -p "Press ENTER after RMAN DUPLICATE is completed to continue..."

# Step 4: Create redo and standby redo logs dynamically based on Primary info
create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"

# Step 5: Post Steps Reminder
log "Post Steps Reminder:"
echo "- Register Standby Database with SRVCTL if not already done."
echo "- Add Standby Database into Data Guard Broker:"
echo "  dgmgrl sys/\$SYS_PASS@\$PRIMARY_DB_CONN"
echo "  ADD DATABASE \"\$STANDBY_DB_UNIQUE_NAME\" AS CONNECT IDENTIFIER IS \"\$STANDBY_DB_NAME\" MAINTAINED AS PHYSICAL;"
echo "  ENABLE DATABASE \"\$STANDBY_DB_UNIQUE_NAME\";"
echo "- Start Redo Apply on Standby:"
echo "  EDIT DATABASE \"\$STANDBY_DB_UNIQUE_NAME\" SET STATE='APPLY-ON';"

log "Standby RAC Creation Process Completed Successfully"


#!/bin/bash

# Configuration
REPORT_FILE="firewall_report.html"
EMAIL_FROM="dba@example.com"
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT="Firewall Policy Validation Report"
TNS_FILE="${1}"

# Check if tnsnames.ora file is provided
if [ -z "${TNS_FILE}" ] || [ ! -f "${TNS_FILE}" ]; then
    echo "Usage: $0 <tnsnames.ora_file>"
    echo "Please provide valid tnsnames.ora file path"
    exit 1
fi

# Check for dependencies
command -v nc >/dev/null 2>&1 || { echo "netcat (nc) is required but not installed. Aborting."; exit 1; }

# Initialize HTML report
initialize_report() {
    cat << EOF > "${REPORT_FILE}"
<html>
<head>
    <title>Firewall Policy Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 80%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { background-color: #90EE90; }
        .failure { background-color: #FFB6C1; }
    </style>
</head>
<body>
    <h2>Firewall Policy Validation Report</h2>
    <p>Generated at: $(date)</p>
    <table>
        <tr>
            <th>DB Name</th>
            <th>Hostname</th>
            <th>Port 1521 Status</th>
        </tr>
EOF
}

# Extract dbname and hosts from tnsnames.ora
extract_entries() {
    awk -v RS= '{
        dbname = ""; host = ""
        # Extract dbname from first line
        if (match($0, /^[^=]+/)) {
            dbname = substr($0, RSTART, RLENGTH)
            gsub(/^[ \t]+|[ \t]+$/, "", dbname)
        }
        
        # Extract all HOST entries
        remaining = $0
        while (match(remaining, /HOST\s*=\s*[^ \t\)]+/i)) {
            host_line = substr(remaining, RSTART, RLENGTH)
            split(host_line, arr, "=")
            host = arr[2]
            gsub(/^[ \t]+|[ \t]+$/, "", host)
            print dbname "|" host
            remaining = substr(remaining, RSTART + RLENGTH)
        }
    }' "${TNS_FILE}" | sort -u
}

# Test port function
test_port() {
    host=$1
    port=1521
    timeout 3 nc -zv "${host}" "${port}" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "success"
    else
        echo "failure"
    fi
}

# Complete HTML report
finalize_report() {
    cat << EOF >> "${REPORT_FILE}"
    </table>
</body>
</html>
EOF
}

# Email function
send_email() {
    local report_size=$(du -b "${REPORT_FILE}" | awk '{print $1}')
    
    if [ "${report_size}" -lt 1048576 ]; then
        mailx -s "${EMAIL_SUBJECT}" -a "Content-type: text/html" -r "${EMAIL_FROM}" "${EMAIL_TO}" < "${REPORT_FILE}"
    else
        echo "Please find attached the firewall validation report" | \
        mailx -s "${EMAIL_SUBJECT}" -a "${REPORT_FILE}" -r "${EMAIL_FROM}" "${EMAIL_TO}"
    fi
}

# Main execution
initialize_report

while IFS="|" read -r dbname host; do
    [ -z "$host" ] && continue  # Skip invalid entries
    
    status=$(test_port "${host}")
    
    if [ "${status}" = "success" ]; then
        class="success"
        status_text="Open"
    else
        class="failure"
        status_text="Closed"
    fi
    
    echo "Processing DB: ${dbname} - Host: ${host} - Status: ${status_text}"
    
    cat << EOF >> "${REPORT_FILE}"
        <tr>
            <td>${dbname}</td>
            <td>${host}</td>
            <td class="${class}">${status_text}</td>
        </tr>
EOF
done < <(extract_entries)

finalize_report

# Send email
send_email

echo "Report generated: ${REPORT_FILE}"

#!/bin/bash

# Configuration
REPORT_FILE="firewall_report.html"
EMAIL_FROM="dba@example.com"
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT="Firewall Policy Validation Report"
TNS_FILE="${1}"

# Check if tnsnames.ora file is provided
if [ -z "${TNS_FILE}" ] || [ ! -f "${TNS_FILE}" ]; then
    echo "Usage: $0 <tnsnames.ora_file>"
    echo "Please provide valid tnsnames.ora file path"
    exit 1
fi

# Check for dependencies
command -v nc >/dev/null 2>&1 || { echo "netcat (nc) is required but not installed. Aborting."; exit 1; }

# Initialize HTML report
initialize_report() {
    cat << EOF > "${REPORT_FILE}"
<html>
<head>
    <title>Firewall Policy Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 50%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { background-color: #90EE90; }
        .failure { background-color: #FFB6C1; }
    </style>
</head>
<body>
    <h2>Firewall Policy Validation Report</h2>
    <p>Generated at: $(date)</p>
    <table>
        <tr>
            <th>Hostname</th>
            <th>Port 1521 Status</th>
        </tr>
EOF
}

# Extract hosts from tnsnames.ora
extract_hosts() {
    grep -iE 'HOST\s*=\s*' "${TNS_FILE}" | \
    awk -F'=' '{print $2}' | \
    awk '{gsub(/^[ \t]+|[ \t]+$/, ""); print}' | \
    sort -u
}

# Test port function
test_port() {
    host=$1
    port=1521
    timeout 3 nc -zv "${host}" "${port}" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "success"
    else
        echo "failure"
    fi
}

# Complete HTML report
finalize_report() {
    cat << EOF >> "${REPORT_FILE}"
    </table>
</body>
</html>
EOF
}

# Email function
send_email() {
    local report_size=$(du -b "${REPORT_FILE}" | awk '{print $1}')
    
    if [ "${report_size}" -lt 1048576 ]; then
        # Send HTML content in body
        mailx -s "${EMAIL_SUBJECT}" -a "Content-type: text/html" -r "${EMAIL_FROM}" "${EMAIL_TO}" < "${REPORT_FILE}"
    else
        # Send as attachment
        echo "Please find attached the firewall validation report" | \
        mailx -s "${EMAIL_SUBJECT}" -a "${REPORT_FILE}" -r "${EMAIL_FROM}" "${EMAIL_TO}"
    fi
}

# Main execution
initialize_report

while read -r host; do
    status=$(test_port "${host}")
    
    if [ "${status}" = "success" ]; then
        class="success"
        status_text="Open"
    else
        class="failure"
        status_text="Closed"
    fi
    
    echo "Processing host: ${host} - Status: ${status_text}"
    
    cat << EOF >> "${REPORT_FILE}"
        <tr>
            <td>${host}</td>
            <td class="${class}">${status_text}</td>
        </tr>
EOF
done < <(extract_hosts)

finalize_report

# Send email
send_email

echo "Report generated: ${REPORT_FILE}"
##
#!/bin/bash
# Script: recreate_redologs.sh
# Usage: ./recreate_redologs.sh <input_file>

# Initialize variables
INPUT_FILE=$1
LOG_FILE="redo_recreation_$(date +%Y%m%d%H%M%S).log"
TMP_DIR="/tmp/redo_workdir"
mkdir -p $TMP_DIR

# Load input parameters
source $INPUT_FILE || { echo "Error loading input file"; exit 1; }

# Database connection strings
PRIMARY_CONN="${SYS_USER}/${SYS_PASSWORD}@${DB_NAME}"

# Get standby DB name using dgmgrl
get_standby_db() {
  dgmgrl -silent ${PRIMARY_CONN} <<EOF | awk '/Physical standby/{print $1}'
SHOW CONFIGURATION;
EXIT;
EOF
}

STANDBY_DB=$(get_standby_db)
STANDBY_CONN="${SYS_USER}/${SYS_PASSWORD}@${STANDBY_DB}"

# Logging function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to capture existing groups
capture_groups() {
  local conn=$1
  local type=$2
  sqlplus -S $conn <<EOF
SET PAGES 0 FEED OFF HEAD OFF
SELECT group#||','||thread#||','||'$type' FROM v\$log UNION
SELECT group#||','||thread#||','||'STANDBY' FROM v\$standby_log;
EXIT;
EOF
}

# Function to create new log groups
create_new_groups() {
  local conn=$1
  local log_type=$2
  local new_size=$3
  local thread=$4
  local count=$5
  
  max_group=$(sqlplus -S $conn <<EOF
SET PAGES 0 FEED OFF HEAD OFF
SELECT MAX(group#)+1 FROM v\$log UNION SELECT MAX(group#)+1 FROM v\$standby_log;
EXIT;
EOF
)
  
  for ((i=1; i<=$count; i++)); do
    group_num=$((max_group+i-1))
    if [ "$log_type" = "STANDBY" ]; then
      sqlplus -S $conn <<EOF
ALTER DATABASE ADD STANDBY LOGFILE THREAD $thread GROUP $group_num SIZE $new_size;
EOF
    else
      sqlplus -S $conn <<EOF
ALTER DATABASE ADD LOGFILE THREAD $thread GROUP $group_num SIZE $new_size;
EOF
    fi
  done
}

# Main execution
log "Starting redo log recreation process"

# Capture existing groups
log "Capturing existing groups on primary"
capture_groups $PRIMARY_CONN PRIMARY > $TMP_DIR/primary_groups.lst
log "Capturing existing groups on standby"
capture_groups $STANDBY_CONN STANDBY > $TMP_DIR/standby_groups.lst

# Create new groups on primary
log "Creating new primary redo logs"
awk -F, '/PRIMARY/{print $2}' $TMP_DIR/primary_groups.lst | sort -u | while read thread; do
  count=$(grep ",$thread,PRIMARY" $TMP_DIR/primary_groups.lst | wc -l)
  create_new_groups $PRIMARY_CONN PRIMARY $NEW_REDO_SIZE $thread $count
done

# Create new standby logs on standby
log "Creating new standby redo logs"
awk -F, '/STANDBY/{print $2}' $TMP_DIR/standby_groups.lst | sort -u | while read thread; do
  count=$(grep ",$thread,STANDBY" $TMP_DIR/standby_groups.lst | wc -l)
  create_new_groups $STANDBY_CONN STANDBY $NEW_STANDBY_REDO_SIZE $thread $count
done

# Switch logs and wait for old groups to become inactive
log "Forcing log switches on primary"
for i in {1..10}; do
  sqlplus -S $PRIMARY_CONN <<EOF
ALTER SYSTEM ARCHIVE LOG CURRENT;
EOF
  sleep 10
done

# Drop old groups
log "Dropping old groups"
for db in PRIMARY STANDBY; do
  conn=$([ "$db" = "PRIMARY" ] && echo $PRIMARY_CONN || echo $STANDBY_CONN)
  grep "^[0-9]*,.*,$db" $TMP_DIR/${db,,}_groups.lst | cut -d',' -f1 | while read group; do
    sqlplus -S $conn <<EOF
ALTER DATABASE DROP LOGFILE GROUP $group;
EOF
  done
done

log "Process completed successfully. Please verify log file: $LOG_FILE"
exit 0
## pre-check
#!/bin/bash
# Refreshable PDB Clone Precheck Script
# Usage: ./pdb_clone_precheck.sh <input_file.txt>

# Define SQL*Plus path (update if needed)
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"

# Check input file
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 <input_file.txt>"
    echo "Input file format:"
    echo "source_cdb|source_pdb|target_cdb|target_pdb"
    exit 1
fi

INPUT_FILE="$1"
LOG_FILE="pdb_clone_precheck_$(date +%Y%m%d_%H%M%S).log"

# Precheck validation function
validate_clone_prerequisites() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    
    echo "================================================================="
    echo " Starting precheck for:"
    echo " Source: $src_cdb/$src_pdb"
    echo " Target: $tgt_cdb/$tgt_pdb"
    echo "================================================================="

    # 1. Source CDB Checks
    echo "Checking Source CDB ($src_cdb)..."
    $SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$src_cdb as sysdba

-- Check source PDB exists
SET HEAD OFF FEED OFF
SELECT 'VALID' FROM v\$pdbs WHERE name = '$src_pdb';
EXIT
EOF
    [ $? -ne 0 ] && echo "[ERROR] Source PDB $src_pdb not found in $src_cdb" && return 1

    # 2. Source PDB Check
    echo "Checking Source PDB ($src_pdb)..."
    SRC_PDB_STATUS=$($SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$src_cdb as sysdba

SET HEAD OFF FEED OFF
SELECT open_mode FROM v\$pdbs WHERE name = '$src_pdb';
EXIT
EOF
    )
    [[ ! "$SRC_PDB_STATUS" =~ "READ WRITE" && ! "$SRC_PDB_STATUS" =~ "READ ONLY" ]] && \
        echo "[ERROR] Source PDB must be in READ WRITE or READ ONLY mode. Current mode: $SRC_PDB_STATUS" && return 1

    # 3. Local Undo Check
    LOCAL_UNDO=$($SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$src_cdb as sysdba

SET HEAD OFF FEED OFF
SELECT value FROM v\$parameter WHERE name = 'local_undo_enabled';
EXIT
EOF
    )
    [ "$LOCAL_UNDO" != "TRUE" ] && echo "[ERROR] LOCAL_UNDO_ENABLED must be TRUE on source CDB" && return 1

    # 4. Target CDB Check
    echo "Checking Target CDB ($tgt_cdb)..."
    $SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$tgt_cdb as sysdba

-- Check target PDB name availability
SET HEAD OFF FEED OFF
SELECT 'VALID' FROM v\$pdbs WHERE name = '$tgt_pdb';
EXIT
EOF
    [ $? -eq 0 ] && echo "[ERROR] Target PDB $tgt_pdb already exists in $tgt_cdb" && return 1

    # 5. Compatibility Check
    SRC_COMPAT=$($SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$src_cdb as sysdba
SET HEAD OFF FEED OFF
SELECT value FROM v\$parameter WHERE name = 'compatible';
EXIT
EOF
    )

    TGT_COMPAT=$($SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$tgt_cdb as sysdba
SET HEAD OFF FEED OFF
SELECT value FROM v\$parameter WHERE name = 'compatible';
EXIT
EOF
    )

    [ "$SRC_COMPAT" != "$TGT_COMPAT" ] && \
        echo "[ERROR] Compatible parameter mismatch. Source: $SRC_COMPAT, Target: $TGT_COMPAT" && return 1

    # 6. Privilege Check on Target
    echo "Checking Target Privileges..."
    $SQLPLUS "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect /@$tgt_cdb as sysdba
SET HEAD OFF FEED OFF
SELECT 'VALID' FROM dba_sys_privs 
WHERE grantee = USER 
AND privilege = 'CREATE PLUGGABLE DATABASE';
EXIT
EOF
    [ $? -ne 0 ] && echo "[ERROR] User lacks CREATE PLUGGABLE DATABASE privilege on target" && return 1

    echo "All prechecks passed successfully!"
    return 0
}

# Process input file
while IFS="|" read -r src_cdb src_pdb tgt_cdb tgt_pdb; do
    # Skip comments and empty lines
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    
    validate_clone_prerequisites "$src_cdb" "$src_pdb" "$tgt_cdb" "$tgt_pdb" | tee -a "$LOG_FILE"
    echo -e "\n"
done < "$INPUT_FILE"

echo "Precheck completed. Review log file: $LOG_FILE"
exit 0


###
#!/bin/bash
# Refreshable PDB Clone Precheck Script with Advanced Checks
# Usage: ./pdb_clone_precheck.sh <input_file.txt> <email@domain.com>

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
HTML_FILE="pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="$2"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="Oracle PDB Clone Precheck Report"

# HTML Template Functions
html_header() {
    echo "<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
  th { background-color: #f2f2f2; }
  .pass { background-color: #dfffdf; color: #2a652a; }
  .fail { background-color: #ffe8e8; color: #a00; }
  .warning { background-color: #fff3e0; color: #c67605; }
</style>
<title>PDB Clone Precheck Report</title>
</head>
<body>
<h2>Oracle PDB Clone Precheck Report</h2>
<p>Generated at: $(date)</p>
<table>
  <tr><th>Check</th><th>Source</th><th>Target</th><th>Status</th><th>Details</th></tr>" > "$HTML_FILE"
}

html_add_row() {
    local check="$1"
    local source="$2"
    local target="$3"
    local status="$4"
    local details="$5"
    
    case $status in
        "PASS") class="pass" ;;
        "FAIL") class="fail" ;;
        *) class="warning" ;;
    esac
    
    echo "<tr>
          <td>$check</td>
          <td>$source</td>
          <td>$target</td>
          <td class='$class'>$status</td>
          <td>$details</td>
        </tr>" >> "$HTML_FILE"
}

html_footer() {
    echo "</table>
<p>Report generated by Oracle Precheck Script</p>
</body>
</html>" >> "$HTML_FILE"
}

# Database Check Functions
run_sql() {
    local conn="$1"
    local query="$2"
    $SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off
connect $conn
$query
exit
EOF
}

check_tde_settings() {
    local src_cdb="$1"
    local tgt_cdb="$2"
    
    src_tde=$(run_sql "/@$src_cdb as sysdba" "SELECT wallet_type FROM v\$encryption_wallet;")
    tgt_tde=$(run_sql "/@$tgt_cdb as sysdba" "SELECT wallet_type FROM v\$encryption_wallet;")
    
    if [ "$src_tde" != "$tgt_tde" ]; then
        echo "FAIL|TDE mismatch|Source: $src_tde|Target: $tgt_tde"
    else
        echo "PASS|TDE Match|Both using $src_tde"
    fi
}

check_charset() {
    local src_cdb="$1"
    local tgt_cdb="$2"
    
    src_charset=$(run_sql "/@$src_cdb as sysdba" "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
    tgt_charset=$(run_sql "/@$tgt_cdb as sysdba" "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
    
    if [ "$src_charset" != "$tgt_charset" ]; then
        echo "FAIL|Charset mismatch|Source: $src_charset|Target: $tgt_charset"
    else
        echo "PASS|Charset Match|$src_charset"
    fi
}

check_patch_level() {
    local src_cdb="$1"
    local tgt_cdb="$2"
    
    src_patch=$(run_sql "/@$src_cdb as sysdba" "SELECT version || ' - ' || patch_name FROM dba_registry_sqlpatch ORDER BY action_time DESC FETCH FIRST 1 ROWS ONLY;")
    tgt_patch=$(run_sql "/@$tgt_cdb as sysdba" "SELECT version || ' - ' || patch_name FROM dba_registry_sqlpatch ORDER BY action_time DESC FETCH FIRST 1 ROWS ONLY;")
    
    if [ "$src_patch" != "$tgt_patch" ]; then
        echo "FAIL|Patch mismatch|Source: $src_patch|Target: $tgt_patch"
    else
        echo "PASS|Patch Level Match|$src_patch"
    fi
}

# Main Validation Function
validate_clone_prerequisites() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    
    # Basic Checks
    checks=(
        "Source PDB Exists|$(run_sql "/@$src_cdb as sysdba" "SELECT 'PASS' FROM v\$pdbs WHERE name='$src_pdb';")|PASS|Exists"
        "Target PDB Free|$(run_sql "/@$tgt_cdb as sysdba" "SELECT 'PASS' FROM v\$pdbs WHERE name='$tgt_pdb';")|FAIL|Not exists"
        "Local Undo|$(run_sql "/@$src_cdb as sysdba" "SELECT value FROM v\$parameter WHERE name='local_undo_enabled';")|TRUE|Enabled"
    )
    
    # Advanced Checks
    tde_result=$(check_tde_settings "$src_cdb" "$tgt_cdb")
    charset_result=$(check_charset "$src_cdb" "$tgt_cdb")
    patch_result=$(check_patch_level "$src_cdb" "$tgt_cdb")
    
    # Process Results
    for check in "${checks[@]}"; do
        IFS='|' read -r desc query expect <<< "$check"
        result=$(echo "$query" | tr -d '\n')
        [ "$result" = "$expect" ] && status="PASS" || status="FAIL"
        html_add_row "$desc" "$src_cdb" "$tgt_cdb" "$status" "$result"
    done
    
    IFS='|' read -r status details <<< "$tde_result"
    html_add_row "TDE Configuration" "$src_cdb" "$tgt_cdb" "${tde_result%%|*}" "${tde_result#*|}"
    
    IFS='|' read -r status details <<< "$charset_result"
    html_add_row "Character Set" "$src_cdb" "$tgt_cdb" "${charset_result%%|*}" "${charset_result#*|}"
    
    IFS='|' read -r status details <<< "$patch_result"
    html_add_row "Patch Level" "$src_cdb" "$tgt_cdb" "${patch_result%%|*}" "${patch_result#*|}"
}

# Email Function
send_email() {
    if [ -n "$EMAIL_TO" ]; then
        mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"
        echo "Report sent to $EMAIL_TO"
    fi
}

# Main Execution
[ $# -lt 1 ] && echo "Usage: $0 <input_file.txt> [email]" && exit 1

html_header
while IFS="|" read -r src_cdb src_pdb tgt_cdb tgt_pdb; do
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    validate_clone_prerequisites "$src_cdb" "$src_pdb" "$tgt_cdb" "$tgt_pdb"
done < "$1"
html_footer
send_email

echo "Precheck completed. HTML report: $HTML_FILE"
exit 0

####
#!/bin/bash
# Enhanced PDB Clone Precheck Script with Connectivity Checks
# Usage: ./pdb_clone_precheck.sh <input_file.txt> <email@domain.com>

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
HTML_FILE="pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="$2"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="Oracle PDB Clone Precheck Report"
OVERALL_STATUS=0

# HTML Template Functions (keep existing implementation)
html_header() { ... }
html_add_row() { ... }
html_footer() { ... }

# Database Connection Validation
check_db_connectivity() {
    local cdb="$1"
    local cdb_type="$2"
    local query="SELECT 1 FROM DUAL;"
    
    echo "Checking $cdb_type connectivity ($cdb)..."
    local output=$(run_sql "/@$cdb as sysdba" "$query" 2>&1)
    
    if [ $? -ne 0 ]; then
        html_add_row "$cdb_type Connectivity" "$cdb" "N/A" "FAIL" "Connection failed: $output"
        return 1
    else
        html_add_row "$cdb_type Connectivity" "$cdb" "N/A" "PASS" "Successfully connected"
        return 0
    fi
}

# Enhanced Validation Function with Connectivity Checks
validate_clone_prerequisites() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    local status=0

    # Check source DB connectivity
    if ! check_db_connectivity "$src_cdb" "Source CDB"; then
        OVERALL_STATUS=1
        status=1
    fi

    # Check target DB connectivity
    if ! check_db_connectivity "$tgt_cdb" "Target CDB"; then
        OVERALL_STATUS=1
        status=1
    fi

    # Skip further checks if connectivity failed
    [ $status -ne 0 ] && return 1

    # Proceed with other checks (keep existing implementation)
    # TDE, Charset, Patching checks...
}

# Main Execution with Exit Code Handling
[ $# -lt 1 ] && echo "Usage: $0 <input_file.txt> [email]" && exit 1

html_header
while IFS="|" read -r src_cdb src_pdb tgt_cdb tgt_pdb; do
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    
    echo "Processing: $src_cdb/$src_pdb -> $tgt_cdb/$tgt_pdb"
    validate_clone_prerequisites "$src_cdb" "$src_pdb" "$tgt_cdb" "$tgt_pdb"
done < "$1"
html_footer

# Send email and exit with proper status
[ -n "$EMAIL_TO" ] && send_email
echo "Precheck completed. Exit code: $OVERALL_STATUS"
exit $OVERALL_STATUS


###
check_db_connectivity() {
    local cdb="$1"
    local cdb_type="$2"
    local query="SELECT 1 FROM DUAL;"
    
    echo "Checking $cdb_type connectivity ($cdb)..."
    local output=$(run_sql "/@$cdb as sysdba" "$query" 2>&1)
    
    if [ $? -ne 0 ]; then
        html_add_row "$cdb_type Connectivity" "$cdb" "N/A" "FAIL" "Connection failed: $output"
        return 1
    else
        html_add_row "$cdb_type Connectivity" "$cdb" "N/A" "PASS" "Successfully connected"
        return 0
    fi
}

###
validate_clone_prerequisites() {
    # Check source DB connectivity
    if ! check_db_connectivity "$src_cdb" "Source CDB"; then
        OVERALL_STATUS=1
        status=1
    fi

    # Check target DB connectivity
    if ! check_db_connectivity "$tgt_cdb" "Target CDB"; then
        OVERALL_STATUS=1
        status=1
    fi

    # Skip further checks if connectivity failed
    [ $status -ne 0 ] && return 1
    # ... existing checks ...
}


####
#!/bin/bash
# Refreshable PDB Clone Precheck Script with Parameter Comparison
# Usage: ./pdb_clone_precheck.sh <input_file.txt> <email@domain.com>

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
HTML_FILE="pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="$2"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="Oracle PDB Clone Precheck Report"
OVERALL_STATUS=0
EXCLUDED_PARAMS="db_name|db_unique_name|instance_name|control_files|local_listener|remote_login_passwordfile|log_archive_dest_1|dg_broker_config_file1|dg_broker_config_file2"

# HTML Template Functions (keep existing implementation)
html_header() { ... }
html_add_row() { ... }
html_footer() { ... }

# Parameter Comparison Function
compare_parameters() {
    local src_cdb="$1"
    local tgt_cdb="$2"
    local differences=0

    # Get parameters from both databases
    src_params=$(mktemp)
    tgt_params=$(mktemp)
    
    run_sql "/@$src_cdb as sysdba" "SELECT name, value FROM v\$system_parameter 
        WHERE name NOT IN (${EXCLUDED_PARAMS//|/,}) 
        ORDER BY name;" | awk -F' ' '{print $1 "|" $2}' > "$src_params"
    
    run_sql "/@$tgt_cdb as sysdba" "SELECT name, value FROM v\$system_parameter 
        WHERE name NOT IN (${EXCLUDED_PARAMS//|/,}) 
        ORDER BY name;" | awk -F' ' '{print $1 "|" $2}' > "$tgt_params"

    # Compare parameters and format output
    diff --suppress-common-lines -y "$src_params" "$tgt_params" | while read -r line; do
        param=$(echo "$line" | awk -F'|' '{print $1}' | tr -d ' ')
        src_val=$(echo "$line" | awk -F'|' '{print $2}' | awk '{$1=$1;print}')
        tgt_val=$(echo "$line" | awk -F'|' '{print $4}' | awk '{$1=$1;print}')

        html_add_row "Parameter: $param" "$src_val" "$tgt_val" "FAIL" "Parameter mismatch"
        ((differences++))
    done

    [ $differences -gt 0 ] && OVERALL_STATUS=1
    rm "$src_params" "$tgt_params"
}

# Enhanced Validation Function
validate_clone_prerequisites() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    local status=0

    # Check connectivity (existing implementation)
    # ...

    # Perform parameter comparison
    compare_parameters "$src_cdb" "$tgt_cdb"

    # Existing checks (TDE, charset, etc.)
    # ...
}

# Main Execution (keep existing flow)
# ...


###
#!/bin/bash
# Refreshable PDB Clone Precheck Script with Storage Checks
# Usage: ./pdb_clone_precheck.sh <input_file.txt> <email@domain.com>

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
HTML_FILE="pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="$2"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="Oracle PDB Clone Precheck Report"
OVERALL_STATUS=0

# Existing functions (html_header, html_add_row, html_footer, etc.)

check_max_pdb_storage() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    
    # Get source PDB storage limit
    src_storage=$(run_sql "/@$src_cdb as sysdba" "
        ALTER SESSION SET CONTAINER = $src_pdb;
        SELECT value FROM v\$parameter WHERE name = 'max_pdb_storage';")
    
    # Get target CDB storage capabilities (if target PDB exists)
    tgt_storage=$(run_sql "/@$tgt_cdb as sysdba" "
        SELECT NVL2(p.name, 
            (SELECT value FROM v\$parameter 
             WHERE name = 'max_pdb_storage' 
             AND con_id = p.con_id), 'NOT_CREATED')
        FROM v\$pdbs p WHERE p.name = '$tgt_pdb';")

    # Format comparison results
    if [ "$tgt_storage" == "NOT_CREATED" ]; then
        html_add_row "MAX_PDB_STORAGE" "$src_storage" "N/A" "INFO" "Target PDB not created"
    elif [ "$src_storage" != "$tgt_storage" ]; then
        html_add_row "MAX_PDB_STORAGE" "$src_storage" "$tgt_storage" "WARN" "Storage limit mismatch"
        OVERALL_STATUS=1
    else
        html_add_row "MAX_PDB_STORAGE" "$src_storage" "$tgt_storage" "PASS" "Storage limits match"
    fi
}

validate_clone_prerequisites() {
    local src_cdb="$1"
    local src_pdb="$2"
    local tgt_cdb="$3"
    local tgt_pdb="$4"
    local status=0

    # Existing connectivity checks...

    # MAX_PDB_STORAGE Check
    check_max_pdb_storage "$src_cdb" "$src_pdb" "$tgt_cdb" "$tgt_pdb"

    # Existing TDE, charset, patching checks...
}

# Main execution remains the same


pdb_clone_precheck/
├── precheck.conf          # Configuration variables
├── precheck_main.sh       # Main execution script
├── precheck_helpers.sh    # Core helper functions
└── precheck_db_checks.sh  # Database validation functions

1. precheck.conf (Configuration File):

bash
#!/bin/bash
# Configuration File - Edit these values for your environment

# Database Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
EXCLUDED_PARAMS="db_name|db_unique_name|instance_name|control_files|local_listener|remote_login_passwordfile"
WHITELISTED_PARAMS="compatible|db_block_size|memory_target"

# Email Configuration
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="Oracle PDB Clone Precheck Report"

# File Paths
LOG_DIR="./logs"
REPORT_DIR="./reports"


2. precheck_helpers.sh (Helper Functions):

bash
#!/bin/bash
# Helper Functions

html_header() {
    echo "<!DOCTYPE html>
<html>
<head>
<style>
  /* CSS styles */
</style>
</head>
<body>
<h2>Oracle PDB Clone Precheck Report</h2>
<p>Generated at: $(date)</p>
<table>"
}

html_add_row() {
    # Existing implementation
}

html_footer() {
    echo "</table></body></html>"
}

validate_input_file() {
    [ $# -ne 1 ] || [ ! -f "$1" ] && return 1
    return 0
}

initialize_directories() {
    mkdir -p "$LOG_DIR" "$REPORT_DIR"
}


3. precheck_db_checks.sh (Database Validation Functions):

bash
#!/bin/bash
# Database Validation Functions

check_db_connectivity() {
    # Existing implementation
}

check_tde_settings() {
    # Existing implementation
}

compare_parameters() {
    # Existing implementation
}

check_max_pdb_storage() {
    # Existing implementation
}

check_patch_level() {
    # Existing implementation
}


4. precheck_main.sh (Main Script):

bash
#!/bin/bash
# Main Execution Script

# Source configuration and functions
source ./precheck.conf
source ./precheck_helpers.sh
source ./precheck_db_checks.sh

# Initialize environment
initialize_directories
HTML_FILE="${REPORT_DIR}/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
OVERALL_STATUS=0

# Main logic
html_header > "$HTML_FILE"

while IFS="|" read -r src_cdb src_pdb tgt_cdb tgt_pdb; do
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    
    validate_clone_prerequisites "$src_cdb" "$src_pdb" "$tgt_cdb" "$tgt_pdb"
done < "$1"

html_footer >> "$HTML_FILE"
send_email
exit $OVERALL_STATUS


Directory Structure Explanation:

pdb_clone_precheck/
├── config/
│   └── precheck.conf        # Environment-specific settings
├── lib/
│   ├── precheck_helpers.sh  # Generic helper functions
│   └── precheck_db_checks.sh # Database-specific checks
├── bin/
│   └── precheck_main.sh     # Main executable script
├── logs/                    # Auto-generated logs
└── reports/                 # HTML reports
Usage Instructions:

Set Up Directory Structure:

bash
mkdir -p pdb_clone_precheck/{config,lib,bin,logs,reports}
Make Scripts Executable:

bash
chmod +x bin/precheck_main.sh
Run the Script:

bash
cd pdb_clone_precheck
bin/precheck_main.sh input_file.txt dba@company.com
##




db_health_monitor/
├── config.sh
├── dblist.txt
├── db_checks.sh
├── generate_reports.sh
└── templates/
   ├── header.html
   └── footer.html
#!/bin/bash
# Configuration
REPORTS_DIR="./reports"
SUMMARY_REPORT="summary_report_$(date +%Y%m%d).html"
CRITICAL_TABLESPACE_PCT=90
CRITICAL_ACTIVE_SESSIONS=50
CRITICAL_WAIT_SECONDS=300

# Create reports directory
mkdir -p $REPORTS_DIR

<html>
<head>
   <title>Database Health Report</title>
   <style>
       body { font-family: Arial, sans-serif; margin: 20px; }
       table { border-collapse: collapse; width: 100%; }
       th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
       .green { background-color: #dff0d8; color: #3c763d; }
       .red { background-color: #f2dede; color: #a94442; }
       th { background-color: #4CAF50; color: white; }
       a { text-decoration: none; color: #337ab7; }
   </style>
</head>
<body>

</body>
</html>

#!/bin/bash
source config.sh

generate_individual_report() {
   local db_name=$1
   local db_conn=$2
   local report_file="$REPORTS_DIR/${db_name}_report_$(date +%Y%m%d).html"

   # Create individual report
   cat templates/header.html > $report_file
   echo "<h1>${db_name} Health Report</h1>" >> $report_file
   echo "<p>Report generated: $(date)</p>" >> $report_file

   # Add database checks
   add_tablespace_check "$db_conn" "$report_file"
   add_active_sessions_check "$db_conn" "$report_file"
   add_wait_events_check "$db_conn" "$report_file"

   cat templates/footer.html >> $report_file
   echo $report_file
}

add_tablespace_check() {
   local db_conn=$1
   local report_file=$2

   echo "<h2>Tablespace Usage</h2>" >> $report_file
   sqlplus -S /nolog << EOF >> $report_file
   connect $db_conn
   set markup html on
   SELECT tablespace_name,
          round(used_space/1024/1024) used_gb,
          round(tablespace_size/1024/1024) total_gb,
          round(used_percent) pct_used
   FROM dba_tablespace_usage_metrics
   ORDER BY pct_used DESC;
   exit
EOF
}

add_active_sessions_check() {
   local db_conn=$1
   local report_file=$2

   echo "<h2>Active Sessions</h2>" >> $report_file
   sqlplus -S /nolog << EOF >> $report_file
   connect $db_conn
   set markup html on
   SELECT inst_id, COUNT(*) sessions
   FROM gv\$session
   WHERE status = 'ACTIVE'
   GROUP BY inst_id;
   exit
EOF
}

add_wait_events_check() {
   local db_conn=$1
   local report_file=$2

   echo "<h2>Top Wait Events</h2>" >> $report_file
   sqlplus -S /nolog << EOF >> $report_file
   connect $db_conn
   set markup html on
   SELECT event, total_waits,
          round(time_waited_micro/1000000) wait_seconds
   FROM (
       SELECT event, total_waits, time_waited_micro
       FROM gv\$system_event
       WHERE wait_class != 'Idle'
       ORDER BY time_waited_micro DESC
   ) WHERE rownum <= 5;
   exit
EOF
}
==
#!/bin/bash
source config.sh

# Initialize summary report
cat templates/header.html > $SUMMARY_REPORT
echo "<h1>Database Health Summary Report</h1>" >> $SUMMARY_REPORT
echo "<p>Report generated: $(date)</p>" >> $SUMMARY_REPORT
echo "<table><tr><th>Database</th><th>Status</th><th>Details</th></tr>" >> $SUMMARY_REPORT

# Process each database
while IFS='|' read -r db_name db_user db_pass db_sid; do
   db_conn="$db_user/$db_pass@$db_sid"

   # Generate individual report
   report_path=$(generate_individual_report "$db_name" "$db_conn")

   # Check status
   status_check=$(check_database_status "$db_conn")

   # Add to summary report
   echo "<tr>" >> $SUMMARY_REPORT
   echo "<td>$db_name</td>" >> $SUMMARY_REPORT
   echo "<td class='$status_check'>${status_check^^}</td>" >> $SUMMARY_REPORT
   echo "<td><a href='$report_path'>View Details</a></td>" >> $SUMMARY_REPORT
   echo "</tr>" >> $SUMMARY_REPORT

done < dblist.txt

# Complete summary report
echo "</table>" >> $SUMMARY_REPORT
cat templates/footer.html >> $SUMMARY_REPORT

echo "Summary report generated: $SUMMARY_REPORT"

===
check_database_status() {
   local db_conn=$1
   local status="green"

   # Check tablespace usage
   ts_usage=$(sqlplus -S /nolog << EOF
   connect $db_conn
   set pagesize 0 feedback off
   SELECT MAX(used_percent) FROM dba_tablespace_usage_metrics;
   exit
EOF
)
   if (( $(echo "$ts_usage > $CRITICAL_TABLESPACE_PCT" | bc -l) )); then
       status="red"
   fi

   # Check active sessions
   active_sessions=$(sqlplus -S /nolog << EOF
   connect $db_conn
   set pagesize 0 feedback off
   SELECT COUNT(*) FROM gv\$session WHERE status = 'ACTIVE';
   exit
EOF
)
   if [ $active_sessions -gt $CRITICAL_ACTIVE_SESSIONS ]; then
       status="red"
   fi

   echo $status
}



#!/bin/bash

# Usage: ./rac_resize_redologs.sh <input_file> <new_size>
# Example: ./rac_resize_redologs.sh rac_config.txt 1G
# Input file format:
#   primary_scan primary_db
#   standby_scan standby_db

# Check input parameters
if [ $# -ne 2 ]; then
  echo "Usage: $0 <input_file> <new_size>"
  exit 1
fi

INPUT_FILE="$1"
NEW_SIZE="$2"
PRIMARY_HOST=$(awk 'NR==1 {print $1}' "$INPUT_FILE")
PRIMARY_DB=$(awk 'NR==1 {print $2}' "$INPUT_FILE")
STANDBY_HOST=$(awk 'NR==2 {print $1}' "$INPUT_FILE")
STANDBY_DB=$(awk 'NR==2 {print $2}' "$INPUT_FILE")
DG_USER="sys"
LOG_FILE="rac_redolog_resize_$(date +%Y%m%d_%H%M).log"

# Validate input
if [[ -z "$PRIMARY_HOST" || -z "$PRIMARY_DB" || 
      -z "$STANDBY_HOST" || -z "$STANDBY_DB" || -z "$NEW_SIZE" ]]; then
  echo "Invalid input file format. Expected:"
  echo "primary_scan primary_db"
  echo "standby_scan standby_db"
  exit 1
fi

# Get SYS password
read -s -p "Enter SYS password for ${PRIMARY_HOST}/${PRIMARY_DB}: " SYS_PASSWORD
echo

# Function to log messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Verify database role
verify_role() {
  local host=$1
  local db=$2
  local expected_role=$3
  
  role=$(sqlplus -S "${DG_USER}/${SYS_PASSWORD}@//${host}:1521/${db} as sysdba" << EOF
    SET HEADING OFF FEEDBACK OFF PAGESIZE 0
    SELECT database_role FROM v\$database;
    EXIT;
EOF
  )
  if [[ "$role" != "$expected_role" ]]; then
    log "Error: ${host}/${db} is not a ${expected_role} (Role: ${role})"
    exit 1
  fi
  log "${expected_role} database confirmed"
}

# Enhanced online redo log resize with active log handling
resize_online_redologs() {
  local host=$1
  local db=$2
  log "Resizing ONLINE redo logs on ${db} (RAC) to ${NEW_SIZE}..."
  
  sqlplus -S "${DG_USER}/${SYS_PASSWORD}@//${host}:1521/${db} as sysdba" << EOF >> "$LOG_FILE" 2>&1
    SET SERVEROUTPUT ON
    DECLARE
      TYPE thread_t IS TABLE OF NUMBER;
      threads thread_t;
      groups_per_thread NUMBER;
      max_retries NUMBER := 5;
      retry_interval NUMBER := 10; -- seconds
      
      -- Procedure to drop old logs with retries
      PROCEDURE drop_old_logs IS
        CURSOR old_groups_cur IS 
          SELECT group#, thread#, status 
          FROM v\$log 
          WHERE bytes < (SELECT MAX(bytes) FROM v\$log);
      BEGIN
        FOR oldgrp IN old_groups_cur LOOP
          DECLARE
            retries NUMBER := 0;
            current_status VARCHAR2(10);
          BEGIN
            current_status := oldgrp.status;
            
            WHILE current_status != 'INACTIVE' AND retries < max_retries LOOP
              DBMS_OUTPUT.PUT_LINE('Thread ' || oldgrp.thread# || 
                ' Group ' || oldgrp.group# || ' still ' || current_status ||
                ' - forcing log switch (attempt ' || (retries+1) || ')');
                
              -- Force log switch for specific thread
              BEGIN
                EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE THREAD ' || oldgrp.thread#;
              EXCEPTION
                WHEN OTHERS THEN NULL;
              END;
              
              -- Wait for status change
              DBMS_LOCK.SLEEP(retry_interval);
              
              -- Check current status
              BEGIN
                SELECT status INTO current_status
                FROM v\$log
                WHERE group# = oldgrp.group#;
              EXCEPTION
                WHEN OTHERS THEN
                  current_status := 'UNKNOWN';
              END;
              
              retries := retries + 1;
            END LOOP;
            
            IF current_status = 'INACTIVE' THEN
              BEGIN
                EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP ' || oldgrp.group#;
                DBMS_OUTPUT.PUT_LINE('Dropped group ' || oldgrp.group#);
              EXCEPTION
                WHEN OTHERS THEN
                  DBMS_OUTPUT.PUT_LINE('Error dropping group ' || oldgrp.group# || ': ' || SQLERRM);
              END;
            ELSE
              DBMS_OUTPUT.PUT_LINE('Failed to drop group ' || oldgrp.group# || 
                ' - still ' || current_status || ' after ' || max_retries || ' attempts');
            END IF;
          END;
        END LOOP;
      END drop_old_logs;

    BEGIN
      -- Get active threads
      SELECT thread# BULK COLLECT INTO threads FROM v\$thread;

      -- Get current online log groups per thread
      SELECT COUNT(*)/COUNT(DISTINCT thread#) INTO groups_per_thread FROM v\$log;

      -- Add new log groups for each thread
      FOR i IN 1..threads.COUNT LOOP
        FOR j IN 1..groups_per_thread LOOP
          EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE THREAD ' || threads(i) || 
                            ' SIZE ${NEW_SIZE}';
        END LOOP;
      END LOOP;

      -- Force log switches across all threads
      FOR thread_rec IN (SELECT thread# FROM v\$thread) LOOP
        FOR k IN 1..(groups_per_thread * 2) LOOP
          EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE THREAD ' || thread_rec.thread#;
        END LOOP;
      END LOOP;

      -- Drop old logs with retry mechanism
      drop_old_logs;
      
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
    END;
    /
    EXIT;
EOF

  if grep -q "ORA-" "$LOG_FILE"; then
    log "Error resizing online redo logs on ${db}"
    return 1
  fi
  log "Online redo logs resized successfully on ${db} (RAC)"
}

# Other functions remain unchanged (resize_standby_redologs, manage_mrp, etc.)

# Main execution
{
  log "Starting RAC Redo Log Resize Operation"
  verify_role "$PRIMARY_HOST" "$PRIMARY_DB" "PRIMARY"
  verify_role "$STANDBY_HOST" "$STANDBY_DB" "PHYSICAL STANDBY"

  # Process standby
  manage_mrp "OFF"
  manage_standby_file_management "$STANDBY_HOST" "$STANDBY_DB" "MANUAL"
  resize_online_redologs "$STANDBY_HOST" "$STANDBY_DB"
  resize_standby_redologs "$STANDBY_HOST" "$STANDBY_DB"
  manage_standby_file_management "$STANDBY_HOST" "$STANDBY_DB" "AUTO"
  manage_mrp "ON"

  # Process primary
  resize_online_redologs "$PRIMARY_HOST" "$PRIMARY_DB"
  resize_standby_redologs "$PRIMARY_HOST" "$PRIMARY_DB"

  # Verification steps
  log "Operation completed successfully"
} | tee -a "$LOG_FILE"

echo "Detailed log saved to: ${LOG_FILE}"

##########################
#!/bin/bash

# Usage: ./rac_health_scan.sh <input_file>
# Input file format (single line):
#   scan_host db_name

# Check input file
if [ $# -ne 1 ]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"
SCAN_HOST=$(awk '{print $1}' "$INPUT_FILE")
DB_NAME=$(awk '{print $2}' "$INPUT_FILE")
REPORT_FILE="rac_health_$(date +%Y%m%d_%H%M).html"

# Validate input
if [[ -z "$SCAN_HOST" || -z "$DB_NAME" ]]; then
  echo "Invalid input file format. Expected:"
  echo "scan_host db_name"
  exit 1
fi

# Get SYS password
read -s -p "Enter SYS password for ${SCAN_HOST}/${DB_NAME}: " SYS_PASSWORD
echo

# HTML Header
cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
  <title>RAC Health Check: ${DB_NAME}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h2 { color: #2c3e50; border-bottom: 2px solid #3498db; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
    tr:hover { background-color: #f5f5f5; }
    .critical { color: #e74c3c; font-weight: bold; }
    .warning { color: #f39c12; }
    .ok { color: #27ae60; }
  </style>
</head>
<body>
  <h1>Oracle RAC Health Report: ${DB_NAME}</h1>
  <p>Generated at: $(date)</p>
  <p>SCAN Name: ${SCAN_HOST}</p>
EOF

# Function to run SQL and format as HTML table
run_sql_to_html() {
  local title="$1"
  local query="$2"
  local critical="$3"
  
  echo "<h2>${title}</h2>" >> "$REPORT_FILE"
  
  sqlplus -S "sys/${SYS_PASSWORD}@//${SCAN_HOST}:1521/${DB_NAME} as sysdba" << EOF | awk '
    BEGIN { print "<table>"; print "<tr><th>Metric</th><th>Value</th></tr>" }
    /^ERROR/ { print "<tr class=\"critical\"><td colspan=\"2\">" $0 "</td></tr>" }
    /=/ { 
      split($0, arr, "="); 
      cls = "";
      if (arr[2] ~ /CRITICAL/) cls = "critical";
      if (arr[2] ~ /WARNING/) cls = "warning";
      print "<tr><td>" arr[1] "</td><td class=\"" cls "\">" arr[2] "</td></tr>" 
    }
    END { print "</table>" }
  ' >> "$REPORT_FILE"
  
    SET FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 1000
    ${query}
    EXIT
EOF
}

# RAC Node Status
run_sql_to_html "Cluster Node Status" "
  SELECT 'Node ' || instance_number || ': ' || 
         instance_name || ' (' || host_name || ')' || '=' ||
         status || ' | Version: ' || version || ' | Startup: ' || 
         TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI')
  FROM gv\$instance;
"

# Wait Events Analysis
run_sql_to_html "Top Wait Events (Non-Idle)" "
  SELECT event || '=' || 
         ROUND(time_waited_micro/1000000,1) || 's (Waits: ' || 
         total_waits || ', Avg: ' || 
         ROUND(time_waited_micro/total_waits/1000,2) || 'ms)'
  FROM (
    SELECT event, total_waits, time_waited_micro
    FROM gv\$system_event 
    WHERE wait_class NOT IN ('Idle', 'System I/O')
    ORDER BY time_waited_micro DESC
    FETCH FIRST 10 ROWS ONLY
  );
"

# Global Cache Statistics
run_sql_to_html "Global Cache Performance" "
  SELECT 
    'Global Cache CR Block Receive Time (ms)' || '=' ||
    ROUND((SUM(CASE name WHEN 'gc cr block receive time' THEN value END) /
           SUM(CASE name WHEN 'gc cr blocks received' THEN value END)) * 10,2)
    || 'ms [CR] | ' ||
    ROUND((SUM(CASE name WHEN 'gc current block receive time' THEN value END) /
           SUM(CASE name WHEN 'gc current blocks received' THEN value END)) * 10,2)
    || 'ms [Current]'
  FROM gv\$sysstat
  WHERE name IN (
    'gc cr block receive time', 'gc cr blocks received',
    'gc current block receive time', 'gc current blocks received'
  );
"

# Tablespace Usage
run_sql_to_html "Tablespace Usage" "
  SELECT tablespace_name || '=' || 
         ROUND(used_percent,1) || '% used | ' ||
         CASE WHEN used_percent > 90 THEN 'CRITICAL' 
              WHEN used_percent > 80 THEN 'WARNING' 
              ELSE 'OK' END
  FROM (
    SELECT a.tablespace_name, 
           (a.bytes_alloc - nvl(b.bytes_free,0))/a.bytes_alloc*100 used_percent
    FROM (
      SELECT tablespace_name, SUM(bytes) bytes_alloc
      FROM dba_data_files GROUP BY tablespace_name
    ) a,
    (
      SELECT tablespace_name, SUM(bytes) bytes_free
      FROM dba_free_space GROUP BY tablespace_name
    ) b
    WHERE a.tablespace_name = b.tablespace_name(+)
  )
  ORDER BY used_percent DESC;
"

# Cluster Interconnect
run_sql_to_html "Interconnect Health" "
  SELECT 
    'Network Latency (' || name || ')' || '=' ||
    ROUND(value/100,2) || 'ms' ||
    CASE WHEN value/100 > 2 THEN ' CRITICAL' 
         WHEN value/100 > 1 THEN ' WARNING' ELSE '' END
  FROM gv\$sysmetric 
  WHERE metric_name = 'Network Latency'
    AND group_id = 2
    AND value > 0;
"

# HTML Footer
cat >> "$REPORT_FILE" << EOF
</body>
</html>
EOF

echo -e "\nReport generated: ${REPORT_FILE}"

#!/bin/bash
# Oracle DB Health Check with HTML Email using mail command

# Configuration
DB_USER="sys as sysdba"
DB_PASS="your_password"
DB_SID="ORCL"
REPORT_FILE="/tmp/db_health_$(date +%Y%m%d).html"
EMAIL_TO="dba@company.com"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="DB Health Report - $(date +%F)"

# Function: Send HTML email using mail
send_email() {
    local report_file="$1"
    local subject="$2"
    local recipient="$3"
    local sender="$4"
    
    if ! command -v mail >/dev/null; then
        echo "Error: mail command not found!"
        return 1
    fi

    # Send email with HTML headers
    mail -s "$subject" -a "From: $sender" -a "Content-Type: text/html" "$recipient" < "$report_file"
    
    return $?
}

# Function: Run SQL and format as HTML table
run_sql_html() {
    local sql_query="$1"
    local section_title="$2"
    
    echo "<h2>$section_title</h2>" >> "$REPORT_FILE"
    
    sqlplus -S /nolog << EOF >> "$REPORT_FILE"
    connect $DB_USER/$DB_PASS@$DB_SID
    
    set markup html on table "class='sql-table'"
    set pagesize 500
    set linesize 200
    set feedback off
    set heading on
    
    $sql_query
    exit
EOF
}

# Generate HTML Report
{
echo "<html>
<head>
<title>Database Health Report</title>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h1 { color: #2c3e50; }
  h2 { color: #3498db; border-bottom: 2px solid #3498db; }
  table { border-collapse: collapse; width: 100%; margin: 20px 0; }
  th { background-color: #3498db; color: white; padding: 10px; }
  td { padding: 8px; border: 1px solid #ddd; }
  tr:nth-child(even) { background-color: #f2f2f2; }
  .critical { color: #e74c3c; font-weight: bold; }
</style>
</head>
<body>
<h1>Database Health Report</h1>
<p>Generated: $(date)</p>"
} > "$REPORT_FILE"

# Run health checks
run_sql_html "SELECT name, open_mode, log_mode, created FROM v\$database;" "Database Status"
run_sql_html "SELECT inst_id, instance_name, status, host_name FROM gv\$instance;" "Instance Status"
run_sql_html "SELECT tablespace_name, 
    round(used_space/1024/1024) used_gb,
    round(tablespace_size/1024/1024) total_gb,
    round(used_percent) pct_used
    FROM dba_tablespace_usage_metrics
    ORDER BY pct_used DESC;" "Tablespace Usage"

run_sql_html "SELECT event, total_waits, 
    round(time_waited_micro/1000000) wait_sec
    FROM (
        SELECT event, total_waits, time_waited_micro
        FROM v\$system_event
        WHERE wait_class != 'Idle'
        ORDER BY time_waited_micro DESC
    ) WHERE rownum <= 5;" "Top 5 Wait Events"

echo "</body></html>" >> "$REPORT_FILE"

# Send email with error handling
if send_email "$REPORT_FILE" "$EMAIL_SUBJECT" "$EMAIL_TO" "$EMAIL_FROM"; then
    echo "Health report sent successfully to $EMAIL_TO"
else
    echo "Failed to send health report" >&2
    exit 1
fi

# Cleanup
rm -f "$REPORT_FILE"


send_email() {
  local host_entry="$1"
  local report_file="$2"

  local max_inline_size=2097152  # 2MB
  local file_size
  file_size=$(stat -c%s "$report_file")

  if [[ "$file_size" -le "$max_inline_size" ]]; then
    # Try sendmail first for inline HTML
    if command -v sendmail > /dev/null 2>&1; then
      {
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $EMAIL_SUBJECT - $host_entry"
        echo "Content-Type: text/html"
        echo
        cat "$report_file"
      } | sendmail -t
      log_msg "Email sent as inline HTML using sendmail for $host_entry"
    elif command -v mailx > /dev/null 2>&1; then
      mailx -a "Content-Type: text/html" -s "$EMAIL_SUBJECT - $host_entry" "$EMAIL_RECIPIENT" < "$report_file"
      log_msg "Email sent as inline HTML using mailx for $host_entry"
    else
      log_msg "ERROR: Neither sendmail nor mailx available for sending inline HTML email."
    fi
  else
    # Compress report and attach
    local zip_file="${report_file%.html}.zip"
    zip -j "$zip_file" "$report_file" > /dev/null

    if command -v sendmail > /dev/null 2>&1; then
      {
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $EMAIL_SUBJECT - $host_entry (Attached)"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary="MIXED-BOUNDARY""
        echo
        echo "--MIXED-BOUNDARY"
        echo "Content-Type: text/plain"
        echo
        echo "Health check report for $host_entry is attached (compressed)."
        echo
        echo "--MIXED-BOUNDARY"
        echo "Content-Type: application/zip; name="$(basename "$zip_file")""
        echo "Content-Disposition: attachment; filename="$(basename "$zip_file")""
        echo "Content-Transfer-Encoding: base64"
        echo
        base64 "$zip_file"
        echo "--MIXED-BOUNDARY--"
      } | sendmail -t
      log_msg "Email with ZIP attachment sent using sendmail for $host_entry"
    elif command -v mailx > /dev/null 2>&1; then
      echo "Health check report for $host_entry is attached (compressed)." | mailx -a "$zip_file" -s "$EMAIL_SUBJECT - $host_entry (Attached)" "$EMAIL_RECIPIENT"
      log_msg "Email with ZIP attachment sent using mailx for $host_entry"
    else
      log_msg "ERROR: Neither sendmail nor mailx available for sending ZIP attachment."
    fi
  fi
}
