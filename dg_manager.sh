echo "Select Standby Mode:"
echo "1) Single Instance Standby"
echo "2) RAC Standby (Multi-Instance)"
read -rp "Enter choice [1-2]: " mode_choice

if [ "$mode_choice" == "1" ]; then
    IS_RAC=false
else
    IS_RAC=true
fi

read -rp "Enter Primary Database Hostname: " PRIMARY_HOST
read -rp "Enter Primary Database Name (SID): " PRIMARY_DB_NAME
read -rp "Enter Primary TNS Connection Name: " PRIMARY_DB_CONN

read -rp "Enter Standby Database Name (SID): " STANDBY_DB_NAME
read -rp "Enter Standby Database Unique Name: " STANDBY_DB_UNIQUE_NAME

if [ "$IS_RAC" == "true" ]; then
    echo "Enter Standby Hostnames (space separated): "
    read -ra STANDBY_HOSTS_ARRAY
else
    read -rp "Enter Standby Hostname: " STANDBY_HOST_SINGLE
    STANDBY_HOSTS_ARRAY=("$STANDBY_HOST_SINGLE")
fi

read -rp "Enter SYS Password: " SYS_PASS

read -rp "Enter ASM Diskgroup for Datafiles (ex: +DATA01): " ASM_DISKGROUP_DATA
read -rp "Enter ASM Diskgroup for Redo Logs (ex: +DATA01): " ASM_DISKGROUP_REDO

#########################
validate_rman_connections() {
  local PRIMARY_CONN="$1"
  local STANDBY_CONN="$2"

  echo "Validating RMAN connection to Primary Database ($PRIMARY_CONN)..."
  rman target sys/$SYS_PASS@$PRIMARY_CONN auxiliary / <<EOF
exit
EOF
  if [ $? -ne 0 ]; then
    echo "ERROR: RMAN connection to Primary failed."
    exit 1
  fi

  echo "Validating RMAN connection to Standby Database ($STANDBY_CONN)..."
  rman target / auxiliary sys/$SYS_PASS@$STANDBY_CONN <<EOF
exit
EOF
  if [ $? -ne 0 ]; then
    echo "ERROR: RMAN connection to Standby failed."
    exit 1
  fi

  echo "RMAN connection validation successful."
}

#################

# standby_create_driver.sh

#!/bin/bash

set -euo pipefail

# Load configuration and functions
source ./standby_create.conf
source ./functions_standby_rac.sh

log "Starting Standby Creation Process"

# Step 1: Perform pre-checks
precheck_standby_environment

# Step 2: Create required adump directories dynamically for each host
create_required_directories_standby "$STANDBY_DB_UNIQUE_NAME"

# Step 3: Check for Password File
check_password_file

# Step 4: Validate RMAN Connections
validate_rman_connections "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME"

# Step 5: Prepare and start RMAN DUPLICATE in nohup
log "Preparing RMAN DUPLICATE command for Standby creation."

cat > duplicate_standby.rman <<EOF
CONNECT TARGET sys/$SYS_PASS@$PRIMARY_DB_CONN
CONNECT AUXILIARY sys/$SYS_PASS@$STANDBY_DB_NAME

DUPLICATE TARGET DATABASE
  FOR STANDBY
  FROM ACTIVE DATABASE
  DORECOVER
  SPFILE
  SET DB_UNIQUE_NAME='$STANDBY_DB_UNIQUE_NAME'
  SET CLUSTER_DATABASE='${IS_RAC,,}'
  SET LOG_FILE_NAME_CONVERT='$PRIMARY_REDO_PATH','$ASM_DISKGROUP_REDO'
  SET DB_FILE_NAME_CONVERT='$PRIMARY_DATAFILE_PATH','$ASM_DISKGROUP_DATA'
  NOFILENAMECHECK;
EXIT;
EOF

log "Starting RMAN DUPLICATE in background using nohup..."
nohup rman cmdfile=duplicate_standby.rman log=duplicate_standby.log &
RMAN_PID=$!

log "Waiting for RMAN process (PID=$RMAN_PID) to finish..."
wait $RMAN_PID || true

# Step 6: Check completion and send email notification
STATUS=$(check_rman_duplicate_completion duplicate_standby.log)
send_email_notification duplicate_standby.log "$STATUS" "$EMAIL_TO"

if [ "$STATUS" != "SUCCESS" ]; then
  log "RMAN duplicate failed. Exiting."
  exit 1
fi

# Step 7: Add standby database and start it to mount stage
add_and_start_standby_database "$STANDBY_DB_NAME" "$STANDBY_DB_UNIQUE_NAME" "$ORACLE_HOME" "$PRIMARY_REDO_PATH" "$ASM_DISKGROUP_REDO"

# Step 8: Create redo and standby redo logs
create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP_REDO"

