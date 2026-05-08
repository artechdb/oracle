#!/bin/bash
# ================================================================
# Script : rac_copilot_triage.sh
# Purpose: Collect comprehensive Oracle RAC + VM performance data
#          and generate a structured prompt for AI‑assisted triage.
# Scope  : Oracle 19c+ RAC on Linux VM (VMware / KVM / OVM)
# Output : rac_copilot_evidence_<ticket>.log  (drop into Copilot)
# ================================================================
# Usage  : ./rac_copilot_triage.sh <SERVICE_NOW_TICKET>
# Example: ./rac_copilot_triage.sh INC0012345
# Prereqs: Run as oracle (or grid) user with OSWatcher installed
#          and environment sourced (. oraenv or grid_env).
# ================================================================

set -o pipefail

# ---- Config ----
TICKET="${1:-UNKNOWN}"
REPORT_DIR="/tmp/rac_copilot_${TICKET}_$(date +%Y%m%d_%H%M%S)"
EVIDENCE_FILE="${REPORT_DIR}/rac_copilot_evidence_${TICKET}.log"
PROMPT_FILE="${REPORT_DIR}/copilot_prompt_${TICKET}.txt"
OSW_ARCHIVE="/opt/oswbb/archive"              # adjust to your OSWatcher path
OS_COLLECTION_SECS=60                          # how long to collect OS metrics
SQL_OUTPUT="${REPORT_DIR}/db_metrics.txt"

mkdir -p "${REPORT_DIR}"
exec > >(tee -a "${EVIDENCE_FILE}") 2>&1

echo "============================================================"
echo "RAC Copilot Triage Script — Started at $(date)"
echo "ServiceNow Ticket : ${TICKET}"
echo "Hostname          : $(hostname)"
echo "Report Directory  : ${REPORT_DIR}"
echo "============================================================"

# ================================================================
# SECTION 1 : OS / VM Identification & Health
# ================================================================
echo ""
echo "========== OS & VM IDENTIFICATION =========="
echo "TIMESTAMP: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

echo "--- uname ---"
uname -a

echo ""
echo "--- OS Release ---"
cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null

echo ""
echo "--- CPU Info (lscpu) ---"
lscpu 2>/dev/null | head -40

echo ""
echo "--- Memory Info ---"
free -h 2>/dev/null; echo "---"; cat /proc/meminfo 2>/dev/null | head -20

echo ""
echo "--- Block Devices ---"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,ROTA 2>/dev/null

echo ""
echo "--- Network Interfaces ---"
ip addr show 2>/dev/null || ifconfig -a 2>/dev/null

# ---- VM-specific detection ----
echo ""
echo "--- VM Detection ---"
systemd-detect-virt 2>/dev/null && echo "(systemd-detect-virt)"
grep -qi 'vmware\|virtualbox\|kvm\|xen\|microsoft' /sys/class/dmi/id/product_name 2>/dev/null \
    && echo "Physical product: $(cat /sys/class/dmi/id/product_name 2>/dev/null)" \
    || echo "Bare-metal or undetected"
grep -qi 'hypervisor' /proc/cpuinfo 2>/dev/null && echo "Hypervisor flag found in /proc/cpuinfo"

# ================================================================
# SECTION 2 : OS Live Metrics (snapshot over OS_COLLECTION_SECS)
# ================================================================
echo ""
echo "========== OS LIVE METRICS (${OS_COLLECTION_SECS}s collection) =========="

echo ""
echo "--- vmstat (last 3 lines) ---"
vmstat 1 $((OS_COLLECTION_SECS > 10 ? 10 : OS_COLLECTION_SECS)) 2>/dev/null | tail -5

echo ""
echo "--- mpstat ---"
mpstat -P ALL 1 3 2>/dev/null | tail -20

echo ""
echo "--- iostat -xm (last 5 lines) ---"
iostat -xm 1 3 2>/dev/null | tail -15

echo ""
echo "--- netstat -s (TCP retrans / UDP errors) ---"
netstat -s 2>/dev/null | grep -iE "retransmit|drop|error|overflow|reassembly"

