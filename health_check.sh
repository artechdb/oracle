get_report_status() {
    local report_file="$1"
    
    # Check for explicit status classes in the HTML
    if grep -q '<td class="status-fail"' "$report_file"; then
        echo "fail"
    elif grep -q '<td class="status-warning"' "$report_file"; then
        echo "warning"
    elif grep -q '<td class="status-pass"' "$report_file"; then
        echo "pass"
    else
        echo "fail"  # Default to fail if no status found
    fi
}

generate_summary_report() {
    local input_file="$1"
    local summary_file="$2"
    local total_pairs="$3"
    local success_count="$4"
    local fail_count="$5"
    
    # Calculate percentages (warnings counted as passes in stats)
    local success_percent=$(( (success_count + warning_count) * 100 / total_pairs ))
    local fail_percent=$(( fail_count * 100 / total_pairs ))
    
    # Start HTML report
    cat <<EOF > "$summary_file"
<!DOCTYPE html>
<html>
<head>
<style>
  /* ... (existing styles) ... */
  .status-warning {
    background-color: #fff3cd;
    color: #856404;
  }
</style>
</head>
<body>
<!-- ... (existing header content) ... -->
EOF

    # Process each PDB pair
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        
        local report_filename="detailed/${src_cdb}_to_${tgt_cdb}_${pdb}.html"
        local status status_class
        
        if [[ -f "$REPORT_DIR/$report_filename" ]]; then
            status=$(get_report_status "$REPORT_DIR/$report_filename")
            case "$status" in
                "fail")
                    status="FAIL"
                    status_class="status-fail"
                    ;;
                "warning")
                    status="WARNING"
                    status_class="status-warning"
                    ;;
                *)
                    status="PASS"
                    status_class="status-pass"
                    ;;
            esac
        else
            status="MISSING"
            status_class="status-fail"
        fi
        
        # Add row to summary table
        cat <<EOF >> "$summary_file"
    <tr>
      <td>$(to_upper "$src_cdb")</td>
      <td>$(to_upper "$tgt_cdb")</td>
      <td>$(to_upper "$pdb")</td>
      <td class="$status_class">$status</td>
      <td><a class="view-link" href="$report_filename">View Details</a></td>
    </tr>
EOF
    done < "$input_file"

    # Close HTML
    cat <<EOF >> "$summary_file"
</table>

<div class="summary-card">
  <h3>Status Legend</h3>
  <ul>
    <li><span class="status-pass">PASS</span> - All checks passed</li>
    <li><span class="status-warning">WARNING</span> - Non-critical issues found</li>
    <li><span class="status-fail">FAIL</span> - Critical failures found</li>
  </ul>
  <p>Note: Warnings are treated as passing in overall status</p>
</div>
</body>
</html>
EOF
}

# In your main processing loop:
warning_count=0
while IFS="|" read -r src_cdb tgt_cdb pdb; do
    # ... validation code ...
    
    status=$(get_report_status "$report_file")
    case "$status" in
        "fail") ((fail_count++)) ;;
        "warning") ((warning_count++)) ;;
        *) ((success_count++)) ;;
    esac
done < "$input_file"

echo "td.missing { color: #666; font-style: italic; }" >> "$report_file"
echo "h4 { margin-top: 20px; color: #2c3e50; }" >> "$report_file"

