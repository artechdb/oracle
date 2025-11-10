#!/bin/bash
################################################################################
# Oracle 19c Data Guard Switchover Functions
# Description: Functions for performing Data Guard switchover operations
# Created: 2025-11-02
# Updated: 2025-11-09 - Added DGMGRL-based database identification
################################################################################

################################################################################
# DGMGRL Utility Functions
################################################################################

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
        log_message "ERROR" "Error connecting to Data Guard Broker or configuration does not exist"
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
# Function: get_primary_database_dgmgrl
# Description: Gets primary database details from DGMGRL
# Returns: PRIMARY_DB_UNIQUE_NAME (global variable)
################################################################################
get_primary_database_dgmgrl() {
    log_message "INFO" "Identifying primary database..."
    
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
    
    local primary_line=$(echo "${dg_show_config}" | grep -i "Primary database" | head -1)
    
    if [[ -z "${primary_line}" ]]; then
        log_message "ERROR" "Could not identify primary database"
        return 1
    fi
    
    PRIMARY_DB_UNIQUE_NAME=$(echo "${primary_line}" | sed 's/.*Primary database is \(.*\)/\1/' | xargs)
    
    log_message "INFO" "Primary database: ${PRIMARY_DB_UNIQUE_NAME}"
    
    return 0
}

################################################################################
# Function: get_all_standby_databases_dgmgrl
# Description: Gets all standby databases from DGMGRL
# Returns: STANDBY_DBS_ARRAY (array of db_unique_names)
################################################################################
get_all_standby_databases_dgmgrl() {
    log_message "INFO" "Getting all standby databases..."
    
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
    
    STANDBY_DBS_ARRAY=()
    
    while IFS= read -r line; do
        if echo "${line}" | grep -qi "Physical standby database"; then
            # Extract database name - handle various DGMGRL output formats
            # Format: "  STANDBY1 - Physical standby database"
            # or:     "    STANDBY1  - Physical standby database"
            local standby_db=$(echo "${line}" | awk '{print $1}' | xargs)
            
            # Remove any trailing/leading whitespace
            standby_db=$(echo "${standby_db}" | tr -d '[:space:]')
            
            if [[ -n "${standby_db}" ]]; then
                STANDBY_DBS_ARRAY+=("${standby_db}")
                log_message "INFO" "Found standby: '${standby_db}' (length: ${#standby_db})"
            fi
        fi
    done <<< "${dg_show_config}"
    
    log_message "INFO" "Found ${#STANDBY_DBS_ARRAY[@]} standby database(s)"
    
    # Debug: show array contents
    for idx in "${!STANDBY_DBS_ARRAY[@]}"; do
        log_message "INFO" "STANDBY_DBS_ARRAY[${idx}] = '${STANDBY_DBS_ARRAY[$idx]}'"
    done
    
    return 0
}

################################################################################
# Original Functions (Updated to use DGMGRL utilities)
################################################################################

################################################################################
# Function: list_dg_databases
# Description: Lists all databases in Data Guard configuration
# Parameters: $1 - Primary SCAN
#            $2 - Primary Service
# Returns: Array of database names
################################################################################
list_dg_databases() {
    local primary_scan=$1
    local primary_service=$2
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${primary_scan}/${primary_service}"
    
    log_message "INFO" "Listing Data Guard databases..."
    
    local db_list=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
show configuration;
exit;
EOF
)
    
    echo "${db_list}"
}

################################################################################
# Function: pre_switchover_validation_dgmgrl
# Description: Validates Data Guard is ready for switchover using DGMGRL
# Parameters: $1 - Target database unique name
# Returns: 0 if validation passed, 1 if failed
################################################################################
pre_switchover_validation_dgmgrl() {
    local target_db=$1
    
    log_message "INFO" "Validating Data Guard configuration..."
    
    # Check configuration status
    local dg_status=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
show configuration;
exit;
EOF
)
    
    if ! echo "${dg_status}" | grep -qi "SUCCESS"; then
        log_message "ERROR" "Data Guard configuration is not in SUCCESS state"
        echo "${dg_status}"
        return 1
    fi
    
    # Validate target database exists and is a standby
    local target_status=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