echo ""
echo "--- CPU Steal Time (top) ---"
top -bn2 -d 5 2>/dev/null | grep -E "Cpu\(s\)|%Cpu" | tail -1

echo ""
echo "--- NUMA Stats ---"
numactl --hardware 2>/dev/null || echo "numactl not available"
grep -i "numa" /proc/vmstat 2>/dev/null | head -10

echo ""
echo "--- HugePages ---"
grep -i huge /proc/meminfo 2>/dev/null

# ================================================================
# SECTION 3 : Oracle Grid Infrastructure / Clusterware Health
# ================================================================
echo ""
echo "========== GRID INFRASTRUCTURE / CLUSTERWARE =========="

echo ""
echo "--- olsnodes ---"
olsnodes -s -t 2>/dev/null || echo "olsnodes not available"

echo ""
echo "--- crsctl check cluster ---"
crsctl check cluster -all 2>/dev/null || echo "crsctl not available"

echo ""
echo "--- crsctl stat res -t (summary) ---"
crsctl stat res -t 2>/dev/null | head -40

echo ""
echo "--- srvctl status database ---"
srvctl status database -d $(ps -ef | grep pmon | grep -v grep | grep -v asm | awk -F_ '{print $3}' | head -1) 2>/dev/null \
    || echo "Could not determine DB name for srvctl"

echo ""
echo "--- ASM Disk Group Usage ---"
if command -v asmcmd &>/dev/null; then
    asmcmd lsdg 2>/dev/null
else
    echo "asmcmd not available — run from grid home"
fi

# ================================================================
# SECTION 4 : Oracle Database Diagnostics (SQL)
# ================================================================
echo ""
echo "========== DATABASE DIAGNOSTICS (SQL via SQL*Plus) =========="
echo "TIMESTAMP: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Locate sqlplus
SQLPLUS="$(which sqlplus 2>/dev/null || echo 'sqlplus')"

cat > "${REPORT_DIR}/rac_metrics.sql" << 'EOSQL'
-- ================================================================
-- RAC Copilot Triage SQL — All metrics for AI analysis
-- ================================================================
SET LINESIZE 300
SET PAGESIZE 50000
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET TIMING OFF

PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: DATABASE IDENTIFICATION ===
PROMPT ============================================================
PROMPT Include PDB name, open mode, environment, instance info,
PROMPT host, version, startup time and RAC node count in your report.

SELECT 'INSTANCE: ' || instance_name || ' #' || instance_number ||
       ' on ' || host_name || ' version ' || version_full ||
       ' started ' || TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI') ||
       ' status ' || status || ' role ' || INSTANCE_ROLE
  FROM v$instance;

SELECT name || ' (open_mode:' || open_mode || ' DB_ROLE:' || DATABASE_ROLE ||
       ' created:' || TO_CHAR(created,'YYYY-MM-DD') || ')' AS db_info
  FROM v$database;

SELECT COMPR_NAME, COMPR_STATUS, VERSION FROM dba_registry;

SELECT con_id, name, open_mode, restricted, total_size/1024/1024/1024 size_gb
  FROM v$pdbs ORDER BY con_id;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: RAC CLUSTER HEALTH ===
PROMPT ============================================================
PROMPT If is_public=YES, RAC may be using wrong NIC. Must be NO.
PROMPT If any IF_STATE is DOWN, flag as RED.

SELECT * FROM gv$cluster_interconnects;

--- Interconnect latency (v$instance_ping):
SELECT inst1.instance_number src_inst, inst2.instance_number dst_inst,
       elap.connected, elap.ping_latency_ms
  FROM v$instance_ping elap,
       (SELECT instance_number FROM v$instance) inst1,
       (SELECT instance_number FROM v$instance) inst2
 WHERE inst1.instance_number = elap.instance_number(+);

--- GES Statistics:
SELECT inst_id, resource_name1, resource_name2, state, owner_node, blocked, blocker
  FROM gv$ges_blocking_enqueue WHERE blocker = 1;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: CLUSTER-WIDE PROCESS CAPACITY ===
PROMPT ============================================================
PROMPT ACTIVE_PROCESSES vs MAX_PROCESSES per instance.
PROMPT GREEN: <65%, YELLOW: 65-85%, RED: >85%.