compare_parameters() {
    local src_conn="$1"
    local tgt_conn="$2"
    
    # Parameters to exclude from comparison
    local excluded_params="db_name|db_unique_name|instance_name|control_files|local_listener|remote_login_passwordfile"
    local excluded_prefixes="audit_|event|_dump_|trace_|hidden|_statistics"

    # Compare v$system_parameter (memory)
    echo "<h4>System Parameters (v\$system_parameter)</h4>" >> "$report_file"
    compare_param_set "$src_conn" "$tgt_conn" "
        SELECT name, value FROM v\$parameter 
        WHERE name NOT REGEXP '$excluded_prefixes'
        AND name NOT IN (${excluded_params//|/,})
        AND (isdefault = 'FALSE' OR value != default_value)"
    
    # Compare v$spparameter (spfile)
    echo "<h4>SPFile Parameters (v\$spparameter)</h4>" >> "$report_file"
    compare_param_set "$src_conn" "$tgt_conn" "
        SELECT name, value FROM v\$spparameter 
        WHERE name NOT REGEXP '$excluded_prefixes'
        AND name NOT IN (${excluded_params//|/,})
        AND value IS NOT NULL
        AND sid = '*'"
    
    # Compare database properties
    echo "<h4>Database Properties</h4>" >> "$report_file"
    compare_param_set "$src_conn" "$tgt_conn" "
        SELECT property_name, property_value 
        FROM database_properties
        WHERE property_name NOT LIKE 'DEFAULT%'"
}

compare_param_set() {
    local src_conn="$1"
    local tgt_conn="$2"
    local query="$3"
    
    # Get source parameters
    local src_params=$(mktemp)
    run_sql "$src_conn" "$query" | tr -d ' ' > "$src_params"
    
    # Get target parameters
    local tgt_params=$(mktemp)
    run_sql "$tgt_conn" "$query" | tr -d ' ' > "$tgt_params"
    
    # Compare and format differences
    echo "<table><tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> "$report_file"
    
    diff --unchanged-line-format='' \
         --old-line-format="<tr><td>%1\$s</td><td>%2\$s</td><td class=\"missing\">(Not Set)</td></tr>" \
         --new-line-format="<tr><td>%1\$s</td><td class=\"missing\">(Not Set)</td><td>%2\$s</td></tr>" \
         "$src_params" "$tgt_params" | \
    awk -F'|' '{print $1 "|" $2 "|" $4}' >> "$report_file"
    
    # Show value differences for common parameters
    comm -12 <(cut -d'|' -f1 "$src_params" | sort) <(cut -d'|' -f1 "$tgt_params" | sort) | while read param; do
        src_val=$(grep "^${param}|" "$src_params" | cut -d'|' -f2)
        tgt_val=$(grep "^${param}|" "$tgt_params" | cut -d'|' -f2)
        
        if [[ "$src_val" != "$tgt_val" ]]; then
            echo "<tr><td>$param</td><td>$src_val</td><td>$tgt_val</td></tr>" >> "$report_file"
        fi
    done
    
    echo "</table>" >> "$report_file"
    rm -f "$src_params" "$tgt_params"
}

validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    local report_file="$4"
    
    # ... [previous connection validation code remains unchanged] ...

    # 5. Perform compatibility checks (existing checks remain unchanged)
    local checks=(
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Configuration" "$(check_tde_config "$src_conn" "$tgt_conn")"
        # ... [other checks] ...
    )

    # ... [process check results as before] ...

    # 6. Add parameter discrepancy report (reference only)
    echo "<h3>Parameter Discrepancies (Reference Only)</h3>" >> "$report_file"
    echo "<table>" >> "$report_file"
    echo "<tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> "$report_file"
    
    # Get parameter differences (exclude common excluded parameters)
    diff_params=$(compare_parameters "$src_conn" "$tgt_conn")
    if [[ -n "$diff_params" ]]; then
        while IFS='|' read -r param src_val tgt_val; do
            echo "<tr><td>$param</td><td>$src_val</td><td>$tgt_val</td></tr>" >> "$report_file"
        done <<< "$diff_params"
    else
        echo "<tr><td colspan='3'>No significant parameter differences found</td></tr>" >> "$report_file"
    fi
    
    echo "</table>" >> "$report_file"

    # ... [final status determination remains unchanged] ...
}

# Helper function to compare parameters
compare_parameters() {
    local src_conn="$1"
    local tgt_conn="$2"
    
    # Exclude these parameters from comparison
    local excluded_params="db_name|db_unique_name|instance_name|control_files|local_listener"
    
    # Get source parameters
    src_params=$(mktemp)
    run_sql "$src_conn" "
        SELECT name, value FROM v\\$parameter 
        WHERE name NOT LIKE '%dump%'
        AND name NOT IN (${excluded_params//|/,})
        ORDER BY name" > "$src_params"
    
    # Get target parameters
    tgt_params=$(mktemp)
    run_sql "$tgt_conn" "
        SELECT name, value FROM v\\$parameter 
        WHERE name NOT LIKE '%dump%'
        AND name NOT IN (${excluded_params//|/,})
        ORDER BY name" > "$tgt_params"
    
    # Compare and format differences
    diff --unchanged-line-format='' --old-line-format='' \
         --new-line-format='%L' "$src_params" "$tgt_params" | \
    awk -F'|' '{print $1 "|" $2 "|" $4}'
    
    # Cleanup
    rm -f "$src_params" "$tgt_params"
}

validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    local report_file="$4"
    
    # Initialize HTML report for this pair
    html_header "$report_file"
    echo "<h2>PDB Clone Validation: $src_cdb/$pdb → $tgt_cdb</h2>" >> "$report_file"
    echo "<table>" >> "$report_file"
    
    # 1. Resolve connections
    local src_info=$(resolve_connection "$src_cdb")
    local tgt_info=$(resolve_connection "$tgt_cdb")
    
    # 2. Validate connections
    local src_conn tgt_conn
    if [[ "$src_info" == ERROR* ]]; then
        html_add_row "$report_file" "Source Connection" "fail" "${src_info#*|}" ""
        html_footer >> "$report_file"
        return 1
    else
        IFS='|' read -r _ src_host src_port <<< "$src_info"
        src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
        html_add_row "$report_file" "Source Connection" "pass" "Connected to ${src_host}:${src_port}" ""
    fi
    
    if [[ "$tgt_info" == ERROR* ]]; then
        html_add_row "$report_file" "Target Connection" "fail" "${tgt_info#*|}" ""
        html_footer >> "$report_file"
        return 1
    else
        IFS='|' read -r _ tgt_host tgt_port <<< "$tgt_info"
        tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
        html_add_row "$report_file" "Target Connection" "pass" "Connected to ${tgt_host}:${tgt_port}" ""
    fi
    
    # 3. Validate PDB in source
    local pdb_status=$(validate_pdb_connection "$src_conn" "$src_cdb" "$pdb")
    IFS='|' read -r status details <<< "$pdb_status"
    html_add_row "$report_file" "Source PDB Validation" "$status" "$details" ""
    [[ "$status" == "fail" ]] && { html_footer >> "$report_file"; return 1; }
    
    # 4. Validate target PDB doesn't exist
    local target_pdb_check=$(run_sql "$tgt_conn" "
        SELECT 'EXISTS' FROM v\\$pdbs WHERE UPPER(name) = UPPER('$pdb')")
    if [[ -n "$target_pdb_check" ]]; then
        html_add_row "$report_file" "Target PDB Check" "fail" "PDB $pdb already exists in target" ""
        html_footer >> "$report_file"
        return 1
    else
        html_add_row "$report_file" "Target PDB Check" "pass" "PDB $pdb available" ""
    fi
    
    # 5. Perform compatibility checks
    local checks=(
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Configuration" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
        "Character Set" "$(check_charset "$src_conn" "$tgt_conn")"
        "Parameters" "$(check_parameters "$src_conn" "$tgt_conn")"
        "MAX_PDB_STORAGE" "$(check_max_pdb_storage "$src_conn" "$tgt_conn" "$report_file")"
    )
    
    # Process check results
    local critical_fail=false
    for ((i=0; i<${#checks[@]}; i+=2)); do
        local check_name="${checks[i]}"
        IFS='|' read -r status details <<< "${checks[i+1]}"
        
        # Only fail on critical failures (ignore warnings)
        if [[ "$status" == "fail" ]]; then
            critical_fail=true
        fi
        
        html_add_row "$report_file" "$check_name" "$status" "$details" ""
    done
    
    # Final status (only fail if critical failures exist)
    if $critical_fail; then
        html_add_row "$report_file" "Overall Status" "fail" "Critical prechecks failed" ""
        html_footer >> "$report_file"
        return 1
    else
        html_add_row "$report_file" "Overall Status" "pass" "All prechecks passed (with warnings)" ""
        html_footer >> "$report_file"
        return 0
    fi
}
main() {
    local input_file="$1"
    local email_to="${2:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Initialize directories and counters
    REPORT_DIR="./reports/$timestamp"
    DETAILED_DIR="$REPORT_DIR/detailed"
    mkdir -p "$DETAILED_DIR"
    
    local pair_count=0
    local success_count=0
    local warning_count=0
    local fail_count=0
    
    # Process each PDB pair
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        
        echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
        ((pair_count++))
        
        # Generate individual report
        report_file="$DETAILED_DIR/${src_cdb}_to_${tgt_cdb}_${pdb}.html"
        html_header > "$report_file"
        
        # Validate and capture output
        if validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb" "$report_file"; then
            ((success_count++))
        else
            # Check if the failure was just warnings
            if grep -q "class=\"status-warning\"" "$report_file" && \
               ! grep -q "class=\"status-fail\"" "$report_file"; then
                ((warning_count++))
            else
                ((fail_count++))
            fi
        fi
        
        html_footer >> "$report_file"
    done < "$input_file"
    
    # Generate summary report (treat warnings as passes in summary)
    SUMMARY_FILE="$REPORT_DIR/summary_report.html"
    generate_summary_report "$input_file" "$SUMMARY_FILE" "$pair_count" \
                          "$((success_count + warning_count))" "$fail_count"
    
    # Create zip archive
    ZIP_FILE="$REPORT_DIR/pdb_precheck_reports.zip"
    zip -jqr "$ZIP_FILE" "$REPORT_DIR"/*.html "$DETAILED_DIR"/
    
    # Send notification (count warnings as successes)
    if [[ -n "$email_to" ]]; then
        send_notification "$email_to" "$ZIP_FILE" "$pair_count" \
                        "$((success_count + warning_count))"
    fi
    
    # Final status (only fail if actual failures exist)
    if [[ "$fail_count" -gt 0 ]]; then
        echo "Validation completed with $fail_count failure(s) and $warning_count warning(s)"
        echo "Reports available: $ZIP_FILE"
        return 1
    else
        echo "All $pair_count PDB pairs validated successfully ($warning_count with warnings)"
        echo "Reports available: $ZIP_FILE"
        return 0
    fi
}

generate_summary_report() {
    local input_file="$1"
    local summary_file="$2"
    local total_pairs="$3"
    local success_count="$4"
    local fail_count="$5"
    
    # Calculate percentages (treat warnings as passes)
    local success_percent=$(( (success_count + warning_count) * 100 / total_pairs ))
    local fail_percent=$(( fail_count * 100 / total_pairs ))
    
    # Start HTML report
    cat <<EOF > "$summary_file"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>PDB Clone Precheck Summary Report</title>
<style>
  body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 20px;
    color: #333;
  }
  .header {
    background-color: #2c3e50;
    color: white;
    padding: 20px;
    margin-bottom: 30px;
    border-radius: 5px;
  }
  .summary-card {
    background-color: #f8f9fa;
    border-radius: 5px;
    padding: 20px;
    margin-bottom: 30px;
    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
  }
  .progress-container {
    width: 100%;
    background-color: #e9ecef;
    border-radius: 5px;
    margin: 15px 0;
  }
  .progress-bar {
    height: 30px;
    border-radius: 5px;
    text-align: center;
    line-height: 30px;
    color: white;
    font-weight: bold;
  }
  .success-bar {
    background-color: #28a745;
    width: ${success_percent}%;
  }
  .fail-bar {
    background-color: #dc3545;
    width: ${fail_percent}%;
  }
  .report-table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 20px;
  }
  .report-table th, .report-table td {
    border: 1px solid #ddd;
    padding: 12px;
    text-align: left;
  }
  .report-table th {
    background-color: #2c3e50;
    color: white;
  }
  .status-pass {
    background-color: #d4edda;
    color: #155724;
  }
  .status-fail {
    background-color: #f8d7da;
    color: #721c24;
  }
  .view-link {
    color: #007bff;
    text-decoration: none;
    font-weight: bold;
  }
  .view-link:hover {
    text-decoration: underline;
  }
  .timestamp {
    color: #6c757d;
    font-size: 0.9em;
    margin-top: 10px;
  }
</style>
</head>
<body>
<div class="header">
  <h1>Oracle PDB Clone Precheck Summary Report</h1>
  <div class="timestamp">Generated: $(date "+%Y-%m-%d %H:%M:%S")</div>
</div>

<div class="summary-card">
  <h2>Validation Summary</h2>
  <p>Total PDB Pairs Checked: <strong>$total_pairs</strong></p>
  <p>Successful/Warning Prechecks: <strong>$success_count</strong></p>
  <p>Failed Prechecks: <strong>$fail_count</strong></p>
  
  <div class="progress-container">
    <div class="progress-bar success-bar">$success_percent% Valid</div>
    <div class="progress-bar fail-bar">$fail_percent% Failed</div>
  </div>
</div>

<table class="report-table">
  <thead>
    <tr>
      <th>Source CDB</th>
      <th>Target CDB</th>
      <th>PDB Name</th>
      <th>Status</th>
      <th>Details</th>
    </tr>
  </thead>
  <tbody>
EOF

    # Process each PDB pair and add to summary
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        
        local report_filename="detailed/${src_cdb}_to_${tgt_cdb}_${pdb}.html"
        local status status_class
        
        # Check if report exists and get status (treat warnings as passes)
        if [[ -f "$REPORT_DIR/$report_filename" ]]; then
            status=$(grep -oP '(?<=<td class="status-)(pass|fail|warning)' "$REPORT_DIR/$report_filename" | head -1)
            if [[ "$status" == "fail" ]]; then
                status="FAIL"
                status_class="status-fail"
            else
                status="PASS"
                status_class="status-pass"
            fi
        else
            status="MISSING"
            status_class="status-fail"
        fi
        
        # Add row to summary table
        cat <<EOF >> "$summary_file"
    <tr>
      <td>$(to_upper "$src_cdb")</td>
      <td>$(to_upper "$tgt_cdb")</td>
      <td>$(to_upper "$pdb")</td>
      <td class="$status_class">$status</td>
      <td><a class="view-link" href="$report_filename">View Full Report</a></td>
    </tr>
EOF
    done < "$input_file"

    # Close HTML
    cat <<EOF >> "$summary_file"
  </tbody>
</table>

<div class="summary-card">
  <h3>Next Steps</h3>
  <ul>
    <li>Review failed validations in the detailed reports</li>
    <li>Warnings are treated as passing checks in this summary</li>
    <li>All hyperlinks will work when extracted from the ZIP archive</li>
  </ul>
</div>

</body>
</html>
EOF

    echo "Summary report generated: $summary_file"
}
html_header() {
    cat <<EOF > "$1"
<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
  th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
  th { background-color: #f2f2f2; }
  .pass { background-color: #e8f5e9; color: #2e7d32; }
  .fail { background-color: #ffebee; color: #c62828; }
  .warning { background-color: #fff8e1; color: #f57f17; }
  .status-icon {
    display: inline-block;
    width: 20px;
    height: 20px;
    margin-right: 5px;
    border-radius: 50%;
    text-align: center;
    line-height: 20px;
    font-weight: bold;
  }
  .pass .status-icon { background-color: #4caf50; color: white; }
  .fail .status-icon { background-color: #f44336; color: white; }
  .warning .status-icon { background-color: #ffc107; color: black; }
</style>
<title>PDB Precheck Report</title>
</head>
<body>
<h2>Oracle PDB Clone Precheck Report</h2>
<table>
<tr>
  <th>Check</th>
  <th>Status</th>
  <th>Details</th>
  <th>Additional Info</th>
</tr>
EOF
}
send_notification() {
    local email_to="$1"
    local zip_file="$2"
    local total="$3"
    local success="$4"
    local fail_count=$((total - success))
    
    # Generate a boundary string
    local boundary="$(uuidgen)"
    local subject="PDB Precheck Report: $success/$total successful"
    
    # Create temporary email file
    local email_file=$(mktemp)
    
    # Build email headers
    cat <<EOF > "$email_file"
To: $email_to
From: $EMAIL_FROM
Subject: $subject
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--${boundary}
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 7bit

Oracle PDB clone precheck completed.

Summary:
- Total PDB pairs checked: $total
- Successful prechecks: $success
- Failed prechecks: $fail_count

The attached ZIP file contains all validation reports.
Extract the ZIP to view the HTML reports with working hyperlinks.

--${boundary}
Content-Type: application/zip
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$(basename "$zip_file")"

EOF
    
    # Add the zip file as base64 encoded attachment
    base64 "$zip_file" >> "$email_file"
    
    # Close the email
    echo "--${boundary}--" >> "$email_file"
    
    # Send the email using sendmail
    /usr/sbin/sendmail -t -oi < "$email_file"
    
    # Clean up
    rm -f "$email_file"
    
    # Verify delivery
    if [ $? -eq 0 ]; then
        echo "Notification sent to $email_to"
    else
        echo "Failed to send notification email"
        return 1
    fi
}
html_add_row() {
    local report_file="$1"
    local check_name="$2"
    local status="$3"
    local details="$4"
    local extra_info="$5"
    
    # Determine CSS class based on status
    local status_class
    case "$status" in
        "pass") status_class="pass" ;;
        "fail") status_class="fail" ;;
        *) status_class="warning" ;;
    esac
    
    # Escape HTML special characters in details
    details=$(echo "$details" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    
    # Write the table row
    cat <<EOF >> "$report_file"
<tr>
  <td>$check_name</td>
  <td class="$status_class">${status^^}</td>
  <td>${details:-N/A}</td>
  <td>${extra_info:-}</td>
</tr>
EOF
    
    # Add status-specific icons
    sed -i "s|>${status^^}</td>|><span class=\"status-icon\">${status^^}</span></td>|g" "$report_file"
}
validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    local report_file="$4"
    
    # Initialize HTML report for this pair
    html_header "$report_file"
    echo "<h2>PDB Clone Validation: $src_cdb/$pdb → $tgt_cdb</h2>" >> "$report_file"
    echo "<table>" >> "$report_file"
    
    # 1. Resolve connections
    local src_info=$(resolve_connection "$src_cdb")
    local tgt_info=$(resolve_connection "$tgt_cdb")
    
    # 2. Validate connections
    local src_conn tgt_conn
    if [[ "$src_info" == ERROR* ]]; then
        html_add_row "$report_file" "Source Connection" "fail" "${src_info#*|}" ""
        return 1
    else
        IFS='|' read -r _ src_host src_port <<< "$src_info"
        src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
        html_add_row "$report_file" "Source Connection" "pass" "Connected to ${src_host}:${src_port}" ""
    fi
    
    if [[ "$tgt_info" == ERROR* ]]; then
        html_add_row "$report_file" "Target Connection" "fail" "${tgt_info#*|}" ""
        return 1
    else
        IFS='|' read -r _ tgt_host tgt_port <<< "$tgt_info"
        tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
        html_add_row "$report_file" "Target Connection" "pass" "Connected to ${tgt_host}:${tgt_port}" ""
    fi
    
    # 3. Validate PDB in source
    local pdb_status=$(validate_pdb_connection "$src_conn" "$src_cdb" "$pdb")
    IFS='|' read -r status details <<< "$pdb_status"
    html_add_row "$report_file" "Source PDB Validation" "$status" "$details" ""
    [[ "$status" != "pass" ]] && return 1
    
    # 4. Validate target PDB doesn't exist
    local target_pdb_check=$(run_sql "$tgt_conn" "
        SELECT 'EXISTS' FROM v\\$pdbs WHERE UPPER(name) = UPPER('$pdb')")
    if [[ -n "$target_pdb_check" ]]; then
        html_add_row "$report_file" "Target PDB Check" "fail" "PDB $pdb already exists in target" ""
        return 1
    else
        html_add_row "$report_file" "Target PDB Check" "pass" "PDB $pdb available" ""
    fi
    
    # 5. Perform compatibility checks
    local checks=(
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Configuration" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
        "Character Set" "$(check_charset "$src_conn" "$tgt_conn")"
        "Parameters" "$(check_parameters "$src_conn" "$tgt_conn")"
    )
    
    # Process check results
    local all_checks_passed=true
    for ((i=0; i<${#checks[@]}; i+=2)); do
        local check_name="${checks[i]}"
        IFS='|' read -r status details <<< "${checks[i+1]}"
        
        html_add_row "$report_file" "$check_name" "$status" "$details" ""
        
        if [[ "$status" != "pass" ]]; then
            all_checks_passed=false
        fi
    done
    
    # Final status
    if $all_checks_passed; then
        html_add_row "$report_file" "Overall Status" "pass" "All prechecks passed" ""
        return 0
    else
        html_add_row "$report_file" "Overall Status" "fail" "One or more prechecks failed" ""
        return 1
    fi
}
#!/bin/bash
# Oracle PDB Clone Precheck with Zipped Reports
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Load configuration and functions
source ./pdb_precheck_config.sh
source ./pdb_precheck_functions.sh

# Main execution function
main() {
    local input_file="$1"
    local email_to="${2:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Initialize directories
    REPORT_DIR="./reports/$timestamp"
    DETAILED_DIR="$REPORT_DIR/detailed"
    mkdir -p "$DETAILED_DIR"
    
    # Process each PDB pair
    local pair_count=0
    local success_count=0
    local fail_count=0
    
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        
        echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
        ((pair_count++))
        
        # Generate individual report
        report_file="$DETAILED_DIR/${src_cdb}_to_${tgt_cdb}_${pdb}.html"
        html_header > "$report_file"
        
        if validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb" >> "$report_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
        html_footer >> "$report_file"
    done < "$input_file"
    
    # Generate summary report
    SUMMARY_FILE="$REPORT_DIR/summary_report.html"
    generate_summary_report "$input_file" "$SUMMARY_FILE" "$pair_count" "$success_count" "$fail_count"
    
    # Create zip archive
    ZIP_FILE="$REPORT_DIR/pdb_precheck_reports.zip"
    zip -jqr "$ZIP_FILE" "$REPORT_DIR"/*.html "$DETAILED_DIR"/
    
    # Send notification
    if [[ -n "$email_to" ]]; then
        send_notification "$email_to" "$ZIP_FILE" "$pair_count" "$success_count"
    fi
    
    # Final status
    if [[ "$fail_count" -gt 0 ]]; then
        echo "Validation completed with $fail_count failure(s)"
        echo "Reports available: $ZIP_FILE"
        return 1
    else
        echo "All $pair_count PDB pairs validated successfully"
        echo "Reports available: $ZIP_FILE"
        return 0
    fi
}

# Enhanced email function with zip attachment
send_notification() {
    local email_to="$1"
    local zip_file="$2"
    local total="$3"
    local success="$4"
    
    local subject="PDB Precheck Report: $success/$total successful"
    local body=$(cat <<EOF
Oracle PDB clone precheck completed.

Summary:
- Total PDB pairs checked: $total
- Successful prechecks: $success
- Failed prechecks: $((total - success))

The attached ZIP file contains:
1. summary_report.html - Executive summary
2. detailed/*.html - Individual validation reports

All internal hyperlinks will work when extracted from the ZIP archive.
EOF
    )
    
    echo "$body" | mailx -s "$subject" -a "$zip_file" -r "$EMAIL_FROM" "$email_to"
}

# Execute main function
main "$@"
exit $?

#!/bin/bash
# Oracle PDB Clone Precheck - Main Execution Script
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Load configuration and functions
source ./pdb_precheck_config.sh
source ./pdb_precheck_functions.sh

# Main execution function
main() {
    local input_file="$1"
    local email_to="${2:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Initialize directories and files
    REPORT_DIR="./reports/$timestamp"
    HTML_FILE="$REPORT_DIR/detailed_report.html"
    SUMMARY_FILE="$REPORT_DIR/summary_report.html"
    mkdir -p "$REPORT_DIR"
    
    # Start detailed report
    html_header > "$HTML_FILE"
    
    # Process each PDB pair
    local pair_count=0
    local success_count=0
    local fail_count=0
    
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        # Skip comments and empty lines
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        
        echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
        ((pair_count++))
        
        # Validate the PDB pair
        if validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
    done < "$input_file"
    
    # Complete detailed report
    html_footer >> "$HTML_FILE"
    
    # Generate summary report
    generate_summary_report "$input_file" "$SUMMARY_FILE" "$pair_count" "$success_count" "$fail_count"
    
    # Send notification
    if [[ -n "$email_to" ]]; then
        send_notification "$email_to" "$SUMMARY_FILE" "$pair_count" "$success_count"
    fi
    
    # Final status
    if [[ "$fail_count" -gt 0 ]]; then
        echo "Validation completed with $fail_count failure(s)"
        return 1
    else
        echo "All $pair_count PDB pairs validated successfully"
        return 0
    fi
}

# Helper function to send email notification
send_notification() {
    local email_to="$1"
    local report_file="$2"
    local total="$3"
    local success="$4"
    
    local subject="PDB Precheck Report: $success/$total successful"
    local body="Oracle PDB clone precheck completed. See attached report."
    
    echo "$body" | mailx -s "$subject" -a "$report_file" -r "$EMAIL_FROM" "$email_to"
}

# Execute main function
main "$@"
exit $?
generate_summary_report() {
    local input_file="$1"
    local report_file="$REPORT_DIR/summary_report_$(date +%Y%m%d_%H%M%S).html"
    local overall_status="PASS"
    local total_pairs=0
    local passed_pairs=0
    local failed_pairs=0

    # Start HTML report
    cat <<EOF > "$report_file"
<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h1 { color: #333; }
  .summary-table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
  .summary-table th, .summary-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
  .summary-table th { background-color: #f2f2f2; }
  .pass { background-color: #dfffdf; }
  .fail { background-color: #ffe8e8; }
  .warning { background-color: #fff3e0; }
  .status-header { width: 100px; }
  .details-header { width: 300px; }
  .summary-stats { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-radius: 5px; }
  .timestamp { color: #666; font-size: 0.9em; }
</style>
<title>PDB Clone Precheck Summary Report</title>
</head>
<body>
<h1>Oracle PDB Clone Precheck Summary Report</h1>
<div class="timestamp">Generated: $(date)</div>
<div class="summary-stats">
EOF

    # Process each PDB pair and collect results
    while IFS="|" read -r src_cdb tgt_cdb pdb; do
        [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
        ((total_pairs++))
        
        # Get the detailed report filename for this pair
        report_filename="${REPORT_DIR}/${src_cdb}_to_${tgt_cdb}_${pdb}_report.html"
        
        # Check if detailed report exists and get status
        if [[ -f "$report_filename" ]]; then
            status=$(grep -oP '(?<=<td class=")[^"]+' "$report_filename" | head -1)
            if [[ "$status" == "pass" ]]; then
                ((passed_pairs++))
                status_label="PASS"
                status_class="pass"
            else
                ((failed_pairs++))
                status_label="FAIL"
                status_class="fail"
                overall_status="FAIL"
            fi
        else
            ((failed_pairs++))
            status_label="MISSING"
            status_class="fail"
            overall_status="FAIL"
        fi

        # Add row to summary table
        cat <<EOF >> "$report_file"
<table class="summary-table">
<tr>
  <th>Source CDB</th>
  <th>Target CDB</th>
  <th>PDB</th>
  <th class="status-header">Status</th>
  <th class="details-header">Details</th>
</tr>
<tr>
  <td>$(to_upper "$src_cdb")</td>
  <td>$(to_upper "$tgt_cdb")</td>
  <td>$(to_upper "$pdb")</td>
  <td class="$status_class">$status_label</td>
  <td><a href="$(basename "$report_filename")">View Details</a></td>
</tr>
</table>
EOF

    done < "$input_file"

    # Add summary statistics
    cat <<EOF >> "$report_file"
</div>
<div class="summary-stats">
  <h3>Summary Statistics</h3>
  <p>Total PDB Pairs Checked: $total_pairs</p>
  <p>Successful Prechecks: <span class="pass">$passed_pairs</span></p>
  <p>Failed Prechecks: <span class="fail">$failed_pairs</span></p>
  <p>Overall Status: <span class="${overall_status,,}">$overall_status</span></p>
</div>

<h3>Precheck Details</h3>
<p>Click on 'View Details' links above to see individual precheck reports.</p>
</body>
</html>
EOF

    echo "Summary report generated: $report_file"
}

pdb_precheck/
├── bin/
│   └── pdb_precheck_main.sh
├── lib/
│   ├── precheck_config.sh
│   ├── precheck_html.sh
│   └── precheck_validation.sh
├── templates/
│   └── summary.html
└── input.cfg
1. precheck_config.sh:

bash
#!/bin/bash
# Configuration
REPORT_DIR="./reports"
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
HTML_HEADER="<!DOCTYPE html><html><head><title>PDB Precheck Report</title>
<style>...(keep previous styles)...</style></head><body>"
declare -A REPORT_STATUS
2. precheck_html.sh:

bash
#!/bin/bash
# HTML Generation Functions

start_html() {
    echo "$HTML_HEADER" > "$1"
}

add_summary_row() {
    echo "<tr><td>$1</td><td>$2</td><td class='$3'><a href='$4'>$5</a></td></tr>" >> "$2"
}

end_html() {
    echo "</body></html>" >> "$1"
}
3. precheck_validation.sh:

bash
#!/bin/bash
# Validation Functions

validate_connection() {
    local conn_str="$1"
    $SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect $conn_str
SELECT 1 FROM DUAL;
exit
EOF
    return $?
}

check_tde_compatibility() {
    local src_conn="$1" tgt_conn="$2" report_file="$3"
    # TDE validation logic
}

check_parameters() {
    local src_conn="$1" tgt_conn="$2" report_file="$3"
    # Parameter comparison logic
}
4. pdb_precheck_main.sh:

bash
#!/bin/bash
# Main Execution Script

source ./lib/precheck_config.sh
source ./lib/precheck_html.sh
source ./lib/precheck_validation.sh

INPUT_FILE="$1"
SUMMARY_REPORT="$REPORT_DIR/summary_$(date +%Y%m%d_%H%M%S).html"

process_pdb_pair() {
    local src_host=$1 src_port=$2 src_cdb=$3 src_pdb=$4
    local tgt_host=$5 tgt_port=$6 tgt_cdb=$7 tgt_pdb=$8
    
    local report_file="$REPORT_DIR/${src_pdb}_to_${tgt_pdb}_$(date +%s).html"
    local status="PASS"
    
    start_html "$report_file"
    
    # Connection checks
    if ! validate_connection "/@//${src_host}:${src_port}/${src_cdb} as sysdba"; then
        echo "<div class='fail'>Source CDB connection failed</div>" >> "$report_file"
        status="FAIL"
    fi
    
    if ! validate_connection "/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"; then
        echo "<div class='fail'>Target CDB connection failed</div>" >> "$report_file"
        status="FAIL"
    fi

    # Only proceed with checks if connections succeeded
    if [ "$status" == "PASS" ]; then
        check_tde_compatibility "/@//${src_host}:${src_port}/${src_cdb}" \
                              "/@//${tgt_host}:${tgt_port}/${tgt_cdb}" \
                              "$report_file" || status="FAIL"
                              
        check_parameters "/@//${src_host}:${src_port}/${src_cdb}" \
                        "/@//${tgt_host}:${tgt_port}/${tgt_cdb}" \
                        "$report_file" || status="FAIL"
    fi

    end_html "$report_file"
    REPORT_STATUS["${src_pdb}_${tgt_pdb}"]="$status|$report_file"
}

generate_summary() {
    start_html "$SUMMARY_REPORT"
    echo "<h2>PDB Clone Precheck Summary</h2><table><tr><th>Source PDB</th><th>Target PDB</th><th>Status</th></tr>" >> "$SUMMARY_REPORT"
    
    for pair in "${!REPORT_STATUS[@]}"; do
        IFS='|' read -r status report_file <<< "${REPORT_STATUS[$pair]}"
        src_pdb=${pair%%_*}
        tgt_pdb=${pair#*_}
        add_summary_row "$src_pdb" "$tgt_pdb" "$status" "./$(basename "$report_file")" "$status" "$SUMMARY_REPORT"
    done
    
    echo "</table>" >> "$SUMMARY_REPORT"
    end_html "$SUMMARY_REPORT"
}

# Main execution
mkdir -p "$REPORT_DIR"
while IFS="|" read -r src_host src_port src_cdb src_pdb tgt_host tgt_port tgt_cdb tgt_pdb; do
    [[ "$src_host" =~ ^# ]] && continue
    process_pdb_pair "$src_host" "$src_port" "$src_cdb" "$src_pdb" \
                     "$tgt_host" "$tgt_port" "$tgt_cdb" "$tgt_pdb"
done < "$INPUT_FILE"

generate_summary
echo "Summary report: $SUMMARY_REPORT"
Sample Input File Format (input.cfg):

# Format:
# source_host|source_port|source_cdb|source_pdb|target_host|target_port|target_cdb|target_pdb
dbhost01|1521|CDB1|HRPDB|dbhost02|1521|CDB2|HRCLONE
dbhost01|1521|CDB1|FINPDB|dbhost03|1521|CDB3|FINCLONE
Key Features:

Multiple PDB Pair Processing:

bash
while IFS="|" read -r src_host ...; do
    process_pdb_pair ...
done < "$INPUT_FILE"
Individual Reports with Hyperlinks:

bash
REPORT_STATUS["${src_pdb}_${tgt_pdb}"]="$status|$report_file"
add_summary_row ... "./$(basename "$report_file")" ...
Comprehensive Status Tracking:

bash
local status="PASS"
check_tde_compatibility ... || status="FAIL"
Connection Validation:

bash
validate_connection "/@//${src_host}:${src_port}/${src_cdb} as sysdba"
Usage:

bash
chmod +x bin/pdb_precheck_main.sh
./bin/pdb_precheck_main.sh input.cfg
Sample Output Structure:

reports/
├── HRPDB_to_HRCLONE_1620000000.html
├── FINPDB_to_FINCLONE_1620000001.html
└── summary_20231101_1430.html

#!/bin/bash
# Enhanced MAX_STRING_SIZE Check (precheck_db_checks.sh)

check_max_string_size() {
    local src_cdb="$1"
    local tgt_cdb="$2"
    
    # Get MAX_STRING_SIZE with fallback to Oracle default
    src_size=$(run_sql "/@$src_cdb as sysdba" "
        SELECT COALESCE(
            (SELECT value FROM v\$parameter WHERE name = 'max_string_size'),
            'STANDARD'  -- Oracle 19c default if parameter not set
        ) FROM DUAL;")

    tgt_size=$(run_sql "/@$tgt_cdb as sysdba" "
        SELECT COALESCE(
            (SELECT value FROM v\$parameter WHERE name = 'max_string_size'),
            'STANDARD'
        ) FROM DUAL;")

    # Explicit comparison check
    if [ "$src_size" != "$tgt_size" ]; then
        html_add_row "MAX_STRING_SIZE" "$src_size" "$tgt_size" "FAIL" "Critical mismatch - CDBs must have identical settings"
        return 1
    else
        # Additional check for actual extended data usage
        if [ "$src_size" == "STANDARD" ]; then
            src_ext_count=$(run_sql "/@$src_cdb as sysdba" "
                SELECT COUNT(*) FROM dba_tab_columns
                WHERE (data_type = 'VARCHAR2' AND char_used = 'C' AND char_length > 4000)
                   OR (data_type = 'NVARCHAR2' AND char_used = 'C' AND char_length > 2000)
                   OR (data_type = 'RAW' AND data_length > 2000);")
            
            if [ "$src_ext_count" -gt 0 ]; then
                html_add_row "MAX_STRING_SIZE" "STANDARD" "STANDARD" "FAIL" "Source contains $src_ext_count extended-size columns while in STANDARD mode"
                return 1
            fi
        fi
        
        html_add_row "MAX_STRING_SIZE" "$src_size" "$tgt_size" "PASS" "Configuration compatible"
        return 0
    fi
}

col object_name for a35
col cnt for 99999
 
SELECT
  cnt, object_name, object_type,file#, dbablk, obj, tch, hladdr
FROM (
  select count(*) cnt, rfile, block from (
    SELECT /*+ ORDERED USE_NL(l.x$ksuprlat) */
      --l.laddr, u.laddr, u.laddrx, u.laddrr,
      dbms_utility.data_block_address_file(to_number(object,'XXXXXXXX')) rfile,
      dbms_utility.data_block_address_block(to_number(object,'XXXXXXXX')) block
    FROM
       (SELECT /*+ NO_MERGE */ 1 FROM DUAL CONNECT BY LEVEL <= 100000) s,
       (SELECT ksuprlnm LNAME, ksuprsid sid, ksuprlat laddr,
       TO_CHAR(ksulawhy,'XXXXXXXXXXXXXXXX') object
        FROM x$ksuprlat) l,
       (select  indx, kslednam from x$ksled ) e,
       (SELECT
                    indx
                  , ksusesqh     sqlhash
   , ksuseopc
   , ksusep1r laddr
             FROM x$ksuse) u
    WHERE LOWER(l.Lname) LIKE LOWER('%cache buffers chains%')
     AND  u.laddr=l.laddr
     AND  u.ksuseopc=e.indx
     AND  e.kslednam like '%cache buffers chains%'
    )
   group by rfile, block
   ) objs,
     x$bh bh,
     dba_objects o
WHERE
      bh.file#=objs.rfile
 and  bh.dbablk=objs.block
 and  o.object_id=bh.obj
order by cnt
;

select start_time,round (100*"'LOAD'"/"'NUM_CPU_CORES'") AS LOAD from
(
select os.INSTANCE_NUMBER,stat_name,sum(os.value) as load,
min(to_date(to_char(s.begin_interval_time,'DD.MM.YYYY hh24.mi.ss'))) as START_TIME,max(to_date(to_char(s.end_interval_time,'DD.MM.YYYY hh24.mi.ss'))) end_time
from DBA_HIST_OSSTAT os join
DBA_HIST_SNAPSHOT s on s.snap_id= os.SNAP_ID
where os.stat_name in ('LOAD','NUM_CPU_CORES','INSTANCE_NUMBER')
group by os.stat_name, (trunc(to_date(to_char(s.begin_interval_time,'DD.MM.YYYY hh24.mi.ss')),'HH24')),os.INSTANCE_NUMBER   
)
  pivot( max(LOAD) for stat_name in ('LOAD','NUM_CPU_CORES') )
  where instance_number=2
order by instance_number,start_time asc ;

select  cast(min (ash.SAMPLE_TIME) as date) as start#
     ,round (24*60*(cast (max(ash.SAMPLE_TIME) as date) - cast(min (ash.SAMPLE_TIME) as date) ),2) as duration#
     ,ash.sql_id,ash.top_level_sql_id,ash.BLOCKING_SESSION as B_SID,ash.BLOCKING_SESSION_SERIAL# as b_serial#
     ,ash2.SQL_EXEC_ID b_sql_exec_id
     ,ash.event,do.object_name
     ,sum(decode(ash.session_state,'ON CPU',1,0))     "CPU"
     ,sum(decode(ash.session_state,'WAITING',1,0))    -         sum(decode(ash.session_state,'WAITING', decode(ash.wait_class, 'User I/O',1,0),0))    "WAIT"
     ,sum(decode(ash.session_state,'WAITING', decode(ash.wait_class, 'User I/O',1,0),0))    "IO"
     ,sum(decode(ash.session_state,'ON CPU',1,1))     "TOTAL"
     ,du.username,ash2.SQL_EXEC_ID,
          dp.owner||nvl2(dp.object_name,'.'||dp.object_name,null) ||nvl2(dp.procedure_name,'.'||dp.procedure_name,null) as pl_sql_obj
          ,ash2.machine as blocking_machine
from dba_hist_active_sess_history ash
  left join dba_objects do on do.object_id=ash.CURRENT_OBJ#
  join dba_hist_active_sess_history ash2 on ash.BLOCKING_SESSION=ash2.session_id and ash.BLOCKING_SESSION_SERIAL#=ash2.session_serial# and ash.SNAP_ID=ash2.SNAP_ID
    join dba_users du on du.USER_ID=ash2.USER_ID
    left join dba_procedures dp on dp.object_id=ash2.PLSQL_ENTRY_OBJECT_ID and dp.subprogram_id=ash.PLSQL_ENTRY_SUBPROGRAM_ID
where ash.SQL_ID is not NULL      
and ash.SAMPLE_TIME >  trunc(sysdate)
group by ash.SQL_EXEC_ID,ash2.SQL_EXEC_ID, ash2.machine, ash.session_id,ash.session_serial#,ash.event,ash.sql_id,ash.top_level_sql_id,ash.BLOCKING_SESSION,ash.BLOCKING_SESSION_SERIAL#, ash2.sql_id    ,du.username,
          dp.owner||nvl2(dp.object_name,'.'||dp.object_name,null) ||nvl2(dp.procedure_name,'.'||dp.procedure_name,null)
               ,do.object_name
having  sum(decode(ash.session_state,'WAITING',1,0)) - sum(decode(ash.session_state,'WAITING', decode(ash.wait_class, 'User I/O',1,0),0))  >0
and max(ash.SAMPLE_TIME) - min (ash.SAMPLE_TIME) > interval '3' minute
order by 1,ash2.sql_exec_id;

select t.start#,t.end#,t.sql_id,t.plan_hash_value,t.execs,t.avg_sec,u.username,s.sql_text from (
select min(begin_interval_time) start#,max(begin_interval_time) end#, sql_id, plan_hash_value,
sum(nvl(executions_delta,0)) execs,
round ((sum(elapsed_time_delta)/(sum(executions_delta)))/1000000) avg_sec
,PARSING_SCHEMA_ID
,PARSING_USER_ID
from DBA_HIST_SQLSTAT S, DBA_HIST_SNAPSHOT SS
where 1=1
and ss.snap_id = S.snap_id
and ss.instance_number = S.instance_number
and executions_delta > 0
and (elapsed_time_delta/decode(nvl(executions_delta,0),0,1,executions_delta))/1000000 > 5
group by sql_id, plan_hash_value
,PARSING_SCHEMA_ID,PARSING_USER_ID
)t
join dba_hist_sqltext s on s.sql_id=t.sql_id
join dba_users u on t.parsing_user_id=u.user_id
order by execs desc;


select * from (
select s.sql_id,
sum( nvl(s.executions_delta,0)) execs,TO_CHAR (ss.begin_interval_time, ‘DD.MM.YYYY HH24’) date#
— sum((buffer_gets_delta/decode(nvl(buffer_gets_delta,0),0,1,executions_delta))) avg_lio
from DBA_HIST_SQLSTAT S, DBA_HIST_SNAPSHOT SS, dba_hist_sqltext st
where ss.snap_id = S.snap_id
and ss.instance_number = S.instance_number
and executions_delta > 0
and elapsed_time_delta > 0
and st.sql_id=s.sql_id
— and st.sql_text not like ‘/* SQL Analyze%’
— and s.sql_id in ( select p.sql_id from dba_hist_sql_plan p where p.object_name=’OPN_HIS’)
and ss.begin_interval_time > sysdate-7
group by TO_CHAR (ss.begin_interval_time, ‘DD.MM.YYYY HH24’),s.sql_id )
pivot ( sum(execs) for sql_id in (
‘8xjwqbfwwppuf’ )
) order by 1;
ashtop.sql sql_id,u.username,event "sql_plan_operation='TABLE ACCESS' and sql_plan_options='FULL'" sysdate-1/24 sysdate


58_rac_iops_trend.sql
PROMPT === 1-DAY IOPS TREND PER INSTANCE (AWR: DBA_HIST_SYSSTAT) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN snap_time FORMAT A20
COLUMN instance_number FORMAT 99
COLUMN iops FORMAT 999999.99

WITH io_stats AS (
  SELECT s.snap_id,
         s.instance_number,
         TO_CHAR(s.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS snap_time,
         MAX(CASE WHEN ss.stat_name = 'physical read IO requests' THEN ss.value END) AS read_io,
         MAX(CASE WHEN ss.stat_name = 'physical write IO requests' THEN ss.value END) AS write_io,
         s.begin_interval_time,
         s.end_interval_time
    FROM dba_hist_sysstat ss
    JOIN dba_hist_snapshot s
      ON ss.snap_id = s.snap_id AND ss.instance_number = s.instance_number
   WHERE ss.stat_name IN ('physical read IO requests', 'physical write IO requests')
     AND s.begin_interval_time > SYSDATE - 1
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
deltas AS (
  SELECT snap_time,
         instance_number,
         (read_io + write_io) -
         LAG(read_io + write_io) OVER (PARTITION BY instance_number ORDER BY begin_interval_time) AS total_io,
         (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)) * 24 * 60 * 60 AS elapsed_seconds
    FROM io_stats
)
SELECT snap_time,
       instance_number,
       ROUND(total_io / NULLIF(elapsed_seconds, 0), 2) AS iops
  FROM deltas
 WHERE total_io IS NOT NULL
 ORDER BY snap_time DESC, instance_number;

PROMPT === REAL-TIME IOPS PER INSTANCE (GV$SYSSTAT) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN name FORMAT A40
COLUMN value FORMAT 999999999
COLUMN iops FORMAT 999999

SELECT inst_id,
       'IOPS (Read+Write)' AS name,
       reads + writes AS value,
       ROUND((reads + writes) / 60) AS iops -- assuming ~60 sec snapshot
  FROM (
    SELECT inst_id,
           SUM(CASE WHEN name LIKE 'physical read IO requests' THEN value ELSE 0 END) AS reads,
           SUM(CASE WHEN name LIKE 'physical write IO requests' THEN value ELSE 0 END) AS writes
      FROM gv$sysstat
     WHERE name IN ('physical read IO requests', 'physical write IO requests')
     GROUP BY inst_id
  );


File Name	Description
53_rac_wait_skew.sql	RAC node wait skew detection from ASH
PROMPT === TOP WAIT EVENTS PER INSTANCE (RAC SKEW CHECK) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A50
COLUMN wait_count FORMAT 9999999

SELECT inst_id,
       event,
       COUNT(*) AS wait_count
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 5/1440
   AND session_state = 'WAITING'
 GROUP BY inst_id, event
 ORDER BY inst_id, wait_count DESC;
 
54_exadata_smart_scan_stats.sql	Smart scan stats from V$SYSSTAT
PROMPT === EXADATA SMART SCAN UTILIZATION (V$SYSSTAT) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN name FORMAT A50
COLUMN value FORMAT 999999999

SELECT name,
       value
  FROM v$sysstat
 WHERE name LIKE 'cell smart%scan%';
 
55_interconnect_latency.sql	Exadata interconnect performance
PROMPT === INTERCONNECT LATENCY (GV$CELL_GLOBAL_STATISTICS) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN name FORMAT A60
COLUMN value_mb FORMAT 999999999.99

SELECT inst_id,
       name,
       ROUND(value/1024/1024, 2) AS value_mb
  FROM gv$cell_global_statistics
 WHERE name IN (
       'CLO read retries due to stalling',
       'IO bytes sent via Smart Interconnect to cells',
       'IO bytes sent via non-Smart Interconnect to cells'
 )
 ORDER BY inst_id, name;
56_gc_contention.sql	Global cache contention (gc waits)
PROMPT === RAC GLOBAL CACHE CONTENTION EVENTS (GV$EVENT_HISTOGRAM) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A50
COLUMN wait_time_milli FORMAT 999
COLUMN wait_count FORMAT 999999

SELECT inst_id,
       event,
       wait_time_milli,
       wait_count
  FROM gv$event_histogram
 WHERE event IN (
       'gc buffer busy acquire',
       'gc buffer busy release',
       'gc cr block busy'
 )
   AND wait_count > 0
 ORDER BY inst_id, event, wait_time_milli;
57_exadata_offload_ratio.sql	Offload vs logical I/O ratio from AWR
PROMPT === EXADATA OFFLOAD SQL STATS (AWR: DBA_HIST_SQLSTAT) ===
SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN offload_gb FORMAT 999999.99
COLUMN logical_gb FORMAT 999999.99
COLUMN offload_ratio FORMAT 9.99

SELECT sql_id,
       SUM(cell_offload_elig_bytes) / 1024 / 1024 / 1024 AS offload_gb,
       SUM(cell_uncompressed_bytes) / 1024 / 1024 / 1024 AS logical_gb,
       ROUND(SUM(cell_offload_elig_bytes) / NULLIF(SUM(cell_uncompressed_bytes), 0), 2) AS offload_ratio
  FROM dba_hist_sqlstat
 WHERE snap_id IN (
       SELECT snap_id FROM dba_hist_snapshot WHERE begin_interval_time > SYSDATE - 1
 )
 GROUP BY sql_id
 ORDER BY offload_ratio DESC NULLS LAST;
SET PAGESIZE 100
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN cpu_count FORMAT 99
COLUMN db_time FORMAT 999999999
COLUMN db_time_mins FORMAT 999999.99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === DATABASE LOAD (AAS PER MINUTE FROM AWR DELTAS) - ORACLE RAC ===

WITH dbtime_deltas AS (
  SELECT s.instance_number,
         s.snap_id,
         s.begin_interval_time,
         s.end_interval_time,
         tm.value - LAG(tm.value) OVER (PARTITION BY s.instance_number ORDER BY s.snap_id) AS db_time
    FROM dba_hist_snapshot s
    JOIN dba_hist_sys_time_model tm
      ON s.snap_id = tm.snap_id AND s.instance_number = tm.instance_number
   WHERE tm.stat_name = 'DB time'
     AND s.begin_interval_time > SYSDATE - &DAYS_AGO
),
cpu_cores AS (
  SELECT instance_number,
         MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
instance_names AS (
  SELECT DISTINCT inst_id AS instance_number, instance_name FROM gv$instance
),
load_data AS (
  SELECT d.begin_interval_time,
         d.end_interval_time,
         i.instance_name,
         c.cpu_count,
         d.db_time,
         ROUND(d.db_time / 1e6, 2) AS db_time_mins,
         ROUND((d.db_time / 1e6) /
               ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) AS aas,
         CASE
           WHEN ROUND((d.db_time / 1e6) /
                      ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count THEN 'CRITICAL'
           WHEN ROUND((d.db_time / 1e6) /
                      ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count * 0.75 THEN 'WARNING'
           ELSE 'OK'
         END AS status
    FROM dbtime_deltas d
    JOIN cpu_cores c ON d.instance_number = c.instance_number
    LEFT JOIN instance_names i ON d.instance_number = i.instance_number
   WHERE d.db_time IS NOT NULL
)
SELECT TO_CHAR(begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       instance_name,
       cpu_count,
       db_time,
       db_time_mins,
       aas,
       status
  FROM load_data
 ORDER BY begin_interval_time DESC, instance_name;

PROMPT
PROMPT === TOTAL AAS PER MINUTE ACROSS ALL INSTANCES ===

SELECT TO_CHAR(begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       ROUND(SUM(aas), 2) AS total_aas
  FROM load_data
 GROUP BY begin_interval_time
 ORDER BY begin_interval_time DESC;
PROMPT
PROMPT === TOTAL AAS PER MINUTE ACROSS ALL INSTANCES ===

SELECT TO_CHAR(begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       ROUND(SUM(aas), 2) AS total_aas
  FROM load_data
 GROUP BY begin_interval_time
 ORDER BY begin_interval_time DESC;

SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN cpu_count FORMAT 99
COLUMN db_time_mins FORMAT 999999.99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === DATABASE LOAD (AAS PER MINUTE FROM AWR) - ORACLE RAC ===

WITH db_time_data AS (
  SELECT s.snap_id,
         s.instance_number,
         s.begin_interval_time,
         s.end_interval_time,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END) AS db_time
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
     AND tm.stat_name = 'DB time'
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
cpu_cores AS (
  SELECT instance_number,
         MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
instance_names AS (
  SELECT DISTINCT inst_id AS instance_number, instance_name FROM gv$instance
)
SELECT TO_CHAR(d.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       i.instance_name,
       c.cpu_count,
       ROUND(d.db_time / 1e6, 2) AS db_time_mins,
       ROUND((d.db_time / 1e6) /
             ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) AS aas,
       CASE
         WHEN ROUND((d.db_time / 1e6) /
                    ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count THEN 'CRITICAL'
         WHEN ROUND((d.db_time / 1e6) /
                    ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM db_time_data d
  JOIN cpu_cores c ON d.instance_number = c.instance_number
  LEFT JOIN instance_names i ON d.instance_number = i.instance_number
 ORDER BY d.begin_interval_time DESC, i.instance_name;
is_exadata() {
  local db_connect="$1"

  # Query V$VERSION or V$PARAMETER to detect Exadata features
  local result
  result=$(sqlplus -s "$db_connect" <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT 'YES'
  FROM v\$parameter
 WHERE name = 'cell_offload_processing'
   AND value = 'TRUE';
EXIT;
EOF
)

  if [[ "$result" == "YES" ]]; then
    return 0  # true: it's Exadata
  else
    return 1  # false
  fi
}


44_rac_gc_waits.sql – Global cache contention (top events)

45_rac_gc_waits_by_instance.sql – GC wait breakdown per node

46_rac_blocking_ges.sql – GES blocking sessions (RAC locks)

47_rac_interconnect_stats.sql – Interconnect activity (GC blocks)

48_rac_global_enqueue_contention.sql – Enqueue waits via GES
48
SET PAGESIZE 100
SET LINESIZE 200
COLUMN event FORMAT A40
COLUMN samples FORMAT 99999
COLUMN status FORMAT A10

PROMPT === GLOBAL ENQUEUE CONTENTION (GV$ACTIVE_SESSION_HISTORY) ===

SELECT event,
       COUNT(*) AS samples,
       CASE
         WHEN COUNT(*) > 50 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'ges%'
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event
 ORDER BY samples DESC;
47
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN name FORMAT A40
COLUMN mb FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === HIGH INTERCONNECT ACTIVITY (GV$SYSSTAT) ===

SELECT inst_id,
       name,
       ROUND(value / 1024 / 1024, 2) AS mb,
       CASE
         WHEN value > 500000000 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$sysstat
 WHERE name IN (
       'gc current blocks received',
       'gc cr blocks received',
       'gc current blocks served',
       'gc cr blocks served'
     )
 ORDER BY inst_id, name;
46
SET PAGESIZE 100
SET LINESIZE 200
COLUMN blocking_session FORMAT 99999
COLUMN blocking_inst_id FORMAT 99
COLUMN blocks FORMAT 9999
COLUMN first_seen FORMAT A20
COLUMN last_seen FORMAT A20
COLUMN status FORMAT A10

PROMPT === GES BLOCKING EVENTS (GV$ACTIVE_SESSION_HISTORY) ===

SELECT blocking_session, blocking_inst_id,
       COUNT(*) AS blocks,
       TO_CHAR(MIN(sample_time), 'YYYY-MM-DD HH24:MI') AS first_seen,
       TO_CHAR(MAX(sample_time), 'YYYY-MM-DD HH24:MI') AS last_seen,
       CASE
         WHEN COUNT(*) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE blocking_session IS NOT NULL
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY blocking_session, blocking_inst_id
 ORDER BY blocks DESC;
45
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A40
COLUMN count FORMAT 99999
COLUMN status FORMAT A10

PROMPT === GC WAITS BY INSTANCE (GV$ACTIVE_SESSION_HISTORY) ===

SELECT inst_id,
       event,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 500 THEN 'CRITICAL'
         WHEN COUNT(*) > 200 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'gc%' AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY inst_id, event
 ORDER BY inst_id, count DESC;45

44
SET PAGESIZE 100
SET LINESIZE 200
COLUMN event FORMAT A40
COLUMN samples FORMAT 99999
COLUMN pct FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === TOP GLOBAL CACHE WAITS (GV$ACTIVE_SESSION_HISTORY) ===

SELECT event,
       COUNT(*) AS samples,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 2) AS pct,
       CASE
         WHEN event LIKE 'gc%' AND COUNT(*) > 100 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'gc%'
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event
 ORDER BY samples DESC
FETCH FIRST 10 ROWS ONLY;

43
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN cpu_busy_secs FORMAT 999999.99
COLUMN total_cpu_secs FORMAT 999999.99
COLUMN cpu_util_pct FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === REAL-TIME CPU UTILIZATION (GV$OSSTAT) - ORACLE 19C RAC ===

WITH os_stat AS (
  SELECT inst_id,
         MAX(CASE WHEN stat_name = 'BUSY_TIME' THEN value END) AS busy_time,
         MAX(CASE WHEN stat_name = 'IDLE_TIME' THEN value END) AS idle_time
    FROM gv$osstat
   WHERE stat_name IN ('BUSY_TIME', 'IDLE_TIME')
   GROUP BY inst_id
)
SELECT inst_id,
       ROUND(busy_time / 100, 2) AS cpu_busy_secs,
       ROUND((busy_time + idle_time) / 100, 2) AS total_cpu_secs,
       ROUND((busy_time / (busy_time + idle_time)) * 100, 2) AS cpu_util_pct,
       CASE
         WHEN (busy_time / (busy_time + idle_time)) * 100 > 90 THEN 'CRITICAL'
         WHEN (busy_time / (busy_time + idle_time)) * 100 > 75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM os_stat
 ORDER BY inst_id;
42
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN cpu_count FORMAT 99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === REAL-TIME AAS (GV$ACTIVE_SESSION_HISTORY, LAST &MINUTES_AGO MINUTES) ===

WITH active_sessions AS (
  SELECT inst_id,
         COUNT(*) / (&MINUTES_AGO * 60) AS aas
    FROM gv$active_session_history
   WHERE sample_time > SYSDATE - (&MINUTES_AGO / 1440)
     AND session_type = 'FOREGROUND'
   GROUP BY inst_id
),
cpu_cores AS (
  SELECT instance_number AS inst_id, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
)
SELECT a.inst_id,
       c.cpu_count,
       ROUND(a.aas, 2) AS aas,
       CASE
         WHEN a.aas > c.cpu_count THEN 'CRITICAL'
         WHEN a.aas > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM active_sessions a
  JOIN cpu_cores c ON a.inst_id = c.inst_id
 ORDER BY a.inst_id;

 SET PAGESIZE 100
SET LINESIZE 200
COLUMN service_name FORMAT A25
COLUMN inst_id FORMAT 99
COLUMN session_type FORMAT A10
COLUMN active_count FORMAT 99999
COLUMN cpu_count FORMAT 99
COLUMN status FORMAT A10

PROMPT === ACTIVE SESSIONS PER INSTANCE (SCALED TO CPU CORES) - ORACLE 19C RAC ===

WITH session_stats AS (
  SELECT inst_id,
         service_hash,
         session_type,
         COUNT(CASE WHEN session_state IN ('ON CPU','WAITING') THEN 1 END) AS active_count
    FROM gv$active_session_history
   WHERE sample_time > SYSDATE - &DAYS_AGO
   GROUP BY inst_id, service_hash, session_type
),
cpu_cores AS (
  SELECT instance_number AS inst_id, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
services AS (
  SELECT name_hash, name AS service_name FROM gv$services
)
SELECT NVL(s.service_name, 'Unknown') AS service_name,
       ss.inst_id,
       ss.session_type,
       ss.active_count,
       c.cpu_count,
       CASE
         WHEN ss.active_count > c.cpu_count THEN 'CRITICAL'
         WHEN ss.active_count > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM session_stats ss
  JOIN cpu_cores c ON ss.inst_id = c.inst_id
  LEFT JOIN services s ON ss.service_hash = s.name_hash
 ORDER BY ss.inst_id, service_name;
#####
# Example modules
run_sql_file_report "DB Load (AAS)" "$SQL_DIR/01_db_load.sql" "$DB_CONNECT_STRING"
run_sql_file_report "Long Running Sessions" "$SQL_DIR/06_long_running_sessions.sql" "$DB_CONNECT_STRING"
run_sql_file_report "IO Response Time" "$SQL_DIR/07_io_response_time.sql" "$DB_CONNECT_STRING"

if is_exadata; then
  run_sql_file_report "Exadata Offload Efficiency" "$SQL_DIR/35_exadata_offload_efficiency.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Cell Interconnect Waits" "$SQL_DIR/36_exadata_cell_interconnect_waits.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Flash Cache Stats" "$SQL_DIR/37_exadata_flashcache_stats.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Smart Scan Usage" "$SQL_DIR/38_exadata_smart_scan_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "ASM Diskgroup Status" "$SQL_DIR/39_exadata_asm_diskgroup_status.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Wait Class Usage" "$SQL_DIR/40_exadata_wait_class_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "IORM Plan Check" "$SQL_DIR/41_exadata_iorm_plan.sql" "$DB_CONNECT_STRING"
fi

echo "</body></html>" >> "$HTML_REPORT"
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN cpu_count FORMAT 99
COLUMN db_time_mins FORMAT 999999.99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === DATABASE LOAD (AAS AUTO-SCALED BY CPU CORES PER INSTANCE) - ORACLE 19C RAC ===

WITH db_time_data AS (
  SELECT s.snap_id,
         s.instance_number,
         s.begin_interval_time,
         s.end_interval_time,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END) AS db_time
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
     AND tm.stat_name = 'DB time'
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
cpu_cores AS (
  SELECT instance_number,
         MAX(VALUE) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name FROM gv$instance
)
SELECT TO_CHAR(d.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       i.instance_name,
       c.cpu_count,
       ROUND(d.db_time / 1000000 / 60, 2) AS db_time_mins,
       ROUND((d.db_time / 1000000 / 60) /
             ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) AS aas,
       CASE
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count * 1.0 THEN 'CRITICAL'
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    ((CAST(d.end_interval_time AS DATE) - CAST(d.begin_interval_time AS DATE)) * 24 * 60), 2) > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM db_time_data d
  JOIN cpu_cores c ON d.instance_number = c.instance_number
  LEFT JOIN instance_names i ON d.instance_number = i.instance_number
 ORDER BY d.begin_interval_time DESC, i.instance_name;
 if is_exadata; then
  run_sql_file_report "Exadata Offload Efficiency" "$SQL_DIR/35_exadata_offload_efficiency.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Cell Interconnect Waits" "$SQL_DIR/36_exadata_cell_interconnect_waits.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Flash Cache Stats" "$SQL_DIR/37_exadata_flashcache_stats.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Smart Scan Usage" "$SQL_DIR/38_exadata_smart_scan_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "ASM Diskgroup Status" "$SQL_DIR/39_exadata_asm_diskgroup_status.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Wait Class Usage" "$SQL_DIR/40_exadata_wait_class_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "IORM Plan Check" "$SQL_DIR/41_exadata_iorm_plan.sql" "$DB_CONNECT_STRING"
fi

PROMPT === EXADATA CELL OFFLOAD EFFICIENCY ===
SELECT name,
       value,
       CASE
         WHEN name = 'cell physical IO interconnect bytes returned by smart scan' AND value = 0 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM v$sysstat
 WHERE name IN (
       'cell physical IO interconnect bytes returned by smart scan',
       'cell physical IO bytes eligible for predicate offload'
     );

##
PROMPT === INTERCONNECT-RELATED WAITS (EXADATA) ===
SELECT event,
       total_waits,
       time_waited_micro/1000000 AS time_secs,
       CASE
         WHEN event LIKE 'cell%' AND time_waited_micro > 1000000 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM v$system_event
 WHERE event LIKE 'cell%'
 ORDER BY time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;

##
PROMPT === FLASH CACHE STATISTICS (EXADATA) ===
SELECT name, value
  FROM v$sysstat
 WHERE name LIKE '%flash cache%'
 ORDER BY name;

##
PROMPT === SMART SCAN USAGE CHECK (RECENT SQLs) ===
SELECT sql_id,
       offload_eligibility,
       offload_returned_bytes/1024/1024 AS returned_mb,
       offload_eligible_bytes/1024/1024 AS eligible_mb,
       CASE
         WHEN offload_eligibility = 'NONE' THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM v$sql_monitor
 WHERE offload_eligibility IS NOT NULL
   AND last_refresh_time > SYSDATE - 1/24
 ORDER BY last_refresh_time DESC
FETCH FIRST 10 ROWS ONLY;

##
PROMPT === ASM DISKGROUP SPACE & STATE ===
SELECT name, total_mb, free_mb, state,
       ROUND((free_mb/total_mb)*100, 2) AS pct_free,
       CASE
         WHEN state != 'MOUNTED' THEN 'CRITICAL'
         WHEN (free_mb/total_mb)*100 < 10 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM v$asm_diskgroup;

PROMPT === EXADATA-SPECIFIC WAITS (GV$SESSION) ===
SELECT inst_id, wait_class, COUNT(*) AS count
  FROM gv$session
 WHERE wait_class IN ('Exadata', 'User I/O')
 GROUP BY inst_id, wait_class;
   ##
  PROMPT === IORM PLAN CHECK ===
SELECT plan_name,
       active,
       objective,
       status
  FROM v$cell_iorm_plan
 WHERE active = 'YES';
##
                                         
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN db_time_secs FORMAT 999999.99
COLUMN cpu_time_secs FORMAT 999999.99
COLUMN io_mb FORMAT 999999.99
COLUMN skew_status FORMAT A10

PROMPT === RAC INSTANCE SKEW ANALYSIS (DB TIME, CPU TIME, I/O) - ORACLE 19C ===

WITH workload AS (
  SELECT s.snap_id,
         s.begin_interval_time,
         s.instance_number,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END)/1000000 AS db_time_secs,
         MAX(CASE WHEN tm.stat_name = 'DB CPU' THEN tm.value END)/1000000 AS cpu_time_secs
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
     AND tm.stat_name IN ('DB time', 'DB CPU')
   GROUP BY s.snap_id, s.begin_interval_time, s.instance_number
),
io_stats AS (
  SELECT ss.snap_id,
         ss.instance_number,
         (SUM(CASE WHEN ss.stat_name IN ('physical read bytes', 'physical write bytes') THEN ss.value ELSE 0 END)/1024/1024) AS io_mb
    FROM dba_hist_sysstat ss
   WHERE ss.stat_name IN ('physical read bytes', 'physical write bytes')
   GROUP BY ss.snap_id, ss.instance_number
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name FROM gv$instance
),
combined AS (
  SELECT w.snap_id,
         w.begin_interval_time,
         w.instance_number,
         w.db_time_secs,
         w.cpu_time_secs,
         COALESCE(i.io_mb, 0) AS io_mb
    FROM workload w
    LEFT JOIN io_stats i ON w.snap_id = i.snap_id AND w.instance_number = i.instance_number
)
SELECT TO_CHAR(c.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       i.instance_name,
       ROUND(c.db_time_secs, 2) AS db_time_secs,
       ROUND(c.cpu_time_secs, 2) AS cpu_time_secs,
       ROUND(c.io_mb, 2) AS io_mb,
       CASE
         WHEN c.db_time_secs > (SELECT AVG(db_time_secs)*1.5 FROM combined c2 WHERE c2.begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.db_time_secs > (SELECT AVG(db_time_secs)*1.2 FROM combined c2 WHERE c2.begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         WHEN c.io_mb > (SELECT AVG(io_mb)*1.5 FROM combined c3 WHERE c3.begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.io_mb > (SELECT AVG(io_mb)*1.2 FROM combined c3 WHERE c3.begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         ELSE 'OK'
       END AS skew_status
  FROM combined c
  LEFT JOIN instance_names i ON c.instance_number = i.instance_number
 ORDER BY c.begin_interval_time DESC, i.instance_name;

 
 SET PAGESIZE 100
SELECT name,
       space_limit/1024/1024 AS limit_mb,
       space_used/1024/1024 AS used_mb,
       space_reclaimable/1024/1024 AS reclaimable_mb,
       ROUND((space_used/space_limit)*100, 2) AS pct_used,
       CASE
         WHEN ROUND((space_used/space_limit)*100, 2) > 95 THEN 'CRITICAL'
         WHEN ROUND((space_used/space_limit)*100, 2) > 85 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM v$recovery_file_dest;
  
determine_primary_cdb() {
    local input_conn="$1"
    local html_file="$2"
    local primary_conn=""
    local db_role=""
    local primary_host=""
    local primary_port=""
    local primary_service=""

    echo "<div class='section'>" >> "$html_file"
    echo "<h2>Primary CDB Determination</h2>" >> "$html_file"

    # Get database role and configuration
    db_info=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'ROLE=' || database_role || '|FAL_SERVER=' || NVL(fal_server, 'NONE') || '|DG_BROKER=' || 
       (SELECT CASE WHEN COUNT(*) > 0 THEN 'ACTIVE' ELSE 'INACTIVE' END 
        FROM v\$parameter WHERE name = 'dg_broker_start' AND value = 'TRUE')
FROM v\$database;
EOF
    )

    # Parse database info
    IFS='|' read -r role_part fal_part broker_part <<< "$db_info"
    db_role=$(echo "$role_part" | cut -d'=' -f2)
    fal_server=$(echo "$fal_part" | cut -d'=' -f2)
    dg_broker=$(echo "$broker_part" | cut -d'=' -f2)

    case $db_role in
        "PRIMARY")
            echo "<p class='ok'>✅ Connected database is already PRIMARY</p>" >> "$html_file"
            primary_conn="$input_conn"
            ;;
        "PHYSICAL STANDBY")
            echo "<p class='info'>🔍 Connected to STANDBY database</p>" >> "$html_file"
            
            # Try Data Guard Broker first
            if [ "$dg_broker" = "ACTIVE" ]; then
                echo "<p class='info'>🔍 Checking Data Guard Broker configuration</p>" >> "$html_file"
                broker_config=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT db_unique_name || '|' || hostname || '|' || db_domain 
FROM v\$dg_broker_config 
WHERE type = 'DATABASE' AND role = 'PRIMARY';
EOF
                )
                IFS='|' read -r primary_name primary_host primary_domain <<< "$broker_config"
                primary_service="${primary_name}.${primary_domain}"
                primary_port="1521"  # Default port for broker
            fi

            # Fallback to FAL_SERVER
            if [ -z "$primary_host" ] && [ "$fal_server" != "NONE" ]; then
                echo "<p class='info'>🔍 Using FAL_SERVER: $fal_server</p>" >> "$html_file"
                
                # Try to resolve FAL_SERVER from tnsnames.ora
                tns_entry=$(cat $ORACLE_HOME/network/admin/tnsnames.ora | grep -i "^$fal_server\s*=")
                
                # Parse TNS entry
                primary_host=$(echo "$tns_entry" | sed -n 's/.*HOST\s*=\s*\([^)]*\).*/\1/p' | head -1)
                primary_port=$(echo "$tns_entry" | sed -n 's/.*PORT\s*=\s*\([0-9]*\).*/\1/p' | head -1)
                primary_service=$(echo "$tns_entry" | sed -n 's/.*SERVICE_NAME\s*=\s*\([^)]*\).*/\1/p' | head -1)
                
                # Fallback to direct parsing if tnsnames.ora not accessible
                if [ -z "$primary_host" ]; then
                    primary_host=$(echo "$fal_server" | cut -d':' -f1)
                    primary_port=$(echo "$fal_server" | cut -d':' -f2 | cut -d'/' -f1)
                    primary_service=$(echo "$fal_server" | cut -d'/' -f2)
                fi
            fi

            # Validate results
            if [ -n "$primary_host" ] && [ -n "$primary_service" ]; then
                primary_port=${primary_port:-1521}  # Default port if not found
                primary_conn="sys@\"$primary_host:$primary_port/$primary_service\" as sysdba"
                echo "<p class='ok'>✅ Discovered primary CDB connection</p>" >> "$html_file"
                echo "<table>
                        <tr><th>Parameter</th><th>Value</th></tr>
                        <tr><td>Host</td><td>$primary_host</td></tr>
                        <tr><td>Port</td><td>$primary_port</td></tr>
                        <tr><td>Service</td><td>$primary_service</td></tr>
                      </table>" >> "$html_file"
            else
                echo "<p class='critical'>❌ Failed to determine primary CDB</p>" >> "$html_file"
                echo "<pre>Debug info:
                DG Broker Status: $dg_broker
                FAL_SERVER: $fal_server
                Broker Config: $broker_config
                Parsed Host: $primary_host
                Parsed Port: $primary_port
                Parsed Service: $primary_service</pre>" >> "$html_file"
                return 1
            fi

            # Verify primary connection
            verify_primary=$(sqlplus -s /nolog << EOF
connect $primary_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT database_role FROM v\$database;
EOF
            )

            if [[ "$verify_primary" == *"PRIMARY"* ]]; then
                echo "<p class='ok'>✅ Verified primary CDB connection</p>" >> "$html_file"
            else
                echo "<p class='critical'>❌ Primary verification failed</p>" >> "$html_file"
                echo "<pre>Verification output: $verify_primary</pre>" >> "$html_file"
                primary_conn=""
            fi
            ;;
        *)
            echo "<p class='critical'>❌ Unsupported database role: $db_role</p>" >> "$html_file"
            return 1
            ;;
    esac

    echo "</div>" >> "$html_file"
    echo "$primary_conn"
}

determine_primary_cdb() {
    local input_conn="$1"
    local html_file="$2"
    local primary_conn=""
    local db_role=""
    local db_unique_name=""

    echo "<div class='section'>" >> "$html_file"
    echo "<h2>Primary CDB Determination</h2>" >> "$html_file"

    # Get database role and unique name
    db_info=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'ROLE=' || database_role || '|UNIQUE_NAME=' || db_unique_name FROM v\$database;
EOF
    )

    # Clean SQL*Plus output
    db_info=$(echo "$db_info" | sed '/^Disconnected/d;/^$/d')

    # Parse database information
    IFS='|' read -r role_part unique_part <<< "$db_info"
    db_role=$(echo "$role_part" | cut -d'=' -f2)
    db_unique_name=$(echo "$unique_part" | cut -d'=' -f2)

    case $db_role in
        "PRIMARY")
            echo "<p class='ok'>✅ Connected to PRIMARY CDB: $db_unique_name</p>" >> "$html_file"
            primary_conn="$input_conn"
            ;;
        "PHYSICAL STANDBY")
            echo "<p class='info'>🔍 Connected to STANDBY CDB: $db_unique_name</p>" >> "$html_file"
            
            # Try to find primary using Data Guard Broker
            primary_info=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'HOST=' || target_host || '|PORT=' || target_port || '|SERVICE=' || database 
FROM v\$dg_broker_targets 
WHERE target_type = 'PRIMARY' AND ROWNUM = 1;
EOF
            )

            if [[ "$primary_info" == *"HOST="* ]]; then
                IFS='|' read -r host_part port_part service_part <<< "$primary_info"
                primary_host=$(echo "$host_part" | cut -d'=' -f2)
                primary_port=$(echo "$port_part" | cut -d'=' -f2)
                primary_service=$(echo "$service_part" | cut -d'=' -f2)
            else
                # Fallback to archive log destinations
                tns_desc=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT value FROM v\$parameter 
WHERE name = 'log_archive_dest_2' 
AND value LIKE 'SERVICE%';
EOF
                )
                primary_host=$(echo "$tns_desc" | sed -n 's/.*HOST=\([^)]*\)).*/\1/p')
                primary_port=$(echo "$tns_desc" | sed -n 's/.*PORT=\([0-9]*\)).*/\1/p')
                primary_service=$(echo "$tns_desc" | sed -n 's/.*SERVICE=\([^)]*\)).*/\1/p')
            fi

            if [ -n "$primary_host" ] && [ -n "$primary_port" ] && [ -n "$primary_service" ]; then
                primary_conn="sys@\"$primary_host:$primary_port/$primary_service\" as sysdba"
                echo "<p class='ok'>✅ Discovered primary CDB connection</p>" >> "$html_file"
                echo "<table>
                        <tr><th>Parameter</th><th>Value</th></tr>
                        <tr><td>Host</td><td>$primary_host</td></tr>
                        <tr><td>Port</td><td>$primary_port</td></tr>
                        <tr><td>Service</td><td>$primary_service</td></tr>
                      </table>" >> "$html_file"
            else
                echo "<p class='critical'>❌ Failed to determine primary CDB</p>" >> "$html_file"
                return 1
            fi
            ;;
        *)
            echo "<p class='critical'>❌ Invalid database role: $db_role</p>" >> "$html_file"
            return 1
            ;;
    esac

    # Verify primary connection
    if [ -n "$primary_conn" ]; then
        verify_primary=$(sqlplus -s /nolog << EOF
connect $primary_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'PRIMARY_VERIFICATION=' || database_role FROM v\$database;
EOF
        )

        if [[ "$verify_primary" == *"PRIMARY_VERIFICATION=PRIMARY"* ]]; then
            echo "<p class='ok'>✅ Verified primary CDB connection</p>" >> "$html_file"
        else
            echo "<p class='critical'>❌ Primary verification failed</p>" >> "$html_file"
            primary_conn=""
        fi
    fi

    echo "</div>" >> "$html_file"
    echo "$primary_conn"
}

determine_primary_cdb() {
    local standby_conn="$1"
    local html_file="$2"
    local primary_conn=""
    local tns_desc=""
    local primary_host=""
    local primary_port=""
    local primary_db_name=""
    local primary_db_unique_name=""

    echo "<div class='section'>" >> "$html_file"
    echo "<h2>Primary CDB Determination</h2>" >> "$html_file"

    # Verify standby status
    standby_check=$(sqlplus -s /nolog << EOF
connect $standby_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT database_role FROM v\$database;
EOF
    )

    if [[ "$standby_check" != *"PHYSICAL STANDBY"* ]]; then
        echo "<p class='critical'>❌ Provided database is not a physical standby</p>" >> "$html_file"
        echo "</div>" >> "$html_file"
        return 1
    fi

    # Try Data Guard Broker first
    broker_config=$(sqlplus -s /nolog << EOF
connect $standby_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'BROKER_CONFIG=' || LOWER(value) FROM v\$parameter WHERE name = 'dg_broker_config_file';
EOF
    )

    if [[ "$broker_config" == *"dg_broker_config_file"* ]]; then
        primary_info=$(sqlplus -s /nolog << EOF
connect $standby_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'PRIMARY_DB=' || database || '|HOST=' || target_host || '|PORT=' || target_port 
FROM v\$dg_broker_targets 
WHERE target_type = 'PRIMARY';
EOF
        )
        IFS='|' read -r db_part host_part port_part <<< "$(echo "$primary_info" | grep 'PRIMARY_DB=')"
        primary_db_unique_name=$(echo "$db_part" | cut -d'=' -f2)
        primary_host=$(echo "$host_part" | cut -d'=' -f2)
        primary_port=$(echo "$port_part" | cut -d'=' -f2)
    fi

    # Fallback to archive log destinations
    if [ -z "$primary_host" ]; then
        tns_desc=$(sqlplus -s /nolog << EOF
connect $standby_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT value FROM v\$parameter WHERE name = 'log_archive_dest_2' AND value LIKE 'SERVICE%';
EOF
        )

        # Parse TNS descriptor
        primary_host=$(echo "$tns_desc" | sed -n 's/.*HOST=\([^)]*\)).*/\1/p' | head -1)
        primary_port=$(echo "$tns_desc" | sed -n 's/.*PORT=\([0-9]*\)).*/\1/p' | head -1)
        primary_db_unique_name=$(sqlplus -s /nolog << EOF
connect $standby_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT UPPER(db_unique_name) FROM v\$database;
EOF
        )
    fi

    # Validate results
    if [ -n "$primary_host" ] && [ -n "$primary_port" ] && [ -n "$primary_db_unique_name" ]; then
        primary_conn="sys@\"$primary_host:$primary_port/$primary_db_unique_name\" as sysdba"
        echo "<p class='ok'>✅ Primary CDB determined successfully</p>" >> "$html_file"
        echo "<table>
                <tr><th>Parameter</th><th>Value</th></tr>
                <tr><td>Host</td><td>$primary_host</td></tr>
                <tr><td>Port</td><td>$primary_port</td></tr>
                <tr><td>DB Unique Name</td><td>$primary_db_unique_name</td></tr>
                <tr><td>Connection String</td><td>$primary_conn</td></tr>
              </table>" >> "$html_file"
    else
        echo "<p class='critical'>❌ Failed to determine primary CDB</p>" >> "$html_file"
        echo "<pre>Debug info:
        Host: $primary_host
        Port: $primary_port
        DB Unique Name: $primary_db_unique_name
        TNS Descriptor: $tns_desc</pre>" >> "$html_file"
        return 1
    fi

    # Verify primary connectivity
    verify_primary=$(sqlplus -s /nolog << EOF
connect $primary_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'PRIMARY_STATUS=' || database_role FROM v\$database;
EOF
    )

    if [[ "$verify_primary" == *"PRIMARY_STATUS=PRIMARY"* ]]; then
        echo "<p class='ok'>✅ Verified primary CDB connection</p>" >> "$html_file"
    else
        echo "<p class='warning'>⚠️ Primary connection verification failed</p>" >> "$html_file"
        echo "<pre>Verification output: $verify_primary</pre>" >> "$html_file"
    fi

    echo "</div>" >> "$html_file"
    echo "$primary_conn"
}

run_ashtop_5minutes() {
  local title="ASHTOP - Last 5 Minutes"
  local sql_file="$SQL_DIR/20_ashtop_5minutes.sql"
  local temp_output="/tmp/ashtop_5m_output.txt"

  # Run the SQL and save output
  sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" > "$temp_output"

  # Extract AAS value (2nd column)
  local max_aas
  max_aas=$(awk 'NF > 2 && $2 ~ /^[0-9.]+$/ {print $2}' "$temp_output" | sort -nr | head -1)

  # Determine status
  local status_label
  if [[ -n "$max_aas" && $(echo "$max_aas > 20" | bc) -eq 1 ]]; then
    status_label="<span style='color:red;font-weight:bold;'>CRITICAL (AAS $max_aas)</span>"
  elif [[ -n "$max_aas" && $(echo "$max_aas > 10" | bc) -eq 1 ]]; then
    status_label="<span style='color:orange;font-weight:bold;'>WARNING (AAS $max_aas)</span>"
  else
    status_label="<span style='color:green;font-weight:bold;'>OK (AAS $max_aas)</span>"
  fi

  # Inject section header with status label
  echo "<h2>$title - $status_label</h2><pre>" >> "$HTML_REPORT"

  # Write output with CRITICAL/WARNING color tags
  while IFS= read -r line; do
    if echo "$line" | grep -q 'CRITICAL'; then
      line=$(echo "$line" | sed 's/CRITICAL/<span style="color:red;font-weight:bold;">CRITICAL<\/span>/g')
    elif echo "$line" | grep -q 'WARNING'; then
      line=$(echo "$line" | sed 's/WARNING/<span style="color:orange;font-weight:bold;">WARNING<\/span>/g')
    fi
    echo "$line" >> "$HTML_REPORT"
  done < "$temp_output"

  echo "</pre>" >> "$HTML_REPORT"
}

SET PAGESIZE 100
SELECT tablespace_name,
       ROUND(used_space*8/1024) AS used_mb,
       ROUND((tablespace_size - used_space)*8/1024) AS free_mb,
       ROUND((used_space/tablespace_size)*100,2) AS pct_used
  FROM dba_tablespace_usage_metrics
 ORDER BY pct_used DESC;
 
run_ashtop_5minutes() {
  local title="ASHTOP - Last 5 Minutes"
  local sql_file="$SQL_DIR/20_ashtop_5minutes.sql"
  local temp_output="/tmp/ashtop_5m_output.txt"

  # Run and capture output to a temp file
  sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" > "$temp_output"

  # Inject section header
  append_section "$title"

  # Output full result to HTML with coloring (your original logic)
  while IFS= read -r line; do
    if echo "$line" | grep -q 'CRITICAL'; then
      line=$(echo "$line" | sed 's/CRITICAL/<span style="color:red;font-weight:bold;">CRITICAL<\/span>/g')
    elif echo "$line" | grep -q 'WARNING'; then
      line=$(echo "$line" | sed 's/WARNING/<span style="color:orange;font-weight:bold;">WARNING<\/span>/g')
    fi
    echo "$line" >> "$HTML_REPORT"
  done < "$temp_output"

  # Extract AAS from second column
  local max_aas
  max_aas=$(awk 'NF > 2 && $2 ~ /^[0-9.]+$/ {print $2}' "$temp_output" | sort -nr | head -1)

  # Append overall health status
  if [[ -n "$max_aas" && $(echo "$max_aas > 20" | bc) -eq 1 ]]; then
    echo "<p><b>Status: <span style='color:red;'>CRITICAL (AAS $max_aas)</span></b></p>" >> "$HTML_REPORT"
  elif [[ -n "$max_aas" && $(echo "$max_aas > 10" | bc) -eq 1 ]]; then
    echo "<p><b>Status: <span style='color:orange;'>WARNING (AAS $max_aas)</span></b></p>" >> "$HTML_REPORT"
  else
    echo "<p><b>Status: <span style='color:green;'>OK (AAS $max_aas)</span></b></p>" >> "$HTML_REPORT"
  fi

  echo "</pre>" >> "$HTML_REPORT"
}

SET PAGESIZE 100
SELECT day,
       session_state,
       count,
       CASE 
         WHEN session_state = 'ACTIVE' AND count > 80 THEN 'CRITICAL'
         WHEN session_state = 'ACTIVE' AND count > 20 THEN 'WARNING'
         ELSE 'OK'
       END AS status
FROM (
    SELECT TO_CHAR(sample_time, 'YYYY-MM-DD') day,
           session_state,
           COUNT(*) AS count
      FROM dba_hist_active_sess_history
     WHERE sample_time > SYSDATE - &DAYS_AGO
     GROUP BY TO_CHAR(sample_time, 'YYYY-MM-DD'), session_state
)
ORDER BY day, session_state;

SET PAGESIZE 100
SET LINESIZE 200
COLUMN destination FORMAT A40
COLUMN database_mode FORMAT A15
COLUMN status FORMAT A10

PROMPT === CHECK FOR PRIMARY DESTINATION FROM STANDBY ===

SELECT destination,
       database_mode,
       status
  FROM v$archive_dest_status
 WHERE database_mode = 'PRIMARY'
   AND status = 'VALID';



run_ashtop_5min_check() {
  local db_connect="$1"
  local html_output="$2"
  local tmp_output="/tmp/ashtop_5m.txt"

  sqlplus -s "$db_connect" <<EOF > "$tmp_output"
SET PAGESIZE 100
SET LINESIZE 200
SET TRIMSPOOL ON
SET TRIMOUT ON
SET HEADING ON
SET FEEDBACK OFF
SET COLSEP ' | '
PROMPT === ASHTOP (LAST 5 MINUTES) ===
@sql/lib/ashtop.sql username,sql_id session_type='FOREGROUND' sysdate-1/288 sysdate
EOF

  echo "<h2>ASHTOP - Last 5 Minutes</h2><pre>" >> "$html_output"
  cat "$tmp_output" >> "$html_output"
  echo "</pre>" >> "$html_output"

  # Extract AAS (2nd column), skip header lines
  local max_aas
  max_aas=$(awk 'NF > 2 && $2 ~ /^[0-9.]+$/ {print $2}' "$tmp_output" | sort -nr | head -1)

  if [[ $(echo "$max_aas > 20" | bc) -eq 1 ]]; then
    echo "<p><b>Status: <span style='color:red;'>CRITICAL (AAS $max_aas)</span></b></p>" >> "$html_output"
  elif [[ $(echo "$max_aas > 10" | bc) -eq 1 ]]; then
    echo "<p><b>Status: <span style='color:orange;'>WARNING (AAS $max_aas)</span></b></p>" >> "$html_output"
  else
    echo "<p><b>Status: <span style='color:green;'>OK (AAS $max_aas)</span></b></p>" >> "$html_output"
  fi
}

ashtop.sql sql_id,u.username,event "sql_plan_operation='TABLE ACCESS' and sql_plan_options='FULL'" sysdate-1/24 sysdate

SET PAGESIZE 100
SET LINESIZE 200
COLUMN role FORMAT A20
COLUMN primary_dest FORMAT A60

PROMPT === CHECK DATABASE ROLE AND PRIMARY DB DESTINATION ===

-- Step 1: Check if current DB is a standby
SELECT database_role AS role FROM v$database;

-- Step 2: If standby, find the primary DB name from archive destination config
PROMPT --- If standby, checking for PRIMARY destination in V$ARCHIVE_DEST_STATUS ---
SELECT destination AS primary_dest
  FROM v$archive_dest_status
 WHERE status = 'VALID'
   AND target = 'PRIMARY'
   AND rownum = 1;
# ========== DB CONNECTIVITY VALIDATION ==========
check_db_connectivity() {
    echo "Validating database connectivity..."
    sqlplus -s "$DB_CONNECT_STRING" <<EOF > /dev/null
WHENEVER SQLERROR EXIT FAILURE
SELECT 'Connection Successful' FROM dual;
EXIT
EOF
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Cannot connect to Oracle DB with provided credentials."
        exit 1
    else
        echo "✅ Database connection successful."
    fi
}
run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    append_section "$title"
    while IFS= read -r line; do
        if echo "$line" | grep -q 'CRITICAL'; then
            line=$(echo "$line" | sed 's/CRITICAL/<span style="color:red;"><b>CRITICAL<\/b><\/span>/g')
        elif echo "$line" | grep -q 'WARNING'; then
            line=$(echo "$line" | sed 's/WARNING/<span style="color:orange;"><b>WARNING<\/b><\/span>/g')
        fi
        echo "$line" >> "$HTML_REPORT"
    done < <(
        sqlplus -s "$DB_CONNECT_STRING" <<EOF
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF
SET VERIFY OFF
DEFINE DAYS_AGO=$DAYS_AGO
DEFINE HOURS_AGO=$HOURS_AGO
DEFINE MINUTES_AGO=$MINUTES_AGO
@$sql_file
EXIT
EOF
    )
    echo "</pre>" >> "$HTML_REPORT"
}