show database ${target_db};
exit;
EOF
)
    
    if ! echo "${target_status}" | grep -qi "PHYSICAL STANDBY"; then
        log_message "ERROR" "Target database ${target_db} is not a physical standby"
        return 1
    fi
    
    log_message "INFO" "Pre-switchover validation passed"
    return 0
}

################################################################################
# Function: rollback_switchover_dgmgrl
# Description: Attempts to rollback a failed switchover
# Parameters: $1 - Original primary database name
# Returns: 0 if rollback successful, 1 if failed
################################################################################
rollback_switchover_dgmgrl() {
    local original_primary=$1
    
    log_message "INFO" "Attempting to switch back to ${original_primary}..."
    
    local rollback_output=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
switchover to ${original_primary};
exit;
EOF
)
    
    if echo "${rollback_output}" | grep -qi "succeed"; then
        log_message "INFO" "Rollback successful"
        return 0
    else
        log_message "ERROR" "Rollback failed"
        return 1
    fi
}

################################################################################
# Function: pre_switchover_validation
# Description: Performs comprehensive pre-switchover validation
# Parameters: $1 - Primary SCAN
#            $2 - Primary Service
#            $3 - Target database name
# Returns: 0 if validation passed, 1 if failed
################################################################################
pre_switchover_validation() {
    local primary_scan=$1
    local primary_service=$2
    local target_db=$3
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${primary_scan}/${primary_service}"
    
    log_message "INFO" "Starting pre-switchover validation..."
    
    local validation_failed=0
    
    # Check 1: Validate Data Guard configuration
    log_message "INFO" "Validating Data Guard configuration..."
    if ! check_dg_configuration "${primary_scan}" "${primary_service}" > /dev/null; then
        log_message "ERROR" "Data Guard configuration check failed"
        validation_failed=1
    fi
    
    # Check 2: Check for archive log gaps
    log_message "INFO" "Checking for archive log gaps..."
    local gaps=$(${ORACLE_HOME}/bin/sqlplus -S "${SYS_USER}/${SYS_PASSWORD}@${primary_scan}/${primary_service} ${SYS_CONNECT_MODE}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$archive_gap;
exit;
EOF
)
    
    gaps=$(echo "${gaps}" | xargs)
    if [[ ${gaps} -gt 0 ]]; then
        log_message "ERROR" "Archive log gaps detected: ${gaps} gaps"
        validation_failed=1
    else
        log_message "INFO" "No archive log gaps detected"
    fi
    
    # Check 3: Validate database readiness
    log_message "INFO" "Validating database readiness..."
    local validation_output=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
validate database ${target_db};
exit;
EOF
)
    
    if echo "${validation_output}" | grep -qi "error"; then
        log_message "ERROR" "Database validation failed for ${target_db}"
        log_message "ERROR" "${validation_output}"
        validation_failed=1
    else
        log_message "INFO" "Database validation passed for ${target_db}"
    fi
    
    # Check 4: Check switchover status
    log_message "INFO" "Checking switchover status..."
    local switchover_status=$(${ORACLE_HOME}/bin/sqlplus -S "${SYS_USER}/${SYS_PASSWORD}@${primary_scan}/${primary_service} ${SYS_CONNECT_MODE}" << EOF
set heading off feedback off pagesize 0
select switchover_status from v\$database;
exit;
EOF
)
    
    switchover_status=$(echo "${switchover_status}" | xargs)
    log_message "INFO" "Current switchover status: ${switchover_status}"
    
    if [[ "${switchover_status}" != "TO STANDBY" ]] && [[ "${switchover_status}" != "SESSIONS ACTIVE" ]]; then
        log_message "ERROR" "Primary database not ready for switchover. Status: ${switchover_status}"
        validation_failed=1
    fi
    
    # Check 5: Verify target database switchover readiness
    log_message "INFO" "Verifying target database switchover readiness..."
    local target_status=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
