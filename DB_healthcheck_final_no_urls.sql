
#!/bin/bash

# Function to get Oracle parameters from a CDB
get_db_parameters() {
  local conn_str=$1
  local out_file=$2
  
  sqlplus -s /nolog << EOF > /dev/null
  connect $conn_str
  set pagesize 0
  set feedback off
  set verify off
  set linesize 1000
  set trimspool on
  spool $out_file
  select name || '=' || value from v\$parameter 
  where name not in (
    'instance_name',
    'db_unique_name',
    'service_names',
    'local_listener',
    'remote_listener',
    'log_archive_dest_1',
    'log_archive_dest_2',
    'fal_server',
    'db_file_name_convert',
    'log_file_name_convert',
    'db_create_file_dest',
    'db_recovery_file_dest'
  );
  spool off
  exit
EOF
}

# Function to compare parameters and generate HTML
generate_html_report() {
  local file1=$1
  local file2=$2
  local html_file=$3

  echo "<html>
<head>
<style>
  table {border-collapse: collapse; width: 100%;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  tr:nth-child(even) {background-color: #f2f2f2;}
  .diff {color: red; font-weight: bold;}
</style>
</head>
<body>
<h2>Oracle CDB Parameter Comparison</h2>
<p>Generated at: $(date)</p>
<table>
  <tr><th>Parameter</th><th>CDB1 Value</th><th>CDB2 Value</th></tr>" > $html_file

  awk -F= '
    NR==FNR {a[$1]=$2; next} 
    $1 in a {if(a[$1] != $2) print $1,a[$1],$2; delete a[$1]} 
    END {for (i in a) print i,a[$1],""}
  ' $file1 $file2 | while read param val1 val2
  do
    echo "<tr>
            <td>$param</td>
            <td $( [ "$val1" != "$val2" ] && echo 'class="diff"')>$val1</td>
            <td $( [ "$val1" != "$val2" ] && echo 'class="diff"')>$val2</td>
          </tr>"
  done >> $html_file

  echo "</table></body></html>" >> $html_file
}

# Function to send email
send_email() {
  local html_file=$1
  local recipient=$2
  local subject=$3

  (
  echo "To: $recipient"
  echo "Subject: $subject"
  echo "Content-Type: text/html"
  echo
  cat $html_file
  ) | sendmail -t
}

#!/bin/bash

# Source functions
source ./oracle_compare_functions.sh

# Configuration
CDB1_CONN="sys/password@cdb1 as sysdba"
CDB2_CONN="sys/password@cdb2 as sysdba"
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/parameter_compare_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle CDB Parameter Comparison Report"

# Create temporary directory
mkdir -p "$TMP_DIR"

# Get parameters from both CDBs
get_db_parameters "$CDB1_CONN" "$TMP_DIR/cdb1_params.txt"
get_db_parameters "$CDB2_CONN" "$TMP_DIR/cdb2_params.txt"

# Clean parameter files (remove empty lines and SQL*Plus formatting)
sed -i '/^$/d' $TMP_DIR/cdb1_params.txt $TMP_DIR/cdb2_params.txt
sed -i '/^Disconnected/d' $TMP_DIR/cdb1_params.txt $TMP_DIR/cdb2_params.txt

# Generate HTML report
generate_html_report "$TMP_DIR/cdb1_params.txt" "$TMP_DIR/cdb2_params.txt" "$REPORT_FILE"

# Send email with HTML report
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"

# Cleanup temporary files
rm -rf "$TMP_DIR"


#!/bin/bash

# Common function to initialize HTML
init_html_report() {
  local html_file=$1
  cat << EOF > $html_file
<html>
<head>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  tr:nth-child(even) {background-color: #f2f2f2;}
  .diff {color: red; font-weight: bold;}
  .section {margin-top: 30px; border-bottom: 2px solid #444;}
  h2 {color: #2c3e50;}
</style>
</head>
<body>
<h1>Oracle CDB Comparison Report</h1>
<p>Generated at: $(date)</p>
EOF
}

# Function to perform PDB clone pre-check
pdb_clone_precheck() {
  local src_conn=$1
  local tgt_conn=$2
  local html_file=$3
  
  echo "<div class='section'>" >> $html_file
  echo "<h2>PDB Clone Pre-Check Results</h2>" >> $html_file
  
  # Get source CDB information
  src_info=$(sqlplus -s $src_conn << EOF
set pagesize 0 feedback off verify off
SELECT 'CDB_NAME=' || name FROM v\$database;
SELECT 'VERSION=' || version FROM v\$instance;
SELECT 'ARCHIVE_LOG=' || log_mode FROM v\$database;
SELECT 'CHARACTERSET=' || value FROM nls_database_parameters 
WHERE parameter = 'NLS_CHARACTERSET';
SELECT 'PDB_COUNT=' || COUNT(*) FROM v\$pdbs WHERE open_mode = 'READ WRITE';
EOF
)

  # Get target CDB information
  tgt_info=$(sqlplus -s $tgt_conn << EOF
set pagesize 0 feedback off verify off
SELECT 'CDB_NAME=' || name FROM v\$database;
SELECT 'COMPATIBLE=' || value FROM v\$parameter WHERE name = 'compatible';
SELECT 'DB_CREATE_FILE_DEST=' || value FROM v\$parameter 
WHERE name = 'db_create_file_dest';
SELECT 'STORAGE_AVAILABLE_GB=' || 
ROUND((SUM(free_space)/1024/1024/1024)) FROM dba_data_files;
EOF
)

  # Parse information into arrays
  declare -A src_arr tgt_arr
  while IFS='=' read -r key value; do
    [ ! -z "$key" ] && src_arr["$key"]="$value"
  done <<< "$src_info"
  
  while IFS='=' read -r key value; do
    [ ! -z "$key" ] && tgt_arr["$key"]="$value"
  done <<< "$tgt_info"

  # Generate comparison table
  echo "<table><tr><th>Check Item</th><th>Source Value</th><th>Target Value</th><th>Status</th></tr>" >> $html_file

  # Check 1: Compatibility version
  if [ "${src_arr[VERSION]}" != "${tgt_arr[COMPATIBLE]}" ]; then
    status="❌ Mismatch"
  else
    status="✅ Match"
  fi
  echo "<tr>
        <td>Version Compatibility</td>
        <td>${src_arr[VERSION]}</td>
        <td>${tgt_arr[COMPATIBLE]}</td>
        <td>$status</td>
      </tr>" >> $html_file

  # Check 2: Character set
  if [ "${src_arr[CHARACTERSET]}" != "${tgt_arr[CHARACTERSET]}" ]; then
    status="❌ Mismatch"
  else
    status="✅ Match"
  fi
  echo "<tr>
        <td>Character Set</td>
        <td>${src_arr[CHARACTERSET]}</td>
        <td>${tgt_arr[CHARACTERSET]}</td>
        <td>$status</td>
      </tr>" >> $html_file

  # Check 3: Archive log mode
  status=""
  [ "${src_arr[ARCHIVE_LOG]}" != "ARCHIVELOG" ] && status+="⚠️ Source not in ARCHIVELOG mode"
  echo "<tr>
        <td>Archive Log Mode</td>
        <td>${src_arr[ARCHIVE_LOG]}</td>
        <td>-</td>
        <td>$status</td>
      </tr>" >> $html_file

  # Check 4: Target storage
  if [ "${tgt_arr[STORAGE_AVAILABLE_GB]}" -lt 50 ]; then
    status="⚠️ Low storage (${tgt_arr[STORAGE_AVAILABLE_GB]}GB)"
  else
    status="✅ Adequate"
  fi
  echo "<tr>
        <td>Target Storage Available</td>
        <td>-</td>
        <td>${tgt_arr[STORAGE_AVAILABLE_GB]}GB</td>
        <td>$status</td>
      </tr>" >> $html_file

  echo "</table></div>" >> $html_file
}

# (Keep existing get_db_parameters, generate_html_report, and send_email functions from previous version)

#!/bin/bash

source ./oracle_compare_functions.sh

# Configuration
SRC_CDB="sys/src_password@source_cdb as sysdba"
TGT_CDB="sys/tgt_password@target_cdb as sysdba"
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/cdb_comparison_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle CDB Comparison Report"

# Create temporary directory
mkdir -p "$TMP_DIR"

# Initialize HTML report
init_html_report "$REPORT_FILE"

# Perform PDB Clone Pre-Check
pdb_clone_precheck "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Parameter comparison section
echo "<div class='section'>" >> $REPORT_FILE
echo "<h2>Parameter Differences</h2>" >> $REPORT_FILE

# Get parameters from both CDBs
get_db_parameters "$SRC_CDB" "$TMP_DIR/src_params.txt"
get_db_parameters "$TGT_CDB" "$TMP_DIR/tgt_params.txt"

# Clean parameter files
sed -i '/^$/d' $TMP_DIR/src_params.txt $TMP_DIR/tgt_params.txt
sed -i '/^Disconnected/d' $TMP_DIR/src_params.txt $TMP_DIR/tgt_params.txt

# Generate parameter comparison
generate_html_report "$TMP_DIR/src_params.txt" "$TMP_DIR/tgt_params.txt" "$REPORT_FILE.tmp"
tail -n +12 "$REPORT_FILE.tmp" | head -n -1 >> "$REPORT_FILE"
rm "$REPORT_FILE.tmp"

echo "</div></body></html>" >> $REPORT_FILE

# Send email and cleanup
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"
rm -rf "$TMP_DIR"


#!/bin/bash

# Common function to initialize HTML
init_html_report() {
  local html_file=$1
  cat << EOF > $html_file
<html>
<head>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  tr:nth-child(even) {background-color: #f2f2f2;}
  .diff {color: red; font-weight: bold;}
  .section {margin-top: 30px; border-bottom: 2px solid #444;}
  h2 {color: #2c3e50;}
  .warning {color: #e67e22;}
  .critical {color: #e74c3c;}
</style>
</head>
<body>
<h1>Oracle CDB Comparison Report</h1>
<p>Generated at: $(date)</p>
EOF
}

# Function to perform PDB clone pre-check
pdb_clone_precheck() {
  local src_conn=$1
  local tgt_conn=$2
  local html_file=$3
  
  echo "<div class='section'>" >> $html_file
  echo "<h2>PDB Clone Pre-Check Results</h2>" >> $html_file
  
  # Get source CDB information
  src_info=$(sqlplus -s $src_conn << EOF
set pagesize 0 feedback off verify off
SELECT 'CDB_NAME=' || name FROM v\$database;
SELECT 'VERSION=' || version FROM v\$instance;
SELECT 'ARCHIVE_LOG=' || log_mode FROM v\$database;
SELECT 'CHARACTERSET=' || value FROM nls_database_parameters 
WHERE parameter = 'NLS_CHARACTERSET';
SELECT 'PDB_COUNT=' || COUNT(*) FROM v\$pdbs WHERE open_mode = 'READ WRITE';
SELECT 'LOCAL_UNDO=' || local_undo_enabled FROM v\$database;
SELECT 'TDE_STATUS=' || status FROM v\$encryption_wallet;
SELECT 'TDE_WALLET_TYPE=' || wallet_type FROM v\$encryption_wallet;
SELECT 'TDE_MASTER_KEY=' || key_id FROM v\$encryption_keys 
WHERE activation_time = (SELECT MAX(activation_time) FROM v\$encryption_keys);
EOF
)

  # Get target CDB information
  tgt_info=$(sqlplus -s $tgt_conn << EOF
set pagesize 0 feedback off verify off
SELECT 'CDB_NAME=' || name FROM v\$database;
SELECT 'COMPATIBLE=' || value FROM v\$parameter WHERE name = 'compatible';
SELECT 'DB_CREATE_FILE_DEST=' || value FROM v\$parameter 
WHERE name = 'db_create_file_dest';
SELECT 'STORAGE_AVAILABLE_GB=' || 
ROUND((SUM(free_space)/1024/1024/1024)) FROM dba_data_files;
SELECT 'LOCAL_UNDO=' || local_undo_enabled FROM v\$database;
SELECT 'TDE_STATUS=' || status FROM v\$encryption_wallet;
SELECT 'TDE_WALLET_TYPE=' || wallet_type FROM v\$encryption_wallet;
SELECT 'TDE_KEYSTORE=' || wrl_parameter FROM v\$encryption_wallet;
EOF
)

  # Parse information into arrays
  declare -A src_arr tgt_arr
  while IFS='=' read -r key value; do
    [ ! -z "$key" ] && src_arr["$key"]="$value"
  done <<< "$src_info"
  
  while IFS='=' read -r key value; do
    [ ! -z "$key" ] && tgt_arr["$key"]="$value"
  done <<< "$tgt_info"

  # Generate comparison table
  echo "<table><tr><th>Check Item</th><th>Source Value</th><th>Target Value</th><th>Status</th></tr>" >> $html_file

  # Existing checks (version, character set, archive log, storage)
  # ... [keep previous checks here] ...

  # Local Undo Check
  echo "<tr>
        <td>Local Undo Mode</td>
        <td>${src_arr[LOCAL_UNDO]}</td>
        <td>${tgt_arr[LOCAL_UNDO]}</td>
        <td>$(
          [ "${src_arr[LOCAL_UNDO]}" = "${tgt_arr[LOCAL_UNDO]}" ] && 
          echo '✅ Match' || 
          echo '⚠️ Mismatch - Clone may require NOCOPY option'
        )</td>
      </tr>" >> $html_file

  # TDE Configuration Check
  tde_status=""
  if [ "${src_arr[TDE_STATUS]}" = "OPEN" ]; then
    if [ "${tgt_arr[TDE_STATUS]}" = "OPEN" ]; then
      if [ "${src_arr[TDE_WALLET_TYPE]}" = "${tgt_arr[TDE_WALLET_TYPE]}" ]; then
        tde_status="✅ Active (${src_arr[TDE_WALLET_TYPE]})"
      else
        tde_status="❌ Wallet type mismatch (${src_arr[TDE_WALLET_TYPE]} vs ${tgt_arr[TDE_WALLET_TYPE]})"
      fi
    else
      tde_status="❌ Target TDE wallet not open"
    fi
  else
    tde_status="✅ TDE not enabled in source"
  fi

  echo "<tr>
        <td>TDE Configuration</td>
        <td>${src_arr[TDE_STATUS]} (${src_arr[TDE_WALLET_TYPE]})</td>
        <td>${tgt_arr[TDE_STATUS]} (${tgt_arr[TDE_WALLET_TYPE]})</td>
        <td>$tde_status</td>
      </tr>" >> $html_file

  # TDE Keystore Check
  if [ "${src_arr[TDE_STATUS]}" = "OPEN" ]; then
    echo "<tr>
          <td>TDE Master Key</td>
          <td>${src_arr[TDE_MASTER_KEY]:0:8}...[redacted]</td>
          <td>${tgt_arr[TDE_KEYSTORE]}</td>
          <td>$( [ -n "${tgt_arr[TDE_KEYSTORE]}" ] && 
                echo '✅ Keystore configured' || 
                echo '❌ No keystore available')</td>
        </tr>" >> $html_file
  fi

  echo "</table></div>" >> $html_file
}

# (Keep existing get_db_parameters, generate_html_report, and send_email functions)


#!/bin/bash

# Add these new functions below existing ones

# Function to compare installed patches
compare_patches() {
  local conn1=$1
  local conn2=$2
  local html_file=$3

  echo "<div class='section'>" >> $html_file
  echo "<h2>Patch Comparison</h2>" >> $html_file

  # Get patches from both CDBs
  sqlplus -s $conn1 << EOF > /tmp/patches1.txt
set pagesize 0 feedback off
SELECT patch_id || ':' || patch_uid || ':' || action_time || ':' || description 
FROM registry\$history;
EOF

  sqlplus -s $conn2 << EOF > /tmp/patches2.txt
set pagesize 0 feedback off
SELECT patch_id || ':' || patch_uid || ':' || action_time || ':' || description 
FROM registry\$history;
EOF

  # Process patches
  echo "<table>
        <tr><th>Patch ID</th><th>Description</th><th>Source Applied</th><th>Target Applied</th></tr>" >> $html_file

  awk -F: 'BEGIN {OFS=":"} 
    NR==FNR {a[$1$2]=$0; next} 
    {if ($1$2 in a) {print a[$1$2],$0; delete a[$1$2]} 
    END {for (i in a) print a[i], ":::Missing"} ' /tmp/patches1.txt /tmp/patches2.txt | while read line
  do
    IFS=':' read -r -a data <<< "$line"
    echo "<tr>
            <td>${data[0]}</td>
            <td>${data[3]}</td>
            <td>${data[2]}</td>
            <td $( [ "${data[4]}" != "Missing" ] || echo 'class="critical"')>
                ${data[6]:-Missing}
            </td>
          </tr>"
  done >> $html_file

  echo "</table></div>" >> $html_file
  rm /tmp/patches1.txt /tmp/patches2.txt
}

# Function to compare database components
compare_components() {
  local conn1=$1
  local conn2=$2
  local html_file=$3

  echo "<div class='section'>" >> $html_file
  echo "<h2>Database Components Comparison</h2>" >> $html_file

  # Get components from both CDBs
  sqlplus -s $conn1 << EOF > /tmp/comp1.txt
set pagesize 0 feedback off
SELECT comp_name || ':' || version || ':' || status 
FROM dba_registry;
EOF

  sqlplus -s $conn2 << EOF > /tmp/comp2.txt
set pagesize 0 feedback off
SELECT comp_name || ':' || version || ':' || status 
FROM dba_registry;
EOF

  echo "<table>
        <tr><th>Component</th><th>Source Version</th><th>Target Version</th><th>Status</th></tr>" >> $html_file

  awk -F: 'BEGIN {OFS=":"} 
    NR==FNR {a[$1]=$0; next} 
    {if ($1 in a) {split(a[$1],b,":"); print $0,b[2],b[3]; delete a[$1]} 
    END {for (i in a) print a[i], "Missing:Missing"}' /tmp/comp2.txt /tmp/comp1.txt | while read line
  do
    IFS=':' read -r -a data <<< "$line"
    status=""
    if [ "${data[1]}" != "${data[3]}" ]; then
      status="class='diff'"
    elif [ "${data[6]}" = "Missing" ]; then
      status="class='critical'"
    fi

    echo "<tr>
            <td>${data[0]}</td>
            <td $status>${data[1]} (${data[2]})</td>
            <td $status>${data[3]} (${data[4]})</td>
            <td>$( [ "${data[1]}" = "${data[3]}" ] && echo '✅ Match' || echo '❌ Mismatch')</td>
          </tr>"
  done >> $html_file

  echo "</table></div>" >> $html_file
  rm /tmp/comp1.txt /tmp/comp2.txt
}


#!/bin/bash

source ./oracle_compare_functions.sh

# Configuration (existing)
SRC_CDB="sys/src_password@source_cdb as sysdba"
TGT_CDB="sys/tgt_password@target_cdb as sysdba"
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/cdb_comparison_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle CDB Comparison Report"

# Create temporary directory
mkdir -p "$TMP_DIR"

# Initialize HTML report
init_html_report "$REPORT_FILE"

# Perform PDB Clone Pre-Check (existing)
pdb_clone_precheck "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Compare Patches
compare_patches "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Compare Components
compare_components "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Parameter comparison section (existing)
echo "<div class='section'>" >> $REPORT_FILE
echo "<h2>Parameter Differences</h2>" >> $REPORT_FILE
# ... [existing parameter comparison code] ...
echo "</div></body></html>" >> $REPORT_FILE

# Send email and cleanup
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"
rm -rf "$TMP_DIR"

#!/bin/bash

# Add this new function for CDB parameter comparison
compare_cdb_parameters() {
  local conn1=$1
  local conn2=$2
  local html_file=$3

  echo "<div class='section'>" >> $html_file
  echo "<h2>CDB Parameter Comparison</h2>" >> $html_file
  
  # Get CDB-specific parameters from both databases
  sqlplus -s $conn1 << EOF > /tmp/cdb1_params.txt
set pagesize 0 feedback off
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE' 
AND name NOT IN (
  'db_unique_name',
  'service_names',
  'local_listener',
  'log_archive_dest_1',
  'db_file_name_convert',
  'log_file_name_convert'
);
EOF

  sqlplus -s $conn2 << EOF > /tmp/cdb2_params.txt
set pagesize 0 feedback off
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE' 
AND name NOT IN (
  'db_unique_name',
  'service_names',
  'local_listener',
  'log_archive_dest_1',
  'db_file_name_convert',
  'log_file_name_convert'
);
EOF

  # Clean parameter files
  sed -i '/^$/d' /tmp/cdb1_params.txt /tmp/cdb2_params.txt
  sed -i '/^Disconnected/d' /tmp/cdb1_params.txt /tmp/cdb2_params.txt

  echo "<table>
        <tr><th>Parameter</th><th>CDB1 Value</th><th>CDB2 Value</th><th>Status</th></tr>" >> $html_file

  awk -F= '
    NR==FNR {a[$1]=$2; next} 
    {if ($1 in a) {
        if(a[$1] != $2) 
            printf "<tr><td>%s</td><td class=\"diff\">%s</td><td class=\"diff\">%s</td><td>❌ Mismatch</td></tr>\n", $1,a[$1],$2
        else
            printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>✅ Match</td></tr>\n", $1,a[$1],$2
        delete a[$1]
    }}
    END {for (i in a) printf "<tr><td>%s</td><td>%s</td><td class=\"critical\">Missing</td><td>⚠️ Not Found</td></tr>\n", i,a[i]}
  ' /tmp/cdb1_params.txt /tmp/cdb2_params.txt >> $html_file

  echo "</table></div>" >> $html_file
  rm /tmp/cdb1_params.txt /tmp/cdb2_params.txt
}

# Keep existing functions (init_html_report, pdb_clone_precheck, etc.)


#!/bin/bash

source ./oracle_compare_functions.sh

# Configuration (existing)
SRC_CDB="sys/src_password@source_cdb as sysdba"
TGT_CDB="sys/tgt_password@target_cdb as sysdba"
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/cdb_comparison_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle CDB Comparison Report"

# Create temporary directory
mkdir -p "$TMP_DIR"

# Initialize HTML report
init_html_report "$REPORT_FILE"

# Perform PDB Clone Pre-Check (existing)
pdb_clone_precheck "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Add CDB parameter comparison
compare_cdb_parameters "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Existing comparisons (patches, components, etc.)
compare_patches "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"
compare_components "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Send email and cleanup
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"
rm -rf "$TMP_DIR"

#!/bin/bash

# Add these new functions for PDB comparison

# Function to get list of open PDBs
get_open_pdbs() {
  local conn=$1
  sqlplus -s $conn << EOF
set pagesize 0 feedback off
SELECT name FROM v\$pdbs WHERE open_mode = 'READ WRITE' ORDER BY 1;
EOF
}

# Function to get PDB parameters
get_pdb_parameters() {
  local conn=$1
  local pdb_name=$2
  local out_file=$3
  
  sqlplus -s $conn << EOF > $out_file
ALTER SESSION SET CONTAINER = $pdb_name;
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN (
  'service_names',
  'local_listener',
  'db_file_name_convert',
  'log_file_name_convert'
);
EXIT
EOF

  # Clean output
  sed -i '/^Session altered/d' $out_file
  sed -i '/^Disconnected/d' $out_file
  sed -i '/^$/d' $out_file
}

# Function to compare PDB parameters
compare_pdb_parameters() {
  local src_conn=$1
  local tgt_conn=$2
  local html_file=$3

  echo "<div class='section'>" >> $html_file
  echo "<h2>PDB Parameter Comparison</h2>" >> $html_file

  # Get PDB lists from both CDBs
  src_pdbs=$(get_open_pdbs "$src_conn")
  tgt_pdbs=$(get_open_pdbs "$tgt_conn")

  # Compare common PDBs
  echo "<h3>Common PDBs</h3>" >> $html_file
  for pdb in $src_pdbs; do
    if [[ " ${tgt_pdbs[@]} " =~ " ${pdb} " ]]; then
      echo "<h4>PDB: ${pdb}</h4>" >> $html_file
      get_pdb_parameters "$src_conn" "$pdb" "/tmp/src_pdb_params.txt"
      get_pdb_parameters "$tgt_conn" "$pdb" "/tmp/tgt_pdb_params.txt"

      echo "<table><tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> $html_file
      awk -F= '
        BEGIN {count=0}
        NR==FNR {a[$1]=$2; next}
        {
          if ($1 in a) {
            if (a[$1] != $2) {
              printf "<tr><td>%s</td><td class=\"diff\">%s</td><td class=\"diff\">%s</td></tr>\n", $1,a[$1],$2
            }
            delete a[$1]
          } else {
            printf "<tr><td>%s</td><td>%s</td><td class=\"critical\">Missing</td></tr>\n", $1,$2
          }
        }
        END {
          for (i in a) {
            printf "<tr><td>%s</td><td class=\"critical\">Missing</td><td>%s</td></tr>\n", i,a[i]
          }
        }
      ' "/tmp/src_pdb_params.txt" "/tmp/tgt_pdb_params.txt" >> $html_file
      echo "</table>" >> $html_file
    fi
  done

  # Show PDB existence differences
  echo "<h3>PDB Existence Differences</h3>" >> $html_file
  comm -23 <(echo "$src_pdbs" | sort) <(echo "$tgt_pdbs" | sort) | while read pdb; do
    echo "<p class='warning'>PDB exists only in source: $pdb</p>" >> $html_file
  done

  comm -13 <(echo "$src_pdbs" | sort) <(echo "$tgt_pdbs" | sort) | while read pdb; do
    echo "<p class='warning'>PDB exists only in target: $pdb</p>" >> $html_file
  done

  echo "</div>" >> $html_file
}

#!/bin/bash

source ./oracle_compare_functions.sh

# Configuration (existing)
SRC_CDB="sys/src_password@source_cdb as sysdba"
TGT_CDB="sys/tgt_password@target_cdb as sysdba"
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/cdb_comparison_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle CDB Comparison Report"

# Create temporary directory
mkdir -p "$TMP_DIR"

# Initialize HTML report
init_html_report "$REPORT_FILE"

# Perform existing checks
pdb_clone_precheck "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"
compare_cdb_parameters "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Add new PDB comparison section
compare_pdb_parameters "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Existing comparisons (patches, components)
compare_patches "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"
compare_components "$SRC_CDB" "$TGT_CDB" "$REPORT_FILE"

# Send email and cleanup
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"
rm -rf "$TMP_DIR"

#!/bin/bash

# Function to compare specific PDB parameters
compare_specific_pdb() {
  local src_conn=$1
  local tgt_conn=$2
  local pdb_name=$3
  local html_file=$4

  echo "<div class='section'>" >> $html_file
  echo "<h2>PDB Comparison: ${pdb_name}</h2>" >> $html_file

  # Check PDB existence
  src_exists=$(sqlplus -s $src_conn << EOF
set pagesize 0 feedback off
SELECT COUNT(*) FROM v\$pdbs WHERE name = '${pdb_name}' AND open_mode = 'READ WRITE';
EOF
)

  tgt_exists=$(sqlplus -s $tgt_conn << EOF
set pagesize 0 feedback off
SELECT COUNT(*) FROM v\$pdbs WHERE name = '${pdb_name}' AND open_mode = 'READ WRITE';
EOF
)

  # Clean SQL*Plus output
  src_exists=$(echo $src_exists | tr -d '\n\r')
  tgt_exists=$(echo $tgt_exists | tr -d '\n\r')

  if [ $src_exists -eq 0 ] || [ $tgt_exists -eq 0 ]; then
    echo "<p class='warning'>" >> $html_file
    [ $src_exists -eq 0 ] && echo "PDB ${pdb_name} not found in source CDB<br/>" >> $html_file
    [ $tgt_exists -eq 0 ] && echo "PDB ${pdb_name} not found in target CDB<br/>" >> $html_file
    echo "</p>" >> $html_file
    return
  fi

  # Get parameters from both PDBs
  sqlplus -s $src_conn << EOF > /tmp/src_pdb_params.txt
ALTER SESSION SET CONTAINER = ${pdb_name};
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN (
  'service_names',
  'local_listener',
  'db_file_name_convert',
  'log_file_name_convert'
);
EOF

  sqlplus -s $tgt_conn << EOF > /tmp/tgt_pdb_params.txt
ALTER SESSION SET CONTAINER = ${pdb_name};
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN (
  'service_names',
  'local_listener',
  'db_file_name_convert',
  'log_file_name_convert'
);
EOF

  # Clean files
  sed -i '/^Session altered/d; /^Disconnected/d; /^$/d' /tmp/src_pdb_params.txt /tmp/tgt_pdb_params.txt

  # Generate comparison table
  echo "<table><tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> $html_file

  awk -F= '
    BEGIN {
      mismatch_count=0
      print_count=0
    }
    NR==FNR {a[$1]=$2; next} 
    {
      if ($1 in a) {
        if (a[$1] != $2) {
          printf "<tr><td>%s</td><td class=\"diff\">%s</td><td class=\"diff\">%s</td></tr>\n", $1,a[$1],$2
          mismatch_count++
        }
        delete a[$1]
      } else {
        printf "<tr><td>%s</td><td>%s</td><td class=\"critical\">Missing</td></tr>\n", $1,$2
        mismatch_count++
      }
    }
    END {
      for (i in a) {
        printf "<tr><td>%s</td><td class=\"critical\">Missing</td><td>%s</td></tr>\n", i,a[i]
        mismatch_count++
      }
      exit mismatch_count
    }
  ' /tmp/src_pdb_params.txt /tmp/tgt_pdb_params.txt >> $html_file

  awk_exit=$?
  if [ $awk_exit -eq 0 ]; then
    echo "<tr><td colspan='3' class='success'>All parameters match</td></tr>" >> $html_file
  fi

  echo "</table></div>" >> $html_file
  rm /tmp/src_pdb_params.txt /tmp/tgt_pdb_params.txt
}

#!/bin/bash

source ./oracle_compare_functions.sh

# Configuration
SRC_CDB="sys/src_password@source_cdb as sysdba"
TGT_CDB="sys/tgt_password@target_cdb as sysdba"
PDB_NAME=""  # Will be populated from command line
TMP_DIR="/tmp/oracle_compare"
REPORT_FILE="$TMP_DIR/cdb_comparison_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@company.com"
EMAIL_SUB="Oracle PDB Comparison Report"

# Parse command line arguments
while getopts "p:" opt; do
  case $opt in
    p) PDB_NAME="${OPTARG^^}";;  # Convert to uppercase
    *) echo "Usage: $0 -p pdb_name"; exit 1;;
  esac
done

# Validate input
if [ -z "$PDB_NAME" ]; then
  echo "Error: PDB name must be specified with -p option"
  exit 1
fi

# Create temporary directory
mkdir -p "$TMP_DIR"

# Initialize HTML report
init_html_report "$REPORT_FILE"

# Perform PDB comparison
compare_specific_pdb "$SRC_CDB" "$TGT_CDB" "$PDB_NAME" "$REPORT_FILE"

# Send email and cleanup
send_email "$REPORT_FILE" "$EMAIL_TO" "$EMAIL_SUB"
rm -rf "$TMP_DIR"

#!/bin/bash

# Initialize HTML report
init_html_report() {
  local html_file=$1
  local pdb_name=$2
  cat << EOF > $html_file
<html>
<head>
<title>PDB Compatibility Report: $pdb_name</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  tr:nth-child(even) {background-color: #f2f2f2;}
  .diff {color: red; font-weight: bold;}
  .ok {color: green;}
  .warning {background-color: #fff3cd;}
  .critical {background-color: #f8d7da;}
  h2 {color: #2c3e50; border-bottom: 2px solid #444;}
</style>
</head>
<body>
<h1>PDB Plug-in Compatibility Check: $pdb_name</h1>
<p>Generated at: $(date)</p>
EOF
}

# Get database properties
get_db_properties() {
  local conn=$1
  local pdb_name=$2
  sqlplus -s /nolog << EOF
connect $conn
set heading off
set pagesize 0
set feedback off
SELECT 'VERSION=' || version FROM v\$instance;
SELECT 'COMPATIBLE=' || value FROM v\$parameter WHERE name = 'compatible';
SELECT 'CHARACTERSET=' || value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';
SELECT 'NCHARACTERSET=' || value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';
SELECT 'ENDIAN_FORMAT=' || endian_format FROM v\$transportable_platform tp, v\$database d WHERE tp.platform_name = d.platform_name;
SELECT 'LOCAL_UNDO=' || local_undo_enabled FROM v\$database;
SELECT 'TDE_STATUS=' || status FROM v\$encryption_wallet;
SELECT 'TDE_WALLET_TYPE=' || wallet_type FROM v\$encryption_wallet;
SELECT 'PLATFORM_NAME=' || platform_name FROM v\$database;
SELECT 'PATCH_LEVEL=' || version || ',' || bundle_series FROM dba_registry_sqlpatch ORDER BY action_time DESC FETCH FIRST 1 ROW ONLY;
EXIT;
EOF
}

# Check version compatibility
check_version_compatibility() {
  local src_version=$1
  local tgt_version=$2
  local html_file=$3
  
  echo "<h2>Version Compatibility</h2>" >> $html_file
  echo "<table><tr><th>Check</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file
  
  # Convert versions to numerical format
  src_ver_num=$(echo $src_version | awk -F. '{printf "%02d%02d%02d%02d", $1,$2,$3,$4}')
  tgt_ver_num=$(echo $tgt_version | awk -F. '{printf "%02d%02d%02d%02d", $1,$2,$3,$4}')

  if [ $tgt_ver_num -ge $src_ver_num ]; then
    status="<td class='ok'>✅ Compatible</td>"
  else
    status="<td class='critical'>❌ Target version lower than source</td>"
  fi
  
  echo "<tr>
        <td>Database Version</td>
        <td>$src_version</td>
        <td>$tgt_version</td>
        $status
      </tr>" >> $html_file
}

# Check compatibility parameters
check_compatibility_params() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>Compatibility Parameters</h2>" >> $html_file
  echo "<table><tr><th>Parameter</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file

  # Compatible parameter check
  src_compatible=$(echo "$src_props" | grep '^COMPATIBLE=' | cut -d= -f2)
  tgt_compatible=$(echo "$tgt_props" | grep '^COMPATIBLE=' | cut -d= -f2)

  if [ "$tgt_compatible" \< "$src_compatible" ]; then
    status="<td class='critical'>❌ Target compatible parameter too low</td>"
  else
    status="<td class='ok'>✅ Compatible</td>"
  fi

  echo "<tr>
        <td>COMPATIBLE</td>
        <td>$src_compatible</td>
        <td>$tgt_compatible</td>
        $status
      </tr>" >> $html_file
}

# Check character set compatibility
check_charset_compatibility() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>Character Set Compatibility</h2>" >> $html_file
  echo "<table><tr><th>Character Set</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file

  check_set "NLS_CHARACTERSET" "Character Set"
  check_set "NLS_NCHAR_CHARACTERSET" "National Character Set"

  echo "</table>" >> $html_file
}

check_set() {
  local param=$1
  local name=$2
  
  src_val=$(echo "$src_props" | grep "^$param=" | cut -d= -f2)
  tgt_val=$(echo "$tgt_props" | grep "^$param=" | cut -d= -f2)

  if [ "$src_val" != "$tgt_val" ]; then
    status="<td class='critical'>❌ Mismatch</td>"
  else
    status="<td class='ok'>✅ Match</td>"
  fi

  echo "<tr>
        <td>$name</td>
        <td>$src_val</td>
        <td>$tgt_val</td>
        $status
      </tr>" >> $html_file
}

# Check platform compatibility
check_platform_compatibility() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>Platform Compatibility</h2>" >> $html_file
  echo "<table><tr><th>Check</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file

  src_platform=$(echo "$src_props" | grep '^PLATFORM_NAME=' | cut -d= -f2)
  tgt_platform=$(echo "$tgt_props" | grep '^PLATFORM_NAME=' | cut -d= -f2)
  src_endian=$(echo "$src_props" | grep '^ENDIAN_FORMAT=' | cut -d= -f2)
  tgt_endian=$(echo "$tgt_props" | grep '^ENDIAN_FORMAT=' | cut -d= -f2)

  if [ "$src_platform" != "$tgt_platform" ]; then
    platform_status="⚠️ Different Platforms"
    if [ "$src_endian" != "$tgt_endian" ]; then
      endian_status="❌ Endian mismatch"
    else
      endian_status="✅ Same endian format"
    fi
  else
    platform_status="✅ Same Platform"
    endian_status="-"
  fi

  echo "<tr>
        <td>Platform</td>
        <td>$src_platform</td>
        <td>$tgt_platform</td>
        <td>$platform_status</td>
      </tr>
      <tr>
        <td>Endian Format</td>
        <td>$src_endian</td>
        <td>$tgt_endian</td>
        <td>$endian_status</td>
      </tr>" >> $html_file

  echo "</table>" >> $html_file
}

# Check encryption compatibility
check_encryption_compatibility() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>Encryption Compatibility</h2>" >> $html_file
  echo "<table><tr><th>Check</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file

  src_tde_status=$(echo "$src_props" | grep '^TDE_STATUS=' | cut -d= -f2)
  tgt_tde_status=$(echo "$tgt_props" | grep '^TDE_STATUS=' | cut -d= -f2)
  src_tde_type=$(echo "$src_props" | grep '^TDE_WALLET_TYPE=' | cut -d= -f2)
  tgt_tde_type=$(echo "$tgt_props" | grep '^TDE_WALLET_TYPE=' | cut -d= -f2)

  if [ "$src_tde_status" = "OPEN" ]; then
    if [ "$tgt_tde_status" != "OPEN" ]; then
      status="❌ Target TDE wallet not open"
    elif [ "$src_tde_type" != "$tgt_tde_type" ]; then
      status="❌ Wallet type mismatch"
    else
      status="✅ Compatible"
    fi
  else
    status="✅ TDE not enabled in source"
  fi

  echo "<tr>
        <td>TDE Configuration</td>
        <td>$src_tde_status ($src_tde_type)</td>
        <td>$tgt_tde_status ($tgt_tde_type)</td>
        <td>$status</td>
      </tr>" >> $html_file

  echo "</table>" >> $html_file
}

# Finalize HTML report
finalize_html_report() {
  local html_file=$1
  echo "</body></html>" >> $html_file
}

#!/bin/bash

source ./pdb_compatibility_functions.sh

# Configuration
SRC_CDB="sys/source_password@source_cdb as sysdba"
TGT_CDB="sys/target_password@target_cdb as sysdba"
PDB_NAME="YOUR_PDB_NAME"
REPORT_FILE="/tmp/pdb_compatibility_$(date +%Y%m%d%H%M%S).html"
EMAIL_TO="dba@example.com"

# Initialize report
init_html_report "$REPORT_FILE" "$PDB_NAME"

# Get properties from both CDBs
src_properties=$(get_db_properties "$SRC_CDB" "$PDB_NAME")
tgt_properties=$(get_db_properties "$TGT_CDB" "$PDB_NAME")

# Perform compatibility checks
check_version_compatibility \
  "$(echo "$src_properties" | grep '^VERSION=' | cut -d= -f2)" \
  "$(echo "$tgt_properties" | grep '^VERSION=' | cut -d= -f2)" \
  "$REPORT_FILE"

check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"

# Finalize report
finalize_html_report "$REPORT_FILE"

# Send email
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Compatibility Report - $PDB_NAME"
echo "Content-Type: text/html"
echo
cat "$REPORT_FILE"
) | sendmail -t

# Cleanup
rm "$REPORT_FILE"


# Add to get_db_properties function
get_db_properties() {
  # ... existing properties ...
  SELECT 'DBTIMEZONE=' || dbtimezone FROM dual;
  SELECT 'TIMEZONE_VERSION=' || version FROM v\$timezone_file;
  # ... rest of existing query ...
}

# Add new time zone check function
check_timezone_compatibility() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>Time Zone Compatibility</h2>" >> $html_file
  echo "<table><tr><th>Check</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> $html_file

  # Database Time Zone
  src_tz=$(echo "$src_props" | grep '^DBTIMEZONE=' | cut -d= -f2)
  tgt_tz=$(echo "$tgt_props" | grep '^DBTIMEZONE=' | cut -d= -f2)
  
  if [ "$src_tz" != "$tgt_tz" ]; then
    tz_status="⚠️ Different Time Zones<br>Data conversion will occur"
    tz_class="warning"
  else
    tz_status="✅ Matching Time Zones"
    tz_class="ok"
  fi

  echo "<tr class='$tz_class'>
        <td>Database Time Zone</td>
        <td>$src_tz</td>
        <td>$tgt_tz</td>
        <td>$tz_status</td>
      </tr>" >> $html_file

  # Time Zone File Version
  src_tz_ver=$(echo "$src_props" | grep '^TIMEZONE_VERSION=' | cut -d= -f2)
  tgt_tz_ver=$(echo "$tgt_props" | grep '^TIMEZONE_VERSION=' | cut -d= -f2)

  if [ "$tgt_tz_ver" -lt "$src_tz_ver" ]; then
    ver_status="❌ Target version older than source"
    ver_class="critical"
  else
    ver_status="✅ Compatible version"
    ver_class="ok"
  fi

  echo "<tr class='$ver_class'>
        <td>Timezone File Version</td>
        <td>$src_tz_ver</td>
        <td>$tgt_tz_ver</td>
        <td>$ver_status</td>
      </tr>" >> $html_file

  echo "</table>" >> $html_file
}


#!/bin/bash

# Load configuration
CONFIG_FILE=${1:-pdb_migration.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi
source "$CONFIG_FILE"

# Source functions
source ./pdb_compatibility_functions.sh

# Build connection strings
SRC_CONN="${SOURCE_USER}/${SOURCE_PASSWORD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SOURCE_SCAN_HOST})(PORT=${SOURCE_PORT}))(CONNECT_DATA=(SERVICE_NAME=${SOURCE_PDB})(SERVER=DEDICATED)))"
TGT_CONN="${TARGET_USER}/${TARGET_PASSWORD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${TARGET_SCAN_HOST})(PORT=${TARGET_PORT}))(CONNECT_DATA=(SERVICE_NAME=${TARGET_PDB})(SERVER=DEDICATED)))"

# Initialize report
REPORT_FILE="/tmp/pdb_compatibility_$(date +%Y%m%d%H%M%S).html"
init_html_report "$REPORT_FILE" "$SOURCE_PDB"

# Verify connections
echo "<h2>Connection Verification</h2>" >> "$REPORT_FILE"
echo "<table>" >> "$REPORT_FILE"

verify_connection() {
  local conn=$1
  local type=$2
  local result=$(sqlplus -s /nolog << EOF
connect $conn
SELECT 'SUCCESS' FROM dual;
EOF
  )
  if [[ "$result" == *"SUCCESS"* ]]; then
    echo "<tr><td>$type Connection</td><td class='ok'>✅ Successful</td></tr>" >> "$REPORT_FILE"
    return 0
  else
    echo "<tr><td>$type Connection</td><td class='critical'>❌ Failed</td></tr>" >> "$REPORT_FILE"
    return 1
  fi
}

verify_connection "$SRC_CONN" "Source" || exit 1
verify_connection "$TGT_CONN" "Target" || exit 1
echo "</table>" >> "$REPORT_FILE"

# Get properties from both databases
src_properties=$(get_db_properties "$SRC_CONN")
tgt_properties=$(get_db_properties "$TGT_CONN")

# Perform all compatibility checks
check_version_compatibility \
  "$(echo "$src_properties" | grep '^VERSION=' | cut -d= -f2)" \
  "$(echo "$tgt_properties" | grep '^VERSION=' | cut -d= -f2)" \
  "$REPORT_FILE"

check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"

# Finalize report
finalize_html_report "$REPORT_FILE"

# Send email
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Compatibility Report - $SOURCE_PDB to $TARGET_PDB"
echo "Content-Type: text/html"
echo
cat "$REPORT_FILE"
) | sendmail -t

# Cleanup
rm "$REPORT_FILE"

#!/bin/bash

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Parse configuration
source_config() {
  local section=$1
  local key=$2
  sed -n "/^\[$section\]/,/^\[/p" "$CONFIG_FILE" | grep "^$key=" | cut -d'=' -f2-
}

# Initialize variables
SOURCE_HOST=$(source_config SOURCE_CDB HOST)
SOURCE_PORT=$(source_config SOURCE_CDB PORT)
SOURCE_USER=$(source_config SOURCE_CDB USER)
SOURCE_PWD=$(source_config SOURCE_CDB PASSWORD)
TARGET_HOST=$(source_config TARGET_CDB HOST)
TARGET_PORT=$(source_config TARGET_CDB PORT)
TARGET_USER=$(source_config TARGET_CDB USER)
TARGET_PWD=$(source_config TARGET_CDB PASSWORD)
EMAIL_TO=$(source_config EMAIL TO)
PDB_PAIRS=$(source_config PDBS "" | grep -v '^#' | grep -v '^$')

# Source functions
source ./pdb_compatibility_functions.sh

# Initialize summary report
SUMMARY_FILE="/tmp/pdb_migration_summary_$(date +%Y%m%d%H%M%S).html"
init_summary_report "$SUMMARY_FILE"

# Process each PDB pair
for pair in $PDB_PAIRS; do
  SOURCE_PDB=$(echo "$pair" | cut -d':' -f1)
  TARGET_PDB=$(echo "$pair" | cut -d':' -f2)
  
  # Build connection strings
  SRC_CONN="${SOURCE_USER}/${SOURCE_PWD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SOURCE_HOST})(PORT=${SOURCE_PORT}))(CONNECT_DATA=(SERVICE_NAME=${SOURCE_PDB})(SERVER=DEDICATED)))"
  TGT_CONN="${TARGET_USER}/${TARGET_PWD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${TARGET_HOST})(PORT=${TARGET_PORT}))(CONNECT_DATA=(SERVICE_NAME=${TARGET_PDB})(SERVER=DEDICATED)))"

  # Initialize individual report
  REPORT_FILE="/tmp/pdb_compatibility_${SOURCE_PDB}_to_${TARGET_PDB}_$(date +%Y%m%d%H%M%S).html"
  init_html_report "$REPORT_FILE" "$SOURCE_PDB to $TARGET_PDB"
  
  # Verify connections
  verify_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # Get properties and perform checks
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_PDB" "$TARGET_PDB" "$REPORT_FILE"
  
  # Send individual report
  send_email "$REPORT_FILE" "$EMAIL_TO" "PDB Compatibility: $SOURCE_PDB to $TARGET_PDB"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"
send_email "$SUMMARY_FILE" "$EMAIL_TO" "PDB Migration Summary Report"

# Cleanup
rm /tmp/pdb_compatibility_*.html


#!/bin/bash

# Initialize summary report
init_summary_report() {
  local html_file=$1
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Migration Summary Report</title>
<style>
  table {border-collapse: collapse; width: 100%;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .pass {background-color: #d4edda; color: #155724;}
  .fail {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .section {margin-bottom: 30px;}
</style>
</head>
<body>
<h1>PDB Migration Summary Report</h1>
<p>Generated at: $(date)</p>
<table>
  <tr><th>Source PDB</th><th>Target PDB</th><th>Status</th><th>Details</th></tr>
EOF
}

# Update summary report
update_summary_report() {
  local summary_file=$1
  local src_pdb=$2
  local tgt_pdb=$3
  local report_file=$4
  
  # Check for failures in the report
  if grep -q "critical" "$report_file" || grep -q "❌" "$report_file"; then
    status="FAIL"
    status_class="fail"
  else
    status="PASS"
    status_class="pass"
  fi
  
  # Extract report filename without path
  report_filename=$(basename "$report_file")
  
  echo "<tr class='$status_class'>
        <td>$src_pdb</td>
        <td>$tgt_pdb</td>
        <td>$status</td>
        <td><a href='$report_filename'>View Details</a></td>
      </tr>" >> "$summary_file"
}

# Finalize summary report
finalize_summary_report() {
  local summary_file=$1
  echo "</table>" >> "$summary_file"
  
  # Count results
  pass_count=$(grep -c "class='pass'" "$summary_file")
  fail_count=$(grep -c "class='fail'" "$summary_file")
  
  echo "<div class='section'>
        <h2>Summary</h2>
        <p>Total PDBs checked: $((pass_count + fail_count))</p>
        <p class='pass'>Passed: $pass_count</p>
        <p class='fail'>Failed: $fail_count</p>
        </div>" >> "$summary_file"
  
  echo "</body></html>" >> "$summary_file"
}

# Initialize individual report (existing init_html_report)
# All other existing functions remain the same
# Add this new function for connection verification
verify_connection() {
  local conn=$1
  local type=$2
  local report_file=$3
  
  result=$(sqlplus -s /nolog << EOF
connect $conn
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  if [[ "$result" == *"SUCCESS"* ]]; then
    echo "<p class='ok'>✅ $type connection successful</p>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ $type connection failed</p>" >> "$report_file"
    return 1
  fi
}


#!/bin/bash

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Source functions
source ./pdb_compatibility_functions.sh

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize summary report
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_PDB="${config[0]}"
  SOURCE_CDB="${config[1]}"
  SOURCE_HOST="${config[2]}"
  SOURCE_PORT="${config[3]}"
  SOURCE_USER="${config[4]}"
  SOURCE_PWD="${config[5]}"
  TARGET_PDB="${config[6]}"
  TARGET_CDB="${config[7]}"
  TARGET_HOST="${config[8]}"
  TARGET_PORT="${config[9]}"
  TARGET_USER="${config[10]}"
  TARGET_PWD="${config[11]}"

  # Build connection strings
  SRC_CONN="${SOURCE_USER}/${SOURCE_PWD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SOURCE_HOST})(PORT=${SOURCE_PORT}))(CONNECT_DATA=(SERVICE_NAME=${SOURCE_PDB})(SERVER=DEDICATED)))"
  TGT_CONN="${TARGET_USER}/${TARGET_PWD}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${TARGET_HOST})(PORT=${TARGET_PORT}))(CONNECT_DATA=(SERVICE_NAME=${TARGET_PDB})(SERVER=DEDICATED)))"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify connections
  echo "<h2>Connection Details</h2>" >> "$REPORT_FILE"
  echo "<table>" >> "$REPORT_FILE"
  echo "<tr><th>Parameter</th><th>Source</th><th>Target</th></tr>" >> "$REPORT_FILE"
  echo "<tr><td>CDB Name</td><td>$SOURCE_CDB</td><td>$TARGET_CDB</td></tr>" >> "$REPORT_FILE"
  echo "<tr><td>PDB Name</td><td>$SOURCE_PDB</td><td>$TARGET_PDB</td></tr>" >> "$REPORT_FILE"
  echo "<tr><td>Host</td><td>$SOURCE_HOST</td><td>$TARGET_HOST</td></tr>" >> "$REPORT_FILE"
  echo "</table>" >> "$REPORT_FILE"

  verify_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # Get properties and perform checks
  src_properties=$(get_db_properties "$SRC_CONN" "$SOURCE_PDB")
  tgt_properties=$(get_db_properties "$TGT_CONN" "$TARGET_PDB")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

#!/bin/bash

# Initialize summary report
init_summary_report() {
  local html_file=$1
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Migration Summary Report</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .pass {background-color: #d4edda; color: #155724;}
  .fail {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .section {margin-bottom: 30px;}
  h2 {color: #2c3e50; border-bottom: 2px solid #444;}
</style>
</head>
<body>
<h1>PDB Migration Summary Report</h1>
<p>Generated at: $(date)</p>
<table>
  <tr>
    <th>Source (CDB/PDB)</th>
    <th>Target (CDB/PDB)</th>
    <th>Status</th>
    <th>Details</th>
    <th>Issues Found</th>
  </tr>
EOF
}

# Update summary report
update_summary_report() {
  local summary_file=$1
  local src_db="$2"
  local tgt_db="$3"
  local report_file="$4"
  
  # Count critical issues
  critical_count=$(grep -c "class='critical'" "$report_file")
  warning_count=$(grep -c "class='warning'" "$report_file")
  
  if [ "$critical_count" -gt 0 ]; then
    status="FAIL"
    status_class="fail"
  else
    status="PASS"
    status_class="pass"
  fi
  
  # Extract report filename without path
  report_filename=$(basename "$report_file")
  
  echo "<tr class='$status_class'>
        <td>$src_db</td>
        <td>$tgt_db</td>
        <td>$status</td>
        <td><a href='$report_filename'>View Report</a></td>
        <td>
          Critical: $critical_count<br>
          Warnings: $warning_count
        </td>
      </tr>" >> "$summary_file"
}

# Finalize summary report
finalize_summary_report() {
  local summary_file=$1
  
  # Count results
  pass_count=$(grep -c "class='pass'" "$summary_file")
  fail_count=$(grep -c "class='fail'" "$summary_file")
  total_count=$((pass_count + fail_count))
  
  # Add summary statistics
  echo "<div class='section'>
        <h2>Summary Statistics</h2>
        <table>
          <tr><th>Total Migrations Checked</th><td>$total_count</td></tr>
          <tr class='pass'><th>Passed</th><td>$pass_count</td></tr>
          <tr class='fail'><th>Failed</th><td>$fail_count</td></tr>
        </table>
        </div>" >> "$summary_file"
  
  # Add timestamp
  echo "<p>Report generated at: $(date)</p>" >> "$summary_file"
  
  echo "</body></html>" >> "$summary_file"
}

# Initialize individual report
init_html_report() {
  local html_file="$1"
  local migration="$2"
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Compatibility Report: $migration</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .critical {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .ok {background-color: #d4edda; color: #155724;}
  .section {margin-bottom: 30px; border-top: 2px solid #444; padding-top: 15px;}
  h2 {color: #2c3e50;}
  h3 {color: #2c3e50; margin-top: 20px;}
</style>
</head>
<body>
<h1>PDB Compatibility Report: $migration</h1>
<p>Generated at: $(date)</p>
EOF
}


#!/bin/bash

# Add this new function to check database status
get_database_status() {
  local conn=$1
  local cdb_name=$2
  local out_file=$3
  
  sqlplus -s /nolog << EOF > "$out_file"
connect $conn
set pagesize 1000
set linesize 200
set feedback off
set heading off

prompt DATABASE_NAME=
select name from v\$database;

prompt INSTANCE_NAME=
select instance_name from v\$instance;

prompt STATUS=
select status from v\$instance;

prompt VERSION=
select version from v\$instance;

prompt OPEN_MODE=
select open_mode from v\$database;

prompt DATABASE_ROLE=
select database_role from v\$database;

prompt HOST_NAME=
select host_name from v\$instance;

prompt STARTUP_TIME=
select to_char(startup_time, 'YYYY-MM-DD HH24:MI:SS') from v\$instance;

prompt PDB_COUNT=
select count(*) from v\$pdbs;

prompt PDB_LIST=
select name, open_mode, restricted from v\$pdbs order by 1;

prompt SERVICES=
select name from v\$services order by 1;

prompt TBS_SIZE_GB=
select round(sum(bytes)/1024/1024/1024,2) from dba_data_files;

prompt ARCHIVE_LOG=
select log_mode from v\$database;

prompt FLASHBACK=
select flashback_on from v\$database;

prompt CPU_COUNT=
select value from v\$parameter where name = 'cpu_count';

prompt MEMORY_TARGET_GB=
select round(value/1024/1024/1024,2) from v\$parameter where name = 'memory_target';

exit;
EOF

  # Clean up SQL*Plus output
  sed -i '/^Disconnected/d' "$out_file"
  sed -i '/^SQL>/d' "$out_file"
}

# Function to display database status in HTML
display_database_status() {
  local src_status_file=$1
  local tgt_status_file=$2
  local html_file=$3

  # Parse status files into associative arrays
  declare -A src_status tgt_status
  while IFS='=' read -r key value; do
    [ -n "$key" ] && src_status["$key"]=$(echo "$value" | xargs)
  done < "$src_status_file"

  while IFS='=' read -r key value; do
    [ -n "$key" ] && tgt_status["$key"]=$(echo "$value" | xargs)
  done < "$tgt_status_file"

  echo "<div class='section'>" >> "$html_file"
  echo "<h2>Database Status Overview</h2>" >> "$html_file"
  
  # Host Information Table
  echo "<h3>Host Information</h3>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>Parameter</th><th>Source</th><th>Target</th></tr>" >> "$html_file"
  echo "<tr><td>Host Name</td><td>${src_status[HOST_NAME]}</td><td>${tgt_status[HOST_NAME]}</td></tr>" >> "$html_file"
  echo "<tr><td>Database Name</td><td>${src_status[DATABASE_NAME]}</td><td>${tgt_status[DATABASE_NAME]}</td></tr>" >> "$html_file"
  echo "<tr><td>Instance Name</td><td>${src_status[INSTANCE_NAME]}</td><td>${tgt_status[INSTANCE_NAME]}</td></tr>" >> "$html_file"
  echo "</table>" >> "$html_file"

  # Database Status Table
  echo "<h3>Database Status</h3>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>Parameter</th><th>Source</th><th>Target</th></tr>" >> "$html_file"
  echo "<tr><td>Status</td><td>${src_status[STATUS]}</td><td>${tgt_status[STATUS]}</td></tr>" >> "$html_file"
  echo "<tr><td>Open Mode</td><td>${src_status[OPEN_MODE]}</td><td>${tgt_status[OPEN_MODE]}</td></tr>" >> "$html_file"
  echo "<tr><td>Database Role</td><td>${src_status[DATABASE_ROLE]}</td><td>${tgt_status[DATABASE_ROLE]}</td></tr>" >> "$html_file"
  echo "<tr><td>Version</td><td>${src_status[VERSION]}</td><td>${tgt_status[VERSION]}</td></tr>" >> "$html_file"
  echo "<tr><td>Startup Time</td><td>${src_status[STARTUP_TIME]}</td><td>${tgt_status[STARTUP_TIME]}</td></tr>" >> "$html_file"
  echo "<tr><td>Archive Log Mode</td><td>${src_status[ARCHIVE_LOG]}</td><td>${tgt_status[ARCHIVE_LOG]}</td></tr>" >> "$html_file"
  echo "<tr><td>Flashback</td><td>${src_status[FLASHBACK]}</td><td>${tgt_status[FLASHBACK]}</td></tr>" >> "$html_file"
  echo "</table>" >> "$html_file"

  # Resource Information Table
  echo "<h3>Resource Information</h3>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>Parameter</th><th>Source</th><th>Target</th></tr>" >> "$html_file"
  echo "<tr><td>CPU Count</td><td>${src_status[CPU_COUNT]}</td><td>${tgt_status[CPU_COUNT]}</td></tr>" >> "$html_file"
  echo "<tr><td>Memory Target (GB)</td><td>${src_status[MEMORY_TARGET_GB]}</td><td>${tgt_status[MEMORY_TARGET_GB]}</td></tr>" >> "$html_file"
  echo "<tr><td>Tablespace Size (GB)</td><td>${src_status[TBS_SIZE_GB]}</td><td>${tgt_status[TBS_SIZE_GB]}</td></tr>" >> "$html_file"
  echo "</table>" >> "$html_file"

  # PDB Information
  echo "<h3>PDB Information</h3>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>Parameter</th><th>Source</th><th>Target</th></tr>" >> "$html_file"
  echo "<tr><td>PDB Count</td><td>${src_status[PDB_COUNT]}</td><td>${tgt_status[PDB_COUNT]}</td></tr>" >> "$html_file"
  echo "</table>" >> "$html_file"

  # PDB List (Source)
  echo "<h4>Source PDBs</h4>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>PDB Name</th><th>Open Mode</th><th>Restricted</th></tr>" >> "$html_file"
  echo "${src_status[PDB_LIST]}" | while read -r pdb; do
    pdb_name=$(echo "$pdb" | awk '{print $1}')
    open_mode=$(echo "$pdb" | awk '{print $2}')
    restricted=$(echo "$pdb" | awk '{print $3}')
    echo "<tr><td>$pdb_name</td><td>$open_mode</td><td>$restricted</td></tr>" >> "$html_file"
  done
  echo "</table>" >> "$html_file"

  # PDB List (Target)
  echo "<h4>Target PDBs</h4>" >> "$html_file"
  echo "<table>" >> "$html_file"
  echo "<tr><th>PDB Name</th><th>Open Mode</th><th>Restricted</th></tr>" >> "$html_file"
  echo "${tgt_status[PDB_LIST]}" | while read -r pdb; do
    pdb_name=$(echo "$pdb" | awk '{print $1}')
    open_mode=$(echo "$pdb" | awk '{print $2}')
    restricted=$(echo "$pdb" | awk '{print $3}')
    echo "<tr><td>$pdb_name</td><td>$open_mode</td><td>$restricted</td></tr>" >> "$html_file"
  done
  echo "</table>" >> "$html_file"

  echo "</div>" >> "$html_file"
}


#!/bin/bash

# ... (previous configuration loading code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... (previous configuration parsing code remains the same) ...

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Get database status for both CDBs
  SRC_STATUS_FILE="$REPORT_DIR/source_status_${SOURCE_CDB}.txt"
  TGT_STATUS_FILE="$REPORT_DIR/target_status_${TARGET_CDB}.txt"
  
  get_database_status "$SRC_CONN" "$SOURCE_CDB" "$SRC_STATUS_FILE"
  get_database_status "$TGT_CONN" "$TARGET_CDB" "$TGT_STATUS_FILE"
  
  # Display database status section
  display_database_status "$SRC_STATUS_FILE" "$TGT_STATUS_FILE" "$REPORT_FILE"
  
  # ... (rest of the script remains the same) ...
done

# ... (remaining script code) ...

init_html_report() {
  local html_file="$1"
  local migration="$2"
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Compatibility Report: $migration</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .critical {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .ok {background-color: #d4edda; color: #155724;}
  .section {margin-bottom: 30px; border-top: 2px solid #444; padding-top: 15px;}
  h2 {color: #2c3e50;}
  h3 {color: #2c3e50; margin-top: 20px;}
  h4 {color: #2c3e50; margin-top: 15px;}
  .status-up {color: green; font-weight: bold;}
  .status-down {color: red; font-weight: bold;}
</style>
</head>
<body>
<h1>PDB Compatibility Report: $migration</h1>
<p>Generated at: $(date)</p>
EOF
}

#!/bin/bash

# ... (previous configuration loading code) ...

# Build connection strings using BEQ (OS authentication)
SRC_CONN="/@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SOURCE_HOST})(PORT=${SOURCE_PORT})(CONNECT_DATA=(SERVICE_NAME=${SOURCE_PDB})(SERVER=DEDICATED)))"
TGT_CONN="/@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${TARGET_HOST})(PORT=${TARGET_PORT})(CONNECT_DATA=(SERVICE_NAME=${TARGET_PDB})(SERVER=DEDICATED)))"

# Verify OS authentication works
verify_os_authentication() {
  local conn=$1
  local type=$2
  local report_file=$3
  
  result=$(sqlplus -s /nolog << EOF
connect $conn
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  if [[ "$result" == *"SUCCESS"* ]]; then
    echo "<p class='ok'>✅ $type OS authentication successful</p>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ $type OS authentication failed. Ensure proper Oracle permissions are set.</p>" >> "$report_file"
    return 1
  fi
}

# ... (in the main processing loop) ...

  # Verify connections using OS auth
  verify_os_authentication "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_os_authentication "$TGT_CONN" "Target" "$REPORT_FILE" || continue

# ... (rest of the script remains the same) ...



#!/bin/bash

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Source functions
source ./pdb_compatibility_functions.sh

# Get wallet paths
SOURCE_WALLET_PATH=$(sed -n '/^\[WALLET\]/,/^$/p' "$CONFIG_FILE" | grep '^SOURCE_WALLET_PATH=' | cut -d'=' -f2)
TARGET_WALLET_PATH=$(sed -n '/^\[WALLET\]/,/^$/p' "$CONFIG_FILE" | grep '^TARGET_WALLET_PATH=' | cut -d'=' -f2)

# Verify wallets exist
if [ ! -d "$SOURCE_WALLET_PATH" ]; then
  echo "Error: Source wallet not found at $SOURCE_WALLET_PATH"
  exit 1
fi
if [ ! -d "$TARGET_WALLET_PATH" ]; then
  echo "Error: Target wallet not found at $TARGET_WALLET_PATH"
  exit 1
fi

# Set TNS_ADMIN to wallet locations
export TNS_ADMIN="$SOURCE_WALLET_PATH"

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize summary report
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[WALLET\]' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_CDB="${config[0]}"
  SOURCE_PDB="${config[1]}"
  SOURCE_HOST="${config[2]}"
  SOURCE_PORT="${config[3]}"
  TARGET_CDB="${config[4]}"
  TARGET_PDB="${config[5]}"
  TARGET_HOST="${config[6]}"
  TARGET_PORT="${config[7]}"

  # Build connection strings using wallet
  SRC_CONN="/@${SOURCE_CDB}_${SOURCE_PDB}"
  TGT_CONN="/@${TARGET_CDB}_${TARGET_PDB}"

  # Create TNS entries in wallet directories
  create_tns_entry "$SOURCE_WALLET_PATH" "${SOURCE_CDB}_${SOURCE_PDB}" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_PDB"
  create_tns_entry "$TARGET_WALLET_PATH" "${TARGET_CDB}_${TARGET_PDB}" "$TARGET_HOST" "$TARGET_PORT" "$TARGET_PDB"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify wallet connections
  verify_wallet_connection "$SRC_CONN" "Source" "$SOURCE_WALLET_PATH" "$REPORT_FILE" || continue
  verify_wallet_connection "$TGT_CONN" "Target" "$TARGET_WALLET_PATH" "$REPORT_FILE" || continue

  # ... rest of the processing remains the same ...
done

# ... rest of the script (email sending, cleanup) ...

#!/bin/bash

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Source functions
source ./pdb_compatibility_functions.sh

# Get wallet paths
SOURCE_WALLET_PATH=$(sed -n '/^\[WALLET\]/,/^$/p' "$CONFIG_FILE" | grep '^SOURCE_WALLET_PATH=' | cut -d'=' -f2)
TARGET_WALLET_PATH=$(sed -n '/^\[WALLET\]/,/^$/p' "$CONFIG_FILE" | grep '^TARGET_WALLET_PATH=' | cut -d'=' -f2)

# Verify wallets exist
if [ ! -d "$SOURCE_WALLET_PATH" ]; then
  echo "Error: Source wallet not found at $SOURCE_WALLET_PATH"
  exit 1
fi
if [ ! -d "$TARGET_WALLET_PATH" ]; then
  echo "Error: Target wallet not found at $TARGET_WALLET_PATH"
  exit 1
fi

# Set TNS_ADMIN to wallet locations
export TNS_ADMIN="$SOURCE_WALLET_PATH"

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize summary report
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[WALLET\]' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_CDB="${config[0]}"
  SOURCE_PDB="${config[1]}"
  SOURCE_HOST="${config[2]}"
  SOURCE_PORT="${config[3]}"
  TARGET_CDB="${config[4]}"
  TARGET_PDB="${config[5]}"
  TARGET_HOST="${config[6]}"
  TARGET_PORT="${config[7]}"

  # Build connection strings using wallet
  SRC_CONN="/@${SOURCE_CDB}_${SOURCE_PDB}"
  TGT_CONN="/@${TARGET_CDB}_${TARGET_PDB}"

  # Create TNS entries in wallet directories
  create_tns_entry "$SOURCE_WALLET_PATH" "${SOURCE_CDB}_${SOURCE_PDB}" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_PDB"
  create_tns_entry "$TARGET_WALLET_PATH" "${TARGET_CDB}_${TARGET_PDB}" "$TARGET_HOST" "$TARGET_PORT" "$TARGET_PDB"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify wallet connections
  verify_wallet_connection "$SRC_CONN" "Source" "$SOURCE_WALLET_PATH" "$REPORT_FILE" || continue
  verify_wallet_connection "$TGT_CONN" "Target" "$TARGET_WALLET_PATH" "$REPORT_FILE" || continue

  # ... rest of the processing remains the same ...
done

# ... rest of the script (email sending, cleanup) ...

#!/bin/bash

# Function to create TNS entries in wallet directory
create_tns_entry() {
  local wallet_path=$1
  local alias=$2
  local host=$3
  local port=$4
  local service_name=$5
  
  tns_entry="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${host})(PORT=${port}))(CONNECT_DATA=(SERVICE_NAME=${service_name})))"
  
  # Create tnsnames.ora if it doesn't exist
  if [ ! -f "${wallet_path}/tnsnames.ora" ]; then
    echo "# TNSNAMES.ORA generated by PDB compatibility tool" > "${wallet_path}/tnsnames.ora"
    echo "# Created: $(date)" >> "${wallet_path}/tnsnames.ora"
  fi
  
  # Add or update entry
  if grep -q "^${alias}=" "${wallet_path}/tnsnames.ora"; then
    sed -i "/^${alias}=/c\\${alias}=${tns_entry}" "${wallet_path}/tnsnames.ora"
  else
    echo "${alias}=${tns_entry}" >> "${wallet_path}/tnsnames.ora"
  fi
}

# Function to verify wallet connection
verify_wallet_connection() {
  local conn=$1
  local type=$2
  local wallet_path=$3
  local report_file=$4
  
  # Temporarily set TNS_ADMIN to the specific wallet path
  export TNS_ADMIN="$wallet_path"
  
  result=$(sqlplus -s /nolog << EOF
connect $conn
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  if [[ "$result" == *"SUCCESS"* ]]; then
    echo "<p class='ok'>✅ $type wallet authentication successful</p>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ $type wallet authentication failed. Check wallet configuration.</p>" >> "$report_file"
    echo "<p class='warning'>Wallet path: $wallet_path</p>" >> "$report_file"
    echo "<p class='warning'>Connection string: $conn</p>" >> "$report_file"
    return 1
  fi
}

# ... keep all other existing functions ...


#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize summary report
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_CDB="${config[0]}"
  SOURCE_PDB="${config[1]}"
  SOURCE_TNS="${config[2]}"
  TARGET_CDB="${config[3]}"
  TARGET_PDB="${config[4]}"
  TARGET_TNS="${config[5]}"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify wallet connections
  verify_db_connection "$SOURCE_TNS" "Source" "$REPORT_FILE" || continue
  verify_db_connection "$TARGET_TNS" "Target" "$REPORT_FILE" || continue

  # Get database properties
  src_properties=$(get_db_properties "/@$SOURCE_TNS")
  tgt_properties=$(get_db_properties "/@$TARGET_TNS")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"


#!/bin/bash

# Function to verify database connection using wallet
verify_db_connection() {
  local tns_alias=$1
  local type=$2
  local report_file=$3
  
  result=$(sqlplus -s /nolog << EOF
connect /@$tns_alias
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  # Clean up SQL*Plus output
  clean_result=$(echo "$result" | tr -d '\n' | grep -o 'SUCCESS')
  
  if [ "$clean_result" = "SUCCESS" ]; then
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Connection Status: $type</h2>" >> "$report_file"
    echo "<p class='ok'>✅ Successfully connected using TNS alias: $tns_alias</p>" >> "$report_file"
    
    # Get basic connection info
    conn_info=$(sqlplus -s /nolog << EOF
connect /@$tns_alias
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Instance: ' || instance_name || ' | Version: ' || version || ' | Host: ' || host_name 
FROM v\$instance;
EOF
    )
    echo "<p>Connection details: $conn_info</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 0
  else
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Connection Status: $type</h2>" >> "$report_file"
    echo "<p class='critical'>❌ Failed to connect using TNS alias: $tns_alias</p>" >> "$report_file"
    echo "<p class='warning'>Ensure the wallet is properly configured with this TNS alias</p>" >> "$report_file"
    echo "<pre>Error details: $result</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi
}

# Function to get database properties
get_db_properties() {
  local conn=$1
  sqlplus -s /nolog << EOF
connect $conn
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

prompt VERSION=
SELECT version FROM v\$instance;

prompt COMPATIBLE=
SELECT value FROM v\$parameter WHERE name = 'compatible';

prompt CHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';

prompt NCHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';

prompt PLATFORM_NAME=
SELECT platform_name FROM v\$database;

prompt ENDIAN_FORMAT=
SELECT endian_format FROM v\$transportable_platform tp, v\$database d 
WHERE tp.platform_name = d.platform_name;

prompt LOCAL_UNDO=
SELECT local_undo_enabled FROM v\$database;

prompt TDE_STATUS=
SELECT status FROM v\$encryption_wallet;

prompt TDE_WALLET_TYPE=
SELECT wallet_type FROM v\$encryption_wallet;

prompt TIMEZONE_VERSION=
SELECT version FROM v\$timezone_file;

prompt DBTIMEZONE=
SELECT dbtimezone FROM dual;

prompt CDB=
SELECT cdb FROM v\$database;

prompt PDB=
SELECT sys_context('USERENV', 'CON_NAME') FROM dual;

EXIT;
EOF
}

# ... (keep all other existing functions like check_version_compatibility, etc.) ...

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize summary report
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_PDB="${config[0]}"
  SOURCE_SCAN="${config[1]}"
  SOURCE_PORT="${config[2]}"
  TARGET_PDB="${config[3]}"
  TARGET_SCAN="${config[4]}"
  TARGET_PORT="${config[5]}"

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${SOURCE_PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${TARGET_PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_PDB}_to_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_PDB} to ${TARGET_PDB}"
  
  # Verify connections
  verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_PDB" "$TARGET_PDB" "$REPORT_FILE"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

#!/bin/bash

# Function to verify database connection using Easy Connect
verify_db_connection() {
  local conn_str=$1
  local type=$2
  local report_file=$3
  
  # Test connection
  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  # Check if connection was successful
  if [[ "$result" == *"SUCCESS"* ]]; then
    # Get connection details
    conn_info=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Instance: ' || instance_name || 
       ' | Version: ' || version || 
       ' | Host: ' || host_name ||
       ' | CDB: ' || (SELECT cdb FROM v\$database) ||
       ' | Container: ' || sys_context('USERENV', 'CON_NAME')
FROM v\$instance;
EOF
    )
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Connection Status: $type</h2>" >> "$report_file"
    echo "<p class='ok'>✅ Successfully connected to: $conn_str</p>" >> "$report_file"
    echo "<p>Connection details: $conn_info</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 0
  else
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Connection Status: $type</h2>" >> "$report_file"
    echo "<p class='critical'>❌ Failed to connect to: $conn_str</p>" >> "$report_file"
    echo "<pre>Error details: $result</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi
}

# Function to get database properties
get_db_properties() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

prompt VERSION=
SELECT version FROM v\$instance;

prompt COMPATIBLE=
SELECT value FROM v\$parameter WHERE name = 'compatible';

prompt CHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';

prompt NCHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';

prompt PLATFORM_NAME=
SELECT platform_name FROM v\$database;

prompt ENDIAN_FORMAT=
SELECT endian_format FROM v\$transportable_platform tp, v\$database d 
WHERE tp.platform_name = d.platform_name;

prompt LOCAL_UNDO=
SELECT local_undo_enabled FROM v\$database;

prompt TDE_STATUS=
SELECT status FROM v\$encryption_wallet;

prompt TDE_WALLET_TYPE=
SELECT wallet_type FROM v\$encryption_wallet;

prompt TIMEZONE_VERSION=
SELECT version FROM v\$timezone_file;

prompt DBTIMEZONE=
SELECT dbtimezone FROM dual;

EXIT;
EOF
}

# ... (keep all other existing functions like check_version_compatibility, etc.) ...

# Default port (can be overridden per line)
PORT=1521

# Format for each migration check:
# SOURCE_PDB:SOURCE_SCAN:TARGET_PDB:TARGET_SCAN[:PORT_OVERRIDE]

# Examples (using default port)
HRPDB:source-scan.example.com:HRPROD:target-scan.example.com
SALESPDB:source-scan.example.com:SALESPROD:target-scan.example.com

# Example with port override
FINPDB:source-scan.example.com:FINPROD:target-scan.example.com:1522

[EMAIL]
TO=dba-team@example.com

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}  # Fallback to 1521 if not specified

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Parse configuration line
  IFS=':' read -r -a config <<< "$line"
  
  SOURCE_PDB="${config[0]}"
  SOURCE_SCAN="${config[1]}"
  TARGET_PDB="${config[2]}"
  TARGET_SCAN="${config[3]}"
  PORT="${config[4]:-$DEFAULT_PORT}"  # Use override if exists, else default

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_PDB}_to_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_PDB} to ${TARGET_PDB} (Port: $PORT)"
  
  # Verify connections
  verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # ... rest of the processing remains the same ...
done

# ... rest of the script (email sending, cleanup) ...

#!/bin/bash

# Add this function to check MAX_STRING_SIZE
check_max_string_size() {
  local src_props=$1
  local tgt_props=$2
  local html_file=$3

  echo "<h2>MAX_STRING_SIZE Compatibility</h2>" >> "$html_file"
  echo "<table><tr><th>Parameter</th><th>Source</th><th>Target</th><th>Status</th></tr>" >> "$html_file"

  src_size=$(echo "$src_props" | grep '^MAX_STRING_SIZE=' | cut -d'=' -f2)
  tgt_size=$(echo "$tgt_props" | grep '^MAX_STRING_SIZE=' | cut -d'=' -f2)

  if [ "$src_size" != "$tgt_size" ]; then
    status="❌ Mismatch - Potential data truncation"
    status_class="critical"
  else
    status="✅ Match"
    status_class="ok"
  fi

  echo "<tr class='$status_class'>
        <td>MAX_STRING_SIZE</td>
        <td>$src_size</td>
        <td>$tgt_size</td>
        <td>$status</td>
      </tr>" >> "$html_file"

  # Add warning if source is EXTENDED but target is STANDARD
  if [ "$src_size" = "EXTENDED" ] && [ "$tgt_size" = "STANDARD" ]; then
    echo "<tr class='warning'>
          <td colspan='4'>
            ⚠️ Warning: Source uses EXTENDED (32K) while target uses STANDARD (4K). 
            This may cause string truncation during migration.
          </td>
        </tr>" >> "$html_file"
  fi

  echo "</table>" >> "$html_file"
}

# Update get_db_properties to include MAX_STRING_SIZE
get_db_properties() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

prompt VERSION=
SELECT version FROM v\$instance;

prompt COMPATIBLE=
SELECT value FROM v\$parameter WHERE name = 'compatible';

prompt CHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';

prompt NCHARACTERSET=
SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';

prompt PLATFORM_NAME=
SELECT platform_name FROM v\$database;

prompt ENDIAN_FORMAT=
SELECT endian_format FROM v\$transportable_platform tp, v\$database d 
WHERE tp.platform_name = d.platform_name;

prompt LOCAL_UNDO=
SELECT local_undo_enabled FROM v\$database;

prompt TDE_STATUS=
SELECT status FROM v\$encryption_wallet;

prompt TDE_WALLET_TYPE=
SELECT wallet_type FROM v\$encryption_wallet;

prompt TIMEZONE_VERSION=
SELECT version FROM v\$timezone_file;

prompt DBTIMEZONE=
SELECT dbtimezone FROM dual;

prompt MAX_STRING_SIZE=
SELECT value FROM v\$parameter WHERE name = 'max_string_size';

EXIT;
EOF
}

#!/bin/bash

# ... (previous configuration code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... (previous parsing code remains the same) ...

  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"  # New check
  
  # ... (rest of the processing remains the same) ...
done

# ... (rest of the script remains the same) ...

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}  # Fallback to 1521 if not specified

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Split into main config and optional port override
  IFS=':' read -r main_config port_override <<< "$line"
  
  # Parse main configuration (pipe-delimited)
  IFS='|' read -r SOURCE_CDB SOURCE_PDB SOURCE_SCAN TARGET_CDB TARGET_PDB TARGET_SCAN <<< "$main_config"
  
  # Use override port if specified, else default
  PORT=${port_override:-$DEFAULT_PORT}

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB} (Port: $PORT)"
  
  # Verify connections
  verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

validate_config_line() {
  local line=$1
  local main_config=$2
  
  # Count pipe-delimited fields
  field_count=$(tr -dc '|' <<< "$main_config" | wc -c)
  
  if [ "$field_count" -ne 5 ]; then
    echo "Error: Invalid configuration line. Expected 6 pipe-delimited fields."
    echo "Format: source_cdb|source_pdb|source_scan|target_cdb|target_pdb|target_scan[:port]"
    echo "Found: $line"
    return 1
  fi
  
  return 0
}

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!" >&2
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Validate and parse the configuration line
  if ! validate_and_parse_line "$line"; then
    echo "Skipping invalid line: $line" >&2
    continue
  fi

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify connections
  if ! verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "COMPLETED"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

exit 0


#!/bin/bash

# Function to validate and parse configuration line
validate_and_parse_line() {
  local line=$1
  
  # Count pipe-delimited fields
  field_count=$(tr -dc '|' <<< "$line" | wc -c)
  
  if [ "$field_count" -ne 5 ]; then
    echo "Error: Invalid configuration line. Expected 6 pipe-delimited fields." >&2
    echo "Format: source_cdb|source_pdb|source_scan|target_cdb|target_pdb|target_scan" >&2
    echo "Found: $line" >&2
    return 1
  fi
  
  # Parse the line
  IFS='|' read -r SOURCE_CDB SOURCE_PDB SOURCE_SCAN TARGET_CDB TARGET_PDB TARGET_SCAN <<< "$line"
  
  # Validate no empty fields
  if [[ -z "$SOURCE_CDB" || -z "$SOURCE_PDB" || -z "$SOURCE_SCAN" || 
        -z "$TARGET_CDB" || -z "$TARGET_PDB" || -z "$TARGET_SCAN" ]]; then
    echo "Error: Empty field(s) in configuration line: $line" >&2
    return 1
  fi
  
  return 0
}

# Function to verify database connection
verify_db_connection() {
  local conn_str=$1
  local type=$2
  local report_file=$3
  
  echo "<div class='section'>" >> "$report_file"
  echo "<h2>Connection Verification: $type</h2>" >> "$report_file"
  
  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'SUCCESS' FROM dual;
EOF
  )
  
  if [[ "$result" == *"SUCCESS"* ]]; then
    conn_info=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Instance: ' || instance_name || 
       ' | Version: ' || version || 
       ' | Host: ' || host_name ||
       ' | CDB: ' || (SELECT cdb FROM v\$database) ||
       ' | Container: ' || sys_context('USERENV', 'CON_NAME')
FROM v\$instance;
EOF
    )
    
    echo "<p class='ok'>✅ Successfully connected to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
    echo "<p>Connection details: $conn_info</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ Failed to connect to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
    echo "<pre>Error details: $result</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi
}

# Update summary report function to handle connection failures
update_summary_report() {
  local summary_file=$1
  local src_db="$2"
  local tgt_db="$3"
  local report_file="$4"
  local status="$5"
  
  report_filename=$(basename "$report_file")
  
  case "$status" in
    "CONNECTION_FAILED")
      echo "<tr class='critical'>
            <td>$src_db</td>
            <td>$tgt_db</td>
            <td>❌ Connection Failed</td>
            <td><a href='$report_filename'>View Details</a></td>
            <td>N/A</td>
          </tr>" >> "$summary_file"
      ;;
    "COMPLETED")
      # Check for failures in the report
      if grep -q "class='critical'" "$report_file"; then
        critical_count=$(grep -c "class='critical'" "$report_file")
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='critical'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>❌ Failed ($critical_count critical issues)</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Critical: $critical_count<br>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      else
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='ok'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>✅ Passed</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      fi
      ;;
  esac
}

# ... (keep all other existing functions) ...


#!/bin/bash

# Function to check PDB existence
check_pdb_existence() {
  local conn_str=$1
  local pdb_name=$2
  local type=$3
  local report_file=$4

  echo "<div class='section'>" >> "$report_file"
  echo "<h2>PDB Existence Check: $type</h2>" >> "$report_file"

  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'EXISTS' FROM v\$pdbs WHERE name = UPPER('$pdb_name');
EOF
  )

  if [[ "$result" == *"EXISTS"* ]]; then
    pdb_status=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Status: ' || open_mode || ' | Restricted: ' || restricted || 
       ' | Recovery: ' || recovery_status || ' | Con_ID: ' || con_id
FROM v\$pdbs WHERE name = UPPER('$pdb_name');
EOF
    )
    echo "<p class='ok'>✅ PDB $pdb_name exists</p>" >> "$report_file"
    echo "<p>PDB details: $pdb_status</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ PDB $pdb_name does not exist</p>" >> "$report_file"
    echo "<pre>Available PDBs:" >> "$report_file"
    sqlplus -s /nolog << EOF >> "$report_file"
connect $conn_str
SET PAGESIZE 1000
SET FEEDBACK OFF
SET LINESIZE 100
SET HEADING OFF
SELECT name || ' - ' || open_mode || ' - ' || restricted FROM v\$pdbs ORDER BY name;
EOF
    echo "</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi
}

# Update verify_db_connection to include container check
verify_db_connection() {
  local conn_str=$1
  local type=$2
  local report_file=$3
  local pdb_name=$4

  echo "<div class='section'>" >> "$report_file"
  echo "<h2>Connection Verification: $type</h2>" >> "$report_file"

  # First verify we can connect to the CDB
  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'SUCCESS' FROM dual;
EOF
  )

  if [[ "$result" != *"SUCCESS"* ]]; then
    echo "<p class='critical'>❌ Failed to connect to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
    echo "<pre>Error details: $result</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi

  # Then verify we're connected to the correct PDB
  current_container=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SELECT sys_context('USERENV', 'CON_NAME') FROM dual;
EOF
  )

  if [[ "$current_container" != "$pdb_name" ]]; then
    echo "<p class='critical'>❌ Connected to wrong container: $current_container (expected: $pdb_name)</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi

  conn_info=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Instance: ' || instance_name || 
       ' | Version: ' || version || 
       ' | Host: ' || host_name ||
       ' | CDB: ' || (SELECT cdb FROM v\$database) ||
       ' | Container: ' || sys_context('USERENV', 'CON_NAME')
FROM v\$instance;
EOF
  )
    
  echo "<p class='ok'>✅ Successfully connected to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
  echo "<p>Connection details: $conn_info</p>" >> "$report_file"
  echo "</div>" >> "$report_file"
  return 0
}


#!/bin/bash

# ... (previous configuration code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Validate and parse the configuration line
  if ! validate_and_parse_line "$line"; then
    echo "Skipping invalid line: $line" >&2
    continue
  fi

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"

  # Verify connections and PDB existence
  if ! verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" "$SOURCE_PDB"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! check_pdb_existence "$SRC_CONN" "$SOURCE_PDB" "Source" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "PDB_NOT_FOUND"
    continue
  fi

  if ! verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" "$TARGET_PDB"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! check_pdb_existence "$TGT_CONN" "$TARGET_PDB" "Target" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "PDB_NOT_FOUND"
    continue
  fi

  # ... (rest of the compatibility checks remain the same) ...
done

# ... (rest of the script remains the same) ...

update_summary_report() {
  local summary_file=$1
  local src_db="$2"
  local tgt_db="$3"
  local report_file="$4"
  local status="$5"
  
  report_filename=$(basename "$report_file")
  
  case "$status" in
    "CONNECTION_FAILED")
      echo "<tr class='critical'>
            <td>$src_db</td>
            <td>$tgt_db</td>
            <td>❌ Connection Failed</td>
            <td><a href='$report_filename'>View Details</a></td>
            <td>N/A</td>
          </tr>" >> "$summary_file"
      ;;
    "PDB_NOT_FOUND")
      echo "<tr class='critical'>
            <td>$src_db</td>
            <td>$tgt_db</td>
            <td>❌ PDB Not Found</td>
            <td><a href='$report_filename'>View Details</a></td>
            <td>N/A</td>
          </tr>" >> "$summary_file"
      ;;
    "COMPLETED")
      # Check for failures in the report
      if grep -q "class='critical'" "$report_file"; then
        critical_count=$(grep -c "class='critical'" "$report_file")
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='critical'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>❌ Failed ($critical_count issues)</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Critical: $critical_count<br>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      else
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='ok'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>✅ Passed</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      fi
      ;;
  esac
}

#!/bin/bash

# Function to get CDB-level parameters
get_cdb_parameters() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- CDB-specific parameters
prompt CDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE'
AND name NOT IN (
  'db_unique_name',
  'service_names',
  'local_listener',
  'remote_listener',
  'log_archive_dest_1',
  'log_archive_dest_2',
  'fal_server'
);
prompt CDB_PARAMETERS_END
EXIT;
EOF
}

# Function to get PDB-level parameters
get_pdb_parameters() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- PDB-specific parameters
prompt PDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN (
  'service_names',
  'local_listener',
  'db_file_name_convert',
  'log_file_name_convert'
);
prompt PDB_PARAMETERS_END
EXIT;
EOF
}

# Function to compare parameters and generate HTML
compare_parameters() {
  local src_params=$1
  local tgt_params=$2
  local title=$3
  local html_file=$4

  echo "<div class='section'>" >> "$html_file"
  echo "<h2>$title Parameter Comparison</h2>" >> "$html_file"
  echo "<table><tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> "$html_file"

  awk -F= '
    BEGIN {count=0}
    NR==FNR {a[$1]=$2; next}
    {
      if ($1 in a) {
        if (a[$1] != $2) {
          printf "<tr><td>%s</td><td class=\"diff\">%s</td><td class=\"diff\">%s</td></tr>\n", $1,a[$1],$2
          count++
        }
        delete a[$1]
      } else {
        printf "<tr><td>%s</td><td>%s</td><td class=\"critical\">Missing</td></tr>\n", $1,$2
        count++
      }
    }
    END {
      for (i in a) {
        printf "<tr><td>%s</td><td class=\"critical\">Missing</td><td>%s</td></tr>\n", i,a[i]
        count++
      }
      exit (count > 0 ? 1 : 0)
    }
  ' <(echo "$src_params") <(echo "$tgt_params") >> "$html_file"

  if [ $? -eq 0 ]; then
    echo "<tr><td colspan='3' class='ok'>✅ All parameters match</td></tr>" >> "$html_file"
  fi

  echo "</table></div>" >> "$html_file"
}

# Function to extract parameters between markers
extract_parameters() {
  local full_output=$1
  local marker=$2
  awk -v marker="$marker" '
    $0 ~ marker "_START" {start=1; next}
    $0 ~ marker "_END" {exit}
    start {print}
  ' <<< "$full_output"
}


#!/bin/bash

# ... (previous configuration code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... (previous parsing and connection checks remain the same) ...

  # Get CDB and PDB parameters for both source and target
  src_full_output=$(get_db_properties "$SRC_CONN")
  tgt_full_output=$(get_db_properties "$TGT_CONN")

  # Extract and compare CDB parameters
  src_cdb_params=$(extract_parameters "$src_full_output" "CDB_PARAMETERS")
  tgt_cdb_params=$(extract_parameters "$tgt_full_output" "CDB_PARAMETERS")
  compare_parameters "$src_cdb_params" "$tgt_cdb_params" "CDB-Level" "$REPORT_FILE"

  # Extract and compare PDB parameters
  src_pdb_params=$(extract_parameters "$src_full_output" "PDB_PARAMETERS")
  tgt_pdb_params=$(extract_parameters "$tgt_full_output" "PDB_PARAMETERS")
  compare_parameters "$src_pdb_params" "$tgt_pdb_params" "PDB-Level" "$REPORT_FILE"

  # ... (rest of the compatibility checks remain the same) ...
done

# ... (rest of the script remains the same) ...


init_html_report() {
  local html_file="$1"
  local migration="$2"
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Compatibility Report: $migration</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .critical {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .ok {background-color: #d4edda; color: #155724;}
  .diff {background-color: #ffe8e8;}
  .section {margin-bottom: 30px; border-top: 2px solid #444; padding-top: 15px;}
  h2 {color: #2c3e50;}
  h3 {color: #2c3e50; margin-top: 20px;}
</style>
</head>
<body>
<h1>PDB Compatibility Report: $migration</h1>
<p>Generated at: $(date)</p>
EOF
}

# Excluded parameters configuration
[EXCLUDED_PARAMS]
CDB_EXCLUDED=db_unique_name,service_names,local_listener,remote_listener,log_archive_dest_1,log_archive_dest_2,fal_server
PDB_EXCLUDED=service_names,local_listener,db_file_name_convert,log_file_name_convert

# ... rest of the configuration ...


#!/bin/bash

# Load excluded parameters from config
load_excluded_params() {
  local config_file=$1
  CDB_EXCLUDED=$(sed -n '/^\[EXCLUDED_PARAMS\]/,/^$/p' "$config_file" | grep '^CDB_EXCLUDED=' | cut -d'=' -f2)
  PDB_EXCLUDED=$(sed -n '/^\[EXCLUDED_PARAMS\]/,/^$/p' "$config_file" | grep '^PDB_EXCLUDED=' | cut -d'=' -f2)
}

# Function to get CDB-level parameters
get_cdb_parameters() {
  local conn_str=$1
  local excluded_params=$2
  
  # Convert comma-separated list to quoted SQL list
  sql_excluded=$(echo "$excluded_params" | sed "s/,/','/g")
  
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- CDB-specific parameters
prompt CDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE'
AND name NOT IN ('$sql_excluded');
prompt CDB_PARAMETERS_END
EXIT;
EOF
}

# Function to get PDB-level parameters
get_pdb_parameters() {
  local conn_str=$1
  local excluded_params=$2
  
  # Convert comma-separated list to quoted SQL list
  sql_excluded=$(echo "$excluded_params" | sed "s/,/','/g")
  
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- PDB-specific parameters
prompt PDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN ('$sql_excluded');
prompt PDB_PARAMETERS_END
EXIT;
EOF
}

# ... rest of the functions remain the same ...

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!" >&2
  exit 1
fi

# Load excluded parameters
load_excluded_params "$CONFIG_FILE"

# ... rest of the configuration loading ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... previous parsing and connection checks ...

  # Get CDB and PDB parameters for both source and target
  src_full_output=$(get_db_properties "$SRC_CONN")
  tgt_full_output=$(get_db_properties "$TGT_CONN")

  # Extract and compare CDB parameters with excluded params
  src_cdb_params=$(extract_parameters "$(get_cdb_parameters "$SRC_CONN" "$CDB_EXCLUDED")" "CDB_PARAMETERS")
  tgt_cdb_params=$(extract_parameters "$(get_cdb_parameters "$TGT_CONN" "$CDB_EXCLUDED")" "CDB_PARAMETERS")
  compare_parameters "$src_cdb_params" "$tgt_cdb_params" "CDB-Level" "$REPORT_FILE"

  # Extract and compare PDB parameters with excluded params
  src_pdb_params=$(extract_parameters "$(get_pdb_parameters "$SRC_CONN" "$PDB_EXCLUDED")" "PDB_PARAMETERS")
  tgt_pdb_params=$(extract_parameters "$(get_pdb_parameters "$TGT_CONN" "$PDB_EXCLUDED")" "PDB_PARAMETERS")
  compare_parameters "$src_pdb_params" "$tgt_pdb_params" "PDB-Level" "$REPORT_FILE"

  # ... rest of the compatibility checks ...
done

# ... rest of the script ...

[EXCLUDED_PARAMS]
# Parameters to exclude from CDB-level comparison
CDB_EXCLUDED=db_unique_name,service_names,local_listener,remote_listener,log_archive_dest_1,log_archive_dest_2,fal_server

# Parameters to exclude from PDB-level comparison
PDB_EXCLUDED=service_names,local_listener,db_file_name_convert,log_file_name_convert
