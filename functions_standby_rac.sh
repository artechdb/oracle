#!/bin/bash
# Standby Database Creation Driver Script
source ./functions_standby_rac.sh
source ./standby.conf

prepare_environment
pre_checks
create_static_listener
setup_tns_entries
duplicate_primary_to_standby
create_rac_instances
setup_redo_logs
configure_dg_broker
start_mrp
validate_dg_sync

echo "Standby Database creation completed successfully."
# Standby Configuration File

PRIMARY_DB_NAME=primarydb
STANDBY_DB_NAME=standbydb
PRIMARY_HOST=primary-host
STANDBY_HOSTS=(standby1-host standby2-host)
ASM_DISKGROUP_DATA=+DATA01
ASM_DISKGROUP_FRA=+FRA01
REDO_SIZE_MB=512
STANDBY_REDO_EXTRA_GROUPS=1
create_standby_rac_from_active() {
  local PRIMARY_CONN="$1"
  local STANDBY_HOST1="$2"
  local STANDBY_HOST2="$3"
  local STANDBY_SID="$4"
  local STANDBY_PORT="$5"
  local ORACLE_HOME="$6"
  local SYS_PASS="$7"
  local PRIMARY_REDO_PATH="$8"
  local STANDBY_REDO_PATH="$9"
  local PRIMARY_DATAFILE_PATH="${10}"
  local STANDBY_DATAFILE_PATH="${11}"

  local STANDBY_DB_UNIQUE_NAME="$STANDBY_SID"
  local STANDBY_TNS="${STANDBY_SID}_TNS"

  log "Step 1: Create static listener entry on node1."
  cat >> "$ORACLE_HOME/network/admin/listener.ora" <<EOF

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME=$STANDBY_SID_DGMGRL)
      (ORACLE_HOME=$ORACLE_HOME)
      (SID_NAME=$STANDBY_SID)
    )
  )
EOF

  lsnrctl reload

  log "Step 2: Create TNS entry for standby."
  cat >> "$ORACLE_HOME/network/admin/tnsnames.ora" <<EOF

$STANDBY_TNS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $STANDBY_HOST1)(PORT = $STANDBY_PORT))
    (CONNECT_DATA =
      (SERVICE_NAME = $STANDBY_SID)
    )
  )
EOF

  log "Step 3: Startup standby instance NOMOUNT."
  export ORACLE_SID="$STANDBY_SID"
  sqlplus / as sysdba <<EOF
STARTUP NOMOUNT;
EXIT;
EOF

  log "Step 4: RMAN DUPLICATE FOR STANDBY FROM ACTIVE DATABASE."
  rman target sys/"$SYS_PASS"@$PRIMARY_CONN auxiliary sys/"$SYS_PASS"@$STANDBY_TNS <<EOF
DUPLICATE TARGET DATABASE
  FOR STANDBY
  FROM ACTIVE DATABASE
  DORECOVER
  SPFILE
  SET DB_UNIQUE_NAME='$STANDBY_DB_UNIQUE_NAME'
  SET CLUSTER_DATABASE='true'
  SET LOG_FILE_NAME_CONVERT='$PRIMARY_REDO_PATH','$STANDBY_REDO_PATH'
  SET DATAFILE_NAME_CONVERT='$PRIMARY_DATAFILE_PATH','$STANDBY_DATAFILE_PATH'
  NOFILENAMECHECK;
