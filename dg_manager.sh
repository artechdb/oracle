
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