show database ${target_db} 'SwitchoverStatus';
exit;
EOF
)
    
    log_message "INFO" "Target database status: ${target_status}"
    
    if [[ ${validation_failed} -eq 0 ]]; then
        log_message "INFO" "Pre-switchover validation PASSED"
        return 0
    else
        log_message "ERROR" "Pre-switchover validation FAILED"
        return 1
    fi
}

################################################################################
# Function: perform_switchover
# Description: Performs Data Guard switchover operation using DGMGRL
# Parameters: $1 - Target database unique name
# Returns: 0 if successful, 1 if failed
################################################################################
perform_switchover() {
    local target_db=$1
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local switchover_log="${LOG_BASE_DIR}/switchover_${target_db}_${timestamp}.log"
    
    log_message "INFO" "Starting switchover to ${target_db}..."
    log_message "INFO" "Switchover log: ${switchover_log}"
    
    # Create backup of current configuration
    log_message "INFO" "Backing up current Data Guard configuration..."
    ${ORACLE_HOME}/bin/dgmgrl -silent << EOF > "${switchover_log}" 2>&1
connect ${DG_CONNECT_STRING}
show configuration verbose;
exit;
EOF
    
    # Perform switchover using DGMGRL
    log_message "INFO" "Executing switchover command via DGMGRL..."
    local switchover_output=$(${ORACLE_HOME}/bin/dgmgrl -silent << EOF
connect ${DG_CONNECT_STRING}
switchover to ${target_db};
exit;
EOF
)
    
    echo "${switchover_output}" | tee -a "${switchover_log}"
    
    # Check if switchover was successful
    if echo "${switchover_output}" | grep -qi "succeed"; then
        log_message "INFO" "Switchover command completed successfully"
        
        # Wait for switchover to complete
        log_message "INFO" "Waiting for switchover to complete..."
        sleep 30
        
        return 0
    else
        log_message "ERROR" "Switchover command failed"
        log_message "ERROR" "${switchover_output}"
        return 1
    fi
}

################################################################################
# Function: post_switchover_validation
# Description: Performs post-switchover validation
# Parameters: $1 - New primary SCAN
#            $2 - New primary Service
#            $3 - Database name
# Returns: 0 if validation passed, 1 if failed
################################################################################
post_switchover_validation() {
    local new_primary_scan=$1
    local new_primary_service=$2
    local db_name=$3
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${new_primary_scan}/${new_primary_service}"
    
    log_message "INFO" "Starting post-switchover validation..."
    
    local validation_failed=0
    
    # Wait for database to stabilize
    sleep 10
    
    # Check 1: Verify new primary role
    log_message "INFO" "Verifying new primary database role..."
    local db_role=$(get_db_role "${new_primary_scan}" "${new_primary_service}")
    
    if [[ "${db_role}" != "PRIMARY" ]]; then
        log_message "ERROR" "Database role is not PRIMARY: ${db_role}"
        validation_failed=1
    else
        log_message "INFO" "New primary database role verified: ${db_role}"
    fi
    
    # Check 2: Check Data Guard configuration
    log_message "INFO" "Checking Data Guard configuration..."
    local dg_config=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
show configuration;
exit;
EOF
)
    
    if echo "${dg_config}" | grep -qi "error"; then
        log_message "ERROR" "Data Guard configuration has errors"
        validation_failed=1
    else
        log_message "INFO" "Data Guard configuration is healthy"
    fi
    
    # Check 3: Verify standby database is receiving redo
    log_message "INFO" "Verifying standby database is receiving redo..."
    sleep 10
    
    local standby_status=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
