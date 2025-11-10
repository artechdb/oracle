#!/bin/bash
################################################################################
# Oracle 19c RAC Database Restore Point Functions
# Description: Functions for managing database restore points in Data Guard environments
# Created: 2025-11-02
# Updated: 2025-11-09 - Added DGMGRL-based database identification
################################################################################

################################################################################
# DGMGRL Utility Functions
################################################################################

################################################################################
# Function: stop_apply_on_standby
# Description: Stops apply process on standby using DGMGRL
# Parameters: $1 - Standby database unique name
# Returns: 0 if successful, 1 if failed
################################################################################
stop_apply_on_standby() {
    local standby_unique_name=$1
    
    log_message "INFO" "Stopping apply on ${standby_unique_name}..."
    
    local result=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
edit database ${standby_unique_name} set state='APPLY-OFF';
exit;
EOF
)
    
    if echo "${result}" | grep -qi "succeed"; then
        log_message "INFO" "Apply stopped on ${standby_unique_name}"
        return 0
    else
        log_message "ERROR" "Failed to stop apply on ${standby_unique_name}"
        echo "${result}"
        return 1
    fi
}

################################################################################
# Function: start_apply_on_standby
# Description: Starts apply process on standby using DGMGRL
# Parameters: $1 - Standby database unique name
# Returns: 0 if successful, 1 if failed
################################################################################
start_apply_on_standby() {
    local standby_unique_name=$1
    
    log_message "INFO" "Starting apply on ${standby_unique_name}..."
    
    local result=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
edit database ${standby_unique_name} set state='APPLY-ON';
exit;
EOF
)
    
    if echo "${result}" | grep -qi "succeed"; then
        log_message "INFO" "Apply started on ${standby_unique_name}"
        return 0
    else
        log_message "ERROR" "Failed to start apply on ${standby_unique_name}"
        echo "${result}"
        return 1
    fi
}

################################################################################
# Function: get_dg_broker_configuration
# Description: Gets Data Guard Broker configuration name
# Parameters: $1 - Database name
# Returns: DG_CONFIG_NAME, DG_CONNECT_STRING (global variables)
################################################################################
get_dg_broker_configuration() {
    local db_name=$1
    
    log_message "INFO" "Checking for Data Guard Broker configuration..."
    
    local selected_config=$(load_database_list "${db_name}")
    
    if [[ -z "${selected_config}" ]]; then
        log_message "ERROR" "Database '${db_name}' not found in configuration"
        return 1
    fi
    
    IFS='|' read -r db scan service <<< "${selected_config}"
    
    if ! test_db_connection "${scan}" "${service}" 2>/dev/null; then
        log_message "ERROR" "Cannot connect to database ${db}"
        return 1
    fi
    
    DG_CONNECT_STRING="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service}"
    
    local dg_config_output=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
show configuration;
exit;
EOF
)
    
    if echo "${dg_config_output}" | grep -qi "ORA-\|configuration does not exist"; then
        log_message "WARN" "Not part of Data Guard Broker configuration"
        return 1
    fi
    
    DG_CONFIG_NAME=$(echo "${dg_config_output}" | grep -i "Configuration -" | sed 's/.*Configuration - \(.*\)/\1/' | xargs)
    
    if [[ -z "${DG_CONFIG_NAME}" ]]; then
        log_message "ERROR" "Could not determine Data Guard configuration name"
        return 1
    fi
    
    log_message "INFO" "Found Data Guard configuration: ${DG_CONFIG_NAME}"
    return 0
}