SELECT NVL(TO_CHAR(p.inst_id),'CLUSTER_TOTAL') AS inst_id,
       COUNT(*) AS active_processes,
       MAX(p.max_proc) AS max_processes,
       ROUND(COUNT(*)/MAX(p.max_proc)*100,2) AS pct_used
  FROM (SELECT inst_id FROM gv$process) p
  CROSS JOIN (SELECT inst_id, TO_NUMBER(VALUE) max_proc
                FROM gv$parameter WHERE name='processes') m
 WHERE p.inst_id = m.inst_id
 GROUP BY ROLLUP(p.inst_id) ORDER BY p.inst_id;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: SESSION COUNTS PER INSTANCE ===
PROMPT ============================================================

SELECT inst_id, status, type, COUNT(*) AS session_count
  FROM gv$session GROUP BY inst_id, status, type
 ORDER BY inst_id, status, type;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: CPU SATURATION (CDB-LEVEL, PER INSTANCE) ===
PROMPT ============================================================
PROMPT cpu_wait_sec = db_time_sec - db_cpu_sec.
PROMPT 0: GREEN. Small & stable: YELLOW. Large or growing: RED.

SELECT inst_id,
       ROUND(SUM(CASE WHEN stat_name='DB time' THEN value END)/1e6,2) db_time_sec,
       ROUND(SUM(CASE WHEN stat_name='DB CPU' THEN value END)/1e6,2) db_cpu_sec,
       ROUND((SUM(CASE WHEN stat_name='DB time' THEN value END)-
              SUM(CASE WHEN stat_name='DB CPU' THEN value END))/1e6,2) cpu_wait_sec
  FROM gv$sys_time_model GROUP BY inst_id ORDER BY inst_id;

SELECT inst_id, value AS cpu_count
  FROM gv$parameter WHERE name='cpu_count' ORDER BY inst_id;

SELECT inst_id, name, is_top_plan, cpu_managed, utilization_limit
  FROM gv$rsrc_plan WHERE is_top_plan='TRUE' ORDER BY inst_id;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: VM-SPECIFIC METRICS ===
PROMPT ============================================================
PROMPT CPU steal time >5% on any VM node is RED.
PROMPT BUSY_TIME high but IDLE_TIME near zero = CPU overcommitted.

SELECT inst_id,
       SUM(CASE WHEN stat_name='BUSY_TIME' THEN value END)/100 CPU_BUSY_SEC,
       SUM(CASE WHEN stat_name='IDLE_TIME' THEN value END)/100 CPU_IDLE_SEC,
       SUM(CASE WHEN stat_name='RSRC_MGR_CPU_WAIT_TIME' THEN value END)/100 CPU_RM_WAIT_SEC,
       SUM(CASE WHEN stat_name='NUM_CPUS' THEN value END) NUM_CPUS
  FROM gv$osstat
 WHERE stat_name IN ('BUSY_TIME','IDLE_TIME','RSRC_MGR_CPU_WAIT_TIME','NUM_CPUS')
 GROUP BY inst_id ORDER BY inst_id;

--- System metrics (1-min granularity, last 60 minutes):
PROMPT
PROMPT --- gv$sysmetric_history: CPU Usage Per Sec (last 10 rows) ---
SELECT inst_id, TO_CHAR(end_time,'HH24:MI') tm,
       ROUND(MAX(CASE WHEN metric_name='CPU Usage Per Sec' THEN value END)/100,1) cpu_cores_used,
       ROUND(MAX(CASE WHEN metric_name='Host CPU Utilization (%)' THEN value END),1) host_cpu_pct,
       ROUND(MAX(CASE WHEN metric_name='Database Time Per Sec' THEN value END)/100,1) db_time_cores
  FROM gv$sysmetric_history
 WHERE end_time > SYSDATE - 10/1440
   AND metric_name IN ('CPU Usage Per Sec','Host CPU Utilization (%)','Database Time Per Sec')
   AND group_id = 2
 GROUP BY inst_id, TO_CHAR(end_time,'HH24:MI')
 ORDER BY inst_id, tm;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: RAC GC WAIT EVENTS (CLUSTER-WIDE) ===