show configuration verbose;
exit;
EOF
)
    
    log_message "INFO" "Standby status: ${standby_status}"
    
    # Check 4: Verify no archive log gaps
    log_message "INFO" "Checking for archive log gaps..."
    local gaps=$(${ORACLE_HOME}/bin/sqlplus -S "${SYS_USER}/${SYS_PASSWORD}@${new_primary_scan}/${new_primary_service} ${SYS_CONNECT_MODE}" << EOF
set heading off feedback off pagesize 0
select count(*) from v\$archive_gap;
exit;
EOF
)
    
    gaps=$(echo "${gaps}" | xargs)
    if [[ ${gaps} -gt 0 ]]; then
        log_message "WARN" "Archive log gaps detected: ${gaps} gaps"
        # Not critical for post-switchover
    else
        log_message "INFO" "No archive log gaps detected"
    fi
    
    if [[ ${validation_failed} -eq 0 ]]; then
        log_message "INFO" "Post-switchover validation PASSED"
        return 0
    else
        log_message "ERROR" "Post-switchover validation FAILED"
        return 1
    fi
}

################################################################################
# Function: rollback_switchover
# Description: Attempts to rollback failed switchover
# Parameters: $1 - Original primary SCAN
#            $2 - Original primary Service
#            $3 - Original primary database name
# Returns: 0 if rollback successful, 1 if failed
################################################################################
rollback_switchover() {
    local original_primary_scan=$1
    local original_primary_service=$2
    local original_primary_db=$3
    local connection_string="${SYS_USER}/${SYS_PASSWORD}@${original_primary_scan}/${original_primary_service}"
    
    log_message "WARN" "Initiating switchover rollback..."
    log_message "WARN" "Attempting to switchback to original primary: ${original_primary_db}"
    
    # Try to connect to original primary
    if ! test_db_connection "${original_primary_scan}" "${original_primary_service}"; then
        log_message "ERROR" "Cannot connect to original primary database for rollback"
        return 1
    fi
    
    # Check current role
    local current_role=$(get_db_role "${original_primary_scan}" "${original_primary_service}")
    log_message "INFO" "Current role of original primary: ${current_role}"
    
    if [[ "${current_role}" == "PRIMARY" ]]; then
        log_message "INFO" "Original primary is still primary - no rollback needed"
        return 0
    fi
    
    # Attempt switchback
    log_message "INFO" "Attempting switchback to ${original_primary_db}..."
    
    local switchback_output=$(${ORACLE_HOME}/bin/dgmgrl << EOF
connect ${connection_string}
switchover to ${original_primary_db};
exit;
EOF
)
    
    echo "${switchback_output}"
    
    if echo "${switchback_output}" | grep -qi "succeed"; then
        log_message "INFO" "Switchback to original primary successful"
        sleep 30
        
        # Verify rollback
        local new_role=$(get_db_role "${original_primary_scan}" "${original_primary_service}")
        if [[ "${new_role}" == "PRIMARY" ]]; then
            log_message "INFO" "Rollback completed successfully"
            return 0
        else
            log_message "ERROR" "Rollback verification failed"
            return 1
        fi
    else
        log_message "ERROR" "Switchback command failed"
        return 1
    fi
}