################################################################################
# Function: get_primary_and_standbys_dgmgrl
# Description: Gets primary and all standbys from DGMGRL
# Returns: PRIMARY_DB (db|scan|service), STANDBY_DBS_ARRAY (global variables)
################################################################################
get_primary_and_standbys_dgmgrl() {
    log_message "INFO" "Identifying primary and standby databases..."
    
    if [[ -z "${DG_CONNECT_STRING}" ]]; then
        log_message "ERROR" "Data Guard configuration not initialized"
        return 1
    fi
    
    local dg_show_config=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
show configuration verbose;
exit;
EOF
)
    
    # Find primary
    local primary_line=$(echo "${dg_show_config}" | grep -i "Primary database" | head -1)
    local primary_unique_name=$(echo "${primary_line}" | sed 's/.*Primary database is \(.*\)/\1/' | xargs)
    
    if [[ -n "${primary_unique_name}" ]]; then
        local primary_config=$(load_database_list "${primary_unique_name}")
        if [[ -n "${primary_config}" ]]; then
            PRIMARY_DB="${primary_config}"
            log_message "INFO" "Primary database: ${primary_unique_name}"
        else
            log_message "ERROR" "Primary ${primary_unique_name} not found in database list"
            return 1
        fi
    fi
    
    # Find standbys
    STANDBY_DBS_ARRAY=()
    
    while IFS= read -r line; do
        if echo "${line}" | grep -qi "Physical standby database"; then
            # Extract database name from format: "  STANDBY1 - Physical standby database"
            local standby_db=$(echo "${line}" | sed 's/^[[:space:]]*\([^[:space:]]*\)[[:space:]]*-.*/\1/' | xargs)
            
            if [[ -n "${standby_db}" ]]; then
                local standby_config=$(load_database_list "${standby_db}")
                
                if [[ -n "${standby_config}" ]]; then
                    STANDBY_DBS_ARRAY+=("${standby_config}")
                    log_message "INFO" "Found standby: ${standby_db}"
                else
                    log_message "WARN" "Standby ${standby_db} not found in database list"
                fi
            fi
        fi
    done <<< "${dg_show_config}"
    
    log_message "INFO" "Found ${#STANDBY_DBS_ARRAY[@]} standby database(s)"
    
    return 0
}

################################################################################
# Original Functions (Updated to use DGMGRL utilities)
################################################################################

################################################################################
# Function: get_all_dg_members
# Description: Gets all databases in Data Guard configuration (primary and standbys)
# Parameters: $1 - Database name from user selection
# Returns: PRIMARY_DB, STANDBY_DBS_ARRAY (global variables)
################################################################################
get_all_dg_members() {
    local db_name=$1
    
    log_message "INFO" "Getting all Data Guard members for configuration"
    
    # Use DGMGRL to get configuration
    if ! get_dg_broker_configuration "${db_name}"; then
        log_message "WARN" "Not part of Data Guard Broker configuration, processing single database"
        # Load the specific database as standalone
        local db_config=$(load_database_list "${db_name}")
        if [[ -n "${db_config}" ]]; then
            PRIMARY_DB="${db_config}"
            STANDBY_DBS_ARRAY=()
            log_message "INFO" "Processing as standalone database"
            return 0
        else
            log_message "ERROR" "Database not found: ${db_name}"
            return 1
        fi
    fi
    
    # Get primary and all standbys using DGMGRL
    if ! get_primary_and_standbys_dgmgrl; then
        log_message "ERROR" "Failed to get Data Guard members"
        return 1
    fi
    
    log_message "INFO" "Found ${#STANDBY_DBS_ARRAY[@]} standby database(s) + 1 primary"
    
    return 0
}

################################################################################
# Function: get_db_unique_name
# Description: Gets database unique name
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: DB_UNIQUE_NAME
################################################################################
get_db_unique_name() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    local unique_name=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select db_unique_name from v\$database;
exit;
EOF
)
    
    echo "${unique_name}" | xargs
}

################################################################################
# Function: stop_mrp_on_standby
# Description: Stops MRP (Managed Recovery Process) on standby database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: 0 if successful, 1 if failed
################################################################################
stop_mrp_on_standby() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Stopping MRP on standby: ${scan_host}/${service_name}"
    
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
exit;
EOF
)
    
    if [[ $? -eq 0 ]]; then
        log_message "INFO" "MRP stopped successfully"
        return 0
    else
        # Check if already stopped
        if echo "${result}" | grep -qi "ORA-16136"; then
            log_message "INFO" "MRP already stopped"
            return 0
        fi
        log_message "ERROR" "Failed to stop MRP: ${result}"
        return 1
    fi
}