#!/bin/bash

# ========== CONFIGURATION ==========
ORACLE_USER="system"
ORACLE_PASS="your_password"
ORACLE_SID="ORCL"
EMAIL_TO="dba-team@example.com"
EMAIL_SUBJECT="Oracle RAC Health Check Report - $(date '+%Y-%m-%d %H:%M')"
HTML_REPORT="./output/health_check_$(date +%Y%m%d_%H%M%S).html"
DB_CONNECT_STRING="$ORACLE_USER/$ORACLE_PASS@$ORACLE_SID"

# ========== ANALYSIS WINDOWS ==========
DAYS_AGO=7
HOURS_AGO=1
MINUTES_AGO=5

# ========== THRESHOLDS ==========
MAX_SESSIONS_UTIL=90
MAX_PROCESSES_UTIL=90
DB_LOAD_THRESHOLD=85
MAX_BLOCKED_SESSIONS=0
MAX_IO_RESP_MS=20

# ========== FUNCTIONS ==========
init_html_report() {
    cat templates/report_header.html > "$HTML_REPORT"
    echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"
    echo "<p>Generated on: $(date)</p>" >> "$HTML_REPORT"
}

close_html_report() {
    cat templates/report_footer.html >> "$HTML_REPORT"
}

append_section() {
    local title="$1"
    echo "<h2>$title</h2><pre>" >> "$HTML_REPORT"
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    append_section "$title"
    sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
}