# Step 9: Start MRP process
start_mrp_via_dgmgrl

# Step 10: Check Data Guard sync status
check_dg_sync_status

# Step 11: Post Steps Reminder
log "Post Steps Reminder:"
echo "- Verify all instances registered correctly with srvctl if RAC."
echo "- Data Guard sync status already validated."

log "Standby Creation Process Completed Successfully"

#############################

#!/bin/bash

set -euo pipefail

# Load configuration and functions
source ./standby_create.conf

# Perform Precheck
precheck_standby_environment

# Create required directories on both standby nodes
create_required_directories_standby "$STANDBY_HOST1" "$STANDBY_HOST2" "$STANDBY_DB_UNIQUE_NAME"

# Startup NOMOUNT standby instance manually (assumed done externally if using RAC)

# RMAN DUPLICATE FOR STANDBY (Manual step assumed or can be scripted separately)

# After RMAN duplication and spfile adjustments, create redo and standby redo logs
create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"

# Post-configuration instructions
cat <<EOF

##########################################
# Post Steps
##########################################
- Ensure RMAN DUPLICATE completed successfully.
- Verify the RAC standby database is registered with SRVCTL.
- Register standby database into Data Guard Broker:
  dgmgrl sys/\$SYS_PASS@\$PRIMARY_DB_CONN
  ADD DATABASE '$STANDBY_DB_UNIQUE_NAME' AS CONNECT IDENTIFIER IS '$STANDBY_DB_NAME' MAINTAINED AS PHYSICAL;
  ENABLE DATABASE '$STANDBY_DB_UNIQUE_NAME';
- Start Managed Recovery:
  dgmgrl> EDIT DATABASE '$STANDBY_DB_UNIQUE_NAME' SET STATE='APPLY-ON';

EOF

exit 0
##
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

################################
File	Purpose
standby_create.conf	Configuration variables (primary, standby, paths, ASM, SYS password)
functions_standby_rac.sh	Functions (precheck, directory creation, redo/standby redo setup)
standby_create_driver.sh	Main driver script (load config + functions + step execution)

#################################

log "Preparing RMAN DUPLICATE command for Standby creation."

# Create RMAN command file
cat > duplicate_standby.rman <<EOF
CONNECT TARGET sys/$SYS_PASS@$PRIMARY_DB_CONN
CONNECT AUXILIARY sys/$SYS_PASS@$STANDBY_DB_NAME

DUPLICATE TARGET DATABASE
  FOR STANDBY
  FROM ACTIVE DATABASE
  DORECOVER
  SPFILE
  SET DB_UNIQUE_NAME='$STANDBY_DB_UNIQUE_NAME'
  SET CLUSTER_DATABASE='true'
  SET LOG_FILE_NAME_CONVERT='$PRIMARY_REDO_PATH','$STANDBY_REDO_PATH'
  SET DB_FILE_NAME_CONVERT='$PRIMARY_DATAFILE_PATH','$STANDBY_DATAFILE_PATH'
  NOFILENAMECHECK;
EXIT;
EOF

# Run RMAN DUPLICATE in nohup
log "Starting RMAN DUPLICATE in nohup mode..."
nohup rman cmdfile=duplicate_standby.rman log=duplicate_standby.log &

log "RMAN DUPLICATE started. Monitor progress with: tail -f duplicate_standby.log"

##############

create_required_directories_standby() {
  local DBNAME="$1"

  for host in "${STANDBY_HOSTS[@]}"; do
    log "Creating adump directory on $host"
    ssh oracle@"$host" bash <<EOF
mkdir -p /u01/app/oracle/admin/${DBNAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${DBNAME}/adump
EOF
  done

  log "Adump directories created on all standby nodes."
}
create_single_standby() {
  precheck_standby_environment
  create_required_directories_standby "$STANDBY_HOST1" "$STANDBY_HOST1" "$STANDBY_DB_UNIQUE_NAME"
  
  start_rman_duplicate

  STATUS=$(check_rman_duplicate_completion duplicate_standby.log)
  send_email_notification duplicate_standby.log "$STATUS" "$EMAIL_TO"

  if [ "$STATUS" != "SUCCESS" ]; then
    log "RMAN duplicate failed for single standby. Exiting."
    exit 1
  fi

  create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"
}
create_multiple_standby() {
  # You may loop over multiple standby DB names/hosts loaded from a file or array
  for standby in "${STANDBY_LIST[@]}"; do
    log "Starting creation for Standby Database: $standby"

    # Adjust STANDBY_DB_NAME etc dynamically here
    # (Load from file, or input parameters)

    precheck_standby_environment
    create_required_directories_standby "$STANDBY_HOST1" "$STANDBY_HOST2" "$STANDBY_DB_UNIQUE_NAME"

    start_rman_duplicate

    STATUS=$(check_rman_duplicate_completion duplicate_standby.log)
    send_email_notification duplicate_standby.log "$STATUS" "$EMAIL_TO"

    if [ "$STATUS" != "SUCCESS" ]; then
      log "RMAN duplicate failed for standby $standby. Exiting."
      exit 1
    fi

    create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"
  done
}
create_single_standby() {
  precheck_standby_environment
  create_required_directories_standby "$STANDBY_HOST1" "$STANDBY_HOST2" "$STANDBY_DB_UNIQUE_NAME"
  
  start_rman_duplicate

  STATUS=$(check_rman_duplicate_completion duplicate_standby.log)
  send_email_notification duplicate_standby.log "$STATUS" "$EMAIL_TO"

  if [ "$STATUS" != "SUCCESS" ]; then
    log "RMAN duplicate failed for single standby. Exiting."
    exit 1
  fi

  create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"
}
log "Please select standby creation mode:"
echo "1) Single Standby Database"
echo "2) Multiple Standby Databases"
read -rp "Enter your choice [1-2]: " standby_choice

case "$standby_choice" in
  1)
    log "Single Standby Database creation selected."
    create_single_standby
    ;;
  2)
    log "Multiple Standby Databases creation selected."
    create_multiple_standby
    ;;
  *)
    echo "Invalid selection. Exiting."
    exit 1
    ;;