PROMPT ============================================================
PROMPT Focus on gc cr/current block busy, gc block lost, gc cr multi block.
PROMPT 3-way transfers > 5% of 2-way: YELLOW. gc block lost > 0: RED.

PROMPT --- Top 15 Wait Events (excluding Idle) ---
SELECT * FROM (
  SELECT inst_id, event, wait_class,
         total_waits, time_waited_micro/1e6 time_waited_sec,
         ROUND(time_waited_micro/1e6/NULLIF(total_waits,0)*1000,3) avg_wait_ms
    FROM gv$system_event
   WHERE wait_class <> 'Idle'
   ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 15;

PROMPT --- GC Wait Events Specifically ---
SELECT inst_id, event, total_waits, time_waited_micro/1e6 time_waited_sec
  FROM gv$system_event
 WHERE event LIKE 'gc%'
 ORDER BY time_waited_micro DESC;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: BLOCKING SESSIONS ===
PROMPT ============================================================
PROMPT Cross-instance blocking must be called out explicitly.

SELECT a.inst_id blocker_inst, a.sid blocker_sid,
       a.username blocker_user, a.event blocker_event,
       b.inst_id waiter_inst, b.sid waiter_sid,
       b.username waiter_user, b.event waiter_event,
       b.seconds_in_wait
  FROM gv$session a
  JOIN gv$session b
    ON a.sid = b.final_blocking_session
   AND a.inst_id = b.final_blocking_instance
 WHERE b.final_blocking_session IS NOT NULL
 ORDER BY b.seconds_in_wait DESC;

PROMPT --- Enqueue Locks Held ---
SELECT l.inst_id, l.sid, s.username, s.program, l.type,
       l.lmode, l.request, l.block, l.ctime
  FROM gv$lock l JOIN gv$session s
    ON l.sid = s.sid AND l.inst_id = s.inst_id
 WHERE l.block > 0 AND l.type IN ('TX','TM')
 ORDER BY l.inst_id, l.sid;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: ASH LAST HOUR (CLUSTER-WIDE) ===
PROMPT ============================================================

PROMPT --- Wait Classes (last hour, all instances) ---
SELECT wait_class, COUNT(*) AS samples,
       ROUND(COUNT(*)/36,0) AS est_active_sessions
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND session_state = 'WAITING'
   AND wait_class <> 'Idle'
 GROUP BY wait_class ORDER BY samples DESC;

PROMPT --- Top 10 Wait Events (last hour) ---
SELECT event, wait_class, COUNT(*) AS samples
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND session_state = 'WAITING'
   AND wait_class <> 'Idle'
 GROUP BY event, wait_class ORDER BY samples DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: TOP SQL (last hour ASH) ===
PROMPT ============================================================

SELECT sql_id, COUNT(*) AS ash_samples,
       ROUND(COUNT(*)/36,0) AS est_active_sessions
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND sql_id IS NOT NULL
 GROUP BY sql_id ORDER BY ash_samples DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: SGA / PGA MEMORY ===
PROMPT ============================================================

SELECT inst_id, name, ROUND(bytes/1024/1024) AS size_mb, resizeable
  FROM gv$sgainfo ORDER BY inst_id, name;

SELECT inst_id, ROUND(SUM(pga_alloc_mem)/1024/1024/1024,2) total_pga_gb,
       ROUND(SUM(pga_used_mem)/1024/1024/1024,2) used_pga_gb,
       ROUND(SUM(pga_max_mem)/1024/1024/1024,2) max_pga_gb
  FROM gv$process GROUP BY inst_id ORDER BY inst_id;

SELECT name, value FROM v$parameter
 WHERE name IN ('sga_target','sga_max_size','memory_target','memory_max_target',
                'pga_aggregate_target','shared_pool_size','db_cache_size');

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: TABLESPACE & FRA SPACE ===
PROMPT ============================================================

SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024,2) total_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024,2) max_gb
  FROM dba_data_files GROUP BY tablespace_name
 ORDER BY total_gb DESC;