send_email_report() {
    if command -v mailx &>/dev/null; then
        cat "$HTML_REPORT" | mailx -a "Content-type: text/html" -s "$EMAIL_SUBJECT" "$EMAIL_TO"
    else
        echo "mailx not found. Please install or configure an alternative mail agent."
    fi
}

# ========== INDIVIDUAL CHECK FUNCTIONS ==========
run_check_db_load() { run_sql_file_report "DB Load" "sql/01_db_load.sql"; }
run_check_active_sessions() { run_sql_file_report "Active/Inactive Sessions" "sql/02_active_sessions.sql"; }
run_check_session_processes() { run_sql_file_report "Session & Process Utilization" "sql/03_sessions_processes.sql"; }
run_check_sga_pga_usage() { run_sql_file_report "SGA & PGA Usage" "sql/04_sga_pga_usage.sql"; }
run_check_blocking_sessions() { run_sql_file_report "Blocking Sessions" "sql/05_blocking_sessions.sql"; }
run_check_long_running_sessions() { run_sql_file_report "Long Running Sessions" "sql/06_long_running_sessions.sql"; }
run_check_io_response_time() { run_sql_file_report "IO Response Time" "sql/07_io_response_time.sql"; }
run_check_wait_events() { run_sql_file_report "Wait Events (1 Hour & 5 Min)" "sql/08_wait_events_window.sql"; }
run_check_rac_instance_skew() { run_sql_file_report "RAC Instance Load Skew" "sql/09_rac_instance_skew.sql"; }
run_check_top_waits() { run_sql_file_report "Top Wait Events by Instance" "sql/10_top_waits_by_instance.sql"; }
run_check_global_cache() { run_sql_file_report "Global Cache Statistics" "sql/11_global_cache_stats.sql"; }
run_check_top_sql() { run_sql_file_report "Top SQL by Elapsed Time" "sql/12_top_sql_elapsed.sql"; }
run_check_tablespace_usage() { run_sql_file_report "Tablespace Usage" "sql/13_tablespace_usage.sql"; }
run_check_asm_usage() { run_sql_file_report "ASM Diskgroup Usage" "sql/14_asm_diskgroup_usage.sql"; }
run_check_log_sync() { run_sql_file_report "Redo Log Sync Waits" "sql/15_log_sync_contention.sql"; }
run_check_temp_usage() { run_sql_file_report "Temp Usage" "sql/16_temp_usage.sql"; }
run_check_parse_ratio() { run_sql_file_report "Parse to Execute Ratio" "sql/17_parse_to_exec_ratio.sql"; }
run_check_log_switches() { run_sql_file_report "Log Switch History" "sql/18_log_switch_history.sql"; }
run_check_fra_usage() { run_sql_file_report "FRA Space Usage" "sql/19_fra_usage.sql"; }
run_check_ashtop_5min() { run_sql_file_report "ASH Top - Last 5 Min" "sql/20_ashtop_5min.sql"; }
run_check_ashtop_1hr() { run_sql_file_report "ASH Top - Last 1 Hour" "sql/21_ashtop_1hr.sql"; }