esac
# After starting RMAN nohup
log "Waiting for RMAN duplicate to complete..."
wait

log "Checking RMAN duplicate completion..."
STATUS=$(check_rman_duplicate_completion duplicate_standby.log)

log "Sending email notification..."
send_email_notification duplicate_standby.log "$STATUS" "DBA@example.com"

if [ "$STATUS" = "SUCCESS" ]; then
  log "RMAN duplicate completed successfully. Proceeding to redo creation."
  create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP"
else
  log "RMAN duplicate failed. Please check duplicate_standby.log manually."
  exit 1
fi
send_email_notification() {
  local LOGFILE=$1
  local STATUS=$2
  local MAIL_TO=$3
  local SUBJECT="Standby RAC RMAN DUPLICATE - $STATUS"

  if [ -s "$LOGFILE" ]; then
    if [ $(stat -c%s "$LOGFILE") -lt 1000000 ]; then
      # If file size <1MB, send content in email
      mailx -s "$SUBJECT" "$MAIL_TO" < "$LOGFILE"
    else
      # If file size >=1MB, attach the file
      uuencode "$LOGFILE" "$LOGFILE" | mailx -s "$SUBJECT" "$MAIL_TO"
    fi
  fi
}
check_rman_duplicate_completion() {
  local LOGFILE=$1

  if grep -q "Finished Duplicate Db" "$LOGFILE"; then
    echo "SUCCESS"
  else
    echo "FAILURE"
  fi
}
log "Preparing RMAN DUPLICATE command for Standby creation."

# Create RMAN command file
cat > duplicate_standby.rman <<EOF
CONNECT TARGET sys/$SYS_PASS@$PRIMARY_DB_CONN
CONNECT AUXILIARY sys/$SYS_PASS@$STANDBY_DB_NAME

DUPLICATE TARGET DATABASE
  FOR STANDBY
  FROM ACTIVE DATABASE
  DORECOVER
  SPFILE
  SET DB_UNIQUE_NAME='$STANDBY_DB_UNIQUE_NAME'
  SET CLUSTER_DATABASE='true'
  SET LOG_FILE_NAME_CONVERT='$PRIMARY_REDO_PATH','$STANDBY_REDO_PATH'
  SET DB_FILE_NAME_CONVERT='$PRIMARY_DATAFILE_PATH','$STANDBY_DATAFILE_PATH'
  NOFILENAMECHECK;
EXIT;
EOF

# Run RMAN DUPLICATE in nohup
log "Starting RMAN DUPLICATE in nohup mode..."
nohup rman cmdfile=duplicate_standby.rman log=duplicate_standby.log &

log "RMAN DUPLICATE started. Monitor progress with: tail -f duplicate_standby.log"
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

start_mrp_via_dgmgrl() {
  log "Starting MRP via Data Guard Broker (dgmgrl)..."
  dgmgrl sys/$SYS_PASS@$PRIMARY_DB_CONN <<EOF
EDIT DATABASE "$STANDBY_DB_UNIQUE_NAME" SET STATE='APPLY-ON';
EXIT;
EOF
}

add_and_start_standby_database() {
  local DBNAME="$1"
  local DBUNIQUE="$2"
  local ORACLE_HOME_PATH="$3"
  local PRIMARY_REDO_PATH="$4"
  local ASM_DISKGROUP_REDO="$5"

  log "Adding Standby database into srvctl registry..."

  srvctl add database \
    -d "$DBUNIQUE" \
    -o "$ORACLE_HOME_PATH" \
    -p "$ORACLE_HOME_PATH/dbs/spfile${DBNAME}.ora" \
    -r PHYSICAL_STANDBY \
    -s MOUNT \
    -t "$PRIMARY_REDO_PATH","$ASM_DISKGROUP_REDO"

  log "Starting Standby database into mount stage..."
  srvctl start database -d "$DBUNIQUE" -o mount
}