SELECT ROUND(SPACE_LIMIT/1024/1024/1024,2) fra_total_gb,
       ROUND(SPACE_USED/1024/1024/1024,2) fra_used_gb,
       ROUND(SPACE_USED/SPACE_LIMIT*100,2) fra_pct
  FROM v$recovery_file_dest;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: DATA GUARD STATUS ===
PROMPT ============================================================

SELECT * FROM v$dataguard_stats;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: RECENT ALERT LOG ERRORS ===
PROMPT ============================================================

SELECT TO_CHAR(originating_timestamp,'YYYY-MM-DD HH24:MI') alert_time,
       message_text
  FROM v$diag_alert_ext
 WHERE (message_text LIKE '%ORA-%' OR message_text LIKE '%error%'
        OR message_text LIKE '%fail%')
   AND originating_timestamp > SYSDATE - 1
   AND ROWNUM <= 50
 ORDER BY originating_timestamp DESC;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: REAL-TIME SQL MONITOR (TOP 10) ===
PROMPT ============================================================

SELECT inst_id, sql_id, sql_exec_id, status,
       ROUND(elapsed_time/1e6,1) elapsed_sec,
       ROUND(cpu_time/1e6,1) cpu_sec,
       ROUND(user_io_wait_time/1e6,1) io_wait_sec,
       ROUND(temp_space_allocated/1024/1024,1) temp_mb
  FROM gv$sql_monitor
 WHERE status IN ('EXECUTING','DONE')
   AND (cpu_time + user_io_wait_time) > 0
 ORDER BY elapsed_time DESC FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ============================================================
PROMPT === COPILOT_AUTO_INSTRUCT: DATABASE FILES I/O ===
PROMPT ============================================================

SELECT file_name, ROUND(bytes/1024/1024/1024,2) size_gb
  FROM dba_data_files ORDER BY bytes DESC FETCH FIRST 20 ROWS ONLY;

SELECT name, ROUND(value/1024/1024,2) size_mb
  FROM v$sga ORDER BY name;

PROMPT ============================================================
PROMPT === END DATABASE METRICS ===
PROMPT ============================================================
EOSQL

# ---- Execute SQL ----
echo "Connecting to database ..."
$SQLPLUS -S / as sysdba @"${REPORT_DIR}/rac_metrics.sql" > "${SQL_OUTPUT}" 2>&1
RC=$?
if [ $RC -ne 0 ]; then
    echo "WARNING: SQL*Plus exited with code $RC. Output may be incomplete."
fi
cat "${SQL_OUTPUT}" >> "${EVIDENCE_FILE}"

# ================================================================
# SECTION 5 : Include recent OSWatcher data (optional)
# ================================================================
echo ""
echo "========== OSWATCHER RECENT DATA =========="
if [ -d "${OSW_ARCHIVE}" ]; then
    # Find the most recent oswtop or oswvmstat file
    LATEST_VMSTAT=$(find "${OSW_ARCHIVE}" -name "*vmstat*" -type f -mmin -120 2>/dev/null | tail -1)
    if [ -n "${LATEST_VMSTAT}" ]; then
        echo "--- Last 50 lines of ${LATEST_VMSTAT} ---"
        tail -50 "${LATEST_VMSTAT}"
    else
        echo "No recent OSWatcher vmstat data found. Consider installing OSWbb."
    fi
else
    echo "OSWatcher archive not found at ${OSW_ARCHIVE}."
    echo "Install OSWbb (Doc ID 301137.1) for continuous OS metrics."
fi

# ================================================================
# SECTION 6 : Build Copilot Prompt
# ================================================================
echo ""
echo "========== BUILDING COPILOT PROMPT =========="

cat > "${PROMPT_FILE}" << 'EOPROMPT'
# Role
You are an expert **Oracle RAC & VM Performance DBA**. You triage incidents using evidence from OS, clusterware, and database diagnostics. You provide a **confidence score (0–100%)** for every finding.

# Context
- **ServiceNow Ticket**: <TICKET_PLACEHOLDER>
- **Environment**: Oracle 19c+ RAC running on Linux virtual machines (VMware / KVM / OVM).
- **Evidence Source**: The attached log file contains comprehensive OS + clusterware + database metrics collected simultaneously from all nodes.

# Task
Analyze the **ENTIRE attached evidence file** from scratch. Do NOT rely on prior conversation. Produce:

## A) Executive Summary
2–3 sentences describing the overall health (GREEN / YELLOW / RED) and the single most critical finding.

## B) Full On-Call DBA Report for ServiceNow
For each area below, provide findings, a severity verdict, and a **confidence score**:

1. **Cluster Health** – olsnodes, crsctl, interconnect, GES enqueues
2. **Process & Session Capacity** – per-instance ACTIVE_PROCESSES vs MAX_PROCESSES
3. **CPU Saturation** – DB_Time vs DB_CPU per instance; Host CPU utilization; CPU steal
4. **RAC Global Cache (Cache Fusion)** – gc wait events; 2-way vs 3-way vs disk reads; interconnect latency
5. **Blocking & Locking** – cross-instance blockers; TX/TM locks; duration
6. **Memory Stability** – SGA/PGA sizing; ORA-4031; shared pool free memory
7. **Storage & I/O** – tablespace usage; FRA usage; datafile I/O; ASM disk groups
8. **Top SQL** – ASH samples; SQL Monitor; temp spill
9. **Alert Log** – ORA- errors; cluster communication errors
10. **Data Guard** – transport/apply lag (if applicable)

## C) Numeric Summary
Provide a concise table with:
- Instances: N     | RAC: Yes/No     | DB Version: X.Y.Z
- Active Processes (per node / cluster total)
- Max Processes (per node)
- Active User Sessions (per node / cluster total)
- Blocking Sessions (count; 0 = GREEN)
- GC 3-way % of total GC requests
- FRA % Used
- Top Wait Event (name + avg ms)
- CPU Wait (sec) per instance
- ORA- Errors in last 24h

## D) Actionable Remediation
List the top 3 immediate actions, ordered by urgency.

# Interpretation Rules (MANDATORY)
- **GC wait events**: 2-way is fast; 3-way is hot-block contention; disk read means block not in any cache.
- **gc buffer busy / gc cr block busy**: Hot block accessed concurrently from multiple instances. Focus on application partitioning or reverse-key indexes.
- **gc block lost**: Always RED — indicates private network packet loss. Check UDP buffer sizes (net.core.rmem_max), MTU mismatch, or faulty NIC.
- **CPU steal time**: >5% on VM nodes → RED. Indicates hypervisor CPU overcommitment. Recommend CPU reservations.
- **PX Deq: * waits**: Parallel coordination, NOT blocking. Do NOT escalate.
- **resmgr:cpu quantum**: Expected throttling under Resource Manager. Cross-reference with active plan.
- **ACTIVE_PROCESSES >85% of MAX_PROCESSES**: RED. Risk of ORA-00020.
- **DB TIME >> DB CPU on multiple instances**: CDB-level CPU oversubscription. NOT a single PDB problem.

# Confidence Score Guidance
- **90–100%**: Very clear evidence; metric values and trends well captured.
- **70–89%**: Generally clear, but some inference required or data limited.
- **50–69%**: Partial evidence; key metrics missing or ambiguous.
- **<50%**: Low confidence; critical data unavailable; recommend manual investigation.

# Output Format
Use a clean, structured Markdown format. Include **severity badges** (🟢 GREEN / 🟡 YELLOW / 🔴 RED) and **confidence scores** for each finding.
EOPROMPT

# Replace placeholder with actual ticket
sed -i "s/<TICKET_PLACEHOLDER>/${TICKET}/g" "${PROMPT_FILE}"

echo ""
echo "============================================================"
echo "=== COLLECTION COMPLETE ==="
echo "============================================================"
echo "Evidence file : ${EVIDENCE_FILE}"
echo "Copilot prompt: ${PROMPT_FILE}"
echo ""
echo "=== NEXT STEPS ==="
echo "1) Open a NEW Copilot session (clear prior context)."
echo "2) Copy-paste the contents of:  ${PROMPT_FILE}"
echo "3) Then drag-and-drop the evidence file: ${EVIDENCE_FILE}"
echo "4) Say: 'Analyze the attached evidence file using the instructions above.'"
echo "5) Once analysis is complete, say: 'Create a downloadable .txt artifact with the full report.'"
echo "============================================================"