# ========== MAIN ==========
main() {
    init_html_report

    run_check_db_load
    run_check_active_sessions
    run_check_session_processes
    run_check_sga_pga_usage
    run_check_blocking_sessions
    run_check_long_running_sessions
    run_check_io_response_time
    run_check_wait_events
    run_check_rac_instance_skew
    run_check_top_waits
    run_check_global_cache
    run_check_top_sql
    run_check_tablespace_usage
    run_check_asm_usage
    run_check_log_sync
    run_check_temp_usage
    run_check_parse_ratio
    run_check_log_switches
    run_check_fra_usage
    run_check_ashtop_5min
    run_check_ashtop_1hr

    close_html_report
    send_email_report
}

main

#!/bin/bash

DB_CONNECT_STRING="$1"
HTML_REPORT="health_check_report.html"
SQL_DIR="./sql"

DAYS_AGO=1
HOURS_AGO=1
MINUTES_AGO=5

is_exadata() {
  echo "Checking for Exadata platform..."
  if sqlplus -s "$DB_CONNECT_STRING" <<EOF | grep -q "Exadata"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT platform_name FROM v$database WHERE platform_name LIKE '%Exadata%';
EXIT;
EOF
  then
    echo "✅ Exadata platform detected"
    return 0
  else
    echo "❌ Not an Exadata system"
    return 1
  fi
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    local connect_str="$3"

    local tmp_output=$(mktemp)
    local section_status="OK"

    sqlplus -s "$connect_str" <<EOF > "$tmp_output"
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF
SET VERIFY OFF
DEFINE DAYS_AGO=$DAYS_AGO
DEFINE HOURS_AGO=$HOURS_AGO
DEFINE MINUTES_AGO=$MINUTES_AGO
@$sql_file
EXIT
EOF

    if grep -q 'CRITICAL' "$tmp_output"; then
        section_status="<span style='color:red;'><b>CRITICAL</b></span>"
    elif grep -q 'WARNING' "$tmp_output"; then
        section_status="<span style='color:orange;'><b>WARNING</b></span>"
    else
        section_status="<span style='color:green;'><b>OK</b></span>"
    fi

    echo "<h2>$title - Status: $section_status</h2><pre>" >> "$HTML_REPORT"

    while IFS= read -r line; do
        if echo "$line" | grep -q 'CRITICAL'; then
            line=$(echo "$line" | sed 's/CRITICAL/<span style="color:red;"><b>CRITICAL<\/b><\/span>/g')
        elif echo "$line" | grep -q 'WARNING'; then
            line=$(echo "$line" | sed 's/WARNING/<span style="color:orange;"><b>WARNING<\/b><\/span>/g')
        elif echo "$line" | grep -q 'OK'; then
            line=$(echo "$line" | sed 's/OK/<span style="color:green;"><b>OK<\/b><\/span>/g')
        fi
        echo "$line" >> "$HTML_REPORT"
    done < "$tmp_output"

    rm -f "$tmp_output"
    echo "</pre>" >> "$HTML_REPORT"
}