################################################################################
# Function: start_mrp_on_standby
# Description: Starts MRP on standby database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: 0 if successful, 1 if failed
################################################################################
start_mrp_on_standby() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Starting MRP on standby: ${scan_host}/${service_name}"
    
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
exit;
EOF
)
    
    if [[ $? -eq 0 ]]; then
        log_message "INFO" "MRP started successfully"
        return 0
    else
        log_message "ERROR" "Failed to start MRP: ${result}"
        return 1
    fi
}

################################################################################
# Function: disable_flashback
# Description: Disables flashback database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: 0 if successful, 1 if failed
################################################################################
disable_flashback() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Disabling flashback database: ${scan_host}/${service_name}"
    
    # Check current flashback status
    local flashback_on=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select flashback_on from v\$database;
exit;
EOF
)
    
    flashback_on=$(echo "${flashback_on}" | xargs)
    
    if [[ "${flashback_on}" == "NO" ]]; then
        log_message "INFO" "Flashback already disabled"
        return 0
    fi
    
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
ALTER DATABASE FLASHBACK OFF;
exit;
EOF
)
    
    if [[ $? -eq 0 ]]; then
        log_message "INFO" "Flashback disabled successfully"
        return 0
    else
        log_message "ERROR" "Failed to disable flashback: ${result}"
        return 1
    fi
}

################################################################################
# Function: enable_flashback
# Description: Enables flashback database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: 0 if successful, 1 if failed
################################################################################
enable_flashback() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Enabling flashback database: ${scan_host}/${service_name}"
    
    # Check current flashback status
    local flashback_on=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select flashback_on from v\$database;
exit;
EOF
)
    
    flashback_on=$(echo "${flashback_on}" | xargs)
    
    if [[ "${flashback_on}" == "YES" ]]; then
        log_message "INFO" "Flashback already enabled"
        return 0
    fi
    
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
ALTER DATABASE FLASHBACK ON;
exit;
EOF
)
    
    if [[ $? -eq 0 ]]; then
        log_message "INFO" "Flashback enabled successfully"
        return 0
    else
        log_message "ERROR" "Failed to enable flashback: ${result}"
        return 1
    fi
}