###
validate_rman_connections() {
  local PRIMARY_CONN="$1"
  local STANDBY_CONN="$2"

  echo "Validating RMAN connection to Primary Database ($PRIMARY_CONN)..."
  rman target sys/$SYS_PASS@$PRIMARY_CONN auxiliary / <<EOF
exit
EOF
  if [ $? -ne 0 ]; then
    echo "ERROR: RMAN connection to Primary failed."
    exit 1
  fi

  echo "Validating RMAN connection to Standby Database ($STANDBY_CONN)..."
  rman target / auxiliary sys/$SYS_PASS@$STANDBY_CONN <<EOF
exit
EOF
  if [ $? -ne 0 ]; then
    echo "ERROR: RMAN connection to Standby failed."
    exit 1
  fi

  echo "RMAN connection validation successful."
}
echo "Select Standby Mode:"
echo "1) Single Instance Standby"
echo "2) RAC Standby (Multi-Instance)"
read -rp "Enter choice [1-2]: " mode_choice

if [ "$mode_choice" == "1" ]; then
    IS_RAC=false
else
    IS_RAC=true
fi

read -rp "Enter Primary Database Hostname: " PRIMARY_HOST
read -rp "Enter Primary Database Name (SID): " PRIMARY_DB_NAME
read -rp "Enter Primary TNS Connection Name: " PRIMARY_DB_CONN

read -rp "Enter Standby Database Name (SID): " STANDBY_DB_NAME
read -rp "Enter Standby Database Unique Name: " STANDBY_DB_UNIQUE_NAME

if [ "$IS_RAC" == "true" ]; then
    echo "Enter Standby Hostnames (space separated): "
    read -ra STANDBY_HOSTS_ARRAY
else
    read -rp "Enter Standby Hostname: " STANDBY_HOST_SINGLE
    STANDBY_HOSTS_ARRAY=("$STANDBY_HOST_SINGLE")
fi

read -rp "Enter SYS Password: " SYS_PASS

read -rp "Enter ASM Diskgroup for Datafiles (ex: +DATA01): " ASM_DISKGROUP_DATA
read -rp "Enter ASM Diskgroup for Redo Logs (ex: +DATA01): " ASM_DISKGROUP_REDO
check_password_file() {
  local pwfile="$ORACLE_HOME/dbs/orapw$STANDBY_DB_NAME"

  if [ ! -f "$pwfile" ]; then
    log "ERROR: Password file $pwfile not found."
    log "Please manually copy the password file from Primary ASM:"
    echo "1) Find password file on Primary:"
    echo "   asmcmd find +DATA01 PROD/pwd*"
    echo "2) Copy it locally:"
    echo "   asmcmd cp +DATA01/PROD/PASSWORD/pwdPROD /tmp/orapwPROD"
    echo "3) SCP to Standby and rename as needed:"
    echo "   scp /tmp/orapwPROD standbyhost:/tmp/"
    echo "   mv /tmp/orapwPROD \$ORACLE_HOME/dbs/orapw$STANDBY_DB_NAME"
    echo "   chown oracle:oinstall \$ORACLE_HOME/dbs/orapw$STANDBY_DB_NAME"
    echo "   chmod 600 \$ORACLE_HOME/dbs/orapw$STANDBY_DB_NAME"
    exit 1
  fi

  log "Password file $pwfile found. Continuing..."
}
# standby_create.conf

# Primary Database Info
PRIMARY_DB_NAME=PROD
PRIMARY_DB_CONN=PROD_TNS

# Standby Database Info
STANDBY_DB_NAME=PROD_STBY
STANDBY_DB_UNIQUE_NAME=PROD_STBY
# Standby Hosts - Flexible list
STANDBY_HOSTS=("standbyhost1.example.com" "standbyhost2.example.com")
STANDBY_PORT=1521

# Oracle Environment
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
SYS_PASS=MySysPassword123

# ASM Diskgroup Paths
ASM_DISKGROUP_DATA=+DATA01
ASM_DISKGROUP_REDO=+DATA01

# File Name Conversion (source filesystem if any)
PRIMARY_REDO_PATH=/u01/oradata/PROD/
PRIMARY_DATAFILE_PATH=/u01/oradata/PROD/

# Single or RAC Standby
IS_RAC=true

# Email Notification
EMAIL_TO=dba@example.com