echo "<html><head><title>Oracle RAC Health Check</title></head><body>" > "$HTML_REPORT"
echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"

# Example modules
run_sql_file_report "DB Load (AAS)" "$SQL_DIR/01_db_load.sql" "$DB_CONNECT_STRING"
run_sql_file_report "Long Running Sessions" "$SQL_DIR/06_long_running_sessions.sql" "$DB_CONNECT_STRING"
run_sql_file_report "IO Response Time" "$SQL_DIR/07_io_response_time.sql" "$DB_CONNECT_STRING"

if is_exadata; then
  run_sql_file_report "Exadata Offload Efficiency" "$SQL_DIR/35_exadata_offload_efficiency.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Cell Interconnect Waits" "$SQL_DIR/36_exadata_cell_interconnect_waits.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Flash Cache Stats" "$SQL_DIR/37_exadata_flashcache_stats.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Smart Scan Usage" "$SQL_DIR/38_exadata_smart_scan_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "ASM Diskgroup Status" "$SQL_DIR/39_exadata_asm_diskgroup_status.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Wait Class Usage" "$SQL_DIR/40_exadata_wait_class_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "IORM Plan Check" "$SQL_DIR/41_exadata_iorm_plan.sql" "$DB_CONNECT_STRING"
fi

echo "</body></html>" >> "$HTML_REPORT"
# ========== CONFIGURATION ==========
ORACLE_USER="system"
ORACLE_PASS="your_password"
ORACLE_SID="ORCL"
EMAIL_TO="dba-team@example.com"
EMAIL_SUBJECT="Oracle RAC Health Check Report - $(date '+%Y-%m-%d %H:%M')"
HTML_REPORT="./output/health_check_$(date +%Y%m%d_%H%M%S).html"
DB_CONNECT_STRING="$ORACLE_USER/$ORACLE_PASS@$ORACLE_SID"

# ========== ANALYSIS WINDOWS ==========
DAYS_AGO=7
HOURS_AGO=1
MINUTES_AGO=5

# ========== THRESHOLDS ==========
MAX_SESSIONS_UTIL=90
MAX_PROCESSES_UTIL=90
DB_LOAD_THRESHOLD=85
MAX_BLOCKED_SESSIONS=0
MAX_IO_RESP_MS=20

# ========== FUNCTIONS ==========
init_html_report() {
    cat templates/report_header.html > "$HTML_REPORT"
    echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"
    echo "<p>Generated on: $(date)</p>" >> "$HTML_REPORT"
}

close_html_report() {
    cat templates/report_footer.html >> "$HTML_REPORT"
}

append_section() {
    local title="$1"
    echo "<h2>$title</h2><pre>" >> "$HTML_REPORT"
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    append_section "$title"
    sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
}

send_email_report() {
    if command -v mailx &>/dev/null; then
        cat "$HTML_REPORT" | mailx -a "Content-type: text/html" -s "$EMAIL_SUBJECT" "$EMAIL_TO"
    else
        echo "mailx not found. Please install or configure an alternative mail agent."
    fi
}