################################################################################
# Function: create_restore_point_dg_aware
# Description: Creates restore point on all DG members (standbys first, then primary)
# Parameters: $1 - Restore point name
#            $2 - Guarantee flashback (YES/NO)
#            $3 - Database name from user selection
# Returns: 0 if successful, 1 if failed
################################################################################
create_restore_point_dg_aware() {
    local rp_name=$1
    local guarantee="${2:-NO}"
    local db_name=$3
    
    log_message "INFO" "========================================"
    log_message "INFO" "Creating restore point: ${rp_name}"
    log_message "INFO" "Guarantee: ${guarantee}"
    log_message "INFO" "========================================"
    
    # Validate restore point name
    if [[ ! "${rp_name}" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_message "ERROR" "Invalid restore point name. Must start with letter and contain only alphanumeric characters and underscores"
        return 1
    fi
    
    # Get all DG members
    local dg_members=$(get_all_dg_members "${db_name}")
    
    if [[ -z "${dg_members}" ]]; then
        log_message "ERROR" "No databases found"
        return 1
    fi
    
    # Separate primary and standbys
    local -a standby_array=()
    local primary_scan=""
    local primary_service=""
    local primary_db=""
    
    while IFS= read -r member; do
        IFS='|' read -r db scan service role unique_name <<< "${member}"
        
        if [[ "${role}" == "PRIMARY" ]]; then
            primary_db="${db}"
            primary_scan="${scan}"
            primary_service="${service}"
            log_message "INFO" "Primary: ${db} (${unique_name})"
        elif [[ "${role}" == "PHYSICAL STANDBY" ]]; then
            standby_array+=("${db}|${scan}|${service}|${unique_name}")
            log_message "INFO" "Standby: ${db} (${unique_name})"
        fi
    done <<< "${dg_members}"
    
    local total_standbys=${#standby_array[@]}
    log_message "INFO" "Found ${total_standbys} standby database(s)"
    
    # STEP 1: Create restore point on ALL STANDBYS first
    if [[ ${total_standbys} -gt 0 ]]; then
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 1: Stopping apply on all standbys"
        log_message "INFO" "========================================"
        
        # Stop apply on all standbys first
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            if ! stop_apply_on_standby "${stby_unique}"; then
                log_message "ERROR" "Failed to stop apply on ${stby_db}, aborting"
                return 1
            fi
        done
        
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 2: Creating restore point on STANDBYS"
        log_message "INFO" "========================================"
        
        local standby_counter=1
        local -a failed_standbys=()
        
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            log_message "INFO" "Processing standby ${standby_counter}/${total_standbys}: ${stby_db}"
            
            # Create restore point on standby
            if create_restore_point "${stby_scan}" "${stby_service}" "${rp_name}" "${guarantee}"; then
                log_message "INFO" "✓ Restore point created on standby: ${stby_db}"
            else
                log_message "ERROR" "✗ Failed to create restore point on standby: ${stby_db}"
                failed_standbys+=("${stby_unique}")
            fi
            
            ((standby_counter++))
        done
        
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 3: Restarting apply on all standbys"
        log_message "INFO" "========================================"
        
        # Restart apply on all standbys
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            if ! start_apply_on_standby "${stby_unique}"; then
                log_message "WARN" "Failed to restart apply on ${stby_db} - manual intervention may be required"
            fi
        done
        
        # Check if any standbys failed
        if [[ ${#failed_standbys[@]} -gt 0 ]]; then
            log_message "ERROR" "Failed to create restore point on ${#failed_standbys[@]} standby database(s)"
            return 1
        fi
    else
        log_message "INFO" "No standby databases found, will create on primary only"
    fi
    
    # STEP 4: Create restore point on PRIMARY
    if [[ -n "${primary_scan}" ]]; then
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 4: Creating restore point on PRIMARY"
        log_message "INFO" "========================================"
        
        if create_restore_point "${primary_scan}" "${primary_service}" "${rp_name}" "${guarantee}"; then
            log_message "INFO" "✓ Restore point created on primary: ${primary_db}"
        else
            log_message "ERROR" "✗ Failed to create restore point on primary: ${primary_db}"
            return 1
        fi
    fi
    
    log_message "INFO" "========================================"
    log_message "INFO" "Restore point '${rp_name}' created successfully on all databases"
    log_message "INFO" "========================================"
    
    return 0
}

################################################################################
# Function: drop_restore_point_dg_aware
# Description: Drops restore point following proper DG sequence
#              1. Stop MRP on standbys
#              2. Drop RP on standbys
#              3. Turn off/on flashback on standbys
#              4. Start MRP on standbys
#              5. Drop RP on primary
#              6. Turn off/on flashback on primary
# Parameters: $1 - Restore point name
#            $2 - Database name from user selection
# Returns: 0 if successful, 1 if failed
################################################################################
drop_restore_point_dg_aware() {
    local rp_name=$1
    local db_name=$2
    
    log_message "INFO" "========================================"
    log_message "INFO" "Dropping restore point: ${rp_name}"
    log_message "INFO" "Following Data Guard best practices"
    log_message "INFO" "========================================"
    
    # Get all DG members
    local dg_members=$(get_all_dg_members "${db_name}")
    
    if [[ -z "${dg_members}" ]]; then
        log_message "ERROR" "No databases found"
        return 1
    fi
    
    # Separate primary and standbys
    local -a standby_array=()
    local primary_scan=""
    local primary_service=""
    local primary_db=""
    
    while IFS= read -r member; do
        IFS='|' read -r db scan service role unique_name <<< "${member}"
        
        if [[ "${role}" == "PRIMARY" ]]; then
            primary_db="${db}"
            primary_scan="${scan}"
            primary_service="${service}"
            log_message "INFO" "Primary: ${db} (${unique_name})"
        elif [[ "${role}" == "PHYSICAL STANDBY" ]]; then
            standby_array+=("${db}|${scan}|${service}|${unique_name}")
            log_message "INFO" "Standby: ${db} (${unique_name})"
        fi
    done <<< "${dg_members}"
    
    local total_standbys=${#standby_array[@]}
    local operation_failed=0
    
    # STEP 1-4: Process STANDBYS
    if [[ ${total_standbys} -gt 0 ]]; then
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 1: Stopping apply on all standbys"
        log_message "INFO" "========================================"
        
        # Stop apply on all standbys first
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            if ! stop_apply_on_standby "${stby_unique}"; then
                log_message "ERROR" "Failed to stop apply on ${stby_db}, aborting"
                return 1
            fi
        done
        
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 2: Dropping restore point on all standbys"
        log_message "INFO" "========================================"
        
        local standby_counter=1
        local -a failed_standbys=()
        
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            log_message "INFO" "Processing standby ${standby_counter}/${total_standbys}: ${stby_db}"
            
            # Drop restore point on standby
            if drop_restore_point "${stby_scan}" "${stby_service}" "${rp_name}"; then
                log_message "INFO" "✓ Restore point dropped on standby: ${stby_db}"
            else
                log_message "ERROR" "✗ Failed to drop restore point on standby: ${stby_db}"
                failed_standbys+=("${stby_unique}")
            fi
            
            ((standby_counter++))
        done
        
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 3: Restarting apply on all standbys"
        log_message "INFO" "========================================"
        
        # Restart apply on all standbys
        for standby_info in "${standby_array[@]}"; do
            IFS='|' read -r stby_db stby_scan stby_service stby_unique <<< "${standby_info}"
            
            if ! start_apply_on_standby "${stby_unique}"; then
                log_message "WARN" "Failed to restart apply on ${stby_db} - manual intervention may be required"
            fi
        done
        
        # Check if any standbys failed
        if [[ ${#failed_standbys[@]} -gt 0 ]]; then
            log_message "ERROR" "Failed to drop restore point on ${#failed_standbys[@]} standby database(s)"
            operation_failed=1
        fi
    fi
    
    # STEP 4: Drop restore point on PRIMARY
    if [[ -n "${primary_scan}" ]]; then
        log_message "INFO" "========================================"
        log_message "INFO" "STEP 4: Dropping restore point on PRIMARY"
        log_message "INFO" "========================================"
        
        if drop_restore_point "${primary_scan}" "${primary_service}" "${rp_name}"; then
            log_message "INFO" "✓ Restore point dropped on primary: ${primary_db}"
        else
            log_message "ERROR" "✗ Failed to drop restore point on primary: ${primary_db}"
            operation_failed=1
        fi
    fi
    
    if [[ ${operation_failed} -eq 1 ]]; then
        log_message "ERROR" "Some operations failed during restore point drop"
        return 1
    fi
    
    log_message "INFO" "========================================"
    log_message "INFO" "Restore point '${rp_name}' dropped successfully on all databases"
    log_message "INFO" "========================================"
    
    return 0
}

################################################################################
# Function: create_restore_point (single database)
# Description: Creates restore point on a single database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
#            $3 - Restore point name
#            $4 - Guarantee flashback (YES/NO)
# Returns: 0 if successful, 1 if failed
################################################################################
create_restore_point() {
    local scan_host=$1
    local service_name=$2
    local rp_name=$3
    local guarantee="${4:-NO}"
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "DEBUG" "Creating restore point '${rp_name}' on ${scan_host}/${service_name}"
    
    # Check if restore point already exists
    local existing=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$restore_point where upper(name) = upper('${rp_name}');
exit;
EOF
)
    
    existing=$(echo "${existing}" | xargs)
    
    if [[ ${existing} -gt 0 ]]; then
        log_message "WARN" "Restore point '${rp_name}' already exists on this database"
        return 0
    fi
    
    # Create restore point
    local guarantee_clause=""
    if [[ "${guarantee}" == "YES" ]]; then
        guarantee_clause="GUARANTEE FLASHBACK DATABASE"
    fi
    
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
CREATE RESTORE POINT ${rp_name} ${guarantee_clause};
exit;
EOF
)
    
    if echo "${result}" | grep -qi "restore point created"; then
        local details=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0 linesize 200
select 'SCN: ' || scn || ', Time: ' || to_char(time, 'YYYY-MM-DD HH24:MI:SS') 
from v\$restore_point 
where upper(name) = upper('${rp_name}');
exit;
EOF
)
        log_message "DEBUG" "Restore point created - ${details}"
        return 0
    else
        log_message "ERROR" "Failed to create restore point: ${result}"
        return 1
    fi
}

################################################################################
# Function: drop_restore_point (single database)
# Description: Drops a specific restore point from a single database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
#            $3 - Restore point name
# Returns: 0 if successful, 1 if failed
################################################################################
drop_restore_point() {
    local scan_host=$1
    local service_name=$2
    local rp_name=$3
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "DEBUG" "Dropping restore point '${rp_name}' from ${scan_host}/${service_name}"
    
    # Check if restore point exists
    local existing=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$restore_point where upper(name) = upper('${rp_name}');
exit;
EOF
)
    
    existing=$(echo "${existing}" | xargs)
    
    if [[ ${existing} -eq 0 ]]; then
        log_message "WARN" "Restore point '${rp_name}' does not exist on this database"
        return 0
    fi
    
    # Drop restore point
    local result=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set serveroutput on feedback on
whenever sqlerror exit 1
DROP RESTORE POINT ${rp_name};
exit;
EOF
)
    
    if echo "${result}" | grep -qi "restore point dropped"; then
        log_message "DEBUG" "Restore point dropped successfully"
        return 0
    else
        log_message "ERROR" "Failed to drop restore point: ${result}"
        return 1
    fi
}

################################################################################
# Function: list_restore_points
# Description: Lists all restore points for a database
# Parameters: $1 - SCAN hostname
#            $2 - Service name
# Returns: HTML table with restore point information
################################################################################
list_restore_points() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Listing restore points for ${scan_host}/${service_name}"
    
    local output=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading on feedback off pagesize 1000 linesize 200
set markup html on
SELECT 
    name,
    scn,
    to_char(time, 'YYYY-MM-DD HH24:MI:SS') as "CREATION_TIME",
    database_incarnation#,
    guarantee_flashback_database,
    storage_size/1024/1024 as "SIZE_MB",
    preserved
FROM v\$restore_point
ORDER BY time DESC;
exit;
EOF
)
    
    echo "${output}"
}

################################################################################
# Additional functions from original implementation
################################################################################

# ... (keeping other functions like check_flashback_status, get_fra_usage,
#      generate_restore_point_report, validate_restore_point_prerequisites, etc.)
# ... (rest of the functions remain the same as before)

################################################################################
# End of Restore Point Functions
################################################################################

################################################################################
# Helper functions that remain the same
################################################################################

check_flashback_status() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Checking flashback database status"
    
    local output=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading on feedback off pagesize 1000 linesize 200
set markup html on
SELECT 
    flashback_on,
    log_mode,
    open_mode,
    to_char(oldest_flashback_time, 'YYYY-MM-DD HH24:MI:SS') as "OLDEST_FLASHBACK_TIME",
    to_char(oldest_flashback_scn) as "OLDEST_FLASHBACK_SCN",
    retention_target
FROM v\$database;
exit;
EOF
)
    
    echo "${output}"
}

get_fra_usage() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Checking Fast Recovery Area usage"
    
    local output=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading on feedback off pagesize 1000 linesize 200
set markup html on
SELECT 
    name,
    space_limit/1024/1024/1024 as "SPACE_LIMIT_GB",
    space_used/1024/1024/1024 as "SPACE_USED_GB",
    space_reclaimable/1024/1024/1024 as "SPACE_RECLAIMABLE_GB",
    number_of_files,
    round((space_used/space_limit)*100, 2) as "PCT_USED"
FROM v\$recovery_file_dest;
exit;
EOF
)
    
    echo "${output}"
}