# Function to validate database connectivity and basic environment
function precheck_standby_environment() {
  echo "Performing pre-checks..."

  echo "Checking connectivity to Primary Database..."
  if ! echo "exit" | sqlplus -s sys/$SYS_PASS@$PRIMARY_DB_CONN as sysdba >/dev/null; then
    echo "ERROR: Cannot connect to Primary Database ($PRIMARY_DB_CONN). Exiting."
    exit 1
  fi

  for host in "${STANDBY_HOSTS[@]}"; do
    echo "Checking connectivity to Standby Host: $host"
    if ! ping -c 2 "$host" >/dev/null; then
      echo "ERROR: Cannot ping Standby Host ($host). Exiting."
      exit 1
    fi
  done

  echo "Checking ORACLE_HOME exists..."
  if [ ! -d "$ORACLE_HOME" ]; then
    echo "ERROR: ORACLE_HOME ($ORACLE_HOME) does not exist. Exiting."
    exit 1
  fi

  echo "Pre-checks completed successfully."
}

# Function to create required adump directory on standby hosts
function create_required_directories_standby() {
  local DBNAME="$1"

  for host in "${STANDBY_HOSTS[@]}"; do
    echo "Creating adump directory on $host"
    ssh oracle@"$host" bash <<EOF
mkdir -p /u01/app/oracle/admin/${DBNAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${DBNAME}/adump
EOF
  done

  echo "Adump directories created successfully."
}

# Function to create redo and standby redo logs matching primary using ASM
function create_all_logs_from_primary_info() {
  local PRIMARY_CONN="$1"
  local STANDBY_SID="$2"
  local ASM_DISKGROUP_REDO="$3"

  export ORACLE_SID="$STANDBY_SID"

  echo "Fetching redo log information from Primary..."
  PRIMARY_REDO_SIZE_MB=$(sqlplus -s sys/$SYS_PASS@$PRIMARY_DB_CONN as sysdba <<EOF
SET HEAD OFF FEEDBACK OFF;
SELECT bytes/1024/1024 FROM v\$log WHERE rownum = 1;
EXIT;
EOF
  | xargs)

  THREAD_REDO_COUNTS=$(sqlplus -s sys/$SYS_PASS@$PRIMARY_DB_CONN as sysdba <<EOF
SET HEAD OFF FEEDBACK OFF;
SELECT thread# || ':' || COUNT(group#) FROM v\$log GROUP BY thread#;
EXIT;
EOF
  | xargs)

  for entry in $THREAD_REDO_COUNTS; do
    thread=$(echo "$entry" | cut -d':' -f1)
    redo_count=$(echo "$entry" | cut -d':' -f2)

    echo "Creating Redo Logs for Thread $thread"
    for ((i=1; i<=redo_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD LOGFILE THREAD $thread ('$ASM_DISKGROUP_REDO/$STANDBY_SID/ONLINELOG/redo_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EXIT;
EOF
    done

    echo "Creating Standby Redo Logs for Thread $thread"
    standby_count=$((redo_count + 1))
    for ((i=1; i<=standby_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD STANDBY LOGFILE THREAD $thread ('$ASM_DISKGROUP_REDO/$STANDBY_SID/STANDBYLOG/standby_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EXIT;
EOF
    done
  done

  echo "Redo and Standby Redo logs created successfully."
}


# standby_create_driver.sh

#!/bin/bash

set -euo pipefail

# Load configuration and functions
source ./standby_create.conf
source ./functions_standby_rac.sh

log "Starting Standby Creation Process"

# Step 1: Perform pre-checks
precheck_standby_environment

# Step 2: Create required adump directories dynamically for each host
create_required_directories_standby "$STANDBY_DB_UNIQUE_NAME"

# Step 3: Check for Password File
check_password_file

# Step 4: Validate RMAN Connections
validate_rman_connections "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME"

# Step 5: Prepare and start RMAN DUPLICATE in nohup
log "Preparing RMAN DUPLICATE command for Standby creation."

cat > duplicate_standby.rman <<EOF
CONNECT TARGET sys/$SYS_PASS@$PRIMARY_DB_CONN
CONNECT AUXILIARY sys/$SYS_PASS@$STANDBY_DB_NAME

DUPLICATE TARGET DATABASE
  FOR STANDBY
  FROM ACTIVE DATABASE
  DORECOVER
  SPFILE
  SET DB_UNIQUE_NAME='$STANDBY_DB_UNIQUE_NAME'
  SET CLUSTER_DATABASE='${IS_RAC,,}'
  SET LOG_FILE_NAME_CONVERT='$PRIMARY_REDO_PATH','$ASM_DISKGROUP_REDO'
  SET DB_FILE_NAME_CONVERT='$PRIMARY_DATAFILE_PATH','$ASM_DISKGROUP_DATA'
  NOFILENAMECHECK;
EXIT;
EOF

log "Starting RMAN DUPLICATE in background using nohup..."
nohup rman cmdfile=duplicate_standby.rman log=duplicate_standby.log &
RMAN_PID=$!

log "Waiting for RMAN process (PID=$RMAN_PID) to finish..."
wait $RMAN_PID || true

# Step 6: Check completion and send email notification
STATUS=$(check_rman_duplicate_completion duplicate_standby.log)
send_email_notification duplicate_standby.log "$STATUS" "$EMAIL_TO"

if [ "$STATUS" != "SUCCESS" ]; then
  log "RMAN duplicate failed. Exiting."
  exit 1
fi

# Step 7: Add standby database and start it to mount stage
add_and_start_standby_database "$STANDBY_DB_NAME" "$STANDBY_DB_UNIQUE_NAME" "$ORACLE_HOME" "$PRIMARY_REDO_PATH" "$ASM_DISKGROUP_REDO"

# Step 8: Create redo and standby redo logs
create_all_logs_from_primary_info "$PRIMARY_DB_CONN" "$STANDBY_DB_NAME" "$ASM_DISKGROUP_REDO"

# Step 9: Start MRP process
start_mrp_via_dgmgrl

# Step 10: Check Data Guard sync status
check_dg_sync_status

# Step 11: Post Steps Reminder
log "Post Steps Reminder:"
echo "- Verify all instances registered correctly with srvctl if RAC."
echo "- Data Guard sync status already validated."

log "Standby Creation Process Completed Successfully"

##
check_dg_sync_status() {
  log "Checking Data Guard Broker Configuration Status..."

  dgmgrl sys/$SYS_PASS@$PRIMARY_DB_CONN <<EOF > /tmp/dg_check.log
SHOW CONFIGURATION;
SHOW DATABASE "$STANDBY_DB_UNIQUE_NAME";
EXIT;
EOF

  if grep -q "SUCCESS" /tmp/dg_check.log && grep -q "APPLY-ON" /tmp/dg_check.log; then
    log "Data Guard configuration is healthy and Standby is in APPLY-ON mode."
  else
    log "ERROR: Data Guard is not healthy or Standby not applying redo."
    log "Please review /tmp/dg_check.log for details."
    cat /tmp/dg_check.log
    exit 1
  fi
}

###

#!/bin/bash
# File: lib/dg_manager.sh
CONFIG_FILE="dg_config.cfg"
source "$CONFIG_FILE" 2>/dev/null
HTML_REPORT="/tmp/dg_report_$(date +%Y%m%d).html"

# Function: Stop Standby in Mount State
stop_standby_mount() {
    if [ "$DG_TYPE" == "single" ]; then
        ssh "$STANDBY_HOST" <<EOF
            export ORACLE_SID=$STANDBY_SID
            sqlplus / as sysdba <<SQL
                SHUTDOWN IMMEDIATE;
                STARTUP MOUNT;
                EXIT;
SQL
EOF
    elif [ "$DG_TYPE" == "rac" ]; then
        for node in "${STANDBY_RAC_HOSTS[@]}"; do
            ssh "$node" <<EOF
                srvctl stop database -db $RAC_DB_NAME
                srvctl start database -db $RAC_DB_NAME -startoption mount
EOF
        done
    fi
}

# Function: Setup RAC using srvctl
setup_rac_srvctl() {
    if [ "$DG_TYPE" == "rac" ]; then
        # Add Database to Cluster
        ssh "${STANDBY_RAC_HOSTS[0]}" <<EOF
            srvctl add database -db $RAC_DB_NAME \
                -oraclehome $ORACLE_HOME \
                -dbtype PHYSICAL_STANDBY \
                -dbname $RAC_DB_NAME \
                -spfile "+$DATA_DG/$RAC_DB_NAME/spfile$RAC_DB_NAME.ora"
            
            # Add Instances
            node_num=1
            for node in "${STANDBY_RAC_HOSTS[@]}"; do
                srvctl add instance -db $RAC_DB_NAME \
                    -instance "${RAC_INSTANCE_PREFIX}\${node_num}" \
                    -node "$node"
                ((node_num++))
            done
            
            srvctl config database -db $RAC_DB_NAME
EOF
    fi
}

# Function: Configure Data Guard Broker
configure_dgmgrl() {
    dgmgrl_cmds="/tmp/dgmgrl_cmds_$$.txt"
    cat <<DGMGRL > "$dgmgrl_cmds"
        CREATE CONFIGURATION DG_${DB_NAME} AS PRIMARY DATABASE IS ${DB_NAME} CONNECT IDENTIFIER IS ${PRIMARY_HOST};
        ADD DATABASE ${DB_NAME}_STBY AS CONNECT IDENTIFIER IS ${STANDBY_HOST} MAINTAINED AS PHYSICAL;
        ENABLE CONFIGURATION;
        SHOW CONFIGURATION;
DGMGRL

    dgmgrl sys/$SYS_PASSWORD@$PRIMARY_HOST <<EOF
        @$dgmgrl_cmds
EOF
    rm -f "$dgmgrl_cmds"
}

# Function: Generate HTML Report
generate_html_report() {
    cat <<HTML > "$HTML_REPORT"
<html>
<head>
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    .success { background-color: #dff0d8; }
    .error { background-color: #f2dede; }
</style>
</head>
<body>
    <h2>Data Guard Deployment Report</h2>
    <p>Generated: $(date)</p>
    <table>
        <tr><th>Step</th><th>Status</th><th>Details</th></tr>
HTML

    # Add report entries from log file
    while read -r line; do
        echo "<tr><td>${line%%|*}</td><td>${line#*|}</td><td>${line##*|}</td></tr>" >> "$HTML_REPORT"
    done < /tmp/dg_deploy.log

    cat <<HTML >> "$HTML_REPORT"
    </table>
</body>
</html>
HTML
}

# Function: Send Email Report
send_email_report() {
    local recipient=$(whoami)@example.com  # Set your email
    local subject="Data Guard Deployment Report - $DB_NAME"
    
    mailx -s "$subject" -a "Content-type: text/html" "$recipient" <<EOF
$(cat $HTML_REPORT)
EOF
}

# Main Deployment Workflow
main_deployment() {
    >/tmp/dg_deploy.log  # Initialize log file
    
    # 1. Stop Standby in Mount State
    if stop_standby_mount >>/tmp/dg_deploy.log 2>&1; then
        echo "Mount Stage|Success|Standby successfully mounted" >>/tmp/dg_deploy.log
    else
        echo "Mount Stage|Failed|Error mounting standby" >>/tmp/dg_deploy.log
        return 1
    fi
    
    # 2. Setup RAC (if applicable)
    if [ "$DG_TYPE" == "rac" ]; then
        if setup_rac_srvctl >>/tmp/dg_deploy.log 2>&1; then
            echo "RAC Setup|Success|Cluster configuration completed" >>/tmp/dg_deploy.log
        else
            echo "RAC Setup|Failed|Error configuring RAC" >>/tmp/dg_deploy.log
            return 1
        fi
    fi
    
    # 3. Configure Data Guard Broker
    if configure_dgmgrl >>/tmp/dg_deploy.log 2>&1; then
        echo "Broker Config|Success|DGMGRL configuration applied" >>/tmp/dg_deploy.log
    else
        echo "Broker Config|Failed|Error in broker configuration" >>/tmp/dg_deploy.log
        return 1
    fi
    
    # Generate and send report
    generate_html_report
    send_email_report
}

# Execute main deployment
main_deployment
DG_TYPE="rac"  # or "single"
DB_NAME="ORCL"
PRIMARY_HOST="primary-node"
STANDBY_HOST="standby-node"
RAC_INSTANCE_PREFIX="orclstby"
STANDBY_RAC_HOSTS=("node1" "node2")
DATA_DG="DATA"
LOG_DG="LOG"
SYS_PASSWORD="securepass"
ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1"
##########
#!/bin/bash
# File: lib/dg_manager.sh
CONFIG_FILE="dg_config.cfg"
source "$CONFIG_FILE" 2>/dev/null
HTML_REPORT="/tmp/dg_report_$(date +%Y%m%d).html"

# Function: Stop Standby in Mount State using SRVCTL
stop_standby_mount() {
    if [ "$DG_TYPE" == "single" ]; then
        # For Oracle Restart single instance
        ssh "$STANDBY_HOST" <<EOF
            if srvctl config database -db $DB_NAME >/dev/null 2>&1; then
                srvctl stop database -db $DB_NAME
                srvctl start database -db $DB_NAME -startoption mount
            else
                sqlplus / as sysdba <<SQL
                    SHUTDOWN IMMEDIATE;
                    STARTUP MOUNT;
SQL
            fi
EOF
    elif [ "$DG_TYPE" == "rac" ]; then
        # For RAC databases
        ssh "${STANDBY_RAC_HOSTS[0]}" <<EOF
            srvctl stop database -db $RAC_DB_NAME
            srvctl start database -db $RAC_DB_NAME -startoption mount
EOF
    fi
}

# Function: Setup Single Instance with Oracle Restart
setup_si_srvctl() {
    if [ "$DG_TYPE" == "single" ]; then
        ssh "$STANDBY_HOST" <<EOF
            # Check if database already exists in Oracle Restart
            if ! srvctl config database -db $DB_NAME >/dev/null 2>&1; then
                srvctl add database -db $DB_NAME \
                    -oraclehome $ORACLE_HOME \
                    -dbtype PHYSICAL_STANDBY \
                    -dbname $DB_NAME \
                    -spfile '+$DATA_DG/$DB_NAME/spfile$DB_NAME.ora' \
                    -role PHYSICAL_STANDBY \
                    -startoption MOUNT \
                    -stopoption IMMEDIATE
                
                srvctl modify database -db $DB_NAME \
                    -dbname $DB_NAME \
                    -pwfile '+$DATA_DG/$DB_NAME/orapw$DB_NAME'
                
                srvctl enable database -db $DB_NAME
            fi
            
            srvctl config database -db $DB_NAME
EOF
    fi
}

# Function: Configure Data Guard Broker with DGMGRL
configure_dgmgrl() {
    dgmgrl_cmds="/tmp/dgmgrl_cmds_$$.txt"
    
    cat <<DGMGRL > "$dgmgrl_cmds"
        CREATE CONFIGURATION DG_${DB_NAME} AS PRIMARY DATABASE IS ${DB_NAME} 
            CONNECT IDENTIFIER IS ${PRIMARY_HOST};
        ADD DATABASE ${DB_NAME}_STBY AS CONNECT IDENTIFIER IS ${STANDBY_HOST} 
            MAINTAINED AS PHYSICAL;
        ENABLE CONFIGURATION;
        ENABLE DATABASE ${DB_NAME}_STBY;
        SHOW CONFIGURATION VERBOSE;
DGMGRL

    dgmgrl sys/$SYS_PASSWORD@$PRIMARY_HOST <<EOF
        @$dgmgrl_cmds
EOF
    local status=$?
    rm -f "$dgmgrl_cmds"
    return $status
}

# Enhanced HTML Report Generation
generate_html_report() {
    cat <<HTML > "$HTML_REPORT"
<html>
<head>
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    .success { background-color: #dff0d8; }
    .warning { background-color: #fcf8e3; }
    .error { background-color: #f2dede; }
</style>
</head>
<body>
    <h2>Data Guard Deployment Report</h2>
    <p>Generated: $(date "+%Y-%m-%d %H:%M:%S")</p>
    <h3>Configuration Details</h3>
    <ul>
        <li>Database Name: $DB_NAME</li>
        <li>Database Type: ${DG_TYPE^^}</li>
        <li>Primary Host: $PRIMARY_HOST</li>
        <li>Standby Host: ${STANDBY_HOST:-${STANDBY_RAC_HOSTS[*]}}</li>
    </ul>
    <h3>Deployment Steps</h3>
    <table>
        <tr><th>Step</th><th>Status</th><th>Details</th><th>Timestamp</th></tr>
HTML

    # Add report entries from log file
    while IFS='|' read -r step status details timestamp; do
        echo "<tr class=\"${status,,}\"><td>$step</td><td>$status</td><td>$details</td><td>$timestamp</td></tr>" >> "$HTML_REPORT"
    done < /tmp/dg_deploy.log

    cat <<HTML >> "$HTML_REPORT"
    </table>
</body>
</html>
HTML
}

# Enhanced Email Function
send_email_report() {
    local recipient="dba-team@yourcompany.com"
    local subject="Data Guard Deployment Report - $DB_NAME ($DG_TYPE)"
    
    mailx -s "$subject" -a "Content-type: text/html" "$recipient" <<EOF
$(cat $HTML_REPORT)
EOF
}

# Main Deployment Workflow
main_deployment() {
    {
        echo "Step|Status|Details|Timestamp"
        # 1. Stop and mount standby
        if stop_standby_mount; then
            echo "Mount Database|Success|Standby mounted using SRVCTL|$(date "+%T")"
        else
            echo "Mount Database|Error|Failed to mount standby|$(date "+%T")"
            return 1
        fi
        
        # 2. Configure Oracle Restart/RAC
        if [ "$DG_TYPE" == "single" ]; then
            if setup_si_srvctl; then
                echo "Oracle Restart|Success|Database registered with SRVCTL|$(date "+%T")"
            else
                echo "Oracle Restart|Error|Failed to configure SRVCTL|$(date "+%T")"
                return 1
            fi
        elif [ "$DG_TYPE" == "rac" ]; then
            if setup_rac_srvctl; then
                echo "RAC Config|Success|Cluster configuration completed|$(date "+%T")"
            else
                echo "RAC Config|Error|Failed to configure RAC|$(date "+%T")"
                return 1
            fi
        fi
        
        # 3. Configure Data Guard Broker
        if configure_dgmgrl; then
            echo "Broker Config|Success|DGMGRL configuration applied|$(date "+%T")"
        else
            echo "Broker Config|Error|Failed to configure broker|$(date "+%T")"
            return 1
        fi
        
        # 4. Final verification
        verification_result=$(ssh $STANDBY_HOST "srvctl status database -db $DB_NAME")
        echo "Final Check|Success|$verification_result|$(date "+%T")"
        
    } | tee /tmp/dg_deploy.log
    
    generate_html_report
    send_email_report
}

# Execute main deployment
main_deployment