EOF

  log "Step 5: Register standby database and instances with srvctl."
  srvctl add database -db "$STANDBY_DB_UNIQUE_NAME" -oraclehome "$ORACLE_HOME" -dbname "$STANDBY_SID" -role PHYSICAL_STANDBY -startoption MOUNT
  srvctl add instance -db "$STANDBY_DB_UNIQUE_NAME" -instance "${STANDBY_SID}1" -node "$STANDBY_HOST1"
  srvctl add instance -db "$STANDBY_DB_UNIQUE_NAME" -instance "${STANDBY_SID}2" -node "$STANDBY_HOST2"

  log "Step 6: Start RAC standby database in MOUNT stage."
  srvctl start database -db "$STANDBY_DB_UNIQUE_NAME" -startoption MOUNT

  log "Step 7: Add and enable standby in Data Guard broker."
  echo "ADD DATABASE '$STANDBY_DB_UNIQUE_NAME' AS CONNECT IDENTIFIER IS '$STANDBY_TNS' MAINTAINED AS PHYSICAL;" | dgmgrl sys/"$SYS_PASS"@$PRIMARY_CONN
  echo "ENABLE DATABASE '$STANDBY_DB_UNIQUE_NAME';" | dgmgrl sys/"$SYS_PASS"@$PRIMARY_CONN
}
create_all_logs_from_primary_info() {
  local PRIMARY_CONN="$1"
  local STANDBY_SID="$2"
  local STANDBY_REDO_PATH="$3"

  export ORACLE_SID="$STANDBY_SID"

  log "Fetching redo log information from Primary."
  PRIMARY_REDO_SIZE_MB=$(exec_sqlplus "$PRIMARY_CONN" "
SET HEAD OFF FEEDBACK OFF;
SELECT bytes/1024/1024 FROM v\\$log WHERE rownum = 1;
" | xargs)

  THREAD_REDO_COUNTS=$(exec_sqlplus "$PRIMARY_CONN" "
SET HEAD OFF FEEDBACK OFF;
SELECT thread# || ':' || COUNT(group#) 
FROM v\\$log 
GROUP BY thread#;
" | xargs)

  for entry in $THREAD_REDO_COUNTS; do
    thread=$(echo $entry | cut -d':' -f1)
    redo_count=$(echo $entry | cut -d':' -f2)

    log \"Creating Redo Logs for Thread $thread.\"
    for ((i=1; i<=redo_count; i++)); do
      sqlplus / as sysdba <<EOF
ALTER DATABASE ADD LOGFILE THREAD $thread ('$STANDBY_REDO_PATH/redo_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EOF
    done

    log \"Creating Standby Redo Logs for Thread $thread.\"
    standby_count=$((redo_count + 1))
    for ((i=1; i<=standby_count; i++)); do
      sqlplus / as sysdba <<EOF
ALTER DATABASE ADD STANDBY LOGFILE THREAD $thread ('$STANDBY_REDO_PATH/standby_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EOF
    done
  done
}
create_required_directories_standby() {
  local STANDBY_HOST1="$1"
  local STANDBY_HOST2="$2"
  local STANDBY_DB_UNIQUE_NAME="$3"
  local BASE_DATA_PATH="$4"
  local BASE_FRA_PATH="$5"

  echo "Creating required directories on Standby Node1: $STANDBY_HOST1"
  ssh oracle@"$STANDBY_HOST1" bash <<EOF
mkdir -p ${BASE_DATA_PATH}/${STANDBY_DB_UNIQUE_NAME}
mkdir -p ${BASE_FRA_PATH}/${STANDBY_DB_UNIQUE_NAME}
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall ${BASE_DATA_PATH}/${STANDBY_DB_UNIQUE_NAME}
chown -R oracle:oinstall ${BASE_FRA_PATH}/${STANDBY_DB_UNIQUE_NAME}
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Creating required directories on Standby Node2: $STANDBY_HOST2"
  ssh oracle@"$STANDBY_HOST2" bash <<EOF
mkdir -p ${BASE_DATA_PATH}/${STANDBY_DB_UNIQUE_NAME}
mkdir -p ${BASE_FRA_PATH}/${STANDBY_DB_UNIQUE_NAME}
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall ${BASE_DATA_PATH}/${STANDBY_DB_UNIQUE_NAME}
chown -R oracle:oinstall ${BASE_FRA_PATH}/${STANDBY_DB_UNIQUE_NAME}
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Directory creation completed on both standby nodes."
}
create_required_directories_standby() {
  local STANDBY_HOST1="$1"
  local STANDBY_HOST2="$2"
  local STANDBY_DB_UNIQUE_NAME="$3"

  echo "Creating required adump directory on Standby Node1: $STANDBY_HOST1"
  ssh oracle@"$STANDBY_HOST1" bash <<EOF
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Creating required adump directory on Standby Node2: $STANDBY_HOST2"
  ssh oracle@"$STANDBY_HOST2" bash <<EOF
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Adump directories created successfully on both standby nodes."
}
# standby_create.conf

# Primary Database Info
PRIMARY_DB_NAME=PROD
PRIMARY_DB_CONN=PROD_TNS

# Standby Database Info
STANDBY_DB_NAME=PROD_STBY
STANDBY_DB_UNIQUE_NAME=PROD_STBY
STANDBY_HOST1=standbyhost1.example.com
STANDBY_HOST2=standbyhost2.example.com
STANDBY_PORT=1521

# Oracle Environment
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
SYS_PASS=MySysPassword123

# ASM Diskgroup for Data and Logs
ASM_DISKGROUP=+DATA1

# Function to validate database connectivity and basic environment
function precheck_standby_environment() {
  echo "Performing pre-checks..."

  echo "Checking connectivity to Primary Database..."
  if ! echo "exit" | sqlplus -s sys/$SYS_PASS@$PRIMARY_DB_CONN as sysdba >/dev/null; then
    echo "ERROR: Cannot connect to Primary Database ($PRIMARY_DB_CONN). Exiting."
    exit 1
  fi

  echo "Checking connectivity to Standby Node1..."
  if ! ping -c 2 "$STANDBY_HOST1" >/dev/null; then
    echo "ERROR: Cannot ping Standby Host1 ($STANDBY_HOST1). Exiting."
    exit 1
  fi

  echo "Checking connectivity to Standby Node2..."
  if ! ping -c 2 "$STANDBY_HOST2" >/dev/null; then
    echo "ERROR: Cannot ping Standby Host2 ($STANDBY_HOST2). Exiting."
    exit 1
  fi

  echo "Checking ORACLE_HOME exists on Standby Node1..."
  if [ ! -d "$ORACLE_HOME" ]; then
    echo "ERROR: ORACLE_HOME ($ORACLE_HOME) does not exist. Exiting."
    exit 1
  fi

  echo "Pre-checks completed successfully."
}

# Function to create required adump directory on standby hosts
function create_required_directories_standby() {
  local STANDBY_HOST1="$STANDBY_HOST1"
  local STANDBY_HOST2="$STANDBY_HOST2"
  local STANDBY_DB_UNIQUE_NAME="$STANDBY_DB_UNIQUE_NAME"

  echo "Creating adump directory on Standby Node1: $STANDBY_HOST1"
  ssh oracle@"$STANDBY_HOST1" bash <<EOF
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Creating adump directory on Standby Node2: $STANDBY_HOST2"
  ssh oracle@"$STANDBY_HOST2" bash <<EOF
mkdir -p /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
chown -R oracle:oinstall /u01/app/oracle/admin/${STANDBY_DB_UNIQUE_NAME}/adump
EOF

  echo "Adump directories created successfully on both standby nodes."
}

# Function to create redo and standby redo logs matching primary using ASM
function create_all_logs_from_primary_info() {
  local PRIMARY_CONN="$PRIMARY_DB_CONN"
  local STANDBY_SID="$STANDBY_DB_NAME"
  local ASM_DISKGROUP="$ASM_DISKGROUP"

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
    thread=$(echo $entry | cut -d':' -f1)
    redo_count=$(echo $entry | cut -d':' -f2)

    echo "Creating Redo Logs for Thread $thread in ASM..."
    for ((i=1; i<=redo_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD LOGFILE THREAD $thread ('$ASM_DISKGROUP/$STANDBY_DB_UNIQUE_NAME/ONLINELOG/redo_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EXIT;
EOF
    done

    echo "Creating Standby Redo Logs for Thread $thread in ASM..."
    standby_count=$((redo_count + 1))
    for ((i=1; i<=standby_count; i++)); do
      sqlplus -s / as sysdba <<EOF
ALTER DATABASE ADD STANDBY LOGFILE THREAD $thread ('$ASM_DISKGROUP/$STANDBY_DB_UNIQUE_NAME/STANDBYLOG/standby_t${thread}_g${i}.log') SIZE ${PRIMARY_REDO_SIZE_MB}M;
EXIT;
EOF
    done
  done

  echo "Redo and Standby Redo logs created successfully in ASM."
}
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