get_restore_point_count() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    local count=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$restore_point;
exit;
EOF
)
    
    echo "${count}" | xargs
}

generate_restore_point_report() {
    local db_name=$1
    local scan_host=$2
    local service_name=$3
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="${REPORT_BASE_DIR}/${db_name}_restore_points_${timestamp}.html"
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Generating restore point report for ${db_name}"
    
    if ! test_db_connection "${scan_host}" "${service_name}"; then
        log_message "ERROR" "Cannot connect to database ${db_name}"
        return 1
    fi
    
    local rp_count=$(get_restore_point_count "${scan_host}" "${service_name}")
    
    {
        generate_html_header "Restore Point Report - ${db_name}"
        
        echo "<h2>Database Information</h2>"
        cat << EOFHTML
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Database Name</td><td>${db_name}</td></tr>
            <tr><td>SCAN Host</td><td>${scan_host}</td></tr>
            <tr><td>Service Name</td><td>${service_name}</td></tr>
            <tr><td>Report Time</td><td>$(date '+%Y-%m-%d %H:%M:%S')</td></tr>
            <tr><td>Total Restore Points</td><td><strong>${rp_count}</strong></td></tr>
        </table>
EOFHTML
        
        echo "<h2>Flashback Database Status</h2>"
        check_flashback_status "${scan_host}" "${service_name}"
        
        echo "<h2>Fast Recovery Area Usage</h2>"
        get_fra_usage "${scan_host}" "${service_name}"
        
        echo "<h2>Restore Points</h2>"
        
        if [[ ${rp_count} -eq 0 ]]; then
            echo '<div class="info-box">No restore points currently exist for this database.</div>'
        else
            list_restore_points "${scan_host}" "${service_name}"
        fi
        
        generate_html_footer
        
    } > "${report_file}"
    
    log_message "INFO" "Restore point report generated: ${report_file}"
    send_email "Restore Point Report - ${db_name}" "${report_file}"
    
    echo "${report_file}"
    return 0
}

validate_restore_point_prerequisites() {
    local scan_host=$1
    local service_name=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${scan_host}/${service_name} ${SYS_CONNECT_MODE}"
    
    log_message "INFO" "Validating restore point prerequisites"
    
    local db_mode=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select log_mode from v\$database;
exit;
EOF
)
    
    db_mode=$(echo "${db_mode}" | xargs)
    
    if [[ "${db_mode}" != "ARCHIVELOG" ]]; then
        log_message "WARN" "Database is not in ARCHIVELOG mode. Some restore point operations may be limited."
    fi
    
    local fra_dest=$(${ORACLE_HOME}/bin/sqlplus -S "${connection_string}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$recovery_file_dest;
exit;
EOF
)
    
    fra_dest=$(echo "${fra_dest}" | xargs)
    
    if [[ ${fra_dest} -eq 0 ]]; then
        log_message "WARN" "Fast Recovery Area is not configured. Guaranteed restore points cannot be created."
    fi
    
    log_message "INFO" "Prerequisites validation completed"
    return 0
}

################################################################################
# End of Restore Point Functions
################################################################################