# ========== MAIN ==========
main() {
    init_html_report

    for file in sql/*.sql; do
        title=$(basename "$file" .sql | sed 's/^[0-9]*_//; s/_/ /g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
        run_sql_file_report "$title" "$file"
    done

    close_html_report
    send_email_report
}

main
#
01_db_load.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN aas FORMAT 999.99
COLUMN db_time_mins FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === DATABASE LOAD (AAS BASED ON DB TIME IN MINUTES) - ORACLE 19C RAC ===

WITH db_time_data AS (
  SELECT s.snap_id,
         s.instance_number,
         s.begin_interval_time,
         s.end_interval_time,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END) AS db_time
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name
    FROM gv$instance
)
SELECT TO_CHAR(d.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       i.instance_name,
       ROUND(d.db_time / 1000000 / 60, 2) AS db_time_mins,
       ROUND((d.db_time / 1000000 / 60) /
             (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) AS aas,
       CASE
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) > 4 THEN 'CRITICAL'
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) > 2 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM db_time_data d
  LEFT JOIN instance_names i ON d.instance_number = i.instance_number
 ORDER BY d.begin_interval_time DESC, i.instance_name;
<html>
<head>
  <title>Oracle RAC Health Check Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
    h1, h2 { color: #2c3e50; }
    pre { background-color: #fff; padding: 10px; border: 1px solid #ccc; overflow: auto; }
  </style>
</head>
<body>

 02_active_sessions.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sample_time FORMAT A20
COLUMN instance FORMAT 99
COLUMN service_name FORMAT A20
COLUMN session_type FORMAT A15
COLUMN status FORMAT A10
COLUMN active_count FORMAT 99999
COLUMN inactive_count FORMAT 99999

PROMPT === ACTIVE / INACTIVE SESSIONS BY SERVICE NAME (LAST &DAYS_AGO DAYS) - ORACLE 19C RAC ===

SELECT service_hash,
       service_name,
       instance_number AS instance,
       session_type,
       COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) AS active_count,
       COUNT(CASE WHEN session_state = 'CACHED' OR session_state = 'INACTIVE' THEN 1 END) AS inactive_count,
       CASE
         WHEN COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) > 80 THEN 'CRITICAL'
         WHEN COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) > 20 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - &DAYS_AGO
 GROUP BY service_hash, service_name, instance_number, session_type
 ORDER BY instance, service_name;
 03_sessions_processes.sql
 SET PAGESIZE 100
SELECT inst_id,
       resource_name,
       current_utilization,
       max_utilization,
       limit_value,
       ROUND((current_utilization/limit_value)*100,2) AS utilization_pct,
       CASE
         WHEN ROUND((current_utilization/limit_value)*100,2) > 90 THEN 'CRITICAL'
         WHEN ROUND((current_utilization/limit_value)*100,2) > 80 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$resource_limit
 WHERE resource_name IN ('sessions', 'processes')
 ORDER BY inst_id, resource_name;
 04_sga_pga_usage.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN instance FORMAT 99
COLUMN pga_alloc_mb FORMAT 999999.99
COLUMN sga_mem_mb FORMAT 999999.99
COLUMN status FORMAT A10

WITH pga AS (
  SELECT inst_id,
         ROUND(SUM(value)/1024/1024, 2) AS pga_alloc_mb
    FROM gv$pgastat
   WHERE name = 'total PGA allocated'
   GROUP BY inst_id
),
sga AS (
  SELECT inst_id,
         ROUND(SUM(value)/1024/1024, 2) AS sga_mem_mb
    FROM gv$sga
   GROUP BY inst_id
)
SELECT p.inst_id AS instance,
       p.pga_alloc_mb,
       s.sga_mem_mb,
       CASE
         WHEN p.pga_alloc_mb > 2048 THEN 'CRITICAL'
         WHEN p.pga_alloc_mb > 1024 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM pga p
  JOIN sga s ON p.inst_id = s.inst_id
 ORDER BY p.inst_id;

 05_blocking_sessions.sql
 SET PAGESIZE 100
SELECT inst_id,
       sid, serial#,
       blocking_session,
       blocking_instance,
       wait_class, seconds_in_wait, event,
       CASE
         WHEN blocking_session IS NOT NULL THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$session
 WHERE blocking_session IS NOT NULL;

 06_long_running_sessions.sql
 SET PAGESIZE 100
SELECT inst_id,
       sid, serial#, username, status, logon_time,
       ROUND((SYSDATE - logon_time)*24, 2) AS hours_logged_in
  FROM gv$session
 WHERE status = 'ACTIVE' AND logon_time < SYSDATE - 1/24;
 07_io_response_time.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN avg_latency FORMAT 999.99
COLUMN io_requests FORMAT 9999999
COLUMN status FORMAT A10

PROMPT ===7. IO RESPONSE TIME (AVG SYNC SINGLE-BLOCK READ LATENCY) - ORACLE 19C ===

WITH io_latency AS (
  SELECT s.snap_id,
         CAST(s.begin_interval_time AS DATE) AS begin_interval_time,
         h.instance_number,
         MAX(CASE WHEN h.metric_name = 'Average Synchronous Single-Block Read Latency' THEN h.value END) AS avg_latency,
         MAX(CASE WHEN h.metric_name = 'Physical Read Total IO Requests Per Sec' THEN h.value END) +
         MAX(CASE WHEN h.metric_name = 'Physical Write Total IO Requests Per Sec' THEN h.value END) AS io_requests
    FROM dba_hist_sysmetric_history h
    JOIN dba_hist_snapshot s ON h.snap_id = s.snap_id AND h.instance_number = s.instance_number
   WHERE h.metric_name IN (
         'Average Synchronous Single-Block Read Latency',
         'Physical Read Total IO Requests Per Sec',
         'Physical Write Total IO Requests Per Sec'
       )
     AND s.begin_interval_time >= SYSDATE - &DAYS_AGO
   GROUP BY s.snap_id, s.begin_interval_time, h.instance_number
),
instances AS (
  SELECT DISTINCT instance_number, instance_name FROM gv$instance
)
SELECT TO_CHAR(i.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       n.instance_name,
       ROUND(i.avg_latency, 2) AS avg_latency,
       ROUND(i.io_requests, 2) AS io_requests,
       CASE
         WHEN i.avg_latency > 20 THEN 'CRITICAL'
         WHEN i.avg_latency > 10 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM io_latency i
  LEFT JOIN instances n ON i.instance_number = n.instance_number
 ORDER BY i.begin_interval_time DESC, n.instance_name;
 08_wait_events_window.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sample_time FORMAT A20
COLUMN event FORMAT A40
COLUMN wait_class FORMAT A20
COLUMN instance FORMAT 99
COLUMN count FORMAT 99999
COLUMN status FORMAT A10

PROMPT ===8. TOP WAIT EVENTS (LAST &MINUTES_AGO MINUTES AND &HOURS_AGO HOURS) - ORACLE 19C RAC ===

-- Top events in the last &MINUTES_AGO minutes
PROMPT
PROMPT --- Wait Events (Last &MINUTES_AGO Minutes) ---

SELECT event,
       wait_class,
       instance_number AS instance,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 100 THEN 'CRITICAL'
         WHEN COUNT(*) > 50 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE CAST(sample_time AS DATE) >= SYSDATE - (&MINUTES_AGO / (24 * 60))
 GROUP BY event, wait_class, instance_number
 ORDER BY count DESC
FETCH FIRST 10 ROWS ONLY;

-- Top events in the last &HOURS_AGO hours
PROMPT
PROMPT --- Wait Events (Last &HOURS_AGO Hours) ---

SELECT event,
       wait_class,
       instance_number AS instance,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 500 THEN 'CRITICAL'
         WHEN COUNT(*) > 200 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE CAST(sample_time AS DATE) >= SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event, wait_class, instance_number
 ORDER BY count DESC
FETCH FIRST 10 ROWS ONLY;
09_rac_instance_skew.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN db_time_per_cpu FORMAT 999999.99
COLUMN io_mb FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === 9.INSTANCE SKEW (PER-CPU LOAD & I/O) - ORACLE 19C RAC ===

WITH workload AS (
  SELECT s.snap_id,
         s.begin_interval_time,
         s.instance_number,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END)/1000000 AS db_time_secs
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
     AND tm.stat_name = 'DB time'
   GROUP BY s.snap_id, s.begin_interval_time, s.instance_number
),
io_stats AS (
  SELECT snap_id,
         instance_number,
         SUM(CASE WHEN stat_name IN ('physical read bytes', 'physical write bytes') THEN value ELSE 0 END)/1024/1024 AS io_mb
    FROM dba_hist_sysstat
   WHERE stat_name IN ('physical read bytes', 'physical write bytes')
   GROUP BY snap_id, instance_number
),
cpu_cores AS (
  SELECT instance_number, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name FROM gv$instance
),
combined AS (
  SELECT w.snap_id,
         w.begin_interval_time,
         w.instance_number,
         w.db_time_secs,
         i.io_mb,
         c.cpu_count,
         ROUND(w.db_time_secs / c.cpu_count, 2) AS db_time_per_cpu
    FROM workload w
    JOIN cpu_cores c ON w.instance_number = c.instance_number
    LEFT JOIN io_stats i ON w.snap_id = i.snap_id AND w.instance_number = i.instance_number
)
SELECT TO_CHAR(c.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       n.instance_name,
       c.db_time_per_cpu,
       ROUND(c.io_mb, 2) AS io_mb,
       CASE
         WHEN c.db_time_per_cpu > (SELECT AVG(db_time_per_cpu) * 1.5 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.db_time_per_cpu > (SELECT AVG(db_time_per_cpu) * 1.2 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         WHEN c.io_mb > (SELECT AVG(io_mb) * 1.5 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.io_mb > (SELECT AVG(io_mb) * 1.2 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM combined c
  LEFT JOIN instance_names n ON c.instance_number = n.instance_number
 ORDER BY c.begin_interval_time DESC, n.instance_name;
 10_top_waits_by_instance.sql
 SET PAGESIZE 100
SELECT inst_id, event, COUNT(*) AS waits
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - &HOURS_AGO/24
 GROUP BY inst_id, event
 ORDER BY inst_id, waits DESC FETCH FIRST 10 ROWS WITH TIES;
 11_global_cache_stats.sql
 SET PAGESIZE 100
SELECT inst_id, name, value
  FROM gv$sysstat
 WHERE name IN ('gc cr blocks received', 'gc current blocks received',
                'gc cr block busy', 'gc current block busy',
                'gc cr block lost', 'gc current block lost')
 ORDER BY inst_id;
 12_top_sql_elapsed.sql
 SET PAGESIZE 100
SELECT *
  FROM (SELECT sql_id, plan_hash_value, elapsed_time_delta/1000000 elapsed_sec,
               executions_delta execs,
               module, sql_text
          FROM dba_hist_sqlstat NATURAL JOIN dba_hist_sqltext
         WHERE snap_id IN (SELECT MAX(snap_id) FROM dba_hist_snapshot WHERE begin_interval_time > SYSDATE - &HOURS_AGO/24)
         ORDER BY elapsed_sec DESC)
 WHERE ROWNUM <= 10;
 
 13_tablespace_usage.sql
 SET PAGESIZE 100
SELECT tablespace_name,
       ROUND(used_space*8/1024) AS used_mb,
       ROUND((tablespace_size - used_space)*8/1024) AS free_mb,
       ROUND((used_space/tablespace_size)*100,2) AS pct_used
  FROM dba_tablespace_usage_metrics
 ORDER BY pct_used DESC;
 14_asm_diskgroup_usage.sql
 SET PAGESIZE 100
SELECT name,
       ROUND(total_mb/1024) total_gb,
       ROUND(free_mb/1024) free_gb,
       ROUND((1-(free_mb/total_mb))*100,2) pct_used
  FROM v$asm_diskgroup;
15_log_sync_contention.sql
SET PAGESIZE 100
SELECT inst_id,
       event,
       COUNT(*) AS wait_count,
       ROUND(AVG(wait_time)) AS avg_wait_ms
  FROM gv$active_session_history
 WHERE event = 'log file sync'
   AND sample_time > SYSDATE - &HOURS_AGO/24
 GROUP BY inst_id, event
 ORDER BY wait_count DESC;
 
16_temp_usage.sql
SET PAGESIZE 100
SELECT inst_id, tablespace_name,
       ROUND(used_blocks*8192/1024/1024) used_mb
  FROM gv$sort_segment
 WHERE used_blocks > 0;
 
17_parse_to_exec_ratio.sql
SET PAGESIZE 100
SELECT inst_id,
       ROUND((parse_calls/executions)*100, 2) AS parse_to_exec_pct,
       executions, parse_calls
  FROM gv$sql
 WHERE executions > 100
 ORDER BY parse_to_exec_pct DESC
 FETCH FIRST 10 ROWS WITH TIES;
 
18_log_switch_history.sql
SET PAGESIZE 100
SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hour,
       COUNT(*) AS switch_count
  FROM v$log_history
 WHERE first_time >= SYSDATE - &DAYS_AGO
 GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD HH24')
 ORDER BY hour;
 
19_fra_usage.sql
SET PAGESIZE 100
SELECT name,
       space_limit/1024/1024 AS limit_mb,
       space_used/1024/1024 AS used_mb,
       space_reclaimable/1024/1024 AS reclaimable_mb,
       ROUND((space_used/space_limit)*100, 2) AS pct_used,
       CASE
         WHEN ROUND((space_used/space_limit)*100, 2) > 95 THEN 'CRITICAL'
         WHEN ROUND((space_used/space_limit)*100, 2) > 85 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM v$recovery_file_dest;
  20_ashtop_5minutes.sql
  SET PAGESIZE 100
SET LINESIZE 200
COLUMN username FORMAT A15
COLUMN sql_id FORMAT A15
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === ASH TOP SQL (LAST 5 MINUTES) WITH AAS THRESHOLD ===

SELECT username,
       sql_id,
       COUNT(*) / (5 * 60) AS aas,
       CASE
         WHEN COUNT(*) / (5 * 60) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 5 / (24 * 60)
   AND session_type = 'FOREGROUND'
 GROUP BY username, sql_id
 ORDER BY aas DESC
FETCH FIRST 10 ROWS ONLY;
21_ashtop_1hour.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN username FORMAT A15
COLUMN sql_id FORMAT A15
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === ASH TOP SQL (LAST 1 HOUR) WITH AAS THRESHOLD ===

SELECT username,
       sql_id,
       COUNT(*) / (60 * 60) AS aas,
       CASE
         WHEN COUNT(*) / (60 * 60) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 1 / 24
   AND session_type = 'FOREGROUND'
 GROUP BY username, sql_id
 ORDER BY aas DESC
FETCH FIRST 10 ROWS ONLY;
22
SET PAGESIZE 100
SET LINESIZE 200
COLUMN originating_timestamp FORMAT A30
COLUMN message_text FORMAT A100
COLUMN inst_id FORMAT 99
COLUMN status FORMAT A10

PROMPT === ORA- ERRORS IN ALERT LOG (LAST 3 HOURS) - ORACLE 19C RAC ===

SELECT inst_id,
       TO_CHAR(CAST(originating_timestamp AS DATE), 'YYYY-MM-DD HH24:MI:SS') AS originating_timestamp,
       message_text,
       CASE
         WHEN LOWER(message_text) LIKE '%ora-%' THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$diag_alert_ext
 WHERE CAST(originating_timestamp AS DATE) > SYSDATE - 3/24
   AND LOWER(message_text) LIKE '%ora-%'
 ORDER BY originating_timestamp DESC;
 23
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN sid FORMAT 99999
COLUMN serial# FORMAT 99999
COLUMN username FORMAT A15
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20
COLUMN status FORMAT A10

PROMPT === DATABASE OBJECT LOCKING DETAILS (GV$LOCK + DBA_OBJECTS) ===

SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       o.object_name,
       o.object_type,
       CASE
         WHEN l.lmode IN (4, 5, 6) THEN 'LOCKED'
         ELSE 'REQUEST'
       END AS status
  FROM gv$session s
  JOIN gv$lock l ON s.sid = l.sid AND s.inst_id = l.inst_id
  JOIN dba_objects o ON l.id1 = o.object_id
 WHERE s.username IS NOT NULL
   AND l.type = 'TX'
 ORDER BY s.inst_id, s.sid;

24_invalid_objects_last_hour.sql

SET PAGESIZE 100
SET LINESIZE 200
SELECT owner, object_name, object_type, status, last_ddl_time
  FROM dba_objects
 WHERE status = 'INVALID'
   AND last_ddl_time > SYSDATE - 1/24
 ORDER BY last_ddl_time DESC;

 25_invalid_indexes_last_hour.sql
SET PAGESIZE 100
SET LINESIZE 200
SELECT i.owner, i.index_name, i.index_type, i.status, i.last_analyzed,
       p.partition_name
  FROM dba_indexes i
  LEFT JOIN dba_ind_partitions p ON i.index_name = p.index_name AND i.owner = p.index_owner
 WHERE i.status = 'UNUSABLE'
    OR (p.status = 'UNUSABLE' AND p.last_analyzed > SYSDATE - 1/24)
 ORDER BY i.owner, i.index_name;

 26_top10_long_running_sessions.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT s.inst_id, s.sid, s.serial#, s.username, s.program,
       s.sql_id, s.status,
       ROUND((SYSDATE - s.logon_time) * 24 * 60, 2) AS minutes_active
  FROM gv$session s
 WHERE s.status = 'ACTIVE'
   AND s.type = 'USER'
   AND s.logon_time > SYSDATE - 1/24
 ORDER BY minutes_active DESC FETCH FIRST 10 ROWS ONLY;

 27_session_failures_last_hour.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT session_id, instance_number, username, action_name, error_number, error_message, event_timestamp
  FROM dba_audit_session
 WHERE returncode != 0
   AND event_timestamp > SYSDATE - 1/24
 ORDER BY event_timestamp DESC;

 28_active_db_services.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT name, network_name, creation_date
  FROM dba_services
 WHERE enabled = 'TRUE';


 29_current_active_session_count.sql

 SET PAGESIZE 100
SET LINESIZE 200
SELECT inst_id, COUNT(*) AS active_sessions
  FROM gv$session
 WHERE status = 'ACTIVE'
 GROUP BY inst_id
 ORDER BY inst_id;

 30_downgraded_parallel_sessions.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT sid, username, degree, requested_degree, sql_id, program
  FROM gv$px_session
 WHERE degree < requested_degree
 ORDER BY degree;

 31_unstable_sql_plans_24h.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN plan_hash_value FORMAT 9999999999
COLUMN execs FORMAT 999999
COLUMN avg_etime FORMAT 99999.99
COLUMN module FORMAT A20

SELECT sql_id,
       COUNT(DISTINCT plan_hash_value) AS plan_count,
       MIN(plan_hash_value) KEEP (DENSE_RANK FIRST ORDER BY elapsed_time_total DESC) AS sample_plan,
       SUM(executions_delta) AS execs,
       ROUND(SUM(elapsed_time_delta)/1000000/NULLIF(SUM(executions_delta), 0), 2) AS avg_etime_secs,
       MIN(module) AS module
  FROM dba_hist_sqlstat
 WHERE snap_id IN (
       SELECT snap_id FROM dba_hist_snapshot
        WHERE begin_interval_time > SYSDATE - 1)
 GROUP BY sql_id
HAVING COUNT(DISTINCT plan_hash_value) > 1
ORDER BY plan_count DESC, execs DESC
FETCH FIRST 20 ROWS ONLY;
 
32_sga_pga_advisory.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN target_mb FORMAT 99999
COLUMN est_extra_rw_mb FORMAT 99999.99
COLUMN est_cache_hit FORMAT 999.99
COLUMN advice FORMAT A10

PROMPT === PGA TARGET ADVICE (Oracle 19c) ===
SELECT ROUND(pga_target_for_estimate / 1024 / 1024) AS target_mb,
       ROUND(estd_extra_bytes_rw / 1024 / 1024, 2) AS est_extra_rw_mb,
       estd_pga_cache_hit_percentage AS est_cache_hit,
       CASE
         WHEN estd_pga_cache_hit_percentage >= 99 THEN 'OK'
         WHEN estd_pga_cache_hit_percentage >= 90 THEN 'WARNING'
         ELSE 'CRITICAL'
       END AS advice
  FROM v$pga_target_advice
 WHERE estd_pga_cache_hit_percentage IS NOT NULL
 ORDER BY target_mb;

PROMPT
PROMPT === SGA TARGET ADVICE (Oracle 19c) ===
SELECT ROUND(sga_size / 1024) AS target_mb,
       estd_db_time / 100 AS est_db_time_seconds,
       estd_physical_reads,
       CASE
         WHEN estd_db_time <=
              MIN(estd_db_time) OVER () THEN 'OK'
         WHEN estd_db_time <=
              MIN(estd_db_time) OVER () * 1.1 THEN 'WARNING'
         ELSE 'CRITICAL'
       END AS advice
  FROM v$sga_target_advice
 WHERE sga_size_factor BETWEEN 0.5 AND 2
 ORDER BY sga_size;
 33_top_sql_io.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN executions FORMAT 9999999
COLUMN disk_reads FORMAT 9999999
COLUMN avg_io FORMAT 999999.99
COLUMN module FORMAT A20

PROMPT === TOP 5 SQLs BY DISK READS ===
SELECT *
  FROM (
    SELECT sql_id,
           executions_delta AS executions,
           disk_reads_delta AS disk_reads,
           ROUND(disk_reads_delta / NULLIF(executions_delta, 0), 2) AS avg_io,
           module
      FROM dba_hist_sqlstat
     WHERE executions_delta > 0
     ORDER BY disk_reads_delta DESC
  )
WHERE ROWNUM <= 5;
34_top_sql_cpu.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN executions FORMAT 9999999
COLUMN cpu_time FORMAT 9999999.99
COLUMN avg_cpu FORMAT 999999.99
COLUMN module FORMAT A20

PROMPT === TOP 5 SQLs BY CPU TIME ===
SELECT *
  FROM (
    SELECT sql_id,
           executions_delta AS executions,
           cpu_time_delta/1000000 AS cpu_time,
           ROUND((cpu_time_delta/1000000)/NULLIF(executions_delta, 0), 2) AS avg_cpu,
           module
      FROM dba_hist_sqlstat
     WHERE executions_delta > 0
     ORDER BY cpu_time_delta DESC
  )
WHERE ROWNUM <= 5;
42_realtime_aas.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN cpu_count FORMAT 99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT ===42. REAL-TIME AAS (GV$ACTIVE_SESSION_HISTORY, LAST &MINUTES_AGO MINUTES) ===

WITH active_sessions AS (
  SELECT inst_id,
         COUNT(*) / (&MINUTES_AGO * 60) AS aas
    FROM gv$active_session_history
   WHERE sample_time > SYSDATE - (&MINUTES_AGO / 1440)
     AND session_type = 'FOREGROUND'
   GROUP BY inst_id
),
cpu_cores AS (
  SELECT instance_number AS inst_id, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
)
SELECT a.inst_id,
       c.cpu_count,
       ROUND(a.aas, 2) AS aas,
       CASE
         WHEN a.aas > c.cpu_count THEN 'CRITICAL'
         WHEN a.aas > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM active_sessions a
  JOIN cpu_cores c ON a.inst_id = c.inst_id
 ORDER BY a.inst_id;
 43_realtime_cpu_utilization.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN cpu_busy_secs FORMAT 999999.99
COLUMN total_cpu_secs FORMAT 999999.99
COLUMN cpu_util_pct FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === REAL-TIME CPU UTILIZATION (GV$OSSTAT) - ORACLE 19C RAC ===

WITH os_stat AS (
  SELECT inst_id,
         MAX(CASE WHEN stat_name = 'BUSY_TIME' THEN value END) AS busy_time,
         MAX(CASE WHEN stat_name = 'IDLE_TIME' THEN value END) AS idle_time
    FROM gv$osstat
   WHERE stat_name IN ('BUSY_TIME', 'IDLE_TIME')
   GROUP BY inst_id
)
SELECT inst_id,
       ROUND(busy_time / 100, 2) AS cpu_busy_secs,
       ROUND((busy_time + idle_time) / 100, 2) AS total_cpu_secs,
       ROUND((busy_time / (busy_time + idle_time)) * 100, 2) AS cpu_util_pct,
       CASE
         WHEN (busy_time / (busy_time + idle_time)) * 100 > 90 THEN 'CRITICAL'
         WHEN (busy_time / (busy_time + idle_time)) * 100 > 75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM os_stat
 ORDER BY inst_id;
 44_rac_gc_waits.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN event FORMAT A40
COLUMN samples FORMAT 99999
COLUMN pct FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === TOP GLOBAL CACHE WAITS (GV$ACTIVE_SESSION_HISTORY) ===

SELECT event,
       COUNT(*) AS samples,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 2) AS pct,
       CASE
         WHEN event LIKE 'gc%' AND COUNT(*) > 100 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'gc%'
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event
 ORDER BY samples DESC
FETCH FIRST 10 ROWS ONLY;
45_rac_gc_waits_by_instance.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A40
COLUMN count FORMAT 99999
COLUMN status FORMAT A10

PROMPT === GC WAITS BY INSTANCE (GV$ACTIVE_SESSION_HISTORY) ===

SELECT inst_id,
       event,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 500 THEN 'CRITICAL'
         WHEN COUNT(*) > 200 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'gc%' AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY inst_id, event
 ORDER BY inst_id, count DESC;
46_rac_blocking_ges.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN blocking_session FORMAT 99999
COLUMN blocking_inst_id FORMAT 99
COLUMN blocks FORMAT 9999
COLUMN first_seen FORMAT A20
COLUMN last_seen FORMAT A20
COLUMN status FORMAT A10

PROMPT === GES BLOCKING EVENTS (GV$ACTIVE_SESSION_HISTORY) ===

SELECT blocking_session, blocking_inst_id,
       COUNT(*) AS blocks,
       TO_CHAR(MIN(sample_time), 'YYYY-MM-DD HH24:MI') AS first_seen,
       TO_CHAR(MAX(sample_time), 'YYYY-MM-DD HH24:MI') AS last_seen,
       CASE
         WHEN COUNT(*) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE blocking_session IS NOT NULL
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY blocking_session, blocking_inst_id
 ORDER BY blocks DESC;

 47_rac_interconnect_stats.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN name FORMAT A40
COLUMN mb FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === HIGH INTERCONNECT ACTIVITY (GV$SYSSTAT) ===

SELECT inst_id,
       name,
       ROUND(value / 1024 / 1024, 2) AS mb,
       CASE
         WHEN value > 500000000 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$sysstat
 WHERE name IN (
       'gc current blocks received',
       'gc cr blocks received',
       'gc current blocks served',
       'gc cr blocks served'
     )
 ORDER BY inst_id, name;
 48_rac_global_enqueue_contention.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN event FORMAT A40
COLUMN samples FORMAT 99999
COLUMN status FORMAT A10

PROMPT === GLOBAL ENQUEUE CONTENTION (GV$ACTIVE_SESSION_HISTORY) ===

SELECT event,
       COUNT(*) AS samples,
       CASE
         WHEN COUNT(*) > 50 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'ges%'
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event
 ORDER BY samples DESC;
 49
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN sid FORMAT 99999
COLUMN serial# FORMAT 99999
COLUMN username FORMAT A15
COLUMN type FORMAT A10
COLUMN mode_held FORMAT A20
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20

PROMPT === DDL OBJECT LOCKS (GV$LOCK + DBA_OBJECTS) ===

SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       l.type,
       DECODE(l.lmode,
              0, 'None',
              1, 'Null',
              2, 'Row-S (SS)',
              3, 'Row-X (SX)',
              4, 'Share',
              5, 'S/Row-X (SSX)',
              6, 'Exclusive', 'Other') AS mode_held,
       o.object_name,
       o.object_type
  FROM gv$session s
  JOIN gv$lock l ON s.sid = l.sid AND s.inst_id = l.inst_id
  JOIN dba_objects o ON l.id1 = o.object_id
 WHERE l.type IN ('TM', 'DL')
   AND s.username IS NOT NULL
 ORDER BY s.inst_id, s.sid;

 38
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN sql_text FORMAT A50
COLUMN elapsed_time FORMAT 999999.99
COLUMN io_interconnect_bytes FORMAT 999999999
COLUMN status FORMAT A10

PROMPT === EXADATA SMART SCAN USAGE (RECENT SQLS) ===

SELECT sql_id,
       SUBSTR(sql_text, 1, 50) AS sql_text,
       elapsed_time / 1000000 AS elapsed_time,
       io_interconnect_bytes,
       CASE
         WHEN io_interconnect_bytes > 0 THEN 'OK'
         ELSE 'WARNING'
       END AS status
  FROM v$sql_monitor
 WHERE io_interconnect_bytes IS NOT NULL
   AND last_refresh_time > SYSDATE - 1/24
 ORDER BY last_refresh_time DESC
FETCH FIRST 10 ROWS ONLY;

26_top10_long_running_sessions.sql
SET PAGESIZE 100
SET LINESIZE 200
SELECT s.inst_id, s.sid, s.serial#, s.username, s.program,
       s.sql_id, s.status,
       ROUND((SYSDATE - s.logon_time) * 24 * 60, 2) AS minutes_active
  FROM gv$session s
 WHERE s.status = 'ACTIVE'
   AND s.type = 'USER'
   AND s.logon_time > SYSDATE - 1/24
 ORDER BY minutes_active DESC FETCH FIRST 10 ROWS ONLY;

 27_session_failures_last_hour.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT session_id, instance_number, username, action_name, error_number, error_message, event_timestamp
  FROM dba_audit_session
 WHERE returncode != 0
   AND event_timestamp > SYSDATE - 1/24
 ORDER BY event_timestamp DESC;

 28_active_db_services.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT name, network_name, creation_date
  FROM dba_services
 WHERE enabled = 'TRUE';
 29_current_active_session_count.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT inst_id, COUNT(*) AS active_sessions
  FROM gv$session
 WHERE status = 'ACTIVE'
 GROUP BY inst_id
 ORDER BY inst_id;

 30_downgraded_parallel_sessions.sql
 SET PAGESIZE 100
SET LINESIZE 200
SELECT sid, username, degree, requested_degree, sql_id, program
  FROM gv$px_session
 WHERE degree < requested_degree
 ORDER BY degree;

 31_unstable_sql_plans_24h.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN plan_hash_value FORMAT 9999999999
COLUMN execs FORMAT 999999
COLUMN avg_etime FORMAT 99999.99
COLUMN module FORMAT A20

SELECT sql_id,
       COUNT(DISTINCT plan_hash_value) AS plan_count,
       MIN(plan_hash_value) KEEP (DENSE_RANK FIRST ORDER BY elapsed_time_total DESC) AS sample_plan,
       SUM(executions_delta) AS execs,
       ROUND(SUM(elapsed_time_delta)/1000000/NULLIF(SUM(executions_delta), 0), 2) AS avg_etime_secs,
       MIN(module) AS module
  FROM dba_hist_sqlstat
 WHERE snap_id IN (
       SELECT snap_id FROM dba_hist_snapshot
        WHERE begin_interval_time > SYSDATE - 1)
 GROUP BY sql_id
HAVING COUNT(DISTINCT plan_hash_value) > 1
ORDER BY plan_count DESC, execs DESC
FETCH FIRST 20 ROWS ONLY;
38_exadata_smart_scan_usage.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN sql_text FORMAT A50
COLUMN elapsed_time FORMAT 999999.99
COLUMN io_interconnect_bytes FORMAT 999999999
COLUMN status FORMAT A10

PROMPT === EXADATA SMART SCAN USAGE (RECENT SQLS) ===

SELECT sql_id,
       SUBSTR(sql_text, 1, 50) AS sql_text,
       elapsed_time / 1000000 AS elapsed_time,
       io_interconnect_bytes,
       CASE
         WHEN io_interconnect_bytes > 0 THEN 'OK'
         ELSE 'WARNING'
       END AS status
  FROM v$sql_monitor
 WHERE io_interconnect_bytes IS NOT NULL
   AND last_refresh_time > SYSDATE - 1/24
 ORDER BY last_refresh_time DESC
FETCH FIRST 10 ROWS ONLY;

41_exadata_iorm_plan.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN name FORMAT A30
COLUMN value FORMAT A30
COLUMN status FORMAT A10

PROMPT === EXADATA IORM CONFIGURATION (GV$CELL_CONFIG) ===

SELECT inst_id,
       name,
       value,
       CASE
         WHEN name = 'iormPlanStatus' AND LOWER(value) LIKE '%active%' THEN 'OK'
         ELSE 'INFO'
       END AS status
  FROM gv$cell_config
 WHERE name IN ('iormPlanObject', 'iormPlanStatus', 'iormPlan')
 ORDER BY inst_id, name;

 
44_rac_gc_waits.sql – Global cache contention (top events)
PROMPT === GES BLOCKING EVENTS (GV$ACTIVE_SESSION_HISTORY) ===
SELECT blocking_session, blocking_inst_id,
       COUNT(*) AS blocks,
       MIN(sample_time) AS first_seen,
       MAX(sample_time) AS last_seen,
       CASE
         WHEN COUNT(*) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE blocking_session IS NOT NULL
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY blocking_session, blocking_inst_id
 ORDER BY blocks DESC;
45_rac_gc_waits_by_instance.sql – GC wait breakdown per node
PROMPT === GC WAITS BY INSTANCE (GV$ACTIVE_SESSION_HISTORY) ===
SELECT inst_id,
       event,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 500 THEN 'CRITICAL'
         WHEN COUNT(*) > 200 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'gc%' AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY inst_id, event
 ORDER BY inst_id, count DESC;
46_rac_blocking_ges.sql – GES blocking sessions (RAC locks)
PROMPT === GES BLOCKING EVENTS (GV$ACTIVE_SESSION_HISTORY) ===
SELECT blocking_session, blocking_inst_id,
       COUNT(*) AS blocks,
       MIN(sample_time) AS first_seen,
       MAX(sample_time) AS last_seen,
       CASE
         WHEN COUNT(*) > 20 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE blocking_session IS NOT NULL
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY blocking_session, blocking_inst_id
 ORDER BY blocks DESC;

47_rac_interconnect_stats.sql – Interconnect activity (GC blocks)
PROMPT === HIGH INTERCONNECT ACTIVITY (GV$SYSSTAT) ===
SELECT inst_id,
       name,
       ROUND(value / 1024 / 1024, 2) AS mb,
       CASE
         WHEN value > 500000000 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$sysstat
 WHERE name IN (
       'gc current blocks received',
       'gc cr blocks received',
       'gc current blocks served',
       'gc cr blocks served'
     )
 ORDER BY inst_id, name;

48_rac_global_enqueue_contention.sql – Enqueue waits via GES
PROMPT === GLOBAL ENQUEUE CONTENTION (GV$ACTIVE_SESSION_HISTORY) ===
SELECT event,
       COUNT(*) AS samples,
       CASE
         WHEN COUNT(*) > 50 THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE event LIKE 'ges%'
   AND sample_time > SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event
 ORDER BY samples DESC;


50_blocking_session_chains.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN sid FORMAT 99999
COLUMN serial# FORMAT 99999
COLUMN username FORMAT A15
COLUMN blocking_sid FORMAT 99999
COLUMN blocking_inst FORMAT 99
COLUMN wait_event FORMAT A40
COLUMN status FORMAT A10

PROMPT === BLOCKING SESSION CHAINS (GV$SESSION) ===

SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       s.blocking_session AS blocking_sid,
       s.blocking_instance AS blocking_inst,
       s.event AS wait_event,
       CASE
         WHEN s.blocking_session IS NOT NULL THEN 'BLOCKED'
         ELSE 'OK'
       END AS status
  FROM gv$session s
 WHERE s.username IS NOT NULL
   AND s.blocking_session IS NOT NULL
 ORDER BY s.inst_id, s.sid;

 50_blocking_session_chains.sql
51_ora_01017_login_errors.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN originating_timestamp FORMAT A30
COLUMN message_text FORMAT A100
COLUMN host_info FORMAT A40
COLUMN status FORMAT A10

PROMPT === ORA-01017 LOGIN DENIED ERRORS FROM ALERT LOG (LAST 1 HOUR) ===

SELECT TO_CHAR(originating_timestamp, 'YYYY-MM-DD HH24:MI:SS') AS originating_timestamp,
       message_text,
       REGEXP_SUBSTR(message_text, 'host: \S+', 1, 1) AS host_info,
       'CRITICAL' AS status
  FROM x$dbgalertext
 WHERE originating_timestamp > SYSDATE - 1/24
   AND LOWER(message_text) LIKE '%ora-01017%'
 ORDER BY originating_timestamp DESC;
 52_awr_exadata_smart_scan.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN elapsed_s FORMAT 999999.99
COLUMN execs FORMAT 99999
COLUMN buffer_gets FORMAT 999999999
COLUMN disk_reads FORMAT 99999999
COLUMN status FORMAT A10

PROMPT === AWR SMART SCAN INSIGHT (LAST 1 DAY FROM DBA_HIST_SQLSTAT) ===

SELECT s.sql_id,
       ROUND(SUM(s.elapsed_time_delta)/1e6, 2) AS elapsed_s,
       SUM(s.executions_delta) AS execs,
       SUM(s.buffer_gets_delta) AS buffer_gets,
       SUM(s.disk_reads_delta) AS disk_reads,
       CASE
         WHEN SUM(s.disk_reads_delta) > 0 AND SUM(s.buffer_gets_delta)/SUM(s.disk_reads_delta) < 5 THEN 'OK'
         ELSE 'WARNING'
       END AS status
  FROM dba_hist_sqlstat s
 WHERE s.snap_id IN (
       SELECT snap_id FROM dba_hist_snapshot
        WHERE begin_interval_time > SYSDATE - 1
     )
 GROUP BY s.sql_id
 ORDER BY elapsed_s DESC
FETCH FIRST 10 ROWS ONLY;