################################################################################
# Function: generate_switchover_report
# Description: Generates switchover operation report
# Parameters: $1 - Database name
#            $2 - Target database
#            $3 - Switchover status (SUCCESS/FAILED)
#            $4 - Start time
#            $5 - End time
#            $6 - Additional details
################################################################################
generate_switchover_report() {
    local db_name=$1
    local target_db=$2
    local status=$3
    local start_time=$4
    local end_time=$5
    local details=$6
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="${REPORT_BASE_DIR}/${db_name}_switchover_${timestamp}.html"
    
    log_message "INFO" "Generating switchover report for ${db_name}"
    
    # Calculate duration
    local duration=$(($(date -d "${end_time}" +%s) - $(date -d "${start_time}" +%s)))
    local duration_formatted=$(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
    
    # Generate HTML report
    {
        generate_html_header "Data Guard Switchover Report - ${db_name}"
        
        echo "<h2>Switchover Summary</h2>"
        
        local status_class="status-ok"
        if [[ "${status}" == "FAILED" ]]; then
            status_class="status-error"
        fi
        
        cat << EOF
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Database Name</td><td>${db_name}</td></tr>
            <tr><td>Target Database</td><td>${target_db}</td></tr>
            <tr><td>Switchover Status</td><td class="${status_class}">${status}</td></tr>
            <tr><td>Start Time</td><td>${start_time}</td></tr>
            <tr><td>End Time</td><td>${end_time}</td></tr>
            <tr><td>Duration</td><td>${duration_formatted}</td></tr>
            <tr><td>Executed By</td><td>${USER}@$(hostname)</td></tr>
        </table>
EOF
        
        echo "<h2>Switchover Details</h2>"
        echo "<pre>${details}</pre>"
        
        if [[ "${status}" == "SUCCESS" ]]; then
            echo '<div class="info-box">'
            echo '<h3>Switchover Completed Successfully</h3>'
            echo '<p>The Data Guard switchover operation has been completed successfully.</p>'
            echo '<p><strong>New Primary:</strong> ' "${target_db}" '</p>'
            echo '</div>'
        else
            echo '<div class="error-box">'
            echo '<h3>Switchover Failed</h3>'
            echo '<p>The Data Guard switchover operation has failed. Please review the details and take corrective action.</p>'
            echo '</div>'
        fi
        
        echo "<h2>Post-Switchover Actions Required</h2>"
        echo "<ul>"
        echo "<li>Verify application connectivity to new primary database</li>"
        echo "<li>Monitor Data Guard lag and ensure synchronization</li>"
        echo "<li>Update connection strings if necessary</li>"
        echo "<li>Perform application-level testing</li>"
        echo "<li>Update monitoring and backup configurations</li>"
        echo "</ul>"
        
        generate_html_footer
        
    } > "${report_file}"
    
    log_message "INFO" "Switchover report generated: ${report_file}"
    
    # Send email
    local subject="Data Guard Switchover ${status} - ${db_name} to ${target_db}"
    send_email "${subject}" "${report_file}"
    
    echo "${report_file}"
    return 0
}

################################################################################
# Function: execute_switchover_with_validation
# Description: Executes complete switchover with pre/post validation
# Parameters: $1 - Database name
#            $2 - Target database name
# Returns: 0 if successful, 1 if failed
################################################################################
execute_switchover_with_validation() {
    local db_name=$1
    local target_db=$2
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local switchover_details=""
    
    log_message "INFO" "=========================================="
    log_message "INFO" "Starting Data Guard Switchover Process"
    log_message "INFO" "Database: ${db_name}"
    log_message "INFO" "Target: ${target_db}"
    log_message "INFO" "=========================================="
    
    # DG configuration should already be loaded from menu
    # Verify we have the connection string
    if [[ -z "${DG_CONNECT_STRING}" ]] || [[ -z "${DG_CONFIG_NAME}" ]]; then
        log_message "ERROR" "Data Guard configuration not initialized"
        switchover_details="Data Guard configuration not initialized"
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        generate_switchover_report "${db_name}" "${target_db}" "FAILED" "${start_time}" "${end_time}" "${switchover_details}"
        return 1
    fi
    
    log_message "INFO" "Using DG configuration: ${DG_CONFIG_NAME}"
    
    # Verify primary database (should already be identified from menu)
    if [[ -z "${PRIMARY_DB_UNIQUE_NAME}" ]]; then
        log_message "WARN" "Primary database not identified, identifying now..."
        if ! get_primary_database_dgmgrl; then
            log_message "ERROR" "Cannot identify primary database"
            switchover_details="Failed to identify primary database"
            local end_time=$(date '+%Y-%m-%d %H:%M:%S')
            generate_switchover_report "${db_name}" "${target_db}" "FAILED" "${start_time}" "${end_time}" "${switchover_details}"
            return 1
        fi
    fi
    
    log_message "INFO" "Primary database: ${PRIMARY_DB_UNIQUE_NAME}"
    switchover_details+="Primary Database: ${PRIMARY_DB_UNIQUE_NAME}\n"
    switchover_details+="Target Database: ${target_db}\n\n"
    
    # Pre-switchover validation
    log_message "INFO" "Step 1/4: Pre-switchover validation"
    switchover_details+="Step 1: Pre-switchover validation...\n"
    
    if ! pre_switchover_validation_dgmgrl "${target_db}"; then
        log_message "ERROR" "Pre-switchover validation failed. Aborting switchover."
        switchover_details+="Result: FAILED - Pre-switchover validation failed\n"
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        generate_switchover_report "${db_name}" "${target_db}" "FAILED" "${start_time}" "${end_time}" "${switchover_details}"
        return 1
    fi
    
    switchover_details+="Result: PASSED\n\n"
    
    # Perform switchover
    log_message "INFO" "Step 2/4: Performing switchover"
    switchover_details+="Step 2: Performing switchover to ${target_db}...\n"
    
    if ! perform_switchover "${target_db}"; then
        log_message "ERROR" "Switchover operation failed"
        switchover_details+="Result: FAILED - Switchover operation failed\n\n"
        
        # Attempt rollback
        log_message "WARN" "Step 3/4: Attempting rollback"
        switchover_details+="Step 3: Attempting rollback...\n"
        
        if rollback_switchover_dgmgrl "${PRIMARY_DB_UNIQUE_NAME}"; then
            log_message "INFO" "Rollback successful"
            switchover_details+="Result: Rollback SUCCESSFUL\n"
        else
            log_message "ERROR" "Rollback failed - manual intervention required"
            switchover_details+="Result: Rollback FAILED - Manual intervention required\n"
        fi
        
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        generate_switchover_report "${db_name}" "${target_db}" "FAILED" "${start_time}" "${end_time}" "${switchover_details}"
        return 1
    fi
    
    switchover_details+="Result: SUCCESS\n\n"
    
    # Post-switchover validation
    log_message "INFO" "Step 3/4: Post-switchover validation"
    switchover_details+="Step 3: Post-switchover validation...\n"
    
    # Post-switchover validation
    log_message "INFO" "Step 3/4: Post-switchover validation"
    switchover_details+="Step 3: Post-switchover validation...\n"
    
    sleep 30  # Wait for switchover to stabilize
    
    # Re-identify primary using DGMGRL (should now be the target)
    if ! get_primary_database_dgmgrl; then
        log_message "ERROR" "Cannot identify new primary after switchover"
        switchover_details+="Result: FAILED - Cannot identify new primary\n"
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        generate_switchover_report "${db_name}" "${target_db}" "FAILED" "${start_time}" "${end_time}" "${switchover_details}"
        return 1
    fi
    
    # Verify switchover succeeded
    if [[ "${PRIMARY_DB_UNIQUE_NAME}" == "${target_db}" ]]; then
        log_message "INFO" "Switchover successful - ${target_db} is now primary"
        switchover_details+="Result: PASSED - ${target_db} is now PRIMARY\n\n"
    else
        log_message "WARN" "Switchover may not have completed - primary is still ${PRIMARY_DB_UNIQUE_NAME}"
        switchover_details+="Result: WARNING - Primary is ${PRIMARY_DB_UNIQUE_NAME}, expected ${target_db}\n\n"
    fi
    
    # Final status
    log_message "INFO" "Step 4/4: Switchover completed"
    switchover_details+="Step 4: Switchover completed\n"
    switchover_details+="New Primary: ${PRIMARY_DB_UNIQUE_NAME}\n"
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_message "INFO" "=========================================="
    log_message "INFO" "Data Guard Switchover Completed Successfully"
    log_message "INFO" "=========================================="
    
    generate_switchover_report "${db_name}" "${target_db}" "SUCCESS" "${start_time}" "${end_time}" "${switchover_details}"
    
    return 0
}

################################################################################
# End of Data Guard Switchover Functions
################################################################################
