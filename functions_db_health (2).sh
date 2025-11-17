#!/bin/bash
################################################################################
# Oracle 19c RAC - Health Check Functions (Fine-grained + HTML helpers)
# Auto-generated from db_healthcheck_19c_rac_ready.sql
# - Individual query functions per section (aligned with original <h2> labels)
# - No external @sql execution; no wrapper; each query uses inline here-doc
# - Centralized HTML helpers: header/section/footer
# Version: 7.0
# Generated: 2025-11-17
################################################################################

# Requires: functions_common.sh (for log_message, test_db_connection)

# ---------------------------
# HTML helper functions
# ---------------------------
_hc_html_write() {
  local f="$1"; cat >> "$f";
}

hc_html_begin() {
  # $1=report_raw  $2=db_name  $3=scan  $4=service  $5=ts
  local f="$1"; local db="$2"; local scan="$3"; local svc="$4"; local ts="$5"
  _hc_html_write "$f" <<'HTML'
<html><head><meta charset="UTF-8"><title>Oracle 19c RAC Health Check</title>
<style>
body { font-family: Arial, sans-serif; background:#f7f9fc; margin: 16px; }
h1 { color: #0b5aa2; }
h2 { border-left: 4px solid #0b5aa2; padding-left: 8px; color:#333; }
h3 { color:#333; margin-top: 14px; }
table { border-collapse: collapse; width:100%; background:#fff; }
th, td { border:1px solid #ddd; padding:6px; }
th { background: #0b5aa2; color:#fff; }
tr:nth-child(even) { background:#fafafa; }
.meta { background:#f0f6ff; padding:8px; margin:8px 0; }
</style></head><body>
HTML
  _hc_html_write "$f" <<HTML
<h1>Oracle 19c RAC Database Health Check Report</h1>
<div class="meta"><b>Database:</b> ${db} &nbsp; <b>SCAN:</b> ${scan} &nbsp; <b>Service:</b> ${svc} &nbsp; <b>Generated:</b> ${ts}</div>
HTML
}

hc_html_section() {
  # $1=report_raw  $2=title (exactly as original section label)
  local f="$1"; local title="$2"
  _hc_html_write "$f" <<HTML
<h2>${title}</h2>
HTML
}

hc_html_end() {
  local f="$1"
  _hc_html_write "$f" <<'HTML'
</body></html>
HTML
}

# Query 01 for section: prompt Note1: Session Information for Health Check
hc_q_prompt_note1_session_information_for_health_check_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note1_session_information_for_health_check_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set line 9999 
col CREATED format a20
col DATABASE_ROLE format a20
col LOG_MODE format a13
col OPEN_MODE format a20
col VERSION format a10
col sessionid format a20

SELECT d.INST_ID,
       d.DBID,
       d.NAME,
       d.DATABASE_ROLE,
       TO_CHAR(d.CREATED, 'yyyy-mm-dd HH24:mi:ss') CREATED,
       d.LOG_MODE,
       d.OPEN_MODE,
       (SELECT b.VERSION FROM v$instance b WHERE ROWNUM = 1) VERSION,
       (SELECT a.SID || ',' || b.SERIAL# || ',' || c.SPID
          FROM v$mystat a, v$session b, v$process c
         WHERE a.SID = b.SID
           AND  b.PADDR = c.ADDR
           AND  ROWNUM = 1) sessionid
  FROM gv$database d;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt Note1: Session Information for Health Check
hc_section_prompt_note1_session_information_for_health_check() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt Note1: Session Information for Health Check"
  hc_q_prompt_note1_session_information_for_health_check_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: prompt Note2: Database Recycle Bin Status
hc_q_prompt_note2_database_recycle_bin_status_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note2_database_recycle_bin_status_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
col owner format a15
SELECT a.CON_ID,
       nvl(a.owner, 'SUM') owner,
       round(SUM(a.space *
                 (SELECT value FROM v$parameter WHERE name = 'db_block_size')) / 1024 / 1024,
             2) recyb_size_M,
       count(1) recyb_cnt
  FROM cdb_recyclebin a
 GROUP BY a.CON_ID, ROLLUP(a.owner);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt Note2: Database Recycle Bin Status
hc_section_prompt_note2_database_recycle_bin_status() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt Note2: Database Recycle Bin Status"
  hc_q_prompt_note2_database_recycle_bin_status_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: prompt Note: Do not modify any inspection results
hc_q_prompt_note_do_not_modify_any_inspection_results_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_do_not_modify_any_inspection_results_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt 


prompt  Description:

prompt  This script checks various Oracle 11g metrics including key parameters, object status, storage config, and performance (AWR/ASH/ADDM), RMAN backup status, etc.

prompt
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt Note: Do not modify any inspection results
hc_section_prompt_note_do_not_modify_any_inspection_results() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt Note: Do not modify any inspection results"
  hc_q_prompt_note_do_not_modify_any_inspection_results_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: prompt Notes:
hc_q_prompt_notes_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ① A,If the script output is garbled, set the environment variables and SSH software encoding properly.

prompt       1) locale -a | grep zh_CN  AIX: LANG=zh_CN  Linux:LANG=zh_CN.gbk ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 02 for section: prompt Notes:
hc_q_prompt_notes_02() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_02_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt       2) export NLS_LANG="SIMPLIFIED CHINESE_CHINA.ZHS16GBK" ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 03 for section: prompt Notes:
hc_q_prompt_notes_03() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_03_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt       3) Ensure script encoding is set to GBK if running on Windows.

prompt    B. If the final HTML report contains garbled text, open the HTML file with a text editor and change the third line to (charset=UTF-8). 

prompt    C,Running the script on Windows is highly recommended.

prompt    D,The generated HTML report will be saved in the current directory. Oracle user must have write permission here.

prompt  ② Final inspection report is saved to the current directory.

prompt  ③ User privileges must meet the following conditions or run as SYS:

prompt   A. A. The user should at least have DBA role, SELECT ANY DICTIONARY, and EXECUTE on DBMS_SYSTEM and AWR access.
PROMPT        GRANT DBA TO XXX;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 04 for section: prompt Notes:
hc_q_prompt_notes_04() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_04_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
PROMPT        GRANT SELECT ANY DICTIONARY TO XXX;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 05 for section: prompt Notes:
hc_q_prompt_notes_05() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_05_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
PROMPT        GRANT EXECUTE ON DBMS_WORKLOAD_REPOSITORY TO XXX;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 06 for section: prompt Notes:
hc_q_prompt_notes_06() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_06_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
PROMPT        GRANT EXECUTE ON DBMS_SYSTEM TO XXX;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 07 for section: prompt Notes:
hc_q_prompt_notes_07() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_07_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
PROMPT        GRANT SELECT ON MGMT$ALERT_CURRENT TO XXX;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 08 for section: prompt Notes:
hc_q_prompt_notes_08() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_08_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   B. Grant SELECT on x$bh; otherwise, hot blocks cannot be inspected,Script as follows:

prompt         CREATE OR REPLACE VIEW BH AS SELECT * FROM SYS.X$BH;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 09 for section: prompt Notes:
hc_q_prompt_notes_09() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_09_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt         CREATE OR REPLACE PUBLIC SYNONYM X$BH FOR BH;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 10 for section: prompt Notes:
hc_q_prompt_notes_10() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_10_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

prompt  +
----------------------------------------------------------------------------+

prompt  The inspection script execution will take several minutes depending on database size.

prompt  Execution started......

prompt  +
----------------------------------------------------------------------------+

prompt 


-- +----------------------------------------------------------------------------+

-- |                           SCRIPT SETTINGS                                  |

-- +----------------------------------------------------------------------------+

set termout       off
set echo          off
set feedback      off
set heading       off
set verify        off
set wrap          on
set trimspool     on
set serveroutput  on
set escape        on
set sqlblanklines on
set ARRAYSIZE  500

set pagesize 50000
set linesize 32767
set numwidth 18
set long     2000000000 LONGCHUNKSIZE 100000

clear buffer computes columns
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24:mi:ss';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 11 for section: prompt Notes:
hc_q_prompt_notes_11() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_11_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SET APPINFO 'DB_HEALTHCHECK_LHR'


--SQLPLUS 
set termout       off
set errorlogging on
set errorlogging on TABLE SPERRORLOG identifier LHR_DB_HEALTHCHECK
delete from sperrorlog where identifier='LHR_DB_HEALTHCHECK';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 12 for section: prompt Notes:
hc_q_prompt_notes_12() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_12_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COMMIT;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 13 for section: prompt Notes:
hc_q_prompt_notes_13() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_13_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt 

host echo '
-----Oracle Database  Check STRAT,Starting Collect Data Dictionary Information----'	


prompt  ......
host echo start.....,html....


--------------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------------------------------


-- +----------------------------------------------------------------------------+

-- |                   GATHER DATABASE REPORT INFORMATION                       |

-- +----------------------------------------------------------------------------+

COLUMN tdate NEW_VALUE _date NOPRINT
COLUMN time NEW_VALUE _time NOPRINT
COLUMN date_time NEW_VALUE _date_time NOPRINT
COLUMN spool_time NEW_VALUE _spool_time NOPRINT
COLUMN date_time_timezone NEW_VALUE _date_time_timezone NOPRINT
COLUMN v_current_user NEW_VALUE _v_current_user NOPRINT
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') tdate,
       TO_CHAR(SYSDATE, 'HH24:MI:SS') time,
       TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') date_time,
       TO_CHAR(systimestamp, 'YYYY-MM-DD  (') ||
       TRIM(TO_CHAR(systimestamp, 'Day')) ||
       TO_CHAR(systimestamp, ') HH24:MI:SS AM') ||
       TO_CHAR(systimestamp, ' "timezone" TZR') date_time_timezone,
       TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') spool_time,
       user v_current_user
  FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 14 for section: prompt Notes:
hc_q_prompt_notes_14() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_14_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN dbVERSION NEW_VALUE _dbVERSION NOPRINT
COLUMN dbVERSION1 NEW_VALUE _dbVERSION1 NOPRINT
COLUMN host_name NEW_VALUE _host_name NOPRINT
COLUMN instance_name1 NEW_VALUE _instance_name NOPRINT
COLUMN instance_number NEW_VALUE _instance_number NOPRINT
COLUMN thread_number NEW_VALUE _thread_number NOPRINT
SELECT b.VERSION       dbVERSION,
       host_name       host_name,
       instance_name   instance_name1,
       instance_number instance_number,
       thread#         thread_number,
       substr(b.VERSION,1,instr(b.VERSION,'.')-1) dbVERSION1 
  FROM v$instance b;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 15 for section: prompt Notes:
hc_q_prompt_notes_15() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_15_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN startup_time NEW_VALUE _startup_time NOPRINT
SELECT CASE np.value
         WHEN 'TRUE' then
          listagg('[INST_ID ' || d.INST_ID || ':' ||
                    TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') || ']  ',',') within group(order by INST_ID)
         else
          listagg(TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS'),',')   within group(order by INST_ID) || '  '
       end AS startup_time
  FROM gv$instance d, v$parameter np
 WHERE np.NAME = 'cluster_database'
 GROUP BY np.value;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 16 for section: prompt Notes:
hc_q_prompt_notes_16() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_16_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN dbname1 NEW_VALUE _dbname1 NOPRINT
COLUMN dbid NEW_VALUE _dbid NOPRINT
COLUMN dbname NEW_VALUE _dbname NOPRINT
COLUMN reporttitle NEW_VALUE _reporttitle NOPRINT
COLUMN platform_name NEW_VALUE _platform_name NOPRINT
COLUMN FORCE_LOGGING NEW_VALUE _FORCE_LOGGING NOPRINT
COLUMN FLASHBACK_ON NEW_VALUE _FLASHBACK_ON NOPRINT
COLUMN platform_id NEW_VALUE _platform_id NOPRINT
COLUMN creation_date NEW_VALUE _creation_date NOPRINT
COLUMN log_mode NEW_VALUE _log_mode NOPRINT
COLUMN DB_ROLE NEW_VALUE _DB_ROLE NOPRINT
SELECT DECODE((SELECT b.parallel FROM v$instance b), 'YES', (d.NAME || '_' ||  (SELECT b.INSTANCE_NUMBER FROM v$instance b)), 'NO', d.NAME)   dbname1,  
       name dbname,
       dbid dbid,
       'DB_healthcheck_by_lhr_' || name || '_' ||DECODE((SELECT b.parallel FROM v$instance b), 'YES', (SELECT b.INSTANCE_NUMBER FROM v$instance b)|| '_', 'NO', '')  || (SELECT b.VERSION FROM v$instance b) || '_' ||TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') reporttitle,
       platform_name platform_name,
       d.FORCE_LOGGING,
       d.FLASHBACK_ON,
       platform_id platform_id ,
       TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') creation_date ,
       (case when log_mode ='NOARCHIVELOG' then log_mode else log_mode||','||(SELECT a.DESTINATION FROM v$archive_dest a where a.DESTINATION IS NOT NULL  and rownum<=1) end) log_mode,
       D.DATABASE_ROLE   DB_ROLE 
  FROM  v$database d;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 17 for section: prompt Notes:
hc_q_prompt_notes_17() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_17_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN hostinfo NEW_VALUE _hostinfo NOPRINT
SELECT listagg(hostinfo,',') within group(order by hostinfo) hostinfo
  FROM (SELECT CASE (SELECT b.parallel FROM v$instance b)
                 WHEN 'NO' then
                  '  CPUs:' || SUM(CPUs) || '  Cores:' || SUM(Cores) ||
                  '  Sockets:' || SUM(Sockets) || '  Memory:' || SUM(Memory) || 'G'
                 WHEN 'YES' then
                  '[' || 'Inst_id ' || instance_number || ':  CPUs:' ||
                  SUM(CPUs) || '  Cores:' || SUM(Cores) || '  Sockets:' ||
                  SUM(Sockets) || '  Memory:' || SUM(Memory) || 'G]'
               end hostinfo
                       o.dbid,
                       o.instance_number,
                       DECODE(o.stat_name, 'NUM_CPUS', o.value) CPUs,
                       DECODE(o.stat_name, 'NUM_CPU_CORES', o.value) Cores,
                       DECODE(o.stat_name, 'NUM_CPU_SOCKETS', o.value) Sockets,
                       DECODE(o.stat_name,
                              'PHYSICAL_MEMORY_BYTES',
                              trunc(o.value / 1024 / 1024 / 1024, 2)) Memory
                 WHERE o.stat_name IN
                       ('NUM_CPUS',
                        'NUM_CPU_CORES',
                        'NUM_CPU_SOCKETS',
                        'PHYSICAL_MEMORY_BYTES'))
                 GROUP BY t.instance_number)
         GROUP BY instance_number);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 18 for section: prompt Notes:
hc_q_prompt_notes_18() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_18_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN global_name NEW_VALUE _global_name NOPRINT
SELECT global_name global_name FROM global_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 19 for section: prompt Notes:
hc_q_prompt_notes_19() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_19_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN blocksize NEW_VALUE _blocksize NOPRINT
SELECT value blocksize FROM v$parameter WHERE name='db_block_size';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 20 for section: prompt Notes:
hc_q_prompt_notes_20() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_20_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN characterset NEW_VALUE _characterset NOPRINT
SELECT value$ characterset FROM sys.props$ WHERE name='NLS_CHARACTERSET';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 21 for section: prompt Notes:
hc_q_prompt_notes_21() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_21_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN timezone NEW_VALUE _timezone NOPRINT
SELECT d.version timezone FROM v$timezone_file d ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 22 for section: prompt Notes:
hc_q_prompt_notes_22() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_22_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN pdb NEW_VALUE _pdbs NOPRINT 
SELECT CASE
         WHEN COUNT(1) > 0 THEN
          'CDB,PDB' || COUNT(1) || ',:'||listagg(a.NAME,',') within group(order by a.CON_ID)
         ELSE
          'CDB'
       END pdb
  FROM v$pdbs a;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 23 for section: prompt Notes:
hc_q_prompt_notes_23() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_23_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN DGINFO NEW_VALUE _DGINFO NOPRINT
COLUMN DGINFO2 NEW_VALUE _DGINFO2 NOPRINT
SELECT case
         WHEN d.VALUE is null then
          'NO'
         else
          d.VALUE
       end DGINFO,
       case
         WHEN d.VALUE is null then
          'DG'
         else
          d.VALUE
       end DGINFO2
  FROM v$parameter d
 WHERE d.NAME = 'log_archive_config';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 24 for section: prompt Notes:
hc_q_prompt_notes_24() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_24_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN instance_name_all NEW_VALUE _instance_name_all NOPRINT
SELECT listagg(instance_name,',')  within group(order by instance_name) instance_name_all FROM gv$instance g;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 25 for section: prompt Notes:
hc_q_prompt_notes_25() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_25_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN cluster_database NEW_VALUE _cluster_database NOPRINT
SELECT value cluster_database FROM v$parameter WHERE name='cluster_database';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 26 for section: prompt Notes:
hc_q_prompt_notes_26() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_26_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN cluster_database_instances NEW_VALUE _cluster_database_instances NOPRINT
SELECT value cluster_database_instances FROM v$parameter WHERE name='cluster_database_instances';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 27 for section: prompt Notes:
hc_q_prompt_notes_27() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_27_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN rac_database NEW_VALUE _rac_database NOPRINT 
SELECT (SELECT value cluster_database
          FROM v$parameter
         WHERE name = 'cluster_database') || ' : ' ||
       (SELECT value cluster_database_instances
          FROM v$parameter
         WHERE name = 'cluster_database_instances') rac_database
  FROM DUAL;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 28 for section: prompt Notes:
hc_q_prompt_notes_28() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_28_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
WHERE d.instance_number = nd.INSTANCE_NUMBER
   AND  ROWNUM = 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 29 for section: prompt Notes:
hc_q_prompt_notes_29() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_29_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN v_SID NEW_VALUE _v_SID NOPRINT
COLUMN v_SERIAL# NEW_VALUE _v_SERIAL NOPRINT
COLUMN v_SPID NEW_VALUE _v_SPID NOPRINT
COLUMN v_sessionid NEW_VALUE _v_sessionid NOPRINT
SELECT a.SID v_SID,
       b.SERIAL# v_SERIAL#,
       c.SPID v_SPID,
       'INST_ID:'||b.INST_ID||',['||a.SID||','||b.SERIAL# ||','||c.SPID||']' v_sessionid  
FROM   v$mystat  a,
       gv$session b ,
       v$process c
WHERE  a.SID = b.SID
and b.PADDR=c.ADDR
AND    ROWNUM = 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 30 for section: prompt Notes:
hc_q_prompt_notes_30() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_30_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN  lie_v_tmpsize NEW_VALUE v_tmpsize NOPRINT 
COLUMN  lie_v_undosize NEW_VALUE v_undosize NOPRINT
COLUMN  lie_v_plan_cost NEW_VALUE v_plan_cost NOPRINT
COLUMN  lie_v_PLAN_CARDINALITY NEW_VALUE v_PLAN_CARDINALITY NOPRINT
COLUMN  lie_V_ELAPSED_TIME NEW_VALUE V_ELAPSED_TIME NOPRINT
COLUMN  lie_v_EXECUTIONS NEW_VALUE v_EXECUTIONS NOPRINT

--SELECT 50000485760 lie_v_tmpsize, --bytes  10485760=10M

--       50000485760 lie_v_undosize, --bytes

--       500485760   lie_v_plan_cost, --cost 

--       514600000   lie_v_PLAN_CARDINALITY, --

--       18000000000 lie_V_ELAPSED_TIME, ---,5,: 5h*60*60*1000000

--       10000       lie_v_EXECUTIONS --

--  FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 31 for section: prompt Notes:
hc_q_prompt_notes_31() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_31_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT round(SUM(bytes) / 2) lie_v_tmpsize
FROM v$tempfile d
WHERE d.STATUS = 'ONLINE';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 32 for section: prompt Notes:
hc_q_prompt_notes_32() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_32_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT round(SUM(BYTES) / 2) lie_v_undosize
FROM dba_data_files d, dba_tablespaces DT
WHERE DT.TABLESPACE_NAME = D.TABLESPACE_NAME
AND DT.CONTENTS = 'UNDO'
and dt.STATUS = 'ONLINE'
GROUP BY D.TABLESPACE_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 33 for section: prompt Notes:
hc_q_prompt_notes_33() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_33_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT round(max(a.COST) * 0.8) lie_v_plan_cost, round(max(a.CARDINALITY) * 0.8) lie_v_PLAN_CARDINALITY
FROM gv$sql_plan a
where a.OPERATION <> 'MERGE JOIN'
AND a.OPTIONS <> 'CARTESIAN';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 34 for section: prompt Notes:
hc_q_prompt_notes_34() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_34_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT round(max(a.ELAPSED_TIME /
                 (DECODE(a.EXECUTIONS, 0, 1, a.EXECUTIONS))) * 0.8)/1000000 LIE_V_ELAPSED_TIME,
       round(max(a.EXECUTIONS) * 0.8) lie_v_EXECUTIONS
  FROM GV$SQL a
 WHERE not exists (SELECT /*+use_hash(a,aa) leading(aa)*/  1
          FROM gv$sql_plan aa
         WHERE a.SQL_ID = aa.SQL_ID 
           AND  aa.INST_ID = a.INST_ID
           AND  aa.OPERATION = 'MERGE JOIN'
           AND  aa.OPTIONS = 'CARTESIAN');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 35 for section: prompt Notes:
hc_q_prompt_notes_35() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_35_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN  nls_language NEW_VALUE _nls_language NOPRINT 
SELECT d.VALUE nls_language FROM v$parameter d WHERE d.NAME='nls_language';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 36 for section: prompt Notes:
hc_q_prompt_notes_36() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_36_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN ALERTLOG_PATH NEW_VALUE _ALERTLOG_PATH NOPRINT
COLUMN v_osflag NEW_VALUE _v_osflag NOPRINT
SELECT 'alert_' || INSTANCE_NAME || '.log' ALERTLOG_NAME,
       (SELECT CASE
                 WHEN D.PLATFORM_NAME LIKE '%Microsoft%' THEN
                  CHR(92)
                 ELSE
                  CHR(47)
               END PLATFORM
          FROM V$DATABASE D) v_osflag,
       d.value||(SELECT CASE
                 WHEN D.PLATFORM_NAME LIKE '%Microsoft%' THEN
                  CHR(92)
                 ELSE
                  CHR(47)
               END PLATFORM
          FROM V$DATABASE D) || 'alert_' || INSTANCE_NAME || '.log' ALERTLOG_PATH
  FROM v$instance  T,V$DIAG_INFO D
	WHERE D.NAME = 'Diag Trace';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 37 for section: prompt Notes:
hc_q_prompt_notes_37() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_37_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN sqlid NEW_VALUE _sqlid NOPRINT
SELECT '''NULL''' sqlid FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 38 for section: prompt Notes:
hc_q_prompt_notes_38() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_38_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT '''' || nvl(sql_id,'null') || '''' sqlid
  FROM (SELECT d.sql_id
	     AND  d.sql_id IS NOT NULL	
 WHERE ROWNUM <= 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 39 for section: prompt Notes:
hc_q_prompt_notes_39() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_39_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN sqlid1 NEW_VALUE _sqlid1 NOPRINT
SELECT '''NULL''' sqlid1 FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 40 for section: prompt Notes:
hc_q_prompt_notes_40() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_40_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT '''' || nvl(sql_id, 'NULL') || '''' sqlid1
  FROM (SELECT d.SQL_ID
          FROM gv$sql_monitor d
         WHERE d.sql_id IS NOT NULL
         ORDER BY D.ELAPSED_TIME desc)
 WHERE ROWNUM <= 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 41 for section: prompt Notes:
hc_q_prompt_notes_41() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_41_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN GGS_GGSUSER_ROLE NEW_VALUE _GGS_GGSUSER_ROLE NOPRINT
SELECT 'NULL' GGS_GGSUSER_ROLE FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 42 for section: prompt Notes:
hc_q_prompt_notes_42() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_42_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT case
         WHEN SUM(count_gg) > 0 then
          'YES'
         ELSE
          'NO'
       END AS GGS_GGSUSER_ROLE
  FROM (SELECT count(D.ROLE) count_gg
          FROM cdb_roles d
         WHERE d.ROLE = 'GGS_GGSUSER_ROLE'
        UNION ALL 
        SELECT count(*)
          FROM cdb_users d
         WHERE d.username = 'GOLDENGATE');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 43 for section: prompt Notes:
hc_q_prompt_notes_43() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_43_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN DATABASE_SIZE NEW_VALUE _DATABASE_SIZE NOPRINT
WITH wt1 AS
 (SELECT ts.con_id,
         ts.TABLESPACE_NAME,
         df.all_bytes,
         DECODE(df.TYPE,
                'D',
                nvl(fs.FREESIZ, 0),
                'T',
                df.all_bytes - nvl(fs.FREESIZ, 0)) FREESIZ,
         df.MAXSIZ
    FROM cdb_tablespaces ts,
         (SELECT d.con_id,
                 'D' TYPE,
                 TABLESPACE_NAME,
                 COUNT(*) ts_df_count,
                 SUM(BYTES) all_bytes,
                 SUM(DECODE(MAXBYTES, 0, BYTES, MAXBYTES)) MAXSIZ
            FROM cdb_data_files d
           GROUP BY d.con_id, TABLESPACE_NAME
          UNION ALL
          SELECT d.con_id,
                 'T',
                 TABLESPACE_NAME,
                 COUNT(*) ts_df_count,
                 SUM(BYTES) all_bytes,
                 SUM(DECODE(MAXBYTES, 0, BYTES, MAXBYTES))
            FROM cdb_temp_files d
           GROUP BY d.con_id, TABLESPACE_NAME) df,
         (SELECT d.con_id, TABLESPACE_NAME, SUM(BYTES) FREESIZ
            FROM cdb_free_space d
           GROUP BY d.con_id, TABLESPACE_NAME
          UNION ALL
          SELECT d.con_id,
                 tablespace_name,
                 SUM(d.BLOCK_SIZE * a.BLOCKS) bytes
            FROM gv$sort_usage a, cdb_tablespaces d
           WHERE a.tablespace = d.tablespace_name
             and a.con_id = d.con_id
           GROUP BY d.con_id, tablespace_name) fs
   WHERE ts.TABLESPACE_NAME = df.TABLESPACE_NAME
     AND ts.TABLESPACE_NAME = fs.TABLESPACE_NAME(+)
     and ts.con_id = Df.con_id
     and ts.con_id = fs.con_id(+))
SELECT 'All TS Info:[ts_size:' ||
       round(SUM(t.all_bytes) / 1024 / 1024 / 1024, 2) || 'G , Used_Size:' ||
       round(SUM(t.all_bytes - t.FREESIZ) / 1024 / 1024 / 1024, 2) ||
       'G , Used_per:' ||
       round(SUM(t.all_bytes - t.FREESIZ) * 100 / SUM(t.all_bytes), 2) ||
       '% , MAX_Size:' || round(SUM(MAXSIZ) / 1024 / 1024 / 1024) || 'G]' DATABASE_SIZE
  FROM wt1 t;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 44 for section: prompt Notes:
hc_q_prompt_notes_44() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_44_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN recyclebin1 NEW_VALUE _recyclebin1 NOPRINT
SELECT '''NULL''' recyclebin1 FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 45 for section: prompt Notes:
hc_q_prompt_notes_45() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_45_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT ':' || a.VALUE || ',:' ||
       (SELECT round(SUM(a.space * (SELECT value
                                      FROM v$parameter
                                     WHERE name = 'db_block_size')) / 1024 / 1024,
                     2) || 'M,' || count(1) || 'Objects'
          FROM cdb_recyclebin a) recyclebin1
  FROM v$parameter a
 WHERE a.NAME = 'recyclebin';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 46 for section: prompt Notes:
hc_q_prompt_notes_46() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_46_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN TS_DELETE NEW_VALUE _TS_DELETE NOPRINT
SELECT listagg(all_bytes, ',') within group(order by all_bytes) TS_DELETE
  FROM (WITH wt1 AS (SELECT ts.TABLESPACE_NAME,
                            sum(df.all_bytes) all_bytes,
                            sum(DECODE(df.TYPE,
                                       'D',
                                       nvl(fs.FREESIZ, 0),
                                       'T',
                                       df.all_bytes - nvl(fs.FREESIZ, 0))) FREESIZ,
                            sum(df.MAXSIZ) MAXSIZ
                       FROM cdb_tablespaces ts,
                            (SELECT d.con_id,
                                    'D' TYPE,
                                    TABLESPACE_NAME,
                                    COUNT(*) ts_df_count,
                                    SUM(BYTES) all_bytes,
                                    SUM(DECODE(MAXBYTES, 0, BYTES, MAXBYTES)) MAXSIZ
                               FROM cdb_data_files d
                              WHERE D.tablespace_name IN ('SYSTEM', 'SYSAUX')
                                 OR D.tablespace_name like 'UNDO%'
                              GROUP BY d.con_id, TABLESPACE_NAME
                             UNION ALL
                             SELECT d.con_id,
                                    'T',
                                    TABLESPACE_NAME,
                                    COUNT(*) ts_df_count,
                                    SUM(BYTES) all_bytes,
                                    SUM(DECODE(MAXBYTES, 0, BYTES, MAXBYTES))
                               FROM cdb_temp_files d
                              GROUP BY d.con_id, TABLESPACE_NAME) df,
                            (SELECT d.con_id,
                                    TABLESPACE_NAME,
                                    SUM(BYTES) FREESIZ
                               FROM cdb_free_space D
                              WHERE D.tablespace_name IN ('SYSTEM', 'SYSAUX')
                                 OR D.tablespace_name like 'UNDO%'
                              GROUP BY d.con_id, TABLESPACE_NAME
                             UNION ALL
                             SELECT d.con_id,
                                    tablespace_name,
                                    SUM(d.BLOCK_SIZE * a.BLOCKS) bytes
                               FROM gv$sort_usage a, cdb_tablespaces d
                              WHERE a.tablespace = d.tablespace_name
                                and a.con_id = d.con_id
                              GROUP BY d.con_id, tablespace_name) fs
                      WHERE ts.TABLESPACE_NAME = df.TABLESPACE_NAME
                        AND ts.TABLESPACE_NAME = fs.TABLESPACE_NAME(+)
                        and ts.con_id = Df.con_id
                        and ts.con_id = fs.con_id(+)
                      group by ts.TABLESPACE_NAME)
         SELECT tablespace_name || ':' ||
                round((all_bytes - freesiz) / 1024 / 1024 / 1024) || '/' ||
                round(all_bytes / 1024 / 1024 / 1024) all_bytes
           FROM wt1 d
          ORDER BY tablespace_name) V;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 47 for section: prompt Notes:
hc_q_prompt_notes_47() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_47_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="database_version"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● PSU</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

col action_time   for a30
col action       for a10
col namespace     for a10
col version       for a10
col bundle_series for a10
col comments    for a30

SELECT d.con_id,
       to_char(d.action_time, 'YYYY-MM-DD HH24:MI:SS') action_time,
       d.action,
       d.namespace,
       d.id,
       
--d.bundle_series,
       d.comments
  FROM CDB_REGISTRY_HISTORY d
 order by d.con_id, d.action_time;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 48 for section: prompt Notes:
hc_q_prompt_notes_48() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_48_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="database_version"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

col IS_PUBLIC   for a10
SELECT * FROM gv$cluster_interconnects D;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 49 for section: prompt Notes:
hc_q_prompt_notes_49() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_49_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="instance_info"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name_print       FORMAT a75    HEADING ''       ENTMAP OFF
COLUMN instance_number_print     FORMAT a75    HEADING ''        ENTMAP OFF
COLUMN thread_number_print                     HEADING ''          ENTMAP OFF
COLUMN host_name_print           FORMAT a75    HEADING ''           ENTMAP OFF
COLUMN version                                 HEADING ''      ENTMAP OFF
COLUMN START_TIME                FORMAT a75    HEADING ''          ENTMAP OFF
COLUMN uptime                                  HEADING '()'    ENTMAP OFF
COLUMN parallel                  FORMAT a75    HEADING 'RAC'    ENTMAP OFF
COLUMN instance_status           FORMAT a75    HEADING ''     ENTMAP OFF
COLUMN database_status           FORMAT a75    HEADING ''     ENTMAP OFF
COLUMN logins                    FORMAT a75    HEADING ''              ENTMAP OFF
COLUMN archiver                  FORMAT a75    HEADING ''            ENTMAP OFF

SELECT '<div align="center"><font color="#336699"><b>' || INSTANCE_NAME ||
       '</b></font></div>' INSTANCE_NAME_PRINT,
       '<div align="center">' || INSTANCE_NUMBER || '</div>' INSTANCE_NUMBER_PRINT,
       '<div align="center">' || THREAD# || '</div>' THREAD_NUMBER_PRINT,
       '<div align="center">' || HOST_NAME || '</div>' HOST_NAME_PRINT,
       '<div align="center">' || VERSION || '</div>' VERSION,
       '<div align="center">' ||
       TO_CHAR(STARTUP_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' START_TIME,
       ROUND(TO_CHAR(SYSDATE - STARTUP_TIME), 2) UPTIME,
       '<div align="center">' || PARALLEL || '</div>' PARALLEL,
       '<div align="center">' || STATUS || '</div>' INSTANCE_STATUS,
       '<div align="center">' || LOGINS || '</div>' LOGINS,
       DECODE(ARCHIVER,
              'FAILED',
              '<div align="center"><b><font color="#990000">' || ARCHIVER ||
              '</font></b></div>',
              '<div align="center"><b><font color="darkgreen">' || ARCHIVER ||
              '</font></b></div>') ARCHIVER
  FROM GV$INSTANCE
 ORDER BY INSTANCE_NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 50 for section: prompt Notes:
hc_q_prompt_notes_50() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_50_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="database_overview"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
	

COLUMN name                            FORMAT a125    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;DB_NAME&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN dbid                                           HEADING 'DB_ID'                ENTMAP OFF
COLUMN db_unique_name                                 HEADING 'DB_Unique_Name'       ENTMAP OFF
COLUMN creation_date                   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN platform_name_print             FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PLATFORM_NAME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN current_scn                                    HEADING 'SCN'                ENTMAP OFF
COLUMN log_mode                                       HEADING ''                   ENTMAP OFF
COLUMN open_mode                       FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;OPEN_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'                  ENTMAP OFF
COLUMN force_logging                   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FORCE_LOGGING&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN flashback_on                                   HEADING 'Flashback?'              ENTMAP OFF
COLUMN controlfile_type                               HEADING 'Control File Type'           ENTMAP OFF
COLUMN SUPPLEMENTAL_LOG_DATA_MIN       FORMAT a25     HEADING 'SUPPLEMENTAL|LOG_DATA_MIN'  ENTMAP OFF
COLUMN SUPPLEMENTAL_LOG_DATA_PK        FORMAT a25     HEADING 'SUPPLEMENTAL|LOG_DATA_PK'  ENTMAP OFF
COLUMN SUPPLEMENTAL_LOG_DATA_MIN       FORMAT a25     HEADING 'SUPPLEMENTAL|LOG_DATA_MIN'  ENTMAP OFF
COLUMN last_open_incarnation#          FORMAT a50     HEADING 'LAST_OPEN|INCARNATION#'  ENTMAP OFF
COLUMN DATABASE_ROLE                   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DATABASE_ROLE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'                  ENTMAP OFF

SELECT d.INST_ID,
       '<div align="center"><font color="#336699"><b>' || NAME ||
       '</b></font></div>' NAME,
       '<div align="center">' || dbid || '</div>' dbid,
       '<div align="center">' || db_unique_name || '</div>' db_unique_name,
       '<div align="center">' || TO_CHAR(CREATED, 'yyyy-mm-dd HH24:MI:SS') ||
       '</div>' creation_date,
       '<div align="center">' || platform_name || '</div>' platform_name_print,
       '<div align="center">' || current_scn || '</div>' current_scn,
       '<div align="center">' || log_mode || '</div>' log_mode,
       '<div align="center">' || open_mode || '</div>' open_mode,
       '<div align="center">' || force_logging || '</div>' force_logging,
       '<div align="center">' || flashback_on || '</div>' flashback_on,
       '<div align="center">' || controlfile_type || '</div>' controlfile_type,
       '<div align="center">' || last_open_incarnation# || '</div>' last_open_incarnation#,
       d.DATABASE_ROLE,
       d.SUPPLEMENTAL_LOG_DATA_MIN,
       d.SUPPLEMENTAL_LOG_DATA_PK 
FROM   gv$database d;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 51 for section: prompt Notes:
hc_q_prompt_notes_51() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_51_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="pdb_overview"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● PDB</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.CON_ID,
       a.name,
       a.OPEN_MODE,
       a.RESTRICTED,
       a.DBID,
       a.GUID,
       a.CREATE_SCN,   
			 
--a.APPLICATION_ROOT,
			 
--a.APPLICATION_PDB,
			 
--a.APPLICATION_SEED,
			 
--a.APPLICATION_ROOT_CON_ID,
       
--to_char(a.CREATION_TIME, 'YYYY-MM-DD HH24:MI:SS') CREATION_TIME,
       to_char(a.OPEN_TIME, 'YYYY-MM-DD HH24:MI:SS') OPEN_TIME,
       round(a.TOTAL_SIZE/1024/1024) TOTAL_SIZE_M
  FROM v$containers a;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 52 for section: prompt Notes:
hc_q_prompt_notes_52() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_52_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
/*
SELECT a.con_id,
       a.name,
       a.open_mode,
       a.restricted,
       a.dbid,
       a.guid,
       to_char(a.OPEN_TIME,'YYYY-MM-DD HH24:MI:SS') OPEN_TIME,
       a.CREATE_SCN,
       a.TOTAL_SIZE
FROM   v$pdbs a;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 53 for section: prompt Notes:
hc_q_prompt_notes_53() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_53_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT a.con_id,
       a.name,
       a.open_mode,
       a.restricted,
       a.dbid,
       a.guid,
       to_char(a.OPEN_TIME,'YYYY-MM-DD HH24:MI:SS') OPEN_TIME
       a.CREATE_SCN,
       a.CREATION_TIME,
       a.TOTAL_SIZE,
       a.LOCAL_UNDO
FROM   v$pdbs a;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 54 for section: prompt Notes:
hc_q_prompt_notes_54() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_54_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
*/


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="awr_host_info"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN end_interval_time   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;End_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN begin_interval_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Begin_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN STARTUP_TIME   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;STARTUP_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN PLATFORM_NAME   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PLATFORM_NAME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

       BEGIN_INTERVAL_TIME,
       END_INTERVAL_TIME,
       DB_NAME,
       DBID,
       INSTANCE_NAME,
       INSTANCE_NUMBER,
       STARTUP_TIME,
       RELEASE,
       RAC,
       HOST_NAME,
       PLATFORM_NAME,
       CPUS,
       CORES,
       SOCKETS,
       MEMORY_G,
       ELAPSED_TIME,
       DB_TIME
               TO_CHAR(S.BEGIN_INTERVAL_TIME, 'YYYY-MM-DD HH24:MI:SS') BEGIN_INTERVAL_TIME,
               TO_CHAR(S.END_INTERVAL_TIME, 'YYYY-MM-DD HH24:MI:SS') END_INTERVAL_TIME,
               DB_NAME,
               S.DBID,
               INSTANCE_NAME,
               S.INSTANCE_NUMBER,
               TO_CHAR(S.STARTUP_TIME, 'YYYY-MM-DD hh24:MI:SS') STARTUP_TIME,
               VERSION RELEASE,
               PARALLEL RAC,
               HOST_NAME,
               DI.PLATFORM_NAME,
               V.CPUS CPUS,
               V.CORES,
               V.SOCKETS,
               V.MEMORY MEMORY_G,
               ROUND(EXTRACT(DAY FROM
                             S.END_INTERVAL_TIME - S.BEGIN_INTERVAL_TIME) * 1440 +
                     EXTRACT(HOUR FROM
                             S.END_INTERVAL_TIME - S.BEGIN_INTERVAL_TIME) * 60 +
                     EXTRACT(MINUTE FROM
                             S.END_INTERVAL_TIME - S.BEGIN_INTERVAL_TIME) +
                     EXTRACT(SECOND FROM
                             S.END_INTERVAL_TIME - S.BEGIN_INTERVAL_TIME) / 60,
                     2) ELAPSED_TIME,
               ROUND((E.VALUE - B.VALUE) / 1000000 / 60, 2) DB_TIME,
                           DBID,
                           INSTANCE_NUMBER,
                           SUM(CPUS) CPUS,
                           SUM(CORES) CORES,
                           SUM(SOCKETS) SOCKETS,
                           SUM(MEMORY) MEMORY
                                   O.DBID,
                                   O.INSTANCE_NUMBER,
                                   DECODE(O.STAT_NAME, 'NUM_CPUS', O.VALUE) CPUS,
                                   DECODE(O.STAT_NAME,
                                          'NUM_CPU_CORES',
                                          O.VALUE) CORES,
                                   DECODE(O.STAT_NAME,
                                          'NUM_CPU_SOCKETS',
                                          O.VALUE) SOCKETS,
                                   DECODE(O.STAT_NAME,
                                          'PHYSICAL_MEMORY_BYTES',
                                          TRUNC(O.VALUE / 1024 / 1024 / 1024,
                                                2)) MEMORY
                             WHERE O.STAT_NAME IN
                                   ('NUM_CPUS',
                                    'NUM_CPU_CORES',
                                    'NUM_CPU_SOCKETS',
                                    'PHYSICAL_MEMORY_BYTES'))
               S.INSTANCE_NUMBER = V.INSTANCE_NUMBER)
            ON (S.INSTANCE_NUMBER = DI.INSTANCE_NUMBER AND
               S.STARTUP_TIME = DI.STARTUP_TIME AND S.DBID = DI.DBID)
               E.INSTANCE_NUMBER = S.INSTANCE_NUMBER AND
               E.STAT_NAME = 'DB time')
               E.INSTANCE_NUMBER = B.INSTANCE_NUMBER))
 WHERE DRANK <= 10


prompt  <center>[<a class="noLink" href="#directory">BACK</a>] [<a class="noLink" href="#initial_parameter_info">Next Item</a>]</center>


prompt  <a name="DB_LOAD_PROFILE"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON


prompt  <center>[<a class="noLink" href="#awr_loadprofile"><font size=+1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:AWRin the viewload profile</b></font></a>]</center><p>


prompt  <center>[<a class="noLink" href="#directory">BACK</a>] [<a class="noLink" href="#initial_parameter_info">Next Item</a>]</center>


prompt  <a name="dbproperties_info"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SET DEFINE ON

SELECT D.CON_ID, D.PROPERTY_NAME, D.PROPERTY_VALUE, D.DESCRIPTION
  FROM cdb_properties D
 ORDER BY D.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 55 for section: prompt Notes:
hc_q_prompt_notes_55() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_55_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="database_size_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" color="#990000">NOTE</font></b>:   [<a class="noLink" href="#tablespaces_info"></a>]

CLEAR COLUMNS COMPUTES
SET DEFINE OFF


prompt  ● ts_datafile_physical_size_G,(temp)

prompt  ● ts_tempfile_physical_size_G

prompt  ● ts_datafile_used_size_G,,RMAN(as compressed)

select A.CON_ID,
       A.ts_datafile_physical_size_G,
       B.ts_tempfile_physical_size_G,
       C.ts_datafile_used_size_G
  FROM (select A.CON_ID,
               round(sum(bytes) / 1024 / 1024 / 1024, 2) ts_datafile_physical_size_G
          from CDB_data_files A
         GROUP BY A.CON_ID) A,
       (select A.CON_ID,
               round(sum(bytes) / 1024 / 1024 / 1024, 2) ts_tempfile_physical_size_G
          from CDB_temp_files A
         GROUP BY A.CON_ID) B,
       (select A.CON_ID,
               round(sum(bytes) / 1024 / 1024 / 1024, 2) ts_datafile_used_size_G
          from CDB_segments A
         GROUP BY A.CON_ID) C
 WHERE A.CON_ID = B.CON_ID
   AND A.CON_ID = C.CON_ID
   ORDER BY con_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 56 for section: prompt Notes:
hc_q_prompt_notes_56() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_56_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <br/>


prompt  <a name="client_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT sys_context('USERENV', 'ACTION') ACTION,
       sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AUTHENTICATED_IDENTITY,
       
--sys_context('USERENV', 'AUTHENTICATION_TYPE') AUTHENTICATION_TYPE, 
       sys_context('USERENV', 'AUTHENTICATION_METHOD') AUTHENTICATION_METHOD,   
       sys_context('USERENV', 'CURRENT_EDITION_NAME') CURRENT_EDITION_NAME,
       sys_context('USERENV', 'CURRENT_SCHEMA') CURRENT_SCHEMA, 
       sys_context('USERENV', 'CURRENT_USER') CURRENT_USER, 
       sys_context('USERENV', 'DATABASE_ROLE') DATABASE_ROLE, 
       sys_context('USERENV', 'DB_NAME') DB_NAME,
       sys_context('USERENV', 'DB_UNIQUE_NAME') DB_UNIQUE_NAME,  
       sys_context('USERENV', 'HOST') HOST, 
-- userenv('terminal') 
       sys_context('USERENV', 'IDENTIFICATION_TYPE') IDENTIFICATION_TYPE,
       sys_context('USERENV', 'INSTANCE') INSTANCE, 
--userenv('INSTANCE')
       sys_context('USERENV', 'INSTANCE_NAME') INSTANCE_NAME,
       sys_context('USERENV', 'IP_ADDRESS') IP_ADDRESS, 
--ora_client_ip_address
       sys_context('USERENV', 'ISDBA') ISDBA, 
--userenv('ISDBA')
       sys_context('USERENV', 'LANG') LANG, 
--userenv('LANG')
       sys_context('USERENV', 'LANGUAGE') LANGUAGE, 
--userenv('LANGUAGE'),
       sys_context('USERENV', 'MODULE') MODULE,
       sys_context('USERENV', 'NETWORK_PROTOCOL') NETWORK_PROTOCOL,
       sys_context('USERENV', 'NLS_CALENDAR') NLS_CALENDAR,
       sys_context('USERENV', 'NLS_CURRENCY') NLS_CURRENCY,
       sys_context('USERENV', 'NLS_DATE_FORMAT') NLS_DATE_FORMAT,
       sys_context('USERENV', 'NLS_DATE_LANGUAGE') NLS_DATE_LANGUAGE,
       sys_context('USERENV', 'NLS_SORT') NLS_SORT,
       sys_context('USERENV', 'NLS_TERRITORY') NLS_TERRITORY,
       sys_context('USERENV', 'OS_USER') OS_USER, 
       sys_context('USERENV', 'SERVER_HOST') SERVER_HOST,
       sys_context('USERENV', 'SERVICE_NAME') SERVICE_NAME,
       sys_context('USERENV', 'SESSION_EDITION_ID') SESSION_EDITION_ID,
       sys_context('USERENV', 'SESSION_EDITION_NAME') SESSION_EDITION_NAME,
       sys_context('USERENV', 'SESSION_USER') SESSION_USER, 
--ora_login_user 
       sys_context('USERENV', 'SESSIONID') SESSIONID, 
--  userenv('SESSIONID') , v$session.audsid
       sys_context('USERENV', 'SID') SID, 
       sys_context('USERENV', 'TERMINAL') TERMINAL 
--userenv('terminal')
  FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 57 for section: prompt Notes:
hc_q_prompt_notes_57() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_57_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <br/>


prompt  <a name="resource_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN RESOURCE_NAME        FORMAT a75    HEADING ''    ENTMAP OFF	
COLUMN CURRENT_UTILIZATION  FORMAT 999,999,999,999,999    HEADING ''      ENTMAP OFF
COLUMN MAX_UTILIZATION		  FORMAT 999,999,999,999,999    HEADING ''      ENTMAP OFF
COLUMN INITIAL_ALLOCATION   FORMAT 999,999,999,999,999    HEADING ''      ENTMAP OFF
COLUMN LIMIT_VALUE          FORMAT 999,999,999,999,999    HEADING 'Limit Value'      ENTMAP OFF

SELECT a.con_id,
       a.inst_id,
       a.resource_name,
       a.current_utilization,
       a.max_utilization,
       a.initial_allocation,
       a.limit_value
  FROM gv$resource_limit a
 order by a.con_id, a.inst_id, a.resource_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 58 for section: prompt Notes:
hc_q_prompt_notes_58() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_58_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <br/>


--------------------------------------------------------------------


prompt  <a name="db_option_REGISTRY"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


-- +----------------------------------------------------------------------------+

-- |                                 - OPTIONS -                                |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="options"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Options</b></font><hr align="left" width="450">
 
CLEAR COLUMNS  COMPUTES
SET DEFINE OFF

 
COLUMN parameter      HEADING 'Option Name'      ENTMAP OFF
COLUMN value          HEADING 'Installed?'       ENTMAP OFF
 
SELECT a.inst_id,
       DECODE(value,
              'FALSE',
              '<b><font color="#336699">' || parameter || '</font></b>',
              '<b><font color="#336699">' || parameter || '</font></b>') parameter,
       DECODE(value,
              'FALSE',
              '<div align="center"><font color="#990000"><b>' || value ||
              '</b></font></div>',
              '<div align="center">' || value || '</div>') value
  FROM gv$option a
 ORDER BY a.inst_id, parameter;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 59 for section: prompt Notes:
hc_q_prompt_notes_59() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_59_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                       - FEATURE USAGE STATISTICS -                         |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="feature_usage_statistics"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Feature Usage Statistics</b></font>[<a class="noLink" href="#high_water_mark_statistics">Next Item</a>] <hr align="left" width="450">
 
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN feature_name          FORMAT a115    HEADING 'Feature|Name'
COLUMN version               FORMAT a75     HEADING 'Version'
COLUMN detected_usages       FORMAT a75     HEADING 'Detected|Usages'
COLUMN total_samples         FORMAT a75     HEADING 'Total|Samples'
COLUMN currently_used        FORMAT a60     HEADING 'Currently|Used'
COLUMN first_usage_date      FORMAT a95     HEADING 'First Usage|Date'
COLUMN last_usage_date       FORMAT a95     HEADING 'Last Usage|Date'
COLUMN last_sample_date      FORMAT a95     HEADING 'Last Sample|Date'
COLUMN next_sample_date      FORMAT a95     HEADING 'Next Sample|Date'
 
SELECT d.CON_ID,
       '<div align="left"><font color="#336699"><b>' || name ||
       '</b></font></div>' feature_name,
       DECODE(detected_usages,
              0,
              version,
              '<font color="#663300"><b>' || version || '</b></font>') version,
       DECODE(detected_usages,
              0,
              '<div align="right">' || NVL(TO_CHAR(detected_usages), '<br>') ||
              '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR(detected_usages), '<br>') || '</b></font></div>') detected_usages,
       DECODE(detected_usages,
              0,
              '<div align="right">' || NVL(TO_CHAR(total_samples), '<br>') ||
              '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR(total_samples), '<br>') || '</b></font></div>') total_samples,
       DECODE(detected_usages,
              0,
              '<div align="center">' || NVL(currently_used, '<br>') ||
              '</div>',
              '<div align="center"><font color="#663300"><b>' ||
              NVL(currently_used, '<br>') || '</b></font></div>') currently_used,
       DECODE(detected_usages,
              0,
              '<div align="right">' ||
              NVL(TO_CHAR(first_usage_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR(first_usage_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</b></font></div>') first_usage_date,
       DECODE(detected_usages,
              0,
              '<div align="right">' ||
              NVL(TO_CHAR(last_usage_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR(last_usage_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</b></font></div>') last_usage_date,
       DECODE(detected_usages,
              0,
              '<div align="right">' ||
              NVL(TO_CHAR(last_sample_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR(last_sample_date, 'yyyY-MM-DD HH24:MI:SS'), '<br>') ||
              '</b></font></div>') last_sample_date,
       DECODE(detected_usages,
              0,
              '<div align="right">' ||
              NVL(TO_CHAR((last_sample_date + SAMPLE_INTERVAL / 60 / 60 / 24),
                          'yyyY-MM-DD HH24:MI:SS'),
                  '<br>') || '</div>',
              '<div align="right"><font color="#663300"><b>' ||
              NVL(TO_CHAR((last_sample_date + SAMPLE_INTERVAL / 60 / 60 / 24),
                          'yyyY-MM-DD HH24:MI:SS'),
                  '<br>') || '</b></font></div>') next_sample_date
  FROM cdb_feature_usage_statistics d
 ORDER BY d.CON_ID, name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 60 for section: prompt Notes:
hc_q_prompt_notes_60() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_60_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


-- +----------------------------------------------------------------------------+

-- |                      - HIGH WATER MARK STATISTICS -                        |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="high_water_mark_statistics"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● High Water Mark Statistics</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN statistic_name        FORMAT a115                    HEADING 'Statistic Name'
COLUMN version               FORMAT a62                     HEADING 'Version'
COLUMN highwater             FORMAT 9,999,999,999,999,999   HEADING 'Highwater'
COLUMN last_value            FORMAT 9,999,999,999,999,999   HEADING 'Last Value'
COLUMN description           FORMAT a120                    HEADING 'Description'
 

SELECT d.CON_ID,
       '<div align="left"><font color="#336699"><b>' || name ||
       '</b></font></div>' statistic_name,
       '<div align="right">' || version || '</div>' version,
       highwater highwater,
       last_value last_value,
       description description
  FROM cdb_high_water_mark_statistics d
 ORDER BY d.CON_ID, name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 61 for section: prompt Notes:
hc_q_prompt_notes_61() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_61_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


-- +----------------------------------------------------------------------------+

-- |                             - LIBRARIES -                                  |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_libraries_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Libraries</b></font>[<a class="noLink" href="#spfile_info">Next Item</a>] <hr align="left" width="600">
 
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner          FORMAT a75    HEADING 'Owner'             ENTMAP OFF
COLUMN library_name   FORMAT a75    HEADING 'Library Name'      ENTMAP OFF
COLUMN file_spec                    HEADING 'File Spec'         ENTMAP OFF
COLUMN dynamic        FORMAT a75    HEADING 'Dynamic?'          ENTMAP OFF
COLUMN status         FORMAT a75    HEADING 'Status'            ENTMAP OFF
 
 
SELECT D.CON_ID,
       '<div align="left"><font color="#336699"><b>' || owner ||
       '</b></font></div>' owner,
       '<b><font color="#663300">' || library_name || '</font></b>' library_name,
       file_spec file_spec,
       '<div align="center">' || dynamic || '</div>' dynamic,
       DECODE(status,
              'VALID',
              '<div align="center"><font color="darkgreen"><b>' || status ||
              '</b></font></div>',
              '<div align="center"><font color="#990000"><b>' || status ||
              '</b></font></div>') status
  FROM CDB_libraries D
 ORDER BY D.CON_ID, owner, library_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 62 for section: prompt Notes:
hc_q_prompt_notes_62() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_62_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
  
 


-- +----------------------------------------------------------------------------+

-- |                       - INITIALIZATION PARAMETERS -                        |

-- +----------------------------------------------------------------------------+


prompt  <a name="spfile_info"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="initialization_parameters"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font>  [<a class="noLink" href="#initial_parameter_info">Next Item</a>] <hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN spfile  HEADING 'SPFILE Usage'

SELECT case
         WHEN d.VALUE IS NOT NULL then
          'This database ' || '<font color="#663300"><b>IS</b></font>' ||
          ' using an SPFILE.'
         else
          'This database ' || '<font color="#990000"><b>IS NOT</b></font>' ||
          ' using an SPFILE.'
       end AS sspfile
  FROM v$parameter d
 WHERE d.NAME = 'spfile';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 63 for section: prompt Notes:
hc_q_prompt_notes_63() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_63_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN pname                FORMAT a75    HEADING 'Parameter Name'    ENTMAP OFF
COLUMN instance_name_print  FORMAT a45    HEADING 'Instance_Name'     ENTMAP OFF
COLUMN value                FORMAT a75    HEADING 'Value'             ENTMAP OFF
COLUMN isdefault            FORMAT a75    HEADING 'Is Default?'       ENTMAP OFF
COLUMN issys_modifiable     FORMAT a75    HEADING 'Is Dynamic?'       ENTMAP OFF
COLUMN ISDEPRECATED     FORMAT a75    HEADING 'ISDEPRECATED'       ENTMAP OFF
COLUMN DESCRIPTION     FORMAT a200    HEADING 'DESCRIPTION                '       ENTMAP OFF

SELECT P.CON_ID,DECODE(p.isdefault,
              'FALSE',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>') pname,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || i.instance_name ||
              '</b></font>',
              i.instance_name) instance_name_print,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || SUBSTR(p.value, 0, 512) ||
              '</b></font>',
              SUBSTR(p.value, 0, 512)) value,
       p.DISPLAY_VALUE,
       DECODE(p.isdefault,
              'FALSE',
              '<div align="center"><font color="#663300"><b>' || p.isdefault ||
              '</b></font></div>',
              '<div align="center">' || p.isdefault || '</div>') isdefault,
       DECODE(p.isdefault,
              'FALSE',
              '<div align="right"><font color="#663300"><b>' ||
              p.issys_modifiable || '</b></font></div>',
              '<div align="right">' || p.issys_modifiable || '</div>') issys_modifiable,
       p.ISDEPRECATED,
       p.DESCRIPTION
  FROM gv$parameter p, gv$instance i
 WHERE p.inst_id = i.inst_id
 ORDER BY p.name, i.instance_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 64 for section: prompt Notes:
hc_q_prompt_notes_64() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_64_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>] [<a class="noLink" href="#initialization_parameters"></a>]</center><p>


prompt  <a name="Implicit_parameters"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>PDB</b></font></center><p> <hr align="left" width="600">

prompt  PDB CDB  PDB_SPFILE$  con_id difference, therefore, PDB  PDB_SPFILE$ ,V$SYSTEM_PARAMETERFetch

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 

COLUMN pname                FORMAT a75    HEADING 'Parameter Name'    ENTMAP OFF
COLUMN instance_name_print  FORMAT a45    HEADING 'Instance_Name'     ENTMAP OFF
COLUMN value                FORMAT a75    HEADING 'Value'             ENTMAP OFF
COLUMN isdefault            FORMAT a75    HEADING 'Is Default?'       ENTMAP OFF
COLUMN issys_modifiable     FORMAT a75    HEADING 'Is Dynamic?'       ENTMAP OFF
COLUMN ISDEPRECATED     FORMAT a75    HEADING 'ISDEPRECATED'       ENTMAP OFF
COLUMN DESCRIPTION     FORMAT a200    HEADING 'DESCRIPTION                '       ENTMAP OFF
SET DEFINE ON

select  a.pdb_uid ,  b.NAME ,  a.name ,  a.value$
   from  pdb_spfile$ a ,  v$pdbs b
  where  a.pdb_uid =  b.CON_UID
order by b.NAME ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 65 for section: prompt Notes:
hc_q_prompt_notes_65() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_65_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>] </center><p>
 


prompt  <br/>

prompt  <a name="initial_parameter_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN pname                FORMAT a75    HEADING ''    ENTMAP OFF
COLUMN instance_name_print  FORMAT a45    HEADING ''     ENTMAP OFF
COLUMN value                FORMAT a75    HEADING 'Parameter Value'             ENTMAP OFF

SELECT P.CON_ID,DECODE(p.isdefault,
              'FALSE',
              '<b><font color="#663300">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>') pname,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || i.instance_name ||
              '</b></font>',
              i.instance_name) instance_name_print,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || SUBSTR(p.value, 0, 512) ||
              '</b></font>',
              SUBSTR(p.value, 0, 512)) value
  FROM gv$parameter p, gv$instance i
 WHERE p.inst_id = i.inst_id
   AND  p.name in ('shared_pool_size','open_cursors','processes','job_queue_processes','sga_max_size','log_archive_dest_1', 'sessions','spfile','cpu_count','sga_target','db_cache_size','shared_pool_size','large_pool_size','java_pool_size','log_buffer','pga_aggregate_target','sort_area_size','db_block_size','optimizer_mode','cursor_sharing','open_cursors','optimizer_index_cost_adj','optimizer_index_caching','db_file_multiblock_read_count','hash_join_enabled','thread','instance_number','instance_name','local_listener','compatible','commit_point_strength','dblink_encrypt_login','distributed_lock_timeout','distributed_recovery_connection_hold_time','distributed_transactions','global_names','job_queue_interval','job_queue_processes','max_transaction_branches','open_links','open_links_per_instance','parallel_automatic_tuning','parallel_max_servers','parallel_min_servers','parallel_server_idle_time','processes','remote_dependencies_mode','replication_dependency_tracking','shared_pool_size','utl_file_dir','db_create_file_dest')
 ORDER BY p.name, i.instance_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 66 for section: prompt Notes:
hc_q_prompt_notes_66() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_66_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>
 


prompt  <a name="Implicit_parameters"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font></center><p> <hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 

COLUMN pname                FORMAT a75    HEADING 'Parameter Name'    ENTMAP OFF
COLUMN instance_name_print  FORMAT a45    HEADING 'Instance_Name'     ENTMAP OFF
COLUMN value                FORMAT a75    HEADING 'Value'             ENTMAP OFF
COLUMN isdefault            FORMAT a75    HEADING 'Is Default?'       ENTMAP OFF
COLUMN issys_modifiable     FORMAT a75    HEADING 'Is Dynamic?'       ENTMAP OFF
COLUMN ISDEPRECATED     FORMAT a75    HEADING 'ISDEPRECATED'       ENTMAP OFF
COLUMN DESCRIPTION     FORMAT a200    HEADING 'DESCRIPTION                '       ENTMAP OFF
SET DEFINE ON

SELECT P.CON_ID,
       DECODE(p.isdefault,
              'FALSE',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>') pname,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || i.instance_name ||
              '</b></font>',
              i.instance_name) instance_name_print,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || SUBSTR(p.value, 0, 512) ||
              '</b></font>',
              SUBSTR(p.value, 0, 512)) value,
       p.DISPLAY_VALUE,
       DECODE(p.isdefault,
              'FALSE',
              '<div align="center"><font color="#663300"><b>' || p.isdefault ||
              '</b></font></div>',
              '<div align="center">' || p.isdefault || '</div>') isdefault,
       DECODE(p.isdefault,
              'FALSE',
              '<div align="right"><font color="#663300"><b>' ||
              p.issys_modifiable || '</b></font></div>',
              '<div align="right">' || p.issys_modifiable || '</div>') issys_modifiable,
       p.ISDEPRECATED,
       p.DESCRIPTION
  FROM gv$parameter p, gv$instance i
 WHERE p.inst_id = i.inst_id
   AND p.NAME like '=_%' escape '='
 ORDER BY p.name, i.instance_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 67 for section: prompt Notes:
hc_q_prompt_notes_67() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_67_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>] </center><p>
 

 
 

-- +----------------------------------------------------------------------------+

-- |                          - STATISTICS LEVEL -                              |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="statistics_level"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Statistics Level</b></font><hr align="left" width="600">

 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print     FORMAT a20    HEADING 'Instance_Name'         ENTMAP OFF
COLUMN statistics_name         FORMAT a50    HEADING 'Statistics Name'       ENTMAP OFF
COLUMN session_status          FORMAT a20    HEADING 'Session Status'        ENTMAP OFF
COLUMN system_status           FORMAT a20    HEADING 'System Status'         ENTMAP OFF
COLUMN activation_level        FORMAT a20    HEADING 'Activation Level'      ENTMAP OFF
COLUMN statistics_view_name    FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;Statistics View Name&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN session_settable        FORMAT a20   HEADING 'Session Settable?'     ENTMAP OFF

SET DEFINE ON
 
SELECT
    '<div align="center"><font color="#336699"><b>' || i.instance_name    || '</b></font></div>'               instance_name_print
  , '<div align="left" nowrap>'                     || s.statistics_name  || '</div>'                          statistics_name
  ,DESCRIPTION
  , DECODE(   s.session_status
            , 'ENABLED'
            , '<div align="center"><b><font color="darkgreen">' || s.session_status || '</font></b></div>'
            , '<div align="center"><b><font color="#990000">'   || s.session_status || '</font></b></div>')    session_status
  , DECODE(   s.system_status
            , 'ENABLED'
            , '<div align="center"><b><font color="darkgreen">' || s.system_status || '</font></b></div>'
            , '<div align="center"><b><font color="#990000">'   || s.system_status || '</font></b></div>')     system_status
  , (CASE s.activation_level
         WHEN 'TYPICAL' THEN '<div align="center"><b><font color="darkgreen">' || s.activation_level || '</font></b></div>'
         WHEN 'ALL'     THEN '<div align="center"><b><font color="darkblue">'  || s.activation_level || '</font></b></div>'
         WHEN 'BASIC'   THEN '<div align="center"><b><font color="#990000">'   || s.activation_level || '</font></b></div>'
     ELSE
         '<div align="center"><b><font color="#663300">'   || s.activation_level || '</font></b></div>'
     END)                                                      activation_level
  , s.statistics_view_name                                     statistics_view_name
  , '<div align="center">' || s.session_settable || '</div>'   session_settable
FROM
    gv$statistics_level s
  , gv$instance  i
WHERE
      s.inst_id = i.inst_id
ORDER BY
    i.instance_name
  , s.statistics_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 68 for section: prompt Notes:
hc_q_prompt_notes_68() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_68_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


--------------------------------------------------------------------

host echo "            . . ." 

prompt  <a name="database_tablespace_qk"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="tablespaces_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN status                                  HEADING ''            ENTMAP OFF
COLUMN name                                    HEADING ''   ENTMAP OFF
COLUMN type        FORMAT a12                  HEADING ''           ENTMAP OFF
COLUMN extent_mgt  FORMAT a12                  HEADING ''         ENTMAP OFF
COLUMN segment_mgt FORMAT a12                   HEADING 'Segment Management Type'         ENTMAP OFF
COLUMN ts_size     FORMAT 999,999,999,999,999  HEADING '(MB)'   ENTMAP OFF
COLUMN free        FORMAT 999,999,999,999,999  HEADING '(MB)'   ENTMAP OFF
COLUMN used        FORMAT 999,999,999,999,999  HEADING '(MB)'   ENTMAP OFF
COLUMN pct_used                                HEADING 'Pct. Used'         ENTMAP OFF
COLUMN BIGFILE        FORMAT a10  HEADING 'BIGFILE'   ENTMAP OFF
	

COMPUTE SUM label '<font color="#990000"><b>Total:</b></font>'   OF ts_size used free ON report

SELECT CON_ID,
       PDBNAME,
       TS#,
       TS_NAME,
       TS_SIZE_M,
       FREE_SIZE_M,
       USED_SIZE_M,
       USED_PER,
       MAX_SIZE_G,
       USED_PER_MAX,
       BLOCK_SIZE,
       LOGGING,
       TS_DF_COUNT
FROM   (WITH wt1 AS (SELECT ts.CON_ID,
                            (SELECT np.NAME
                             FROM   V$CONTAINERS np
                             WHERE  np.CON_ID = tS.con_id) PDBNAME,
                            (SELECT A.TS#
                             FROM   V$TABLESPACE A
                             WHERE  A.NAME = UPPER(tS.TABLESPACE_NAME)
                             AND    a.CON_ID = tS.con_id) TS#,
                            ts.TABLESPACE_NAME,
                            df.all_bytes,
                            decode(df.TYPE,
                                   'D',
                                   nvl(fs.FREESIZ, 0),
                                   'T',
                                   df.all_bytes - nvl(fs.FREESIZ, 0)) FREESIZ,
                            df.MAXSIZ,
                            ts.BLOCK_SIZE,
                            ts.LOGGING,
                            ts.FORCE_LOGGING,
                            ts.CONTENTS,
                            ts.EXTENT_MANAGEMENT,
                            ts.SEGMENT_SPACE_MANAGEMENT,
                            ts.RETENTION,
                            ts.DEF_TAB_COMPRESSION,
                            df.ts_df_count
                     FROM   cdb_tablespaces ts,
                            (SELECT d.CON_ID,
                                    'D' TYPE,
                                    TABLESPACE_NAME,
                                    COUNT(*) ts_df_count,
                                    SUM(BYTES) all_bytes,
                                    SUM(decode(MAXBYTES, 0, BYTES, MAXBYTES)) MAXSIZ
                             FROM   cdb_data_files d
                             GROUP  BY d.CON_ID,
                                       TABLESPACE_NAME
                             UNION ALL
                             SELECT d.CON_ID,
                                    'T',
                                    TABLESPACE_NAME,
                                    COUNT(*) ts_df_count,
                                    SUM(BYTES) all_bytes,
                                    SUM(decode(MAXBYTES, 0, BYTES, MAXBYTES))
                             FROM   cdb_temp_files d
                             GROUP  BY d.CON_ID,
                                       TABLESPACE_NAME) df,
                            (SELECT d.CON_ID,
                                    TABLESPACE_NAME,
                                    SUM(BYTES) FREESIZ
                             FROM   cdb_free_space d
                             GROUP  BY d.CON_ID,
                                       TABLESPACE_NAME
                             UNION ALL
                             SELECT d.CON_ID,
                                    tablespace_name,
                                    SUM(d.BLOCK_SIZE * a.BLOCKS) bytes
                             FROM   gv$sort_usage   a,
                                    cdb_tablespaces d
                             WHERE  a.tablespace = d.tablespace_name
                             AND    a.CON_ID = d.CON_ID
                             GROUP  BY d.CON_ID,
                                       tablespace_name) fs
                     WHERE  ts.TABLESPACE_NAME = df.TABLESPACE_NAME
                     AND    ts.CON_ID = df.CON_ID
                     AND    ts.TABLESPACE_NAME = fs.TABLESPACE_NAME(+)
                     AND    ts.CON_ID = fs.CON_ID(+))
           SELECT T.CON_ID,
                  (CASE
                      WHEN T.PDBNAME = LAG(T.PDBNAME, 1)
                       OVER(PARTITION BY T.PDBNAME ORDER BY TS#) THEN
                       NULL
                      ELSE
                       T.PDBNAME
                  END) PDBNAME,
                  TS#,
                  t.TABLESPACE_NAME TS_Name,
                  round(t.all_bytes / 1024 / 1024) ts_size_M,
                  round(t.freesiz / 1024 / 1024) Free_Size_M,
                  round((t.all_bytes - t.FREESIZ) / 1024 / 1024) Used_Size_M,
                  round((t.all_bytes - t.FREESIZ) * 100 / t.all_bytes, 3) Used_per,
                  round(MAXSIZ / 1024 / 1024 / 1024, 3) MAX_Size_g,
                  round(decode(MAXSIZ,
                               0,
                               to_number(NULL),
                               (t.all_bytes - FREESIZ)) * 100 / MAXSIZ,
                        3) USED_per_MAX,
                  round(t.BLOCK_SIZE) BLOCK_SIZE,
                  t.LOGGING,
                  t.ts_df_count
           FROM   wt1 t
           UNION ALL
           SELECT DISTINCT T.CON_ID,
                  '' PDBNAME,
                  to_number('') TS#,
                  'ALL TS:' TS_Name,
                  round(SUM(t.all_bytes) / 1024 / 1024, 3) ts_size_M,
                  round(SUM(t.freesiz) / 1024 / 1024) Free_Size_m,
                  round(SUM(t.all_bytes - t.FREESIZ) / 1024 / 1024) Used_Size_M,
                  round(SUM(t.all_bytes - t.FREESIZ) * 100 /
                        SUM(t.all_bytes),
                        3) Used_per,
                  round(SUM(MAXSIZ) / 1024 / 1024 / 1024) MAX_Size,
                  to_number('') "USED,% of MAX Size",
                  to_number('') BLOCK_SIZE,
                  '' LOGGING,
                  to_number('') ts_df_count
           FROM   wt1 t
           GROUP  BY rollup(CON_ID,PDBNAME)
)  
ORDER  BY CON_ID,TS# ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 69 for section: prompt Notes:
hc_q_prompt_notes_69() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_69_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● SYSAUXDetails</b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT D.CON_ID,
       OCCUPANT_NAME,
       OCCUPANT_DESC,
       SCHEMA_NAME,
       MOVE_PROCEDURE,
       MOVE_PROCEDURE_DESC,
       SPACE_USAGE_KBYTES SPACE_USAGE_KB,
       ROUND(SPACE_USAGE_KBYTES / 1024 / 1024, 2) SPACE_USAGE_G
  FROM V$SYSAUX_OCCUPANTS D
 ORDER BY D.CON_ID, D.SPACE_USAGE_KBYTES DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 70 for section: prompt Notes:
hc_q_prompt_notes_70() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_70_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>

 

-- +----------------------------------------------------------------------------+

-- |                          - DATABASE GROWTH -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="database_growth"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>(Database Growth)</b></font><hr align="left" width="500">


prompt  <font size="1" face="Courier New,Helvetica,Geneva,sans-serif" color="#990000">NOTE: cdb_hist_seg_statcdb_hist_seg_stat_obj</font>

 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

       a.con_id,
	   e.name pdbname,
       c.tablespace_name ts_name,
       to_char(to_date(a.rtime, 'mm/dd/yyyy hh24:mi:ss'), 'yyyy-mm-dd hh24:mi') rtime,
       round(a.tablespace_size * c.block_size / 1024 / 1024, 2) ts_size_mb,
       round(a.tablespace_usedsize * c.block_size / 1024 / 1024, 2) ts_used_mb,
       round((a.tablespace_size - a.tablespace_usedsize) * c.block_size / 1024 / 1024,
             2) ts_free_mb,
       round(a.tablespace_usedsize / a.tablespace_size * 100, 2) pct_used
  FROM cdb_hist_tbspc_space_usage a, 
       (SELECT tablespace_id,
			         nb.con_id,
               substr(rtime, 1, 10) rtime,
          FROM cdb_hist_tbspc_space_usage nb
         group by tablespace_id, nb.con_id,substr(rtime, 1, 10)) b,
				 cdb_tablespaces c,
				 v$tablespace d,
				 V$CONTAINERS e
   and a.tablespace_id = b.tablespace_id
	 and a.con_id=b.con_id
	 and a.con_id=c.con_id
	 and a.con_id=d.con_id
	 and a.con_id=e.con_id
	 and a.tablespace_id=d.TS#
	 and d.NAME=c.tablespace_name
	 and  to_date(a.rtime, 'mm/dd/yyyy hh24:mi:ss') >=sysdate-30
   order by a.CON_ID,a.tablespace_id,to_date(a.rtime, 'mm/dd/yyyy hh24:mi:ss') desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 71 for section: prompt Notes:
hc_q_prompt_notes_71() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_71_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <a name="flash_usage"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b> Flashback Database</b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Flashback Database</b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT NAME,                    
       round(space_limit / 1024 / 1024 / 1024, 3) "LIMIT_GB",                   
       round(space_used / 1024 / 1024 / 1024, 3) "USED_GB",                   
       round(space_used / space_limit * 100, 3) "USED%",                    
       round(space_reclaimable / 1024 / 1024 / 1024, 3) "RECLAIM_GB",                   
       number_of_files                 
FROM   v$recovery_file_dest v 
WHERE v.SPACE_LIMIT<>0;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 72 for section: prompt Notes:
hc_q_prompt_notes_72() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_72_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <a name="flash_usage_details"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Flashback Database</b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


---- BREAK ON report

--COMPUTE SUM label '<font color="#990000"><b>Total:</b></font>' OF USED_GB  percent_space_used percent_space_reclaimable RECLAIM_GB  number_of_files  ON report
SELECT nvl(frau.file_type,'<font color="#990000"><b>Total:</b></font>') file_type,
       sum(round(frau.percent_space_used / 100 * rfd.space_limit / 1024 / 1024 / 1024,3)) USED_GB,
       sum(frau.percent_space_used) percent_space_used,
       sum(frau.percent_space_reclaimable) percent_space_reclaimable,
       sum(round(frau.percent_space_reclaimable / 100 * rfd.space_limit / 1024 / 1024 / 1024,3)) RECLAIM_GB,
       sum(frau.number_of_files) number_of_files
FROM   v$flash_recovery_area_usage frau,
       v$recovery_file_dest        rfd
 GROUP  BY ROLLUP(file_type) 		
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 73 for section: prompt Notes:
hc_q_prompt_notes_73() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_73_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <a name="ts_temp_usage"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b> Tablespace Usage</b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT D.CON_ID, d.tablespace_name "Name",
       TO_CHAR(NVL(a.bytes / 1024 / 1024, 0), '99,999,990.900') "Size (M)",
       TO_CHAR(NVL(t.hwm, 0) / 1024 / 1024, '99999999.999') "HWM (M)",
       TO_CHAR(NVL(t.hwm / a.bytes * 100, 0), '990.00') "HWM % ",
       TO_CHAR(NVL(t.bytes / 1024 / 1024, 0), '99999999.999') "Using (M)",
       TO_CHAR(NVL(t.bytes / a.bytes * 100, 0), '990.00') "Using %"
  FROM CDB_tablespaces d,
       (SELECT A.CON_ID, tablespace_name, sum(bytes) bytes
          FROM CDB_temp_files A
         GROUP BY A.CON_ID, tablespace_name) a,
       (SELECT A.CON_ID, tablespace_name,
               sum(bytes_cached) hwm,
               sum(bytes_used) bytes
          FROM v$temp_extent_pool A
         GROUP BY A.CON_ID,  tablespace_name) t
 WHERE d.tablespace_name = a.tablespace_name(+)
   AND  d.tablespace_name = t.tablespace_name(+)  
	 AND D.CON_ID=A.CON_ID(+)  AND D.CON_ID=T.CON_ID(+)
   AND  d.extent_management = 'LOCAL'
   AND  d.contents = 'TEMPORARY';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 74 for section: prompt Notes:
hc_q_prompt_notes_74() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_74_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="ts_undo_usage"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b> UndoTablespace Usage</b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT r.name , rssize/1024/1024/1024 "RSSize(G)",
  s.sid,
  s.serial#,
  s.username ,
  s.status,
  s.sql_hash_value,
  s.SQL_ADDRESS,
  s.MACHINE,
  s.MODULE,
  substr(s.program, 1, 78) ,
  r.usn,
  hwmsize/1024/1024/1024,shrinks ,xacts
FROM sys.v_$session s,sys.v_$transaction t,sys.v_$rollname r, v$rollstat rs
WHERE t.addr = s.taddr AND  t.xidusn = r.usn AND  r.usn=rs.USN
ORDER BY rssize desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 75 for section: prompt Notes:
hc_q_prompt_notes_75() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_75_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="ts_tu_aflag"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>,</b></font><hr align="left" width="450">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,Geneva,sans-serif" color="#990000">NOTE</font>:<font color="red"> UndoTemp</font> </font></b>

prompt  


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN autoextensible          FORMAT a100   HEADING 'autoextensible'  ENTMAP OFF
COLUMN online_status          FORMAT a15   HEADING 'online_status'  ENTMAP OFF
SELECT t.con_id,
       t.FILE_ID,
       t.file_name,
       t.tablespace_name,
       (t.bytes) Undo_TS_SIZE,
       (DECODE(MAXBYTES, 0, BYTES, MAXBYTES)) MAXSIZE,
       DECODE(t.autoextensible,
              'YES',
              '<div align="center"><b><font color="red">' ||
              t.autoextensible || '</font></b></div>',
              t.autoextensible) autoextensible,
       round((t.INCREMENT_BY * 8 * 1024) / 1024 / 1024, 3) INCREMENT_BY_M,
       t.online_status,
       'alter database datafile ' || t.FILE_ID || '  autoextend off' exec_sql
  FROM cdb_data_files t
 WHERE tablespace_name like '%UNDO%'
 order by t.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 76 for section: prompt Notes:
hc_q_prompt_notes_76() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_76_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

COLUMN autoextensible          FORMAT a100   HEADING 'autoextensible'  ENTMAP OFF

SELECT t.CON_ID,
       t.FILE_ID,
       t.file_name,
       t.TABLESPACE_NAME,
       (t.bytes) Temp_TS_SIZE,
       (DECODE(MAXBYTES, 0, BYTES, MAXBYTES)) MAXSIZE,
       t.status,
       DECODE(t.autoextensible,
              'YES',
              '<div align="center"><b><font color="red">' ||
              t.autoextensible || '</font></b></div>',
              t.autoextensible) autoextensible,
       round((t.INCREMENT_BY * 8 * 1024) / 1024 / 1024, 3) INCREMENT_BY_M,
       'alter database tempfile ' || t.FILE_ID || '  autoextend off' exec_sql
  FROM cdb_temp_files t
 order by t.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 77 for section: prompt Notes:
hc_q_prompt_notes_77() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_77_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <br/>


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<     STORAGE    >>>>>                            |

-- |                                                                            |

-- +============================================================================+


-- +----------------------------------------------------------------------------+

-- |                            - DATA FILES -                                  |

-- +----------------------------------------------------------------------------+


prompt  <a name="data_files"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES

SET DEFINE OFF
COLUMN AUTOEXTENSIBLE   format a15    HEADING 'AUTOEXTENSIBLE'  ENTMAP OFF
COLUMN CREATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MAXBYTES      FORMAT 999,999,999,999,999   HEADING 'MAXBYTES'              ENTMAP OFF 
SET DEFINE ON

SELECT FILE_ID,
       CON_ID,
       (CASE
           WHEN T.PDBNAME = LAG(T.PDBNAME, 1)
            OVER(PARTITION BY T.PDBNAME ORDER BY TS#) THEN
            NULL
           ELSE
            T.PDBNAME
       END) PDBNAME,
       TS#,
       TABLESPACE_NAME,
       TS_SIZE_M,
       FILE_NAME,
       FILE_SIZE_M,
       FILE_MAX_SIZE_G,
       AUTOEXTENSIBLE,
       INCREMENT_M,
       AUTOEXTEND_RATIO,
       CREATION_TIME,
       INCREMENT_BY_BLOCK,
       BYTES,
       BLOCKS,
       MAXBYTES,
       MAXBLOCKS,
       USER_BYTES,
       USER_BLOCKS
FROM   (SELECT D.FILE_ID,
               D.CON_ID,
               (SELECT NP.NAME
                FROM   V$CONTAINERS NP
                WHERE  NP.CON_ID = D.CON_ID) PDBNAME,
               (SELECT A.TS#
                FROM   V$TABLESPACE A
                WHERE  A.NAME = UPPER(D.TABLESPACE_NAME)
                AND    A.CON_ID = D.CON_ID) TS#,
               D.TABLESPACE_NAME,
               (SELECT ROUND(SUM(NB.BYTES) / 1024 / 1024, 2)
                FROM   CDB_DATA_FILES NB
                WHERE  NB.TABLESPACE_NAME = D.TABLESPACE_NAME
                AND    NB.CON_ID = D.CON_ID) TS_SIZE_M,
               D.FILE_NAME,
               ROUND(D.BYTES / 1024 / 1024, 2) FILE_SIZE_M,
               ROUND(D.MAXBYTES / 1024 / 1024 / 1024, 2) FILE_MAX_SIZE_G,
               D.AUTOEXTENSIBLE,
               ROUND(D.INCREMENT_BY * 8 * 1024 / 1024 / 1024, 2) INCREMENT_M,
               ROUND(D.BYTES * 100 /
                     DECODE(D.MAXBYTES, 0, BYTES, D.MAXBYTES),
                     2) AUTOEXTEND_RATIO,
               (SELECT B.CREATION_TIME
                FROM   SYS.V_$DATAFILE B
                WHERE  B.FILE# = D.FILE_ID
                AND    B.CON_ID = D.CON_ID) CREATION_TIME,
               D.INCREMENT_BY INCREMENT_BY_BLOCK,
               D.BYTES,
               D.BLOCKS,
               D.MAXBYTES,
               D.MAXBLOCKS,
               D.USER_BYTES,
               D.USER_BLOCKS
        FROM   CDB_DATA_FILES D
        UNION ALL
        SELECT D.FILE_ID,
               D.CON_ID,
               (SELECT NP.NAME
                FROM   V$CONTAINERS NP
                WHERE  NP.CON_ID = D.CON_ID) PDBNAME,
               (SELECT A.TS#
                FROM   V$TABLESPACE A
                WHERE  A.NAME = UPPER(D.TABLESPACE_NAME)
                AND    A.CON_ID = D.CON_ID) TS#,
               D.TABLESPACE_NAME,
               (SELECT ROUND(SUM(NB.BYTES) / 1024 / 1024, 2)
                FROM   V$TEMPFILE NB
                WHERE  NB.NAME = D.FILE_NAME
                AND    NB.CON_ID = D.CON_ID) TS_SIZE,
               D.FILE_NAME,
               ROUND(D.BYTES / 1024 / 1024, 2) FILE_SIZE_M,
               ROUND(D.MAXBYTES / 1024 / 1024 / 1024, 2) FILE_MAX_SIZE_G,
               D.AUTOEXTENSIBLE,
               ROUND(D.INCREMENT_BY * 8 * 1024 / 1024 / 1024, 2) INCREMENT_M,
               ROUND(D.BYTES * 100 /
                     DECODE(D.MAXBYTES, 0, BYTES, D.MAXBYTES),
                     2) AUTOEXTEND_RATIO,
               (SELECT B.CREATION_TIME
                FROM   SYS.V_$DATAFILE B
                WHERE  B.FILE# = D.FILE_ID
                AND    B.CON_ID = D.CON_ID) CREATION_TIME,
               D.INCREMENT_BY INCREMENT_BY_BLOCK,
               D.BYTES,
               D.BLOCKS,
               D.MAXBYTES,
               D.MAXBLOCKS,
               D.USER_BYTES,
               D.USER_BLOCKS
        FROM   CDB_TEMP_FILES D)  T
ORDER  BY CON_ID,TS#,FILE_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 78 for section: prompt Notes:
hc_q_prompt_notes_78() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_78_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


------------------------------------------------------------------------------------------------------------------------------------------------


prompt  <a name="control_files_all"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Control File(Control Files) </b></font><hr align="left" width="600">
 
 

-- +----------------------------------------------------------------------------+

-- |                            - CONTROL FILES -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="control_files"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Control Files</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN name                           HEADING 'Controlfile Name'  ENTMAP OFF
COLUMN status           FORMAT a75    HEADING 'Status'            ENTMAP OFF
COLUMN file_size        FORMAT a75    HEADING 'File Size'         ENTMAP OFF
 
SELECT C.NAME NAME,
       DECODE(C.STATUS,
              NULL,
              '<div align="center"><b><font color="darkgreen">VALID</font></b></div>',
              '<div align="center"><b><font color="#663300">' || C.STATUS ||
              '</font></b></div>') STATUS,
       '<div align="right">' ||
       TO_CHAR(BLOCK_SIZE * FILE_SIZE_BLKS, '999,999,999,999') || '</div>' FILE_SIZE
  FROM V$CONTROLFILE C
 ORDER BY C.NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 79 for section: prompt Notes:
hc_q_prompt_notes_79() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_79_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                         - CONTROL FILE RECORDS -                           |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="control_file_records"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Control File Records</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN type           FORMAT          a95    HEADING 'Record Section Type'      ENTMAP OFF
COLUMN record_size    FORMAT       999,999   HEADING 'Record Size|(in bytes)'   ENTMAP OFF
COLUMN records_total  FORMAT       999,999   HEADING 'Records Allocated'        ENTMAP OFF
COLUMN bytes_alloc    FORMAT   999,999,999   HEADING 'Bytes Allocated'          ENTMAP OFF
COLUMN records_used   FORMAT       999,999   HEADING 'Records Used'             ENTMAP OFF
COLUMN bytes_used     FORMAT   999,999,999   HEADING 'Bytes Used'               ENTMAP OFF
COLUMN pct_used       FORMAT          B999   HEADING '% Used'                   ENTMAP OFF
COLUMN first_index                           HEADING 'First Index'              ENTMAP OFF
COLUMN last_index                            HEADING 'Last Index'               ENTMAP OFF
COLUMN last_recid                            HEADING 'Last RecID'               ENTMAP OFF
 
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>'   of record_size records_total bytes_alloc records_used bytes_used ON report
COMPUTE avg LABEL '<font color="#990000"><b>Average: </b></font>' of pct_used      ON report
 
SELECT
    '<div align="left"><font color="#336699"><b>' || type || '</b></font></div>'  type
  , record_size                                       record_size
  , records_total                                     records_total
  , (records_total * record_size)                     bytes_alloc
  , records_used                                      records_used
  , (records_used * record_size)                      bytes_used
  , NVL(records_used/records_total * 100, 0)          pct_used
  , first_index                                       first_index
  , last_index                                        last_index
  , last_recid                                        last_recid
FROM v$controlfile_record_section
ORDER BY type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 80 for section: prompt Notes:
hc_q_prompt_notes_80() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_80_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


--------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------------
host echo "            ASM. . ." 


prompt  <a name="database_asmdiskcheck"></a>

prompt  <font size="+2" color="00CCFF"><b>ASM</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="asm_disk"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASM</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF


--COMPUTE SUM label '<font color="#990000"><b>Total:</b></font>'   OF TOTAL_MB FREE_MB   ON report

SELECT a.con_id,
       a.inst_id ,
       a.GROUP_NUMBER,
       a.DISK_NUMBER,
       a.NAME,
       a.path,
       a.STATE,
       a.MOUNT_STATUS,
       a.TOTAL_MB,
       a.FREE_MB,
       a.CREATE_DATE,
       a.MOUNT_DATE,
       a.LIBRARY 
--,

--a.OS_MB
  FROM gV$ASM_DISK a
 ORDER BY a.con_id,a.inst_id, a.GROUP_NUMBER, a.DISK_NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 81 for section: prompt Notes:
hc_q_prompt_notes_81() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_81_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="asm_diskgroup"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASM</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF


--COMPUTE SUM label '<font color="#990000"><b>Total:</b></font>'   OF TOTAL_MB FREE_MB   ON report
SELECT di.CON_ID,
       di.inst_id,
       di.GROUP_NUMBER,
       di.NAME,
       di.BLOCK_SIZE,
       di.STATE,
       di.TYPE,
       di.TOTAL_MB,
       di.FREE_MB,
       di.COMPATIBILITY,
       
--di.VOTING_FILES,
       di.OFFLINE_DISKS
  FROM gv$asm_diskgroup di
 ORDER BY di.con_id, di.inst_id, di.GROUP_NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 82 for section: prompt Notes:
hc_q_prompt_notes_82() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_82_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="asm_diskgroupATTRIBUTE"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASM</b></font>[<a class="noLink" href="#asm_diskgroupinstance">Next Item</a>]<hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT * FROM gv$ASM_ATTRIBUTE d WHERE d.NAME NOT LIKE 'template.%' ORDER BY d.con_id,d.inst_id, d.GROUP_NUMBER,d.NAME ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 83 for section: prompt Notes:
hc_q_prompt_notes_83() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_83_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="asm_diskgroupinstance"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASM</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT * FROM gv$asm_client;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 84 for section: prompt Notes:
hc_q_prompt_notes_84() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_84_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


------------------------------------------------------------------------------------------------------------------------------------------------

host echo "            JOB. . ." 

prompt  <a name="database_jobs_yxqk"></a>

prompt  <font size="+2" color="00CCFF"><b>JOB</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="jobs_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● cdb_jobs </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN job_id     FORMAT a75             HEADING 'ID'           ENTMAP OFF
COLUMN username   FORMAT a75             HEADING ''             ENTMAP OFF
COLUMN what       FORMAT a100            HEADING ''             ENTMAP OFF
COLUMN next_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN interval   FORMAT a100             HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'         ENTMAP OFF
COLUMN last_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN failures   FORMAT a75             HEADING 'Failure Count'         ENTMAP OFF
COLUMN broken     FORMAT a75             HEADING '?'          ENTMAP OFF

SET DEFINE ON

SELECT d.CON_ID,
       DECODE(broken,
              'Y',
              '<b><font color="#990000"><div align="center">' || job ||
              '</div></font></b>',
              '<b><font color="#336699"><div align="center">' || job ||
              '</div></font></b>') job_id,
       DECODE(broken,
              'Y',
              '<b><font color="#990000">' || log_user || '</font></b>',
              log_user) username,
       DECODE(broken,
              'Y',
              '<b><font color="#990000">' || what || '</font></b>',
              what) what,
       DECODE(broken,
              'Y',
              '<div nowrap align="right"><b><font color="#990000">' ||
              NVL(TO_CHAR(next_date, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
              '</font></b></div>',
              '<div nowrap align="right">' ||
              NVL(TO_CHAR(next_date, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
              '</div>') next_date,
       DECODE(broken,
              'Y',
              '<b><font color="#990000">' || interval || '</font></b>',
              interval) interval,
       DECODE(broken,
              'Y',
              '<div nowrap align="right"><b><font color="#990000">' ||
              NVL(TO_CHAR(last_date, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
              '</font></b></div>',
              '<div nowrap align="right">' ||
              NVL(TO_CHAR(last_date, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
              '</div>') last_date,
       DECODE(broken,
              'Y',
              '<b><font color="#990000"><div align="center">' ||
              NVL(failures, 0) || '</div></font></b>',
              '<div align="center">' || NVL(failures, 0) || '</div>') failures,
       DECODE(broken,
              'Y',
              '<b><font color="#990000"><div align="center">' || broken ||
              '</div></font></b>',
              '<div align="center">' || broken || '</div>') broken
  FROM cdb_jobs d
 ORDER BY d.CON_ID, d.broken, d.JOB;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 85 for section: prompt Notes:
hc_q_prompt_notes_85() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_85_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● cdb_scheduler_jobs </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
	
COLUMN is_running  FORMAT a10    HEADING 'is_running'  ENTMAP OFF
COLUMN REPEAT_INTERVAL  FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;REPEAT_INTERVAL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN start_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN end_date     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN NEXT_RUN_DATE     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_RUN_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF	
COLUMN last_start_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_RUN_DURATION   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_RUN_DURATION&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN comments  FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;job_comments&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT j.CON_ID,
       j.JOB_CREATOR,
       j.OWNER,
       j.job_name,
       j.state job_STATE,
       DECODE(J.STATE, 'RUNNING', 'Y', 'N') is_running,
       j.job_type,
       j.job_action,
       j.JOB_STYLE,
       j.PROGRAM_OWNER,
       j.PROGRAM_NAME,
       j.schedule_type,
       j.repeat_interval,
       TO_CHAR(j.start_date, 'YYYY-MM-DD HH24:mi:ss') start_date,
       TO_CHAR(j.end_date, 'YYYY-MM-DD HH24:mi:ss') end_date,
       TO_CHAR(J.NEXT_RUN_DATE, 'YYYY-MM-DD HH24:mi:ss') NEXT_RUN_DATE,
       TO_CHAR(J.last_start_date, 'YYYY-MM-DD HH24:mi:ss') last_start_date,
       (J.LAST_RUN_DURATION) LAST_RUN_DURATION,
       j.run_count,
       j.NUMBER_OF_ARGUMENTS,
       j.ENABLED,
       j.AUTO_DROP,
       j.max_run_duration,
       j.max_failures,
       j.max_runs,
       j.LOGGING_LEVEL,
       j.SYSTEM is_systemjob,
       j.comments,
       RJ.running_instance,
       RJ.cpu_used,
       B.username,
       B.SID,
       B.SERIAL#,
       (SELECT nb.spid FROM gv$process nb WHERE nb.ADDR = b.SADDR and nb.inst_id=b.inst_id and nb.con_id=b.con_id) spid,
       b.STATUS,
       B.COMMAND,
       B.LOGON_TIME,
       B.OSUSER
  FROM cdb_scheduler_jobs j
  LEFT OUTER JOIN cdb_scheduler_running_jobs rj
    ON (j.JOB_NAME = rj.JOB_NAME and j.CON_ID = rj.CON_ID)
  LEFT OUTER JOIN gv$session b
    ON (rj.session_id = b.SID AND rj.RUNNING_INSTANCE = b.INST_ID and
       j.CON_ID = b.con_id)
 ORDER BY j.CON_ID, b.INST_ID, j.STATE, j.owner, j.JOB_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 86 for section: prompt Notes:
hc_q_prompt_notes_86() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_86_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <br/>


prompt  <a name="jobs_info_errores"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>jobError Message</b></font> [<a class="noLink" href="#database_rmanbackinfo">Next Item</a>]<hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: ,job3 </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN LOG_DATE   FORMAT a240    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOG_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN detail_ADDITIONAL_INFO   FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DETAIL_ADDITIONAL_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'
COLUMN log_ADDITIONAL_INFO   FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOG_ADDITIONAL_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF 
COLUMN run_duration   FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;run_duration&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'
COLUMN ACTUAL_START_DATE   FORMAT a240    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ACTUAL_START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF 

SET DEFINE ON 

SELECT *
  FROM (SELECT n.CON_ID,
               n.OWNER,
               n.log_id,
               n.job_name,
               n.job_class,
               TO_CHAR(n.log_date, 'YYYY-MM-DD HH24:mi:ss') LOG_DATE,
               n.OPERATION,
               n.status,
               jrd.error#,
               jrd.run_duration,
               TO_CHAR(jrd.ACTUAL_START_DATE, 'YYYY-MM-DD HH24:mi:ss') ACTUAL_START_DATE,
               jrd.INSTANCE_ID,
               jrd.SESSION_ID,
               jrd.SLAVE_PID,
               n.additional_info log_ADDITIONAL_INFO,
               jrd.ADDITIONAL_INFO detail_ADDITIONAL_INFO,
               DENSE_RANK() over(partition by n.OWNER, n.JOB_NAME ORDER BY n.LOG_ID desc) rank_order
          FROM cdb_scheduler_job_log N, cdb_scheduler_job_run_details jrd
         WHERE n.log_id = jrd.log_id(+)
           and n.CON_ID = jrd.CON_ID(+)
           AND n.STATUS <> 'SUCCEEDED'
           and n.job_name not like 'ORA$AT_OS_OPT_SY%'
           AND n.log_date >= sysdate - 7
         ORDER BY n.log_date DESC)
 WHERE rank_order <= 3;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 87 for section: prompt Notes:
hc_q_prompt_notes_87() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_87_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


-- +====================================================================================================================+

-- |

-- | <<<<<     Inspection     >>>>>                                         |

-- |                                                                                                                    |

-- +====================================================================================================================+

   
host echo  start...Inspection. .

prompt  <p>

prompt  <a name="check_detail"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u>Inspection</u></b></font></center>

prompt  <p>


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<     BACKUPS     >>>>>                           |

-- |                                                                            |

-- +============================================================================+

host echo "            RMAN. . ." 

prompt  <a name="database_rmanbackinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>RMAN</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="rman_backup_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" >● Last 20 RMAN backup jobs</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN backup_name           FORMAT a130   HEADING 'Backup Name'          ENTMAP OFF
COLUMN START_TIME            FORMAT a75    HEADING 'Start Time'           ENTMAP OFF
COLUMN elapsed_time          FORMAT a75    HEADING ''         ENTMAP OFF
COLUMN status                              HEADING ''               ENTMAP OFF
COLUMN input_type                          HEADING ''           ENTMAP OFF
COLUMN output_device_type                  HEADING ''       ENTMAP OFF
COLUMN input_size                          HEADING ''           ENTMAP OFF
COLUMN output_size                         HEADING ''          ENTMAP OFF
COLUMN INPUT_BYTES_PER_SEC                 HEADING 'IO'          ENTMAP OFF
COLUMN output_rate_per_sec                 HEADING 'IO'  ENTMAP OFF

SELECT '<div nowrap><b><font color="#336699">' || r.command_id ||
       '</font></b></div>' backup_name,
       '<div nowrap align="right">' ||
       TO_CHAR(r.START_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' START_TIME,
       '<div nowrap align="right">' || r.time_taken_display || '</div>' elapsed_time,
       ELAPSED_SECONDS,
       DECODE(r.status,
              'COMPLETED',
              '<div align="center"><b><font color="darkgreen">' || r.status ||
              '</font></b></div>',
              'RUNNING',
              '<div align="center"><b><font color="#000099">' || r.status ||
              '</font></b></div>',
              'FAILED',
              '<div align="center"><b><font color="#990000">' || r.status ||
              '</font></b></div>',
              '<div align="center"><b><font color="#663300">' || r.status ||
              '</font></b></div>') status,
       r.input_type input_type,
       r.output_device_type output_device_type,
       '<div nowrap align="right">' || r.input_bytes_display || '</div>' input_size,
       '<div nowrap align="right">' || r.output_bytes_display || '</div>' output_size,
       '<div nowrap align="right">' || r.INPUT_BYTES_PER_SEC_DISPLAY ||
       '</div>' INPUT_BYTES_PER_SEC,
       '<div nowrap align="right">' || r.output_bytes_per_sec_display ||
       '</div>' output_rate_per_sec
  FROM (SELECT command_id,
               START_TIME,
               time_taken_display,
               ELAPSED_SECONDS,
               status,
               input_type,
               output_device_type,
               input_bytes_display,
               INPUT_BYTES_PER_SEC_DISPLAY,
               output_bytes_display,
               output_bytes_per_sec_display
          FROM v$rman_backup_job_details a
         ORDER BY START_TIME DESC) r
 WHERE ROWNUM <= 20;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 88 for section: prompt Notes:
hc_q_prompt_notes_88() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_88_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" >● RMANBackup Efficiency</font></b>

prompt  ●  type  'aggregate'  EPS Column Value, if EPS Column value significantlyless than, 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT device_type device,
       TYPE,
       filename,
       to_char(open_time, 'yyyy-mm-dd hh24:mi:ss') open_time,
       to_char(close_time, 'yyyy-mm-dd hh24:mi:ss') close_time,
       elapsed_time elapse,
       round(effective_bytes_per_second / 1024 / 1024, 2) EPS_M
  FROM v$backup_async_io a
 where a.TYPE = 'AGGREGATE'
   and a.OPEN_TIME between sysdate - 1 and sysdate
   and a.EFFECTIVE_BYTES_PER_SECOND IS NOT NULL
 order by a.OPEN_TIME desc, a.SID, a.SERIAL;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 89 for section: prompt Notes:
hc_q_prompt_notes_89() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_89_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


-- +----------------------------------------------------------------------------+

-- |                           - RMAN CONFIGURATION -                           |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_configuration"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN </b></font><hr align="left" width="600">


prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" >● All non-default RMAN configuration settings</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN name     FORMAT a130   HEADING 'Name'   ENTMAP OFF
COLUMN value                  HEADING 'Value'  ENTMAP OFF

SELECT '<div nowrap><b><font color="#336699">' || name ||
       '</font></b></div>' name,
       value
  FROM v$rman_configuration
 ORDER BY name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 90 for section: prompt Notes:
hc_q_prompt_notes_90() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_90_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="rman_all_backupsetinfo"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMANAll Backups</b></font>[<a class="noLink" href="#rman_backupset_detail_info">Next Item</a>]<hr align="left" width="600">
 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN BACKUP_TYPE  FORMAT a80    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN KEEP_UNTIL   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KEEP_UNTIL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INCREMENTAL_LEVEL          HEADING 'INCREMENTAL|LEVEL'  ENTMAP OFF 
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT BS_key,
       BP_key,
       BACKUP_TYPE,
       INCREMENTAL_LEVEL, 
       START_TIME   START_TIME,  
       END_TIME,
       ELAPSED_TIME,
       piece_name, 
       bs_size,
       DEVICE_TYPE,
       TAG,
       CONTROLFILE_INCLUDED,
       bs_status,
       bs_compressed,
       KEEP,
       KEEP_UNTIL,
       KEEP_OPTIONS,
       sum(case
             WHEN datafileNAME IS NOT NULL then
              1
             else
              0
           end) datafiles,
       sum(case
             WHEN SEQUENCE# IS NOT NULL then
              1
             else
              0
           end) archivelog,
       sum(case
             WHEN DB_UNIQUE_NAME IS NOT NULL then
              1
             else
              0
           end) spfile,
       sum(case
             WHEN cf_CHECKPOINT_CHANGE# IS NOT NULL then
              1
             else
              0
           end) controlfile
  FROM (SELECT a.RECID BS_key,
       c.RECID BP_key,
       case
         WHEN a.backup_type = 'L' then
          '<div nowrap><font color="#990000">Archived Redo Logs</font></div>'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          '<div nowrap><font color="#000099">Datafile Full Backup</font></div>'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          '<div nowrap><font color="darkgreen">Incremental Backup</font></div>'
       end backup_type,
       case
         WHEN a.backup_type = 'L' then
          'Archived Redo Logs'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          'Datafile Full Backup'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          'Incremental Backup'
       end backup_type1,
       a.INCREMENTAL_LEVEL,
       round(aa.bs_bytes/1024/1024, 2) bs_size,
       TO_CHAR(a.START_TIME, 'YYYY-MM-DD HH24:MI:SS') START_TIME,
       TO_CHAR(a.COMPLETION_TIME, 'YYYY-MM-DD HH24:MI:SS') END_TIME,
       (round(a.ELAPSED_SECONDS)) ELAPSED_TIME,
       c.HANDLE piece_name,
       c.DEVICE_TYPE,
       c.TAG,
       aa.bs_status,
       aa.bs_compressed,
       a.CONTROLFILE_INCLUDED,
       a.KEEP,
       a.KEEP_UNTIL,
       a.KEEP_OPTIONS,
       
------ data file -------- 
       b.FILE#,
       b.INCREMENTAL_LEVEL df_INCREMENTAL_LEVEL,
       (SELECT nb.NAME FROM v$datafile nb WHERE nb.FILE# = b.FILE#) datafileNAME,
       b.USED_CHANGE_TRACKING,
       b.CHECKPOINT_CHANGE#||'' df_CHECKPOINT_CHANGE#,
       b.CHECKPOINT_TIME df_CHECKPOINT_TIME,
       
------ archive log file --------
       d.THREAD#,
       d.SEQUENCE#,
       d.RESETLOGS_CHANGE#,
       d.FIRST_CHANGE#,
       d.FIRST_TIME,
       d.NEXT_CHANGE#,
       d.NEXT_TIME,
       
------ spfile --------
       e.MODIFICATION_TIME,
       e.DB_UNIQUE_NAME,
       
------ control file --------
       f.CREATION_TIME,
       f.CHECKPOINT_CHANGE#||'' cf_CHECKPOINT_CHANGE#,
       f.CHECKPOINT_TIME    cf_CHECKPOINT_TIME,
       f.FILESIZE_DISPLAY
  FROM v$backup_set a
  LEFT OUTER JOIN v$backup_files aa
    on (aa.bs_key = a.RECID AND  aa.file_type = 'PIECE')
  LEFT OUTER JOIN v$backup_datafile b
    ON (a.SET_STAMP = b.SET_STAMP AND  a.SET_COUNT = b.SET_COUNT)
  LEFT OUTER JOIN v$backup_piece c
    ON (a.SET_STAMP = c.SET_STAMP AND  a.SET_COUNT = c.SET_COUNT)
  LEFT OUTER JOIN V$backup_Archivelog_Details D
    ON (d.BTYPE_KEY = a.RECID)
  LEFT OUTER JOIN v$backup_spfile e
    ON (a.SET_STAMP = e.SET_STAMP AND  a.SET_COUNT = e.SET_COUNT)
  LEFT OUTER JOIN v$backup_controlfile_details f
    ON (f.BTYPE_KEY = a.RECID)
  WHERE a.START_TIME>=SYSDATE - 15
 ORDER BY a.RECID, a.RECID, b.FILE#, d.THREAD#, d.SEQUENCE#)  v
 GROUP BY BS_key,
          BP_key,
          BACKUP_TYPE,
          INCREMENTAL_LEVEL,
          START_TIME,
          END_TIME,
          ELAPSED_TIME,
          piece_name,
          bs_size,
          DEVICE_TYPE,
          TAG,
          CONTROLFILE_INCLUDED,
          bs_status,
          bs_compressed,
          KEEP,
          KEEP_UNTIL,
          KEEP_OPTIONS
 ORDER BY BS_key, BP_key;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 91 for section: prompt Notes:
hc_q_prompt_notes_91() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_91_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="rman_backupset_detail_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMANAll BackupsDetails</b></font>[<a class="noLink" href="#rman_backup_sets">Next Item</a>]<hr align="left" width="600">

prompt  <font size="1" face="Courier New,Helvetica,Geneva,sans-serif" color="#990000">NOTE: </font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 

COLUMN BACKUP_TYPE  FORMAT a80    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INCREMENTAL_LEVEL          HEADING 'INCREMENTAL|LEVEL'  ENTMAP OFF 
COLUMN FIRST_TIME   FORMAT a240    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FIRST_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN NEXT_TIME   FORMAT a240    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN CREATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN df_CHECKPOINT_CHANGE#     FORMAT a50    HEADING 'DF_CHECKPOINT_CHANGE#'  ENTMAP OFF 
COLUMN KEEP_UNTIL   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KEEP_UNTIL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON
 

SELECT DISTINCT *
  FROM (SELECT BS_KEY,
               BP_KEY,
               BACKUP_TYPE,
               INCREMENTAL_LEVEL,
               BS_SIZE,
               START_TIME,
               END_TIME,
               ELAPSED_TIME,
               PIECE_NAME,
               DEVICE_TYPE,
               TAG,
               BS_STATUS,
               BS_COMPRESSED,
               CONTROLFILE_INCLUDED,
               KEEP,
               KEEP_UNTIL,
               KEEP_OPTIONS,
               FILE#,
               DF_INCREMENTAL_LEVEL,
               DATAFILENAME,
               USED_CHANGE_TRACKING,
               DF_CHECKPOINT_CHANGE#,
               DF_CHECKPOINT_TIME,
               THREAD#,
               SEQUENCE#,
               RESETLOGS_CHANGE#,
               FIRST_CHANGE#,
               FIRST_TIME,
               NEXT_CHANGE#,
               NEXT_TIME,
               MODIFICATION_TIME,
               DB_UNIQUE_NAME,
               CREATION_TIME,
               CF_CHECKPOINT_CHANGE#,
               CF_CHECKPOINT_TIME,
               FILESIZE_DISPLAY,
               DENSE_RANK() OVER(PARTITION BY BACKUP_TYPE ORDER BY START_TIME DESC) RANK_ORDER
          FROM (SELECT a.RECID BS_key,
       c.RECID BP_key,
       case
         WHEN a.backup_type = 'L' then
          '<div nowrap><font color="#990000">Archived Redo Logs</font></div>'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          '<div nowrap><font color="#000099">Datafile Full Backup</font></div>'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          '<div nowrap><font color="darkgreen">Incremental Backup</font></div>'
       end backup_type,
       case
         WHEN a.backup_type = 'L' then
          'Archived Redo Logs'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          'Datafile Full Backup'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          'Incremental Backup'
       end backup_type1,
       a.INCREMENTAL_LEVEL,
       round(aa.bs_bytes/1024/1024, 2) bs_size,
       TO_CHAR(a.START_TIME, 'YYYY-MM-DD HH24:MI:SS') START_TIME,
       TO_CHAR(a.COMPLETION_TIME, 'YYYY-MM-DD HH24:MI:SS') END_TIME,
       (round(a.ELAPSED_SECONDS)) ELAPSED_TIME,
       c.HANDLE piece_name,
       c.DEVICE_TYPE,
       c.TAG,
       aa.bs_status,
       aa.bs_compressed,
       a.CONTROLFILE_INCLUDED,
       a.KEEP,
       a.KEEP_UNTIL,
       a.KEEP_OPTIONS,
       
------ data file -------- 
       b.FILE#,
       b.INCREMENTAL_LEVEL df_INCREMENTAL_LEVEL,
       (SELECT nb.NAME FROM v$datafile nb WHERE nb.FILE# = b.FILE#) datafileNAME,
       b.USED_CHANGE_TRACKING,
       b.CHECKPOINT_CHANGE#||'' df_CHECKPOINT_CHANGE#,
       b.CHECKPOINT_TIME df_CHECKPOINT_TIME,
       
------ archive log file --------
       d.THREAD#,
       d.SEQUENCE#,
       d.RESETLOGS_CHANGE#,
       d.FIRST_CHANGE#,
       d.FIRST_TIME,
       d.NEXT_CHANGE#,
       d.NEXT_TIME,
       
------ spfile --------
       e.MODIFICATION_TIME,
       e.DB_UNIQUE_NAME,
       
------ control file --------
       f.CREATION_TIME,
       f.CHECKPOINT_CHANGE#||'' cf_CHECKPOINT_CHANGE#,
       f.CHECKPOINT_TIME    cf_CHECKPOINT_TIME,
       f.FILESIZE_DISPLAY
  FROM v$backup_set a
  LEFT OUTER JOIN v$backup_files aa
    on (aa.bs_key = a.RECID AND  aa.file_type = 'PIECE')
  LEFT OUTER JOIN v$backup_datafile b
    ON (a.SET_STAMP = b.SET_STAMP AND  a.SET_COUNT = b.SET_COUNT)
  LEFT OUTER JOIN v$backup_piece c
    ON (a.SET_STAMP = c.SET_STAMP AND  a.SET_COUNT = c.SET_COUNT)
  LEFT OUTER JOIN V$backup_Archivelog_Details D
    ON (d.BTYPE_KEY = a.RECID)
  LEFT OUTER JOIN v$backup_spfile e
    ON (a.SET_STAMP = e.SET_STAMP AND  a.SET_COUNT = e.SET_COUNT)
  LEFT OUTER JOIN v$backup_controlfile_details f
    ON (f.BTYPE_KEY = a.RECID)
  WHERE a.START_TIME>=SYSDATE - 15 
  AND A.BACKUP_TYPE<>'L'
 ORDER BY a.RECID, a.RECID, b.FILE#, d.THREAD#, d.SEQUENCE#)) A
 WHERE A.RANK_ORDER <= 10
 ORDER BY A.BS_KEY, A.BP_KEY, A.FILE#, A.THREAD#, A.SEQUENCE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 92 for section: prompt Notes:
hc_q_prompt_notes_92() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_92_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - RMAN BACKUP SETS -                             |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_backup_sets"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN bs_key                 FORMAT a75                    HEADING 'BS Key'                 ENTMAP OFF
COLUMN BACKUP_TYPE            FORMAT a80                    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN device_type                                          HEADING 'Device Type'            ENTMAP OFF
COLUMN controlfile_included   FORMAT a30                    HEADING 'Controlfile Included?'  ENTMAP OFF
COLUMN spfile_included        FORMAT a30                    HEADING 'SPFILE Included?'       ENTMAP OFF
COLUMN incremental_level                                    HEADING 'Incremental Level'      ENTMAP OFF
COLUMN pieces                 FORMAT 999,999,999,999        HEADING '# of Pieces'            ENTMAP OFF
COLUMN START_TIME             FORMAT a140                   HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN completion_time        FORMAT a180                   HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'             ENTMAP OFF
COLUMN elapsed_seconds        FORMAT 999,999,999,999,999    HEADING 'Elapsed Seconds'        ENTMAP OFF
COLUMN tag                                                  HEADING 'Tag'                    ENTMAP OFF
COLUMN block_size             FORMAT 999,999,999,999,999    HEADING 'Block Size'             ENTMAP OFF
COLUMN keep                   FORMAT a40                    HEADING 'Keep?'                  ENTMAP OFF
COLUMN keep_options           FORMAT a15                    HEADING 'Keep Options'           ENTMAP OFF
COLUMN KEEP_UNTIL   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KEEP_UNTIL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON


-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total:</b></font>' OF pieces elapsed_seconds ON report

SELECT '<div align="center"><font color="#336699"><b>' || BS.RECID ||
       '</b></font></div>' BS_KEY,
       DECODE(BACKUP_TYPE,
              'L',
              '<div nowrap><font color="#990000">Archived Redo Logs</font></div>',
              'D',
              '<div nowrap><font color="#000099">Datafile Full Backup</font></div>',
              'I',
              '<div nowrap><font color="darkgreen">Incremental Backup</font></div>') BACKUP_TYPE,
       '<div nowrap align="right">' || DEVICE_TYPE || '</div>' DEVICE_TYPE,
       '<div align="center">' ||
       DECODE(BS.CONTROLFILE_INCLUDED, 'NO', '-', BS.CONTROLFILE_INCLUDED) ||
       '</div>' CONTROLFILE_INCLUDED,
       '<div align="center">' || NVL(SP.SPFILE_INCLUDED, '-') || '</div>' SPFILE_INCLUDED,
       BS.INCREMENTAL_LEVEL INCREMENTAL_LEVEL,
       BS.PIECES PIECES,
       '<div nowrap align="right">' ||
       TO_CHAR(BS.START_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' START_TIME,
       '<div nowrap align="right">' ||
       TO_CHAR(BS.COMPLETION_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' COMPLETION_TIME,
       BS.ELAPSED_SECONDS ELAPSED_SECONDS,
       BP.TAG TAG,
       BS.BLOCK_SIZE BLOCK_SIZE,
       '<div align="center">' || BS.KEEP || '</div>' KEEP,
       '<div nowrap align="right">' ||
       NVL(TO_CHAR(BS.KEEP_UNTIL, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
       '</div>' KEEP_UNTIL,
       BS.KEEP_OPTIONS KEEP_OPTIONS
  FROM V$BACKUP_SET BS,
       (SELECT DISTINCT SET_STAMP, SET_COUNT, TAG, DEVICE_TYPE
          FROM V$BACKUP_PIECE
         WHERE STATUS IN ('A', 'X')) BP,
       (SELECT DISTINCT SET_STAMP, SET_COUNT, 'YES' SPFILE_INCLUDED
          FROM V$BACKUP_SPFILE) SP
 WHERE BS.SET_STAMP = BP.SET_STAMP
   AND BS.SET_COUNT = BP.SET_COUNT
   AND BS.SET_STAMP = SP.SET_STAMP(+)
   AND BS.SET_COUNT = SP.SET_COUNT(+)
   AND BS.START_TIME >= SYSDATE - 15
 ORDER BY BS.RECID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 93 for section: prompt Notes:
hc_q_prompt_notes_93() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_93_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          - RMAN BACKUP PIECES -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_backup_pieces"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMANBackup Pieces</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN bs_key              FORMAT a75                     HEADING 'BS Key'            ENTMAP OFF
COLUMN piece#                                             HEADING 'Piece #'           ENTMAP OFF
COLUMN copy#                                              HEADING 'Copy #'            ENTMAP OFF
COLUMN bp_key                                             HEADING 'BP Key'            ENTMAP OFF
COLUMN status                                             HEADING 'Status'            ENTMAP OFF
COLUMN handle                                             HEADING 'Handle'            ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN completion_time     FORMAT a75                     HEADING 'End Time'          ENTMAP OFF
COLUMN elapsed_seconds     FORMAT 999,999,999,999,999     HEADING 'Elapsed Seconds'   ENTMAP OFF
COLUMN deleted             FORMAT a10                     HEADING 'Deleted?'          ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON


---- BREAK ON bs_key

SELECT '<div align="center"><font color="#336699"><b>' || BS.RECID ||
       '</b></font></div>' BS_KEY,
       BP.PIECE# PIECE#,
       BP.COPY# COPY#,
       BP.RECID BP_KEY,
       DECODE(STATUS,
              'A',
              '<div nowrap align="center"><font color="darkgreen"><b>Available</b></font></div>',
              'D',
              '<div nowrap align="center"><font color="#000099"><b>Deleted</b></font></div>',
              'X',
              '<div nowrap align="center"><font color="#990000"><b>Expired</b></font></div>') STATUS,
       HANDLE HANDLE,
       '<div nowrap align="right">' ||
       TO_CHAR(BP.START_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' START_TIME,
       '<div nowrap align="right">' ||
       TO_CHAR(BP.COMPLETION_TIME, 'yyyy-mm-dd HH24:MI:SS') || '</div>' COMPLETION_TIME,
       BP.ELAPSED_SECONDS ELAPSED_SECONDS
  FROM V$BACKUP_SET BS, V$BACKUP_PIECE BP
 WHERE BS.SET_STAMP = BP.SET_STAMP
   AND BS.SET_COUNT = BP.SET_COUNT
   AND BP.STATUS IN ('A', 'X')
   AND BP.START_TIME>= SYSDATE - 15
 ORDER BY BS.RECID, PIECE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 94 for section: prompt Notes:
hc_q_prompt_notes_94() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_94_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                       - RMAN BACKUP CONTROL FILES -                        |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_backup_control_files"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN Control File</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" >● Available automatic control files within all available (and expired) backup sets</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN bs_key                 FORMAT a75                     HEADING 'BS Key'                 ENTMAP OFF
COLUMN piece#                                                HEADING 'Piece #'                ENTMAP OFF
COLUMN copy#                                                 HEADING 'Copy #'                 ENTMAP OFF
COLUMN bp_key                                                HEADING 'BP Key'                 ENTMAP OFF
COLUMN controlfile_included   FORMAT a75                     HEADING 'Controlfile Included?'  ENTMAP OFF
COLUMN status                                                HEADING 'Status'                 ENTMAP OFF
COLUMN handle                                                HEADING 'Handle'                 ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN completion_time        FORMAT a40                     HEADING 'End Time'               ENTMAP OFF
COLUMN elapsed_seconds        FORMAT 999,999,999,999,999     HEADING 'Elapsed Seconds'        ENTMAP OFF
COLUMN deleted                FORMAT a10                     HEADING 'Deleted?'               ENTMAP OFF
COLUMN KEEP_UNTIL   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KEEP_UNTIL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON


---- BREAK ON bs_key

SELECT '<div align="center"><font color="#336699"><b>' || BS.RECID ||
       '</b></font></div>' BS_KEY,
       BP.PIECE# PIECE#,
       BP.COPY# COPY#,
       BP.RECID BP_KEY,
       '<div align="center"><font color="#663300"><b>' ||
       DECODE(BS.CONTROLFILE_INCLUDED, 'NO', '-', BS.CONTROLFILE_INCLUDED) ||
       '</b></font></div>' CONTROLFILE_INCLUDED,
       DECODE(STATUS,
              'A',
              '<div nowrap align="center"><font color="darkgreen"><b>Available</b></font></div>',
              'D',
              '<div nowrap align="center"><font color="#000099"><b>Deleted</b></font></div>',
              'X',
              '<div nowrap align="center"><font color="#990000"><b>Expired</b></font></div>') STATUS,
       HANDLE HANDLE
  FROM V$BACKUP_SET BS, V$BACKUP_PIECE BP
 WHERE BS.SET_STAMP = BP.SET_STAMP
   AND BS.SET_COUNT = BP.SET_COUNT
   AND BP.STATUS IN ('A', 'X')
   AND BS.CONTROLFILE_INCLUDED != 'NO'
   AND BP.START_TIME >= SYSDATE - 15
 ORDER BY BS.RECID, PIECE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 95 for section: prompt Notes:
hc_q_prompt_notes_95() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_95_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN BACKUP_TYPE  FORMAT a80    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INCREMENTAL_LEVEL          HEADING 'INCREMENTAL|LEVEL'  ENTMAP OFF 
COLUMN FIRST_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FIRST_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN NEXT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN CREATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN KEEP_UNTIL   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KEEP_UNTIL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT A.BS_KEY,
       A.BP_KEY,
       A.BACKUP_TYPE,
       A.INCREMENTAL_LEVEL,
       A.BS_SIZE,
       A.START_TIME,
       A.END_TIME,
       A.ELAPSED_TIME,
       A.PIECE_NAME,
       A.DEVICE_TYPE,
       A.TAG,
       A.BS_STATUS,
       A.BS_COMPRESSED,
       A.CONTROLFILE_INCLUDED,
       A.KEEP,
       A.KEEP_UNTIL,
       A.KEEP_OPTIONS, 
       A.MODIFICATION_TIME,
       A.DB_UNIQUE_NAME,
       A.CREATION_TIME,
       A.CF_CHECKPOINT_CHANGE#,
       A.CF_CHECKPOINT_TIME,
       A.FILESIZE_DISPLAY
  FROM (SELECT a.RECID BS_key,
       c.RECID BP_key,
       case
         WHEN a.backup_type = 'L' then
          '<div nowrap><font color="#990000">Archived Redo Logs</font></div>'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          '<div nowrap><font color="#000099">Datafile Full Backup</font></div>'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          '<div nowrap><font color="darkgreen">Incremental Backup</font></div>'
       end backup_type,
       case
         WHEN a.backup_type = 'L' then
          'Archived Redo Logs'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          'Datafile Full Backup'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          'Incremental Backup'
       end backup_type1,
       a.INCREMENTAL_LEVEL,
       round(aa.bs_bytes/1024/1024, 2) bs_size,
       TO_CHAR(a.START_TIME, 'YYYY-MM-DD HH24:MI:SS') START_TIME,
       TO_CHAR(a.COMPLETION_TIME, 'YYYY-MM-DD HH24:MI:SS') END_TIME,
       (round(a.ELAPSED_SECONDS)) ELAPSED_TIME,
       c.HANDLE piece_name,
       c.DEVICE_TYPE,
       c.TAG,
       aa.bs_status,
       aa.bs_compressed,
       a.CONTROLFILE_INCLUDED,
       a.KEEP,
       a.KEEP_UNTIL,
       a.KEEP_OPTIONS,
       
------ data file -------- 
       b.FILE#,
       b.INCREMENTAL_LEVEL df_INCREMENTAL_LEVEL,
       (SELECT nb.NAME FROM v$datafile nb WHERE nb.FILE# = b.FILE#) datafileNAME,
       b.USED_CHANGE_TRACKING,
       b.CHECKPOINT_CHANGE#||'' df_CHECKPOINT_CHANGE#,
       b.CHECKPOINT_TIME df_CHECKPOINT_TIME,
       
------ archive log file --------
       d.THREAD#,
       d.SEQUENCE#,
       d.RESETLOGS_CHANGE#,
       d.FIRST_CHANGE#,
       d.FIRST_TIME,
       d.NEXT_CHANGE#,
       d.NEXT_TIME,
       
------ spfile --------
       e.MODIFICATION_TIME,
       e.DB_UNIQUE_NAME,
       
------ control file --------
       f.CREATION_TIME,
       f.CHECKPOINT_CHANGE#||'' cf_CHECKPOINT_CHANGE#,
       f.CHECKPOINT_TIME    cf_CHECKPOINT_TIME,
       f.FILESIZE_DISPLAY
  FROM v$backup_set a
  LEFT OUTER JOIN v$backup_files aa
    on (aa.bs_key = a.RECID AND  aa.file_type = 'PIECE')
  LEFT OUTER JOIN v$backup_datafile b
    ON (a.SET_STAMP = b.SET_STAMP AND  a.SET_COUNT = b.SET_COUNT)
  LEFT OUTER JOIN v$backup_piece c
    ON (a.SET_STAMP = c.SET_STAMP AND  a.SET_COUNT = c.SET_COUNT)
  LEFT OUTER JOIN V$backup_Archivelog_Details D
    ON (d.BTYPE_KEY = a.RECID)
  LEFT OUTER JOIN v$backup_spfile e
    ON (a.SET_STAMP = e.SET_STAMP AND  a.SET_COUNT = e.SET_COUNT)
  LEFT OUTER JOIN v$backup_controlfile_details f
    ON (f.BTYPE_KEY = a.RECID)
  WHERE a.START_TIME>=SYSDATE - 15
 ORDER BY a.RECID, a.RECID, b.FILE#, d.THREAD#, d.SEQUENCE#) A
  WHERE A.CF_CHECKPOINT_CHANGE# IS NOT NULL 	
 ORDER BY A.BS_KEY, A.BP_KEY, A.FILE#, A.THREAD#, A.SEQUENCE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 96 for section: prompt Notes:
hc_q_prompt_notes_96() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_96_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - RMAN BACKUP SPFILE -                           |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_backup_spfile"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN SPFILE</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New,Helvetica,Geneva,sans-serif" >● Available automatic SPFILE backups within all available (and expired) backup sets</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN bs_key                 FORMAT a75                     HEADING 'BS Key'                 ENTMAP OFF
COLUMN piece#                                                HEADING 'Piece #'                ENTMAP OFF
COLUMN copy#                                                 HEADING 'Copy #'                 ENTMAP OFF
COLUMN bp_key                                                HEADING 'BP Key'                 ENTMAP OFF
COLUMN spfile_included        FORMAT a75                     HEADING 'SPFILE Included?'       ENTMAP OFF
COLUMN status                                                HEADING 'Status'                 ENTMAP OFF
COLUMN handle                                                HEADING 'Handle'                 ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN completion_time        FORMAT a40                     HEADING 'End Time'               ENTMAP OFF
COLUMN elapsed_seconds        FORMAT 999,999,999,999,999     HEADING 'Elapsed Seconds'        ENTMAP OFF
COLUMN deleted                FORMAT a10                     HEADING 'Deleted?'               ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON


-- BREAK ON bs_key

SELECT '<div align="center"><font color="#336699"><b>' || BS.RECID ||
       '</b></font></div>' BS_KEY,
       BP.PIECE# PIECE#,
       BP.COPY# COPY#,
       BP.RECID BP_KEY,
       '<div align="center"><font color="#663300"><b>' ||
       NVL(SP.SPFILE_INCLUDED, '-') || '</b></font></div>' SPFILE_INCLUDED,
       DECODE(STATUS,
              'A',
              '<div nowrap align="center"><font color="darkgreen"><b>Available</b></font></div>',
              'D',
              '<div nowrap align="center"><font color="#000099"><b>Deleted</b></font></div>',
              'X',
              '<div nowrap align="center"><font color="#990000"><b>Expired</b></font></div>') STATUS,
       HANDLE HANDLE
  FROM V$BACKUP_SET BS,
       V$BACKUP_PIECE BP,
       (SELECT DISTINCT SET_STAMP, SET_COUNT, 'YES' SPFILE_INCLUDED
          FROM V$BACKUP_SPFILE) SP
 WHERE BS.SET_STAMP = BP.SET_STAMP
   AND BS.SET_COUNT = BP.SET_COUNT
   AND BP.STATUS IN ('A', 'X')
   AND BS.SET_STAMP = SP.SET_STAMP
   AND BS.SET_COUNT = SP.SET_COUNT
   AND BS.START_TIME >= SYSDATE - 15
 ORDER BY BS.RECID, PIECE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 97 for section: prompt Notes:
hc_q_prompt_notes_97() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_97_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN BACKUP_TYPE  FORMAT a80    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INCREMENTAL_LEVEL          HEADING 'INCREMENTAL|LEVEL'  ENTMAP OFF 
COLUMN FIRST_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FIRST_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN NEXT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN CREATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN piece_name     FORMAT a100    HEADING 'PIECE_NAME'  ENTMAP OFF 
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT A.BS_KEY,
       A.BP_KEY,
       A.BACKUP_TYPE, 
       A.INCREMENTAL_LEVEL,
       A.BS_SIZE,
       A.START_TIME,
       A.END_TIME,
       A.ELAPSED_TIME,
       A.PIECE_NAME,
       A.DEVICE_TYPE,
       A.TAG,
       A.BS_STATUS,
       A.BS_COMPRESSED,
       A.CONTROLFILE_INCLUDED,
       A.KEEP,
       A.KEEP_UNTIL,
       A.KEEP_OPTIONS, 
       A.MODIFICATION_TIME,
       A.DB_UNIQUE_NAME,
       A.CREATION_TIME,
       A.CF_CHECKPOINT_CHANGE#,
       A.CF_CHECKPOINT_TIME,
       A.FILESIZE_DISPLAY
  FROM (SELECT a.RECID BS_key,
       c.RECID BP_key,
       case
         WHEN a.backup_type = 'L' then
          '<div nowrap><font color="#990000">Archived Redo Logs</font></div>'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          '<div nowrap><font color="#000099">Datafile Full Backup</font></div>'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          '<div nowrap><font color="darkgreen">Incremental Backup</font></div>'
       end backup_type,
       case
         WHEN a.backup_type = 'L' then
          'Archived Redo Logs'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          'Datafile Full Backup'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          'Incremental Backup'
       end backup_type1,
       a.INCREMENTAL_LEVEL,
       round(aa.bs_bytes/1024/1024, 2) bs_size,
       TO_CHAR(a.START_TIME, 'YYYY-MM-DD HH24:MI:SS') START_TIME,
       TO_CHAR(a.COMPLETION_TIME, 'YYYY-MM-DD HH24:MI:SS') END_TIME,
       (round(a.ELAPSED_SECONDS)) ELAPSED_TIME,
       c.HANDLE piece_name,
       c.DEVICE_TYPE,
       c.TAG,
       aa.bs_status,
       aa.bs_compressed,
       a.CONTROLFILE_INCLUDED,
       a.KEEP,
       a.KEEP_UNTIL,
       a.KEEP_OPTIONS,
       
------ data file -------- 
       b.FILE#,
       b.INCREMENTAL_LEVEL df_INCREMENTAL_LEVEL,
       (SELECT nb.NAME FROM v$datafile nb WHERE nb.FILE# = b.FILE#) datafileNAME,
       b.USED_CHANGE_TRACKING,
       b.CHECKPOINT_CHANGE#||'' df_CHECKPOINT_CHANGE#,
       b.CHECKPOINT_TIME df_CHECKPOINT_TIME,
       
------ archive log file --------
       d.THREAD#,
       d.SEQUENCE#,
       d.RESETLOGS_CHANGE#,
       d.FIRST_CHANGE#,
       d.FIRST_TIME,
       d.NEXT_CHANGE#,
       d.NEXT_TIME,
       
------ spfile --------
       e.MODIFICATION_TIME,
       e.DB_UNIQUE_NAME,
       
------ control file --------
       f.CREATION_TIME,
       f.CHECKPOINT_CHANGE#||'' cf_CHECKPOINT_CHANGE#,
       f.CHECKPOINT_TIME    cf_CHECKPOINT_TIME,
       f.FILESIZE_DISPLAY
  FROM v$backup_set a
  LEFT OUTER JOIN v$backup_files aa
    on (aa.bs_key = a.RECID AND  aa.file_type = 'PIECE')
  LEFT OUTER JOIN v$backup_datafile b
    ON (a.SET_STAMP = b.SET_STAMP AND  a.SET_COUNT = b.SET_COUNT)
  LEFT OUTER JOIN v$backup_piece c
    ON (a.SET_STAMP = c.SET_STAMP AND  a.SET_COUNT = c.SET_COUNT)
  LEFT OUTER JOIN V$backup_Archivelog_Details D
    ON (d.BTYPE_KEY = a.RECID)
  LEFT OUTER JOIN v$backup_spfile e
    ON (a.SET_STAMP = e.SET_STAMP AND  a.SET_COUNT = e.SET_COUNT)
  LEFT OUTER JOIN v$backup_controlfile_details f
    ON (f.BTYPE_KEY = a.RECID)
  WHERE a.START_TIME>=SYSDATE - 15
 ORDER BY a.RECID, a.RECID, b.FILE#, d.THREAD#, d.SEQUENCE#) A
  WHERE A.DB_UNIQUE_NAME IS NOT NULL 	
 ORDER BY A.BS_KEY, A.BP_KEY, A.FILE#, A.THREAD#, A.SEQUENCE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 98 for section: prompt Notes:
hc_q_prompt_notes_98() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_98_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - RMAN BACKUP Archived Redo Logs -                           |

-- +----------------------------------------------------------------------------+


prompt  <a name="rman_backup_archivedlog"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>RMAN </b></font>[<a class="noLink" href="#flashback_database_info">Next Item</a>]<hr align="left" width="600">
 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN BACKUP_TYPE  FORMAT a80    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BACKUP_TYPE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INCREMENTAL_LEVEL          HEADING 'INCREMENTAL|LEVEL'  ENTMAP OFF 
COLUMN FIRST_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FIRST_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN NEXT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN CREATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN DF_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DF_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN MODIFICATION_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MODIFICATION_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cf_CHECKPOINT_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cf_CHECKPOINT_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT A.BS_KEY,
       A.BP_KEY,
       A.BACKUP_TYPE,
       A.INCREMENTAL_LEVEL,
       A.BS_SIZE,
       A.START_TIME,
       A.END_TIME,
       A.ELAPSED_TIME,
       A.PIECE_NAME,
       A.DEVICE_TYPE,
       A.TAG,
       A.BS_STATUS,
       A.BS_COMPRESSED,
       A.CONTROLFILE_INCLUDED,
       A.KEEP,
       A.THREAD#,
       A.SEQUENCE#,
       A.RESETLOGS_CHANGE#,
       A.FIRST_CHANGE#,
       A.FIRST_TIME,
       A.NEXT_CHANGE#,
       A.NEXT_TIME
  FROM (SELECT a.RECID BS_key,
       c.RECID BP_key,
       case
         WHEN a.backup_type = 'L' then
          '<div nowrap><font color="#990000">Archived Redo Logs</font></div>'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          '<div nowrap><font color="#000099">Datafile Full Backup</font></div>'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          '<div nowrap><font color="darkgreen">Incremental Backup</font></div>'
       end backup_type,
       case
         WHEN a.backup_type = 'L' then
          'Archived Redo Logs'
         WHEN a.backup_type = 'D' AND  a.INCREMENTAL_LEVEL is null then
          'Datafile Full Backup'
         WHEN a.backup_type = 'I' or a.INCREMENTAL_LEVEL IS NOT NULL then
          'Incremental Backup'
       end backup_type1,
       a.INCREMENTAL_LEVEL,
       round(aa.bs_bytes/1024/1024, 2) bs_size,
       TO_CHAR(a.START_TIME, 'YYYY-MM-DD HH24:MI:SS') START_TIME,
       TO_CHAR(a.COMPLETION_TIME, 'YYYY-MM-DD HH24:MI:SS') END_TIME,
       (round(a.ELAPSED_SECONDS)) ELAPSED_TIME,
       c.HANDLE piece_name,
       c.DEVICE_TYPE,
       c.TAG,
       aa.bs_status,
       aa.bs_compressed,
       a.CONTROLFILE_INCLUDED,
       a.KEEP,
       a.KEEP_UNTIL,
       a.KEEP_OPTIONS,
       
------ data file -------- 
       b.FILE#,
       b.INCREMENTAL_LEVEL df_INCREMENTAL_LEVEL,
       (SELECT nb.NAME FROM v$datafile nb WHERE nb.FILE# = b.FILE#) datafileNAME,
       b.USED_CHANGE_TRACKING,
       b.CHECKPOINT_CHANGE#||'' df_CHECKPOINT_CHANGE#,
       b.CHECKPOINT_TIME df_CHECKPOINT_TIME,
       
------ archive log file --------
       d.THREAD#,
       d.SEQUENCE#,
       d.RESETLOGS_CHANGE#,
       d.FIRST_CHANGE#,
       d.FIRST_TIME,
       d.NEXT_CHANGE#,
       d.NEXT_TIME,
       
------ spfile --------
       e.MODIFICATION_TIME,
       e.DB_UNIQUE_NAME,
       
------ control file --------
       f.CREATION_TIME,
       f.CHECKPOINT_CHANGE#||'' cf_CHECKPOINT_CHANGE#,
       f.CHECKPOINT_TIME    cf_CHECKPOINT_TIME,
       f.FILESIZE_DISPLAY
  FROM v$backup_set a
  LEFT OUTER JOIN v$backup_files aa
    on (aa.bs_key = a.RECID AND  aa.file_type = 'PIECE')
  LEFT OUTER JOIN v$backup_datafile b
    ON (a.SET_STAMP = b.SET_STAMP AND  a.SET_COUNT = b.SET_COUNT)
  LEFT OUTER JOIN v$backup_piece c
    ON (a.SET_STAMP = c.SET_STAMP AND  a.SET_COUNT = c.SET_COUNT)
  LEFT OUTER JOIN V$backup_Archivelog_Details D
    ON (d.BTYPE_KEY = a.RECID)
  LEFT OUTER JOIN v$backup_spfile e
    ON (a.SET_STAMP = e.SET_STAMP AND  a.SET_COUNT = e.SET_COUNT)
  LEFT OUTER JOIN v$backup_controlfile_details f
    ON (f.BTYPE_KEY = a.RECID)
  WHERE a.START_TIME>=SYSDATE - 15
 ORDER BY a.RECID, a.RECID, b.FILE#, d.THREAD#, d.SEQUENCE#) A
 WHERE A.BACKUP_TYPE1 = 'Archived Redo Logs'
 ORDER BY A.BS_KEY, A.BP_KEY, A.FILE#, A.THREAD#, A.SEQUENCE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 99 for section: prompt Notes:
hc_q_prompt_notes_99() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_99_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

-- +============================================================================+

-- |                                                                            |

-- |               <<<<<     FLASHBACK TECHNOLOGIES     >>>>>                   |

-- |                                                                            |

-- +============================================================================+
 
 

prompt  <a name="flashback_database_info"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u>Flashback Technologies(Flashback Database)</u></b></font></center>
 
 

-- +----------------------------------------------------------------------------+

-- |                     - FLASHBACK DATABASE PARAMETERS -                      |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="flashback_database_parameters"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Flashback Database Parameters</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: db_flashback_retention_target is specified in minutes; db_recovery_file_dest_size is specified in bytes  </font></b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print   FORMAT a95    HEADING 'Instance_Name'     ENTMAP OFF
COLUMN thread_number_print   FORMAT a95    HEADING 'Thread Number'     ENTMAP OFF
COLUMN name                  FORMAT a125   HEADING 'Name'              ENTMAP OFF
COLUMN value                               HEADING 'Value'             ENTMAP OFF
SET DEFINE ON 

-- BREAK ON report ON instance_name_print ON thread_number_print
 
SELECT '<div align="center"><font color="#336699"><b>' || I.INSTANCE_NAME ||
       '</b></font></div>' INSTANCE_NAME_PRINT,
       '<div align="center">' || I.THREAD# || '</div>' THREAD_NUMBER_PRINT,
       '<div nowrap>' || P.NAME || '</div>' NAME,
       (CASE P.NAME
         WHEN 'db_recovery_file_dest_size' THEN
          '<div nowrap align="right">' ||
          TO_CHAR(P.VALUE, '999,999,999,999,999') || '</div>'
         WHEN 'db_flashback_retention_target' THEN
          '<div nowrap align="right">' ||
          TO_CHAR(P.VALUE, '999,999,999,999,999') || '</div>'
         ELSE
          '<div nowrap align="right">' || NVL(P.VALUE, '(null)') ||
          '</div>'
       END) VALUE
  FROM GV$PARAMETER P, GV$INSTANCE I
 WHERE P.INST_ID = I.INST_ID
   AND P.NAME IN ('db_flashback_retention_target',
                  'db_recovery_file_dest_size',
                  'db_recovery_file_dest')
 ORDER BY 1, 3;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 100 for section: prompt Notes:
hc_q_prompt_notes_100() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_100_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                       - FLASHBACK DATABASE STATUS -                        |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="flashback_database_status"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Flashback Database Status</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN dbid                                HEADING 'DB ID'              ENTMAP OFF
COLUMN name             FORMAT A75         HEADING 'DB Name'            ENTMAP OFF
COLUMN log_mode         FORMAT A75         HEADING 'Log Mode'           ENTMAP OFF
COLUMN flashback_on     FORMAT A75         HEADING 'Flashback DB On?'   ENTMAP OFF
 
SELECT
    '<div align="center"><font color="#336699"><b>' || dbid          || '</b></font></div>'  dbid
  , '<div align="center">'                          || name          || '</div>'             name
  , '<div align="center">'                          || log_mode      || '</div>'             log_mode
  , '<div align="center">'                          || flashback_on  || '</div>'             flashback_on
FROM v$database;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 101 for section: prompt Notes:
hc_q_prompt_notes_101() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_101_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN oldest_flashback_time    FORMAT a125               HEADING 'Oldest Flashback Time'     ENTMAP OFF
COLUMN oldest_flashback_scn                               HEADING 'Oldest Flashback SCN'      ENTMAP OFF
COLUMN retention_target         FORMAT 999,999            HEADING 'Retention Target (min)'    ENTMAP OFF
COLUMN retention_target_hours   FORMAT 999,999            HEADING 'Retention Target (hour)'   ENTMAP OFF
COLUMN flashback_size           FORMAT 9,999,999,999,999  HEADING 'Flashback Size'            ENTMAP OFF
COLUMN estimated_flashback_size FORMAT 9,999,999,999,999  HEADING 'Estimated Flashback Size'  ENTMAP OFF
 
SELECT
    '<div align="center"><font color="#336699"><b>' || TO_CHAR(oldest_flashback_time,'mm/dd/yyyy HH24:MI:SS') || '</b></font></div>'  oldest_flashback_time
  , oldest_flashback_scn             oldest_flashback_scn
  , retention_target                 retention_target
  , retention_target/60              retention_target_hours
  , flashback_size                   flashback_size
  , estimated_flashback_size         estimated_flashback_size
FROM
    v$flashback_database_log
ORDER BY
    1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 102 for section: prompt Notes:
hc_q_prompt_notes_102() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_102_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                  - FLASHBACK DATABASE REDO TIME MATRIX -                   |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="flashback_database_redo_time_matrix"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Flashback Database Redo Time Matrix</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN begin_time               FORMAT a75                HEADING 'Begin Time'               ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN flashback_data           FORMAT 9,999,999,999,999  HEADING 'Flashback Data'           ENTMAP OFF
COLUMN db_data                  FORMAT 9,999,999,999,999  HEADING 'DB Data'                  ENTMAP OFF
COLUMN redo_data                FORMAT 9,999,999,999,999  HEADING 'Redo Data'                ENTMAP OFF
COLUMN estimated_flashback_size FORMAT 9,999,999,999,999  HEADING 'Estimated Flashback Size' ENTMAP OFF
SET DEFINE ON

 
SELECT
    '<div align="right">' || TO_CHAR(begin_time,'mm/dd/yyyy HH24:MI:SS') || '</div>'  begin_time
  , '<div align="right">' || TO_CHAR(END_TIME,'mm/dd/yyyy HH24:MI:SS') || '</div>'    END_TIME
  , flashback_data
  , db_data
  , redo_data
  , estimated_flashback_size
FROM
    v$flashback_database_stat
ORDER BY
   begin_time;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 103 for section: prompt Notes:
hc_q_prompt_notes_103() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_103_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 


-- +----------------------------------------------------------------------------+

-- |                             - ARCHIVING MODE -                             |

-- +----------------------------------------------------------------------------+
host echo "            . . ." 

prompt  <a name="database_archiveloginfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


-- +----------------------------------------------------------------------------+

-- |                             - ARCHIVING MODE -                             |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="archiving_mode"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Archiving Mode</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN db_log_mode                  FORMAT a95                HEADING 'Database|Log Mode'             ENTMAP OFF
COLUMN log_archive_start            FORMAT a95                HEADING 'Automatic|Archival'            ENTMAP OFF
COLUMN oldest_online_log_sequence   FORMAT 999999999999999    HEADING 'Oldest Online |Log Sequence'   ENTMAP OFF
COLUMN current_log_seq              FORMAT 999999999999999    HEADING 'Current |Log Sequence'         ENTMAP OFF
SET DEFINE ON
 
SELECT
    '<div align="center"><font color="#663300"><b>' || d.log_mode           || '</b></font></div>'    db_log_mode
  , '<div align="center"><font color="#663300"><b>' || p.log_archive_start  || '</b></font></div>'    log_archive_start
  , c.current_log_seq                                   current_log_seq
  , o.oldest_online_log_sequence                        oldest_online_log_sequence
FROM
    (select
         DECODE(   log_mode
                 , 'ARCHIVELOG', 'Archive Mode'
                 , 'NOARCHIVELOG', 'No Archive Mode'
                 , log_mode
         )   log_mode
     FROM v$database
    ) d
  , (select
         DECODE(   log_mode
                 , 'ARCHIVELOG', 'Enabled'
                 , 'NOARCHIVELOG', 'Disabled')   log_archive_start
     FROM v$database
    ) p
  , (SELECT a.sequence#   current_log_seq
     FROM   v$log a
     WHERE  a.status = 'CURRENT'
       AND  thread# = &_thread_number
    ) c
  , (SELECT min(a.sequence#) oldest_online_log_sequence
     FROM   v$log a
     WHERE  thread# = &_thread_number
    ) o
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 104 for section: prompt Notes:
hc_q_prompt_notes_104() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_104_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 

 

-- +----------------------------------------------------------------------------+

-- |                         - ARCHIVE DESTINATIONS -                           |

-- +----------------------------------------------------------------------------+
 


prompt  <a name="archiving_instance_parameters"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN name      HEADING 'Parameter Name'   ENTMAP OFF
COLUMN value     HEADING 'Parameter Value'  ENTMAP OFF

SELECT
    '<b><font color="#336699">' || a.name || '</font></b>'    name
  , a.value                                                   value
FROM
    v$parameter a
WHERE
    a.name like 'log_%'
ORDER BY
    a.name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 105 for section: prompt Notes:
hc_q_prompt_notes_105() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_105_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

prompt  <a name="archive_destinations"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Archive Destinations</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN dest_id                                                HEADING 'Destination|ID'            ENTMAP OFF
COLUMN dest_name                                              HEADING 'Destination|Name'          ENTMAP OFF
COLUMN destination                                            HEADING 'Destination'               ENTMAP OFF
COLUMN status                                                 HEADING 'Status'                    ENTMAP OFF
COLUMN schedule                                               HEADING 'Schedule'                  ENTMAP OFF
COLUMN archiver                                               HEADING 'Archiver'                  ENTMAP OFF
COLUMN log_sequence                 FORMAT 999999999999999    HEADING 'Current Log|Sequence'      ENTMAP OFF
 
SELECT
    '<div align="center"><font color="#336699"><b>' || a.dest_id || '</b></font></div>'    dest_id
  , a.dest_name                               dest_name
  , a.destination                             destination
  , DECODE(   a.status
            , 'VALID',    '<div align="center"><b><font color="darkgreen">' || status || '</font></b></div>'
            , 'INACTIVE', '<div align="center"><b><font color="#990000">'   || status || '</font></b></div>'
            ,             '<div align="center"><b><font color="#663300">'   || status || '</font></b></div>' ) status
  , DECODE(   a.schedule
            , 'ACTIVE',   '<div align="center"><b><font color="darkgreen">' || schedule || '</font></b></div>'
            , 'INACTIVE', '<div align="center"><b><font color="#990000">'   || schedule || '</font></b></div>'
            ,             '<div align="center"><b><font color="#663300">'   || schedule || '</font></b></div>' ) schedule
  , a.archiver                                archiver
  , a.log_sequence                            log_sequence
FROM
    v$archive_dest a
ORDER BY
    a.dest_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 106 for section: prompt Notes:
hc_q_prompt_notes_106() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_106_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


-- +----------------------------------------------------------------------------+

-- |                           - ARCHIVING HISTORY -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="archiving_history"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <a name="archiving_history_all"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Archived Logs Status (Past Month) </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN thread#          FORMAT a79                   HEADING ''           ENTMAP OFF
COLUMN f_time           FORMAT a75                   HEADING ''           ENTMAP OFF
COLUMN day_arch         FORMAT 999,999,999,999,999   HEADING '(MB)'   ENTMAP OFF
COLUMN hour_arch         FORMAT 999,999,999,999,999   HEADING '(MB)'   ENTMAP OFF


-- BREAK ON report ON thread#

 
SELECT '<div align="center"><b><font color="#336699">' || a.thread#   || '</font></b></div>'  thread#,
       '<div align="center"><b><font color="#336699">' || a.f_time   || '</font></b></div>'  f_time,
       '<div align="right" nowrap>' ||  round(sum(a.blocks * a.block_size) / 1024 / 1024 )  || '</div>'  day_arch,
       '<div align="right" nowrap>' ||  round(sum(a.blocks * a.block_size) / 1024 /1024 / 24,2)  || '</div>'  hour_arch,
       COUNT(1) 
  FROM (SELECT distinct sequence#,
                        thread#,
                        blocks,
                        block_size,
                        TO_CHAR(first_time, 'yyyy-mm-dd') f_time
          FROM gv$archived_log t
WHERE t.FIRST_TIME <=sysdate  and t.FIRST_TIME >=sysdate-31 ) a
 GROUP BY a.f_time, a.thread#
 ORDER BY 1,2 desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 107 for section: prompt Notes:
hc_q_prompt_notes_107() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_107_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="archive_log_rate"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600"> 

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: DB_RECOVERY_FILE_DEST_SIZE,crosscheck archivelog all; delete expired archivelog all;</font></b>

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: ,View</font></b>
CLEAR COLUMNS COMPUTES
SET DEFINE ON

SELECT A.NAME,
       round(a.SPACE_LIMIT / 1024 / 1024) SPACE_LIMIT_m,
       (a.space_used / 1024 / 1024) space_used_m,
       round(a.space_used / a.SPACE_LIMIT, 2) PERCENT_SPACE_USED,
       round(a.space_reclaimable / 1024 / 1024, 2) space_reclaimable,
       round(a.space_reclaimable / a.SPACE_LIMIT, 2) PERCENT_SPACE_RECLAIMABLE,
       number_of_files
  FROM v$recovery_file_dest A
 WHERE a.SPACE_LIMIT <> 0
UNION ALL
SELECT b.FILE_TYPE,
       (c.SPACE_LIMIT / 1024 / 1024) SPACE_LIMIT_m,
       round(b.PERCENT_SPACE_USED * c.SPACE_LIMIT / 1024 / 1024 / 100, 2) space_used_m,
       b.PERCENT_SPACE_USED PERCENT_SPACE_USED,
       round(b.PERCENT_SPACE_RECLAIMABLE * c.SPACE_LIMIT / 1024 / 1024 / 100,
             2) space_reclaimable,
       (b.PERCENT_SPACE_RECLAIMABLE) PERCENT_SPACE_RECLAIMABLE,
       b.NUMBER_OF_FILES
  FROM v$flash_recovery_area_usage b, v$recovery_file_dest c
 WHERE c.SPACE_LIMIT <> 0
UNION ALL
SELECT bb.FILENAME || '
---' || bb.STATUS,
       (c.SPACE_LIMIT / 1024 / 1024) SPACE_LIMIT_m,
       (bb.BYTES / 1024 / 1024) space_used,
       round(bb.BYTES * 100 / c.SPACE_LIMIT, 2) PERCENT_SPACE_USED,
       0,
       0,
       1
  FROM v$block_change_tracking bb, v$recovery_file_dest c
 WHERE c.SPACE_LIMIT <> 0;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 108 for section: prompt Notes:
hc_q_prompt_notes_108() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_108_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="log_10_ratefenxi"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>7</b></font> [<a class="noLink" href="#log_10_ratefenxiqiehuan">Next Item</a>]<hr align="left" width="600">

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● first_time,,top500</font>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN FIRST_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FIRST_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN END_TIME     FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON 


-- BREAK ON THREAD#
SELECT * FROM (
SELECT t.THREAD#,
       t.SEQUENCE#,
       t.FIRST_TIME,
       nvl(T.END_TIME,
           (SELECT NB.FIRST_TIME
              FROM v$log nb
             WHERE nb.SEQUENCE# = t.SEQUENCE# + 1
               AND  nb.THREAD# = t.THREAD#)) END_TIME,
       round(((nvl(T.END_TIME,
                   (SELECT NB.FIRST_TIME
                      FROM v$log nb
                     WHERE nb.SEQUENCE# = t.SEQUENCE# + 1
                       AND  nb.THREAD# = t.THREAD#)) - t.FIRST_TIME) * 24) * 60,
             2) total_min,
       ROUND(t.BLOCKS * t.BLOCK_SIZE / 1024 / 1024, 3) LOGsize_m,
       t.NAME,
       '<div align="center">' || archived || '</div>' archived,
       '<div align="center">' || applied || '</div>' applied,
       '<div align="center">' || deleted || '</div>' deleted,
       DECODE(status,
              'A',
              '<div align="center"><b><font color="darkgreen">Available</font></b></div>',
              'D',
              '<div align="center"><b><font color="#663300">Deleted</font></b></div>',
              'U',
              '<div align="center"><b><font color="#990000">Unavailable</font></b></div>',
              'X',
              '<div align="center"><b><font color="#990000">Expired</font></b></div>') status
  FROM (SELECT a.THREAD#,
               a.SEQUENCE#,
               a.FIRST_TIME,
               a.BLOCKS,
               a.BLOCK_SIZE,
               a.NAME,
               a.ARCHIVED,
               a.APPLIED,
               a.DELETED,
               a.STATUS,
               lead(a.FIRST_TIME) over(partition by a.THREAD# ORDER BY a.SEQUENCE#) END_TIME
          FROM v$archived_log a
         WHERE a.STANDBY_DEST='NO'  AND  a.FIRST_TIME >= SYSDATE - 7
           AND  a.FIRST_TIME <= SYSDATE) t
 ORDER BY t.THREAD#, t.SEQUENCE# DESC) WHERE rownum<=500;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 109 for section: prompt Notes:
hc_q_prompt_notes_109() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_109_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="log_10_ratefenxiqiehuan"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ,30,24,</font>

COLUMN TOTAL    HEADING 'TOTAL'  ENTMAP OFF 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 

-- BREAK ON report on THREAD# skip 1

--COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' avg label '<font color="#990000"><b>Average: </b></font>' OF TOTAL ON report
COMPUTE sum LABEL 'Sum: ' OF TOTAL ON THREAD#

--COMPUTE avg LABEL '<font color="#990000"><b>Average: </b></font>' OF TOTAL ON report

--COMPUTE sum LABEL 'Total:' avg label 'Average:' OF TOTAL ON report

SELECT  a.THREAD#,  '<div align="center"><font color="#336699"><b>' || SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH:MI:SS'),1,5)  || '</b></font></div>' Day,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'00',1,0)) H00,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'01',1,0)) H01, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'02',1,0)) H02,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'03',1,0)) H03,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'04',1,0)) H04,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'05',1,0)) H05,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'06',1,0)) H06,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'07',1,0)) H07,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'08',1,0)) H08,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'09',1,0)) H09,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'10',1,0)) H10,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'11',1,0)) H11, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'12',1,0)) H12,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'13',1,0)) H13, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'14',1,0)) H14,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'15',1,0)) H15, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'16',1,0)) H16, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'17',1,0)) H17, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'18',1,0)) H18, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'19',1,0)) H19, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'20',1,0)) H20, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'21',1,0)) H21,
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'22',1,0)) H22, 
       SUM(DECODE(SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH24:MI:SS'),10,2),'23',1,0)) H23, 
       COUNT(*) TOTAL 
FROM gv$log_history  a  
 WHERE first_time>=TO_CHAR(SYSDATE - 15)
	group by a.THREAD#,     	
 SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH:MI:SS'),1,5) 
ORDER BY a.THREAD#,SUBSTR(TO_CHAR(first_time, 'MM/DD/RR HH:MI:SS'),1,5) DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 110 for section: prompt Notes:
hc_q_prompt_notes_110() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_110_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          - ONLINE REDO LOGS -                              |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="logsize"></a>  

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Log Group Size</b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.group#,
       a.THREAD#,
       a.SEQUENCE#,
       bytes / 1024 / 1024 size_m,
       a.status,
       a.ARCHIVED,
       a.MEMBERS,
       TO_CHAR(listagg(b.MEMBER,',') within group(order by MEMBER))  MEMBER,
       b.TYPE
FROM   gv$log     a,
       gv$logfile b
WHERE  b.GROUP# = a.GROUP#
AND    a.THREAD# = b.INST_ID
GROUP  BY a.GROUP#,
          a.THREAD#,
          a.SEQUENCE#,
          a.BYTES,
          a.STATUS,
          a.ARCHIVED,
          a.MEMBERS,
          b.TYPE
ORDER  BY a.THREAD#,
          a.GROUP#,
          a.SEQUENCE#;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 111 for section: prompt Notes:
hc_q_prompt_notes_111() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_111_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +============================================================================+

-- |                                                                            |

-- |                    <<<<<     PERFORMANCE     >>>>>                         |

-- |                                                                            |

-- +============================================================================+


-- +----------------------------------------------------------------------------+

-- |                             - SGA INFORMATION -                            |

-- +----------------------------------------------------------------------------+
host echo "            SGA. . ." 

prompt  <a name="database_SGAINFOLHR"></a>

prompt  <font size="+2" color="00CCFF"><b>SGA</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="sga_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SGA</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN inst_id        FORMAT 999    
COLUMN name        FORMAT a75    
COLUMN MBytes  FORMAT 999,999,999,999,999    HEADING '(MB)'      ENTMAP OFF
COLUMN resizeable		  FORMAT a75   HEADING ''      ENTMAP OFF


-- BREAK ON report on inst_id

SELECT inst_id,name,round(bytes/1024/1024) MBytes ,resizeable FROM gv$sgainfo;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 112 for section: prompt Notes:
hc_q_prompt_notes_112() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_112_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center>


prompt  <br/>


prompt  <a name="sga_information"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SGA </b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name FORMAT a79                 HEADING 'Instance_Name'    ENTMAP OFF
COLUMN name          FORMAT a150                HEADING 'Pool Name'        ENTMAP OFF
COLUMN value         FORMAT 999,999,999,999,999 HEADING 'Bytes'            ENTMAP OFF


-- BREAK ON report ON instance_name
COMPUTE sum LABEL '<font color="#990000"><b>Total:</b></font>' OF value ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , '<div align="left"><font color="#336699"><b>' || s.name          || '</b></font></div>'  name
  , s.value                                                                                  value
FROM
    gv$sga       s
  , gv$instance  i
WHERE
    s.inst_id = i.inst_id
ORDER BY
    i.instance_name
  , s.value DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 113 for section: prompt Notes:
hc_q_prompt_notes_113() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_113_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - SGA TARGET ADVICE -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="sga_target_advice"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SGA Target Advice</b></font><hr align="left" width="600">

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> Modify the SGA_TARGET parameter (up to the size of the SGA_MAX_SIZE, if necessary) to reduce the number of "Estimated Physical Reads".</font>
 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name FORMAT a79     HEADING 'Instance_Name'    ENTMAP OFF
COLUMN name          FORMAT a79     HEADING 'Parameter Name'   ENTMAP OFF
COLUMN value         FORMAT a79     HEADING 'Value'            ENTMAP OFF


-- BREAK ON report ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , p.name    name
  , (CASE p.name
         WHEN 'sga_max_size' THEN '<div align="right">' || TO_CHAR(p.value, '999,999,999,999,999') || '</div>'
         WHEN 'sga_target'   THEN '<div align="right">' || TO_CHAR(p.value, '999,999,999,999,999') || '</div>'
     ELSE
         '<div align="right">' || p.value || '</div>'
     END) value
FROM
    gv$parameter p
  , gv$instance  i
WHERE
      p.inst_id = i.inst_id
  AND  p.name IN ('sga_max_size', 'sga_target')
ORDER BY
    i.instance_name
  , p.name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 114 for section: prompt Notes:
hc_q_prompt_notes_114() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_114_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name         FORMAT a79                   HEADING 'Instance_Name'              ENTMAP OFF
COLUMN sga_size              FORMAT 999,999,999,999,999   HEADING 'SGA Size'                   ENTMAP OFF
COLUMN sga_size_factor       FORMAT 999,999,999,999,999   HEADING 'SGA Size Factor'            ENTMAP OFF
COLUMN estd_db_time          FORMAT 999,999,999,999,999   HEADING 'Estimated DB Time'          ENTMAP OFF
COLUMN estd_db_time_factor   FORMAT 999,999,999,999,999   HEADING 'Estimated DB Time Factor'   ENTMAP OFF
COLUMN estd_physical_reads   FORMAT 999,999,999,999,999   HEADING 'Estimated Physical Reads'   ENTMAP OFF


-- BREAK ON report ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , s.sga_size
  , s.sga_size_factor
  , s.estd_db_time
  , s.estd_db_time_factor
  , s.estd_physical_reads
FROM
    gv$sga_target_advice s
  , gv$instance  i
WHERE
    s.inst_id = i.inst_id
ORDER BY
    i.instance_name
  , s.sga_size_factor;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 115 for section: prompt Notes:
hc_q_prompt_notes_115() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_115_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                      - SGA (ASMM) DYNAMIC COMPONENTS -                     |

-- +----------------------------------------------------------------------------+


prompt  <a name="sga_asmm_dynamic_components"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SGA (ASMM) Dynamic Components</b></font><hr align="left" width="600">

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> Provides a summary report of all dynamic components AS part of the Automatic Shared Memory </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  Management (ASMM) configuration. This will display the total real memory allocation for the current </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  SGA FROM the V$SGA_DYNAMIC_COMPONENTS view, which contains both manual AND  autotuned SGA components. </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  AS with the other manageability features of Oracle Database 10g, ASMM requires you to set the </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  STATISTICS_LEVEL parameter to at least TYPICAL (the default) before attempting to enable ASMM. ASMM </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  can be enabled by setting SGA_TARGET to a nonzero value in the initialization parameter file (pfile/spfile). </font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name         FORMAT a79                HEADING 'Instance_Name'        ENTMAP OFF
COLUMN component             FORMAT a79                HEADING 'Component Name'       ENTMAP OFF
COLUMN current_size          FORMAT 999,999,999,999    HEADING 'Current Size'         ENTMAP OFF
COLUMN min_size              FORMAT 999,999,999,999    HEADING 'Min Size'             ENTMAP OFF
COLUMN max_size              FORMAT 999,999,999,999    HEADING 'Max Size'             ENTMAP OFF
COLUMN user_specified_size   FORMAT 999,999,999,999    HEADING 'User Specified|Size'  ENTMAP OFF
COLUMN oper_count            FORMAT 999,999,999,999    HEADING 'Oper.|Count'          ENTMAP OFF
COLUMN last_oper_type        FORMAT a75                HEADING 'Last Oper.|Type'      ENTMAP OFF
COLUMN last_oper_mode        FORMAT a75                HEADING 'Last Oper.|Mode'      ENTMAP OFF
COLUMN last_oper_time        FORMAT a75                HEADING 'Last Oper.|Time'      ENTMAP OFF
COLUMN granule_size          FORMAT 999,999,999,999    HEADING 'Granule Size'         ENTMAP OFF


-- BREAK ON report ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , sdc.component
  , sdc.current_size
  , sdc.min_size
  , sdc.max_size
  , sdc.user_specified_size
  , sdc.oper_count
  , sdc.last_oper_type
  , sdc.last_oper_mode
  , '<div align="right">' || NVL(TO_CHAR(sdc.last_oper_time, 'yyyy-mm-dd HH24:MI:SS'), '<br>') || '</div>'   last_oper_time
  , sdc.granule_size
FROM
    gv$sga_dynamic_components sdc
  , gv$instance  i
ORDER BY
    i.instance_name
  , sdc.component DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 116 for section: prompt Notes:
hc_q_prompt_notes_116() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_116_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - PGA TARGET ADVICE -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="pga_target_advice"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>PGA Target </b></font><hr align="left" width="600">
 

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  The <b>V$PGA_TARGET_ADVICE</b> view predicts how the statistics cache hit percentage AND  over </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  allocation count in V$PGASTAT will be impacted if you change the value of the </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  initialization parameter PGA_AGGREGATE_TARGET. WHEN you set the PGA_AGGREGATE_TARGET and </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  WORKAREA_SIZE_POLICY to <b>AUTO</b> then the *_AREA_SIZE parameter are automatically ignored and </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  Oracle will automatically use the computed value for these parameters. Use the results from </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  the query below to adequately set the initialization parameter PGA_AGGREGATE_TARGET AS to avoid </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  any over allocation. If column ESTD_OVERALLOCATION_COUNT in the V$PGA_TARGET_ADVICE </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  view (below) is nonzero, it indicates that PGA_AGGREGATE_TARGET is too small to even </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  meet the minimum PGA memory needs. If PGA_AGGREGATE_TARGET is set within the over </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  allocation zone, the memory manager will over-allocate memory AND  actual PGA memory </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  consumed will be more than the limit you set. It is therefore meaningless to set a </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  value of PGA_AGGREGATE_TARGET in that zone. After eliminating over-allocations, the </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  goal is to maximize the PGA cache hit percentage, based on your response-time requirement </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">  AND  memory constraints. </font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name FORMAT a79     HEADING 'Instance_Name'    ENTMAP OFF
COLUMN name          FORMAT a79     HEADING 'Parameter Name'   ENTMAP OFF
COLUMN value         FORMAT a79     HEADING 'Value'            ENTMAP OFF


-- BREAK ON report ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , p.name    name
  , (CASE p.name
         WHEN 'pga_aggregate_target' THEN '<div align="right">' || TO_CHAR(p.value, '999,999,999,999,999') || '</div>'
     ELSE
         '<div align="right">' || p.value || '</div>'
     END) value
FROM
    gv$parameter p
  , gv$instance  i
WHERE
      p.inst_id = i.inst_id
  AND  p.name IN ('pga_aggregate_target', 'workarea_size_policy')
ORDER BY
    i.instance_name
  , p.name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 117 for section: prompt Notes:
hc_q_prompt_notes_117() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_117_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name                  FORMAT a79                   HEADING 'Instance_Name'               ENTMAP OFF
COLUMN pga_target_for_estimate        FORMAT 999,999,999,999,999   HEADING 'PGA Target for Estimate'     ENTMAP OFF
COLUMN estd_extra_bytes_rw            FORMAT 999,999,999,999,999   HEADING 'Estimated Extra Bytes R/W'   ENTMAP OFF
COLUMN estd_pga_cache_hit_percentage  FORMAT 999,999,999,999,999   HEADING 'Estimated PGA Cache Hit %'   ENTMAP OFF
COLUMN estd_overalloc_count           FORMAT 999,999,999,999,999   HEADING 'ESTD_OVERALLOC_COUNT'        ENTMAP OFF


-- BREAK ON report ON instance_name

SELECT
    '<div align="left"><font color="#336699"><b>' || i.instance_name || '</b></font></div>'  instance_name
  , p.pga_target_for_estimate
  , p.estd_extra_bytes_rw
  , p.estd_pga_cache_hit_percentage
  , p.estd_overalloc_count
FROM
    gv$pga_target_advice p
  , gv$instance  i
WHERE
    p.inst_id = i.inst_id
ORDER BY
    i.instance_name
  , p.pga_target_for_estimate;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 118 for section: prompt Notes:
hc_q_prompt_notes_118() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_118_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                         - FILE I/O STATISTICS -                            |

-- +----------------------------------------------------------------------------+
host echo "            IO. . ." 

prompt  <a name="database_fileioinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>IO</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="file_io_statistics"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>IO</b></font><hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">Ordered by "Physical Reads" since last startup of the Oracle instance  </font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN tablespace_name   FORMAT a50                   HEAD 'Tablespace'       ENTMAP OFF
COLUMN fname                                          HEAD 'File Name'        ENTMAP OFF
COLUMN phyrds            FORMAT 999,999,999,999,999   HEAD 'Physical Reads'   ENTMAP OFF
COLUMN phywrts           FORMAT 999,999,999,999,999   HEAD 'Physical Writes'  ENTMAP OFF
COLUMN read_pct                                       HEAD 'Read Pct.'        ENTMAP OFF
COLUMN write_pct                                      HEAD 'Write Pct.'       ENTMAP OFF
COLUMN total_io          FORMAT 999,999,999,999,999   HEAD 'Total I/O'        ENTMAP OFF


-- BREAK ON report

--COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF phyrds phywrts total_io ON report

SELECT df.con_id,
       '<font color="#336699"><b>' || df.tablespace_name || '</b></font>' tablespace_name,
       df.file_name fname,
       fs.phyrds phyrds,
       '<div align="right">' ||
       ROUND((fs.phyrds * 100) / (fst.pr + tst.pr), 2) || '%</div>' read_pct,
       fs.phywrts phywrts,
       '<div align="right">' ||
       ROUND((fs.phywrts * 100) / (fst.pw + tst.pw), 2) || '%</div>' write_pct,
       (fs.phyrds + fs.phywrts) total_io
  FROM cdb_data_files df,
       v$filestat fs,
       (SELECT f.CON_ID,sum(f.phyrds) pr, sum(f.phywrts) pw FROM v$filestat f group by f.CON_ID) fst,
       (SELECT t.CON_ID,sum(t.phyrds) pr, sum(t.phywrts) pw FROM v$tempstat t group by t.CON_ID) tst
 WHERE df.file_id = fs.file#
   and Df.con_id = fs.CON_ID
	 and Df.con_id=fst.con_id
	 and Df.con_id=tst.con_id
UNION all
SELECT tf.con_id,
       '<font color="#336699"><b>' || tf.tablespace_name || '</b></font>' tablespace_name,
       tf.file_name fname,
       ts.phyrds phyrds,
       '<div align="right">' ||
       ROUND((ts.phyrds * 100) / (fst.pr + tst.pr), 2) || '%</div>' read_pct,
       ts.phywrts phywrts,
       '<div align="right">' ||
       ROUND((ts.phywrts * 100) / (fst.pw + tst.pw), 2) || '%</div>' write_pct,
       (ts.phyrds + ts.phywrts) total_io
  FROM cdb_temp_files tf,
       v$tempstat ts,
       (SELECT  f.CON_ID,sum(f.phyrds) pr, sum(f.phywrts) pw FROM v$filestat f group by f.CON_ID) fst,
       (SELECT t.con_id,sum(t.phyrds) pr, sum(t.phywrts) pw FROM v$tempstat t group by t.CON_ID) tst
 WHERE tf.file_id = ts.file#
   and tf.con_id = ts.con_id 
	 and tf.con_id=fst.con_id
	 and tf.CON_ID=tst.con_id
 ORDER BY con_id, phyrds DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 119 for section: prompt Notes:
hc_q_prompt_notes_119() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_119_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - FILE I/O TIMINGS -                             |

-- +----------------------------------------------------------------------------+


prompt  <a name="file_io_timings"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>IO</b></font><hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,Geneva,sans-serif">Average time (in milliseconds) for an I/O call per datafile since last startup of the Oracle instance - (ordered by Physical Reads)</font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN fname                                           HEAD 'File Name'                                      ENTMAP OFF
COLUMN phyrds            FORMAT 999,999,999,999,999    HEAD 'Physical Reads'                                 ENTMAP OFF
COLUMN read_rate         FORMAT 999,999,999,999,999.99 HEAD 'Average Read Time<br>(milliseconds per read)'   ENTMAP OFF
COLUMN phywrts           FORMAT 999,999,999,999,999    HEAD 'Physical Writes'                                ENTMAP OFF
COLUMN write_rate        FORMAT 999,999,999,999,999.99 HEAD 'Average Write Time<br>(milliseconds per write)' ENTMAP OFF


-- BREAK ON report

--COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF phyrds phywrts ON report

--COMPUTE avg LABEL '<font color="#990000"><b>Average: </b></font>' OF read_rate write_rate ON report

SELECT s.CON_ID, '<b><font color="#336699">' || d.name || '</font></b>' fname,
       s.phyrds phyrds,
       ROUND((s.readtim / GREATEST(s.phyrds, 1)), 2) read_rate,
       s.phywrts phywrts,
       ROUND((s.writetim / GREATEST(s.phywrts, 1)), 2) write_rate
  FROM v$filestat s, v$datafile d
 WHERE s.file# = d.file#  
 and s.CON_ID=d.CON_ID
UNION
SELECT s.CON_ID, '<b><font color="#336699">' || t.name || '</font></b>' fname,
       s.phyrds phyrds,
       ROUND((s.readtim / GREATEST(s.phyrds, 1)), 2) read_rate,
       s.phywrts phywrts,
       ROUND((s.writetim / GREATEST(s.phywrts, 1)), 2) write_rate
  FROM v$tempstat s, v$tempfile t
 WHERE s.file# = t.file# 
 and s.CON_ID=t.CON_ID
 ORDER BY 1,3 DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 120 for section: prompt Notes:
hc_q_prompt_notes_120() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_120_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

-- +----------------------------------------------------------------------------+

-- |                    - AVERAGE OVERALL I/O PER SECOND -                      |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="average_overall_io_per_sec"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Average Overall I/O per Second</b></font><hr align="left" width="450">
 

prompt   <font face="Courier New,Helvetica,Geneva,sans-serif">Average overall I/O calls (physical read/write calls) since last startup of the Oracle instance</font>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
DECLARE
 
CURSOR get_file_io IS
  SELECT
      NVL(SUM(a.phyrds + a.phywrts), 0)  sum_datafile_io
    , TO_NUMBER(null)                    sum_tempfile_io
  FROM
      v$filestat a
  UNION
  SELECT
      TO_NUMBER(null)                    sum_datafile_io
    , NVL(SUM(b.phyrds + b.phywrts), 0)  sum_tempfile_io
  FROM
      v$tempstat b;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 121 for section: prompt Notes:
hc_q_prompt_notes_121() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_121_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
current_time           DATE;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 122 for section: prompt Notes:
hc_q_prompt_notes_122() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_122_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
elapsed_time_seconds   NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 123 for section: prompt Notes:
hc_q_prompt_notes_123() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_123_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
sum_datafile_io        NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 124 for section: prompt Notes:
hc_q_prompt_notes_124() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_124_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
sum_datafile_io2       NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 125 for section: prompt Notes:
hc_q_prompt_notes_125() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_125_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
sum_tempfile_io        NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 126 for section: prompt Notes:
hc_q_prompt_notes_126() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_126_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
sum_tempfile_io2       NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 127 for section: prompt Notes:
hc_q_prompt_notes_127() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_127_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
total_io               NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 128 for section: prompt Notes:
hc_q_prompt_notes_128() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_128_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
datafile_io_per_sec    NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 129 for section: prompt Notes:
hc_q_prompt_notes_129() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_129_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
tempfile_io_per_sec    NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 130 for section: prompt Notes:
hc_q_prompt_notes_130() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_130_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
total_io_per_sec       NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 131 for section: prompt Notes:
hc_q_prompt_notes_131() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_131_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
BEGIN
    OPEN get_file_io;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 132 for section: prompt Notes:
hc_q_prompt_notes_132() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_132_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
FOR i IN 1..2 LOOP
      FETCH get_file_io INTO sum_datafile_io, sum_tempfile_io;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 133 for section: prompt Notes:
hc_q_prompt_notes_133() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_133_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
IF i = 1 THEN
        sum_datafile_io2 := sum_datafile_io;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 134 for section: prompt Notes:
hc_q_prompt_notes_134() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_134_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
ELSE
        sum_tempfile_io2 := sum_tempfile_io;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 135 for section: prompt Notes:
hc_q_prompt_notes_135() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_135_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END IF;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 136 for section: prompt Notes:
hc_q_prompt_notes_136() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_136_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END LOOP;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 137 for section: prompt Notes:
hc_q_prompt_notes_137() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_137_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
total_io := sum_datafile_io2 + sum_tempfile_io2;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 138 for section: prompt Notes:
hc_q_prompt_notes_138() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_138_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT sysdate INTO current_time FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 139 for section: prompt Notes:
hc_q_prompt_notes_139() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_139_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT CEIL ((current_time - startup_time)*(60*60*24)) INTO elapsed_time_seconds FROM v$instance;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 140 for section: prompt Notes:
hc_q_prompt_notes_140() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_140_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
datafile_io_per_sec := sum_datafile_io2/elapsed_time_seconds;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 141 for section: prompt Notes:
hc_q_prompt_notes_141() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_141_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
tempfile_io_per_sec := sum_tempfile_io2/elapsed_time_seconds;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 142 for section: prompt Notes:
hc_q_prompt_notes_142() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_142_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
total_io_per_sec    := total_io/elapsed_time_seconds;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 143 for section: prompt Notes:
hc_q_prompt_notes_143() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_143_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<table width="60%" border="1" bordercolor="#000000" cellspacing="0px" style="border-collapse:collapse">');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 144 for section: prompt Notes:
hc_q_prompt_notes_144() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_144_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="left" width="50%">Elapsed Time (in seconds)</th><td width="50%">' || TO_CHAR(elapsed_time_seconds, '9,999,999,999,999') || '</td></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 145 for section: prompt Notes:
hc_q_prompt_notes_145() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_145_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="left" width="50%">Datafile I/O Calls per Second</th><td width="50%">' || TO_CHAR(datafile_io_per_sec, '9,999,999,999,999') || '</td></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 146 for section: prompt Notes:
hc_q_prompt_notes_146() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_146_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="left" width="50%">Tempfile I/O Calls per Second</th><td width="50%">' || TO_CHAR(tempfile_io_per_sec, '9,999,999,999,999') || '</td></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 147 for section: prompt Notes:
hc_q_prompt_notes_147() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_147_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="left" width="50%">Total I/O Calls per Second</th><td width="50%">' || TO_CHAR(total_io_per_sec, '9,999,999,999,999') || '</td></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 148 for section: prompt Notes:
hc_q_prompt_notes_148() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_148_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('</table>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 149 for section: prompt Notes:
hc_q_prompt_notes_149() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_149_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 150 for section: prompt Notes:
hc_q_prompt_notes_150() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_150_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
/
 

prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                        - REDO LOG CONTENTION -                             |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="redo_log_contention"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Redo Log Contention</b></font><hr align="left" width="450">
 

prompt   <font face="Courier New,Helvetica,Geneva,sans-serif">All latches like redo% - (ordered by misses)</font>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN name             FORMAT a95                        HEADING 'Latch Name'
COLUMN gets             FORMAT 999,999,999,999,999,999    HEADING 'Gets'
COLUMN misses           FORMAT 999,999,999,999            HEADING 'Misses'
COLUMN sleeps           FORMAT 999,999,999,999            HEADING 'Sleeps'
COLUMN immediate_gets   FORMAT 999,999,999,999,999,999    HEADING 'Immediate Gets'
COLUMN immediate_misses FORMAT 999,999,999,999            HEADING 'Immediate Misses'
 

-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total:</b></font>' OF gets misses sleeps immediate_gets immediate_misses ON report
 
SELECT
    '<div align="left"><font color="#336699"><b>' || INITCAP(name) || '</b></font></div>' name
  , gets
  , misses
  , sleeps
  , immediate_gets
  , immediate_misses
FROM sys.v_$latch
WHERE name LIKE 'redo%'
ORDER BY 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 151 for section: prompt Notes:
hc_q_prompt_notes_151() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_151_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt 

prompt  <b>System statistics like redo%</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN name    FORMAT a95                   HEADING 'Statistics Name'
COLUMN value   FORMAT 999,999,999,999,999   HEADING 'Value'
 
SELECT
    '<div align="left"><font color="#336699"><b>' || INITCAP(name) || '</b></font></div>' name
  , value
WHERE name LIKE 'redo%'
ORDER BY 1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 152 for section: prompt Notes:
hc_q_prompt_notes_152() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_152_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


-- +----------------------------------------------------------------------------+

-- |                           - FULL TABLE SCANS -                             |

-- +----------------------------------------------------------------------------+


prompt  <a name="full_table_scans"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN large_table_scans   FORMAT 999,999,999,999,999  HEADING 'Large Table Scans'   ENTMAP OFF
COLUMN small_table_scans   FORMAT 999,999,999,999,999  HEADING 'Small Table Scans'   ENTMAP OFF
COLUMN pct_large_scans                                 HEADING 'Pct. Large Scans'    ENTMAP OFF

SELECT
    a.value large_table_scans
  , b.value small_table_scans
  , '<div align="right">' || ROUND(100*a.value/DECODE((a.value+b.value),0,1,(a.value+b.value)),2) || '%</div>' pct_large_scans
FROM
WHERE
      a.name = 'table scans (long tables)'
  AND  b.name = 'table scans (short tables)';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 153 for section: prompt Notes:
hc_q_prompt_notes_153() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_153_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                                - SORTS -                                   |

-- +----------------------------------------------------------------------------+


prompt  <a name="sorts"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Sort Activity</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN disk_sorts     FORMAT 999,999,999,999,999    HEADING 'Disk Sorts'       ENTMAP OFF
COLUMN memory_sorts   FORMAT 999,999,999,999,999    HEADING 'Memory Sorts'     ENTMAP OFF
COLUMN pct_disk_sorts                               HEADING 'Pct. Disk Sorts'  ENTMAP OFF

SELECT
    a.value   disk_sorts
  , b.value   memory_sorts
  , '<div align="right">' || ROUND(100*a.value/DECODE((a.value+b.value),0,1,(a.value+b.value)),2) || '%</div>' pct_disk_sorts
FROM
WHERE
      a.name = 'sorts (disk)'
  AND  b.name = 'sorts (memory)';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 154 for section: prompt Notes:
hc_q_prompt_notes_154() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_154_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT name,
       cnt,
       DECODE(total, 0, 0, round(cnt * 100 / total, 4)) "Hit Ratio"
  FROM (SELECT name, value cnt, (sum(value) over()) total
         WHERE name like 'workarea exec%');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 155 for section: prompt Notes:
hc_q_prompt_notes_155() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_155_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 
 
 

-- +----------------------------------------------------------------------------+

-- |                               - OUTLINES -                                 |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_outlines"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Outlines</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN category       FORMAT a125    HEADING 'Category'     ENTMAP OFF
COLUMN owner          FORMAT a125    HEADING 'Owner'        ENTMAP OFF
COLUMN name           FORMAT a125    HEADING 'Name'         ENTMAP OFF
COLUMN used                          HEADING 'Used?'        ENTMAP OFF
COLUMN timestamp      FORMAT a125    HEADING 'Time Stamp'   ENTMAP OFF
COLUMN version                       HEADING 'Version'      ENTMAP OFF
COLUMN sql_text                      HEADING 'SQL Text'     ENTMAP OFF
 
SELECT d.CON_ID,
       '<div nowrap><font color="#336699"><b>' || category ||
       '</b></font></div>' category,
       owner,
       name,
       used,
       '<div nowrap align="right">' ||
       TO_CHAR(timestamp, 'mm/dd/yyyy HH24:MI:SS') || '</div>' timestamp,
       version
  FROM cdb_outlines d
 ORDER BY d.CON_ID, category, owner, name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 156 for section: prompt Notes:
hc_q_prompt_notes_156() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_156_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                            - OUTLINE HINTS -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_outline_hints"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Outline Hints</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN category       FORMAT a125    HEADING 'Category'        ENTMAP OFF
COLUMN owner          FORMAT a125    HEADING 'Owner'           ENTMAP OFF
COLUMN name           FORMAT a125    HEADING 'Name'            ENTMAP OFF
COLUMN node                          HEADING 'Node'            ENTMAP OFF
COLUMN join_pos                      HEADING 'Join Position'   ENTMAP OFF
COLUMN hint                          HEADING 'Hint'            ENTMAP OFF
 

-- BREAK ON category ON owner ON name
 
SELECT a.CON_ID,
       '<div nowrap><font color="#336699"><b>' || a.category ||
       '</b></font></div>' category,
       a.owner owner,
       a.name name,
       '<div align="center">' || b.node || '</div>' node,
       '<div align="center">' || b.join_pos || '</div>' join_pos,
       b.hint hint
  FROM cdb_outlines a, cdb_outline_hints b
 WHERE a.owner = b.owner
   AND b.name = b.name
   and a.CON_ID = b.CON_ID
 ORDER BY category, owner, name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 157 for section: prompt Notes:
hc_q_prompt_notes_157() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_157_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


-- +----------------------------------------------------------------------------+

-- |                - SQL STATEMENTS WITH MOST BUFFER GETS -                    |

-- +----------------------------------------------------------------------------+
host echo "            SQL. . ." 

prompt  <a name="database_SQLinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>SQL</b></font><hr align="left" width="800">

prompt  <p>


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. SYS, SYSTEM, db_monitor) ,SELECT database lever top 10 rows</font></b>


prompt  <a name="sql_statements_with_most_buffer_gets"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Top 10 SQL statements with buffer gets greater than 1000 </font></b> 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'                 ENTMAP OFF
COLUMN buffer_gets     FORMAT 999,999,999,999,999   HEADING 'Buffer Gets'              ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'               ENTMAP OFF
COLUMN gets_per_exec   FORMAT 999,999,999,999,999   HEADING 'Buffer Gets / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON 

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.buffer_gets desc) rank_order
          FROM gv$sqlarea ai 
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%'       ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.buffer_gets DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 158 for section: prompt Notes:
hc_q_prompt_notes_158() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_158_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                 - SQL STATEMENTS WITH MOST DISK READS -                    |

-- +----------------------------------------------------------------------------+


prompt  <a name="sql_statements_with_most_disk_reads"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Top 10 SQL statements with disk reads greater than 1000</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.DISK_READS desc) rank_order
          FROM gv$sqlarea ai 
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%'      ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.DISK_READS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 159 for section: prompt Notes:
hc_q_prompt_notes_159() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_159_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_statements_ELAPSED_TIMEtop10"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON	

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.ELAPSED_TIME desc) rank_order
          FROM gv$sqlarea ai
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%'      ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.ELAPSED_TIME DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 160 for section: prompt Notes:
hc_q_prompt_notes_160() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_160_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_statements_execute10"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
              ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.EXECUTIONS desc) rank_order
          FROM gv$sqlarea ai
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR') 	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%'      ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.EXECUTIONS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 161 for section: prompt Notes:
hc_q_prompt_notes_161() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_161_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_statements_parse10"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.PARSE_CALLS desc) rank_order
          FROM gv$sqlarea ai 
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%' ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.EXECUTIONS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 162 for section: prompt Notes:
hc_q_prompt_notes_162() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_162_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_statements_version_count10"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>VERSION_COUNT TOP10SQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.VERSION_COUNT desc) rank_order
          FROM gv$sqlarea ai 
         WHERE buffer_gets > 1000
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')  	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%' ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.VERSION_COUNT DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 163 for section: prompt Notes:
hc_q_prompt_notes_163() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_163_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_statements_with_most_sharable_mem"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>TOP10SQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: shared memory,SQLlibrary cacheTOP SQL </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT INST_ID,
       '<font color="#336699"><b>' || UPPER(username) || '</b></font>' username,
       SQL_ID,
       A.sharable_mem_m,
       a.buffer_gets buffer_gets,
       DISK_READS,
       LAST_LOAD_TIME,
       LAST_ACTIVE_TIME,
       a.executions,
       PARSE_CALLS,
       VERSION_COUNT,
       loads,
       ((ELAPSED_TIME / 1000000)) ELAPSED_TIME,
       round(a.buffer_gets / DECODE(a.executions, 0, 1, a.executions), 3) buffer_gets_per_exec,
       round(a.disk_reads / DECODE(a.executions, 0, 1, a.executions), 3) disk_reads_per_exec,
       (a.ELAPSED_TIME / 1000000 /
                                       DECODE(a.executions,
                                              0,
                                              1,
                                              a.executions)) ELAPSED_TIME_per_exec,
       client_info,
       a.sql_text sql_text
  FROM (SELECT ai.INST_ID,
               round(ai.sharable_mem/1024/1024) sharable_mem_m,
               ai.buffer_gets,
               ai.DISK_READS,
               ai.executions,
               ai.PARSE_CALLS,
               ai.sql_text,
               ai.parsing_user_id,
               ai.SQL_ID,
               ai.ELAPSED_TIME,
               ai.LAST_LOAD_TIME,
               ai.LAST_ACTIVE_TIME,
               PARSING_SCHEMA_NAME username,
               VERSION_COUNT,
               loads,
               ai.MODULE || '
--' || ai.ACTION client_info,
               DENSE_RANK() over(ORDER BY ai.DISK_READS desc) rank_order
          FROM gv$sqlarea ai 
         WHERE sharable_mem > 0.1*1024*1024
           AND  ai.PARSING_SCHEMA_NAME   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 	
	   AND  ai.ACTION not in ('JOB_AUTO_TUNING_SQL_LHR')	
           AND  ai.SQL_TEXT NOT LIKE '/* SQL Analyze(%'      ) a
 WHERE rank_order <= 10
 ORDER BY INST_ID, a.DISK_READS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 164 for section: prompt Notes:
hc_q_prompt_notes_164() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_164_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="disksortmax_sql"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DISK_SORTSQL</b></font><hr align="left" width="600">
	
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT SESS.INST_ID,
       SESS.USERNAME,
       SESS.SID,
       SESS.SERIAL#,
       SORT1.SQL_ID,
       ((SQL.ELAPSED_TIME / SQL.EXECUTIONS /
                                       1000000)) ELAPSED_TIME,
       SQL.SQL_TEXT,
       SQL.ADDRESS,
       SORT1.BLOCKS
  FROM GV$SESSION SESS, GV$SQLAREA SQL, GV$SORT_USAGE SORT1
 WHERE SESS.SERIAL# = SORT1.SESSION_NUM
   AND SORT1.SQLADDR = SQL.ADDRESS
   AND SORT1.SQLHASH = SQL.HASH_VALUE
   AND SESS.INST_ID = SQL.INST_ID
   AND SESS.INST_ID = SORT1.INST_ID
   AND SORT1.BLOCKS > 200
 ORDER BY SESS.INST_ID, SORT1.BLOCKS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 165 for section: prompt Notes:
hc_q_prompt_notes_165() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_165_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="ashmax_sql"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASHSQL</b></font><hr align="left" width="600">
	
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username        FORMAT a75                   HEADING 'Username'           ENTMAP OFF
COLUMN disk_reads      FORMAT 999,999,999,999,999   HEADING 'Disk Reads'         ENTMAP OFF
COLUMN executions      FORMAT 999,999,999,999,999   HEADING 'Executions'         ENTMAP OFF
COLUMN reads_per_exec  FORMAT 999,999,999,999,999   HEADING 'Reads / Execution'  ENTMAP OFF
COLUMN sql_text        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_Text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN LAST_LOAD_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_LOAD_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LAST_ACTIVE_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ACTIVE_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN client_info   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CLIENT_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' ENTMAP OFF
SET DEFINE ON

SELECT * FROM (SELECT *
  FROM (SELECT DISTINCT ASH.INST_ID,
                        ASH.SESSION_ID SID,
                        ASH.SESSION_SERIAL# SERIAL#,
                        GVS.PARSING_SCHEMA_NAME USERNAME,
                        ASH.SESSION_TYPE,
                        ASH.SQL_ID,
                        ASH.SQL_CHILD_NUMBER,
                        ASH.SQL_OPNAME,
                        ASH.EVENT,
                        ASH.SESSION_STATE,
                        ASH.BLOCKING_SESSION,
                        ASH.BLOCKING_SESSION_SERIAL#,
                        ASH.BLOCKING_INST_ID BLOCKING_INSTANCE,
                        ASH.SQL_EXEC_ID,
                        ASH.SQL_EXEC_START,
                        (ASH.MODULE || '
--' || ASH.ACTION || '--' ||
                        ASH.PROGRAM || '
--' || ASH.MACHINE || '--' ||
                        ASH.CLIENT_ID || '
--' || ASH.SESSION_TYPE) SESSION_INFO,
                        COUNT(*) ASH_COUNTS,
                        (GVS.ELAPSED_TIME / 1000000) ELAPSED_TIME_S,
                        (GVS.CPU_TIME / 1000000) CPU_TIME,
                        GVS.EXECUTIONS,
                        GVS.DISK_READS,
                        GVS.BUFFER_GETS,
                        GVS.LAST_ACTIVE_TIME,
                        GVS.LAST_LOAD_TIME,
                        GVS.PHYSICAL_READ_BYTES,
                        GVS.PHYSICAL_WRITE_BYTES,
                        GVS.SQL_TEXT,
                        DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) RANK_ORDER
         WHERE ASH.INST_ID = GVS.INST_ID
           AND GVS.SQL_ID = ASH.SQL_ID
           AND ASH.SQL_ID IS NOT NULL
           AND GVS.DISK_READS >= 100
         GROUP BY ASH.INST_ID,
                  ASH.SESSION_ID,
                  ASH.SESSION_SERIAL#,
                  ASH.SESSION_TYPE,
                  ASH.SQL_ID,
                  ASH.SQL_CHILD_NUMBER,
                  ASH.SQL_OPNAME,
                  ASH.SQL_EXEC_ID,
                  ASH.EVENT,
                  ASH.SESSION_STATE,
                  ASH.BLOCKING_SESSION,
                  ASH.BLOCKING_SESSION_SERIAL#,
                  ASH.BLOCKING_INST_ID,
                  ASH.CLIENT_ID,
                  ASH.MACHINE,
                  GVS.PARSING_SCHEMA_NAME,
                  ASH.SQL_EXEC_START,
                  (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' ||
                  ASH.MACHINE || '
--' || ASH.CLIENT_ID || '--' ||
                  ASH.SESSION_TYPE),
                  (GVS.ELAPSED_TIME / 1000000),
                  (GVS.CPU_TIME / 1000000),
                  GVS.EXECUTIONS,
                  GVS.DISK_READS,
                  GVS.BUFFER_GETS,
                  GVS.LAST_ACTIVE_TIME,
                  GVS.LAST_LOAD_TIME,
                  GVS.PHYSICAL_READ_BYTES,
                  GVS.PHYSICAL_WRITE_BYTES,
                  GVS.SQL_TEXT
        HAVING COUNT(*) > 10) V
 WHERE RANK_ORDER <= 10
 ORDER BY V.INST_ID,
          V.SID,
          V.SERIAL#,
          V.SESSION_TYPE,
          V.SQL_ID) WHERE ROWNUM<=100;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 166 for section: prompt Notes:
hc_q_prompt_notes_166() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_166_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● CPUSQL

SELECT ASH.INST_ID,
       ASH.SQL_ID,
       (SELECT VS.SQL_TEXT
          FROM GV$SQLAREA VS
         WHERE VS.SQL_ID = ASH.SQL_ID
           AND ASH.INST_ID = VS.INST_ID
	   AND ROWNUM<=1) SQL_TEXT,
       ASH.SQL_CHILD_NUMBER,
       ASH.SESSION_INFO,
       COUNTS,
       PCTLOAD * 100 || '%' PCTLOAD
  FROM (SELECT ASH.INST_ID,
               ASH.SQL_ID,
               ASH.SQL_CHILD_NUMBER,
               (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' ||
               ASH.CLIENT_ID || '
--' || ASH.SESSION_TYPE) SESSION_INFO,
               COUNT(*) COUNTS,
               ROUND(COUNT(*) / SUM(COUNT(*)) OVER(), 2) PCTLOAD,
               DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) RANK_ORDER
         WHERE ASH.SESSION_TYPE <> 'BACKGROUND'
           AND ASH.SESSION_STATE = 'ON CPU'
         GROUP BY ASH.INST_ID,
                  ASH.SQL_ID,
                  ASH.SQL_CHILD_NUMBER,
                  (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' ||
                  ASH.CLIENT_ID || '
--' || ASH.SESSION_TYPE)) ASH
 WHERE RANK_ORDER <= 10
 ORDER BY COUNTS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 167 for section: prompt Notes:
hc_q_prompt_notes_167() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_167_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● I/OSQL
SELECT ASH.INST_ID,
       ASH.SQL_ID,
       (SELECT VS.SQL_TEXT
          FROM GV$SQLAREA VS
         WHERE VS.SQL_ID = ASH.SQL_ID
           AND ASH.INST_ID = VS.INST_ID
	   AND ROWNUM<=1) SQL_TEXT,
       ASH.SQL_CHILD_NUMBER,
       ASH.SESSION_INFO,
       COUNTS,
       PCTLOAD * 100 || '%' PCTLOAD
  FROM (SELECT ASH.INST_ID,
               ASH.SQL_ID,
               ASH.SQL_CHILD_NUMBER,
               (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' ||
               ASH.CLIENT_ID || '
--' || ASH.SESSION_TYPE) SESSION_INFO,
               COUNT(*) COUNTS,
               ROUND(COUNT(*) / SUM(COUNT(*)) OVER(), 2) PCTLOAD,
               DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) RANK_ORDER
         WHERE ASH.SESSION_TYPE <> 'BACKGROUND'
           AND ASH.SESSION_STATE = 'WAITING'
           AND ASH.WAIT_CLASS = 'USER I/O'
         GROUP BY ASH.INST_ID,
                  ASH.SQL_ID,
                  ASH.SQL_CHILD_NUMBER,
                  (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' ||
                  ASH.CLIENT_ID || '
--' || ASH.SESSION_TYPE)) ASH
 WHERE RANK_ORDER <= 10
 ORDER BY COUNTS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 168 for section: prompt Notes:
hc_q_prompt_notes_168() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_168_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● SQL
SELECT ASH.INST_ID,
       ASH.SQL_ID,
       (SELECT VS.SQL_TEXT
          FROM GV$SQLAREA VS
         WHERE VS.SQL_ID = ASH.SQL_ID
           AND ASH.INST_ID = VS.INST_ID
	   AND ROWNUM<=1) SQL_TEXT,
       ASH.SQL_CHILD_NUMBER, 
       ASH.SESSION_INFO,
       "CPU",
       "WAIT",
       "IO",
       "TOTAL"
  FROM (SELECT ASH.INST_ID,
               ASH.SQL_ID,
               ASH.SQL_CHILD_NUMBER, 
               (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM ||  '--' || ASH.CLIENT_ID || '--' ||
               ASH.SESSION_TYPE) SESSION_INFO,
               SUM(DECODE(ASH.SESSION_STATE, 'ON CPU', 1, 0)) "CPU",
               SUM(DECODE(ASH.SESSION_STATE, 'WAITING', 1, 0)) -
               SUM(DECODE(ASH.SESSION_STATE,
                          'WAITING',
                          DECODE(ASH.WAIT_CLASS, 'USER I/O', 1, 0),
                          0)) "WAIT",
               SUM(DECODE(ASH.SESSION_STATE,
                          'WAITING',
                          DECODE(ASH.WAIT_CLASS, 'USER I/O', 1, 0),
                          0)) "IO",
               SUM(DECODE(ASH.SESSION_STATE, 'ON CPU', 1, 1)) "TOTAL",
               DENSE_RANK() OVER(ORDER BY SUM(DECODE(ASH.SESSION_STATE, 'ON CPU', 1, 1)) DESC) RANK_ORDER
         WHERE SQL_ID IS NOT NULL
         GROUP BY ASH.INST_ID,
                  ASH.SQL_ID,
                  ASH.SQL_CHILD_NUMBER, 
                  (ASH.MODULE || '
--' || ASH.ACTION || '--' || ASH.PROGRAM || '--' || ASH.CLIENT_ID || '--' ||
                  ASH.SESSION_TYPE)) ASH
 WHERE RANK_ORDER <= 10
 ORDER BY TOTAL DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 169 for section: prompt Notes:
hc_q_prompt_notes_169() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_169_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="running_rubish_sql_11g"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SQLRUNNING_11G</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN SQL_TEXT        FORMAT a500                  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_TEXT&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'     ENTMAP OFF
COLUMN SQL_EXEC_START   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_EXEC_START&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN LOGON_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOGON_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN monitor_types   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;monitor_types&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

WITH TMPS AS
 (SELECT WB.INST_ID INST_ID,
       WB.SID SID,
       WB.SERIAL#,
       WB.SPID,
       WB.OSUSER,
       WB.USERNAME,
       WA.PLAN_DEPTH,
       WA.PLAN_OPERATION PLAN_OPERATION,
       WA.PLAN_OPTIONS,
       WA.PLAN_PARTITION_START,
       WA.PLAN_PARTITION_STOP,
       WA.STARTS,
       WA.PLAN_COST,
       WA.PLAN_CARDINALITY,
       NVL(WB.SQL_ID, WA.SQL_ID) SQL_ID,
       WB.SQL_EXEC_START,
       WA.PX_SERVERS_REQUESTED,
       WA.PX_SERVERS_ALLOCATED,
       WA.PX_MAXDOP,
       WA.ELAPSED_TIME_S ELAPSED_TIME_S,
       WA.CPU_TIME CPU_TIME,
       WA.BUFFER_GETS,
       WA.PHYSICAL_READ_BYTES,
       WA.PHYSICAL_WRITE_BYTES,
       WA.USER_IO_WAIT_TIME USER_IO_WAIT_TIME,
       NVL((SELECT NS.SQL_TEXT
          FROM GV$SQLAREA NS
         WHERE NS.SQL_ID = WB.SQL_ID
           AND NS.INST_ID = WB.INST_ID),WA.SQL_TEXT) SQL_TEXT,
       WB.LOGON_TIME,
       WB.SQL_EXEC_ID,
       WB.EVENT,
       WB.BLOCKING_INSTANCE BLOCKING_INSTANCE,
       WB.BLOCKING_SESSION BLOCKING_SESSION,
       WB.BLOCKING_SESSION_SERIAL# BLOCKING_SESSION_SERIAL#,
       WB.TADDR,
       WB.SADDR,
       WB.LAST_CALL_ET,
       (WB.SESSION_INFO || '
--' || WB.SESSION_TYPE || '--' || WB.MACHINE) SESSION_INFO,
       (SELECT NS.EXECUTIONS
          FROM GV$SQLAREA NS
         WHERE NS.SQL_ID = WB.SQL_ID
           AND NS.INST_ID = WB.INST_ID) EXECUTIONS,
       'SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(''' || WB.SQL_ID ||
       ''',' || WB.SQL_CHILD_NUMBER || ',''advanced''));' SQL_PLAN,
       WB.ASH_COUNTS,
       WB.SESSION_STATE
  FROM (SELECT A.INST_ID,
               A.SID,
               A.PLAN_DEPTH,
               A.PLAN_OPERATION PLAN_OPERATION,
               A.PLAN_OPTIONS,
               A.PLAN_PARTITION_START,
               A.PLAN_PARTITION_STOP,
               A.STARTS,
               MAX(A.PLAN_COST) OVER(PARTITION BY A.INST_ID, A.SID, A.KEY, A.SQL_EXEC_ID, A.SQL_ID) AS PLAN_COST,
               MAX(A.PLAN_CARDINALITY) OVER(PARTITION BY A.INST_ID, A.SID, A.KEY, A.SQL_EXEC_ID, A.SQL_ID) AS PLAN_CARDINALITY,
               A.SQL_ID,
               A.SQL_EXEC_START,
               B.PX_SERVERS_REQUESTED,
               B.PX_SERVERS_ALLOCATED,
               B.PX_MAXDOP,
               (B.ELAPSED_TIME / 1000000) ELAPSED_TIME_S,
               (B.CPU_TIME / 1000000) CPU_TIME,
               B.BUFFER_GETS,
               B.PHYSICAL_READ_BYTES,
               B.PHYSICAL_WRITE_BYTES,
               (B.USER_IO_WAIT_TIME / 1000000) USER_IO_WAIT_TIME,
               B.SQL_TEXT SQL_TEXT,
               (B.MODULE || '
--' || B.ACTION || '--' || B.PROGRAM || '--' ||
               B.PROCESS_NAME || '
--' || B.CLIENT_IDENTIFIER || '--' ||
               B.CLIENT_INFO || '
--' || B.SERVICE_NAME) SESSION_INFO,
               A.SQL_EXEC_ID
          FROM GV$SQL_PLAN_MONITOR A, GV$SQL_MONITOR B
         WHERE A.SID = B.SID
           AND A.KEY = B.KEY
           AND A.INST_ID = B.INST_ID
           AND A.SQL_EXEC_ID = B.SQL_EXEC_ID
           AND A.STATUS IN ('EXECUTING', 'DONE(ERROR)')
           AND B.STATUS IN ('EXECUTING', 'DONE(ERROR)')
           AND B.PROCESS_NAME NOT LIKE 'p%') WA
 RIGHT OUTER JOIN (SELECT ASH.INST_ID,
                          ASH.SESSION_ID SID,
                          ASH.SESSION_SERIAL# SERIAL#,
                          (SELECT PR.SPID
                             FROM GV$PROCESS PR
                            WHERE GVS.PADDR = PR.ADDR
                              AND PR.INST_ID = ASH.INST_ID) SPID,
                          ASH.SESSION_TYPE,
                          ASH.USER_ID,
                          ASH.SQL_ID,
                          ASH.SQL_CHILD_NUMBER,
                          ASH.SQL_OPNAME,
                          ASH.SQL_EXEC_ID,
                          NVL(ASH.EVENT, GVS.EVENT) EVENT,
                          ASH.SESSION_STATE,
                          ASH.BLOCKING_SESSION,
                          ASH.BLOCKING_SESSION_SERIAL#,
                          ASH.BLOCKING_INST_ID BLOCKING_INSTANCE,
                          ASH.CLIENT_ID,
                          ASH.MACHINE,
                          GVS.LAST_CALL_ET,
                          GVS.TADDR,
                          GVS.SADDR,
                          GVS.LOGON_TIME,
                          GVS.USERNAME,
                          GVS.OSUSER,
                          GVS.SQL_EXEC_START,
       (GVS.MODULE || '
--' || GVS.ACTION || '--' || GVS.PROGRAM || '--' ||
               GVS.PROCESS || '
--' || GVS.CLIENT_IDENTIFIER || '--' ||
               GVS.CLIENT_INFO || '
--' || GVS.SERVICE_NAME) SESSION_INFO,
                          COUNT(*) ASH_COUNTS
                    WHERE ASH.INST_ID = GVS.INST_ID
                      AND GVS.SQL_ID = ASH.SQL_ID
                      AND GVS.SQL_EXEC_ID = ASH.SQL_EXEC_ID
                      AND ASH.SESSION_ID = GVS.SID
                      AND ASH.SESSION_SERIAL# = GVS.SERIAL#
                      AND GVS.STATUS = 'ACTIVE'
                      AND ASH.SQL_ID IS NOT NULL
                    GROUP BY ASH.INST_ID,
                             ASH.SESSION_ID,
                             ASH.SESSION_SERIAL#,
                             ASH.SESSION_TYPE,
                             ASH.USER_ID,
                             ASH.SQL_ID,
                             ASH.SQL_CHILD_NUMBER,
                             ASH.SQL_OPNAME,
                             ASH.SQL_EXEC_ID,
                             NVL(ASH.EVENT, GVS.EVENT),
                             ASH.SESSION_STATE,
                             ASH.BLOCKING_SESSION,
                             ASH.BLOCKING_SESSION_SERIAL#,
                             ASH.BLOCKING_INST_ID,
                             ASH.CLIENT_ID,
                             ASH.MACHINE,
                             GVS.LAST_CALL_ET,
                             GVS.TADDR,
                             GVS.SADDR,
                             GVS.LOGON_TIME,
                             GVS.USERNAME,
                             GVS.OSUSER,
                             GVS.PADDR,  
                          (GVS.MODULE || '
--' || GVS.ACTION || '--' || GVS.PROGRAM || '--' ||
               GVS.PROCESS || '
--' || GVS.CLIENT_IDENTIFIER || '--' ||
               GVS.CLIENT_INFO || '
--' || GVS.SERVICE_NAME),
                             GVS.SQL_EXEC_START
                   HAVING COUNT(*) > 6) WB
    ON (WB.SID = WA.SID AND WB.INST_ID = WA.INST_ID AND
       WB.SQL_ID = WA.SQL_ID AND WB.SQL_EXEC_ID = WA.SQL_EXEC_ID)
)

------------------------------------------ 
SELECT DISTINCT T.INST_ID,
                T.SID,
                T.SERIAL#,
                T.SPID,
                T.OSUSER,
                T.USERNAME,
                T.EVENT,
                T.SESSION_STATE,
                T.SQL_TEXT,
                T.EXECUTIONS,
                T.ELAPSED_TIME_S,
                T.CPU_TIME,
                T.USER_IO_WAIT_TIME,
                T.BUFFER_GETS,
                T.PLAN_OPERATION,
    T.STARTS,
                T.PLAN_PARTITION_START,
                T.PLAN_PARTITION_STOP,
                T.PHYSICAL_READ_BYTES,
                T.PHYSICAL_WRITE_BYTES,
                T.BLOCKING_INSTANCE,
                T.BLOCKING_SESSION,
    T.BLOCKING_SESSION_SERIAL#,
                T.LAST_CALL_ET,
                T.SQL_ID,
                T.SQL_EXEC_START,
                T.SQL_PLAN,
                T.LOGON_TIME,
    T.ASH_COUNTS,
                T.SESSION_INFO, 
                '[' || COUNT(*) OVER(PARTITION BY T.INST_ID, T.SID, T.SERIAL#, T.SQL_ID) || ']' MONITOR_TYPES
  FROM TMPS T
 WHERE T.PLAN_OPERATION = 'MERGE JOIN'
   AND T.PLAN_OPTIONS = 'CARTESIAN'
   AND T.USERNAME NOT IN ('SYS')

UNION ALL


------------------------------------------ SQL
SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       '' MONITOR_TYPES
  FROM TMPS T
 WHERE T.ELAPSED_TIME_S > &V_ELAPSED_TIME 
--5 * 60 * 60
   AND (nvl(PLAN_DEPTH,1)=1)

UNION ALL


------------------------------------------ 

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       '' MONITOR_TYPES
  FROM TMPS T
 WHERE T.PLAN_OPERATION LIKE 'PARTITION%'
   AND T.PLAN_OPTIONS = 'ALL'
  
-- AND T.ELAPSED_TIME_S >= 0.5 * 60 * 60

UNION ALL


------------------------------------------ In Execution PlanCOST

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       'In Execution PlanCOST[' || T.PLAN_COST || ']' MONITOR_TYPES
  FROM TMPS T
 WHERE T.PLAN_COST >= &v_plan_cost
   AND (nvl(PLAN_DEPTH,1)=1)

UNION ALL

------------------------------------------ In Execution Plan

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO, 
       'In Execution Plan[' || T.PLAN_CARDINALITY || ']' MONITOR_TYPES
  FROM TMPS T
 WHERE T.PLAN_CARDINALITY > &v_PLAN_CARDINALITY
   AND (nvl(PLAN_DEPTH,1)=1)

 UNION ALL

------------------------------------------ SQL

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO, 
       'SQL[' || PX_MAXDOP || ']' MONITOR_TYPES
  FROM TMPS T
 WHERE T.PX_MAXDOP>=8
    AND (nvl(PLAN_DEPTH,1)=1)

UNION ALL

------------------------------------------ 

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME, 
       T.ASH_COUNTS,
       T.SESSION_INFO,
       '[' || ROUND(D.TIME_REMAINING) || ']' MONITOR_TYPES
  FROM TMPS T, GV$SESSION_LONGOPS D
 WHERE T.SQL_EXEC_ID = D.SQL_EXEC_ID
   AND T.SID = D.SID
   AND T.SERIAL# = D.SERIAL#
   AND D.TIME_REMAINING > 10
   AND T.INST_ID = D.INST_ID
   AND D.TIME_REMAINING >0
      AND (nvl(PLAN_DEPTH,1)=1)

 UNION ALL
 
------------------------------------------ 

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       '[' || T.EVENT || ']' MONITOR_TYPES
  FROM TMPS T
 WHERE T.EVENT  NOT IN ('db file sequential read', 'db file scattered read','db file parallel write','db file parallel read')
   AND (nvl(PLAN_DEPTH,1)=1)

 UNION ALL

------------------------------------------ TMPTablespace Overutilization

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       'SQLTMP[' || C.BYTES || ']Bytes' MONITOR_TYPES
  FROM TMPS T,
       (SELECT A.INST_ID, A.SESSION_ADDR, SUM(A.BLOCKS) * 8 * 1024 BYTES
          FROM GV$TEMPSEG_USAGE A
         GROUP BY A.INST_ID, A.SESSION_ADDR) C
 WHERE C.SESSION_ADDR = T.SADDR
   AND C.INST_ID = T.INST_ID
   AND C.BYTES > &v_tmpsize 
--50 * 1024 * 1024 * 1024
   AND (nvl(PLAN_DEPTH,1)=1)

UNION ALL

-----------------------------------------  SQLUNDO,INACTIVEUNDO,SQL

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       'SQLUNDO[' || USED_SIZE_BYTES || ']Bytes' MONITOR_TYPES
  FROM TMPS T,
       (SELECT ST.ADDR,
               ST.INST_ID,
               (ST.USED_UBLK * 8 * 1024) USED_SIZE_BYTES
          FROM GV$TRANSACTION ST, V$ROLLNAME R, GV$ROLLSTAT G
         WHERE ST.XIDUSN = R.USN
           AND R.USN = G.USN
           AND G.INST_ID = ST.INST_ID) V1
 WHERE V1.ADDR = T.TADDR
   AND T.INST_ID = V1.INST_ID
   AND USED_SIZE_BYTES > 1024 
--  50 * 1024 * 1024 * 1024

UNION ALL

-----------------------------------------  SQL

SELECT T.INST_ID,
       T.SID,
       T.SERIAL#,
       T.SPID,
       T.OSUSER,
       T.USERNAME,
       T.EVENT,
       T.SESSION_STATE,
       T.SQL_TEXT,
       T.EXECUTIONS,
       T.ELAPSED_TIME_S,
       T.CPU_TIME,
       T.USER_IO_WAIT_TIME,
       T.BUFFER_GETS,
       T.PLAN_OPERATION,
       T.STARTS,
       T.PLAN_PARTITION_START,
       T.PLAN_PARTITION_STOP,
       T.PHYSICAL_READ_BYTES,
       T.PHYSICAL_WRITE_BYTES,
       T.BLOCKING_INSTANCE,
       T.BLOCKING_SESSION,
       T.BLOCKING_SESSION_SERIAL#,
       T.LAST_CALL_ET,
       T.SQL_ID,
       T.SQL_EXEC_START,
       T.SQL_PLAN,
       T.LOGON_TIME,
       T.ASH_COUNTS,
       T.SESSION_INFO,
       'ASHNumber of Captures[' || T.ASH_COUNTS || ']['||SESSION_STATE||']'  MONITOR_TYPES
  FROM TMPS T
WHERE T.ASH_COUNTS>=4
   AND (nvl(PLAN_DEPTH,1)=1)
 ORDER BY SQL_EXEC_START DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 170 for section: prompt Notes:
hc_q_prompt_notes_170() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_170_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="awr_last_sql_infoall"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>LASTIn SnapshotSQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excel,,,</font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE ON

       (SELECT round(sum(db_time) / 1000000 / 60, 2) db_time_m
          FROM (SELECT lead(a.value, 1, null) over(partition by B.instance_number, b.startup_time ORDER BY b.end_interval_time) - a.value db_time
                   AND  a.dbid = b.dbid
                   AND  a.instance_number = b.instance_number
                   AND  a.stat_name = 'DB time'
         WHERE db_time IS NOT NULL) "db_time(m)",
       round(nvl((sqt.elap / 1000000), to_number(null)), 2) "Elapsed Time (s)",
       round(nvl((sqt.cput / 1000000), to_number(null)), 2) "CPU Time (s)",
       round(nvl((sqt.iowait_delta / 1000000), to_number(null)), 2) "User I/O Time (s)",
       round(nvl((sqt.buffer_gets_delta), to_number(null)), 2) "Buffer Gets",
       round(nvl((sqt.disk_reads_delta), to_number(null)), 2) "Physical Reads",
       round(nvl((sqt.rows_processed_delta), to_number(null)), 2) "Rows Processed",
       round(nvl((sqt.parse_calls_delta), to_number(null)), 2) "Parse Calls",
       sqt.exec executions,
       round(DECODE(sqt.exec,
                    0,
                    to_number(null),
                    (sqt.elap / sqt.exec / 1000000)),
             2) "Elapsed Time per Exec (s)",
       round(DECODE(sqt.exec,
                    0,
                    to_number(null),
                    (sqt.cput / sqt.exec / 1000000)),
             2) "CPU per Exec (s)",
       round(DECODE(sqt.exec,
                    0,
                    to_number(null),
                    (sqt.iowait_delta / sqt.exec / 1000000)),
             2) "UIO per Exec (s)",
       round(sqt.cput * 100 / sqt.elap, 2) "%CPU",
       round(sqt.iowait_delta * 100 / sqt.elap, 2) "%IO",
       round(sqt.elap * 100 /
             (SELECT sum(db_time)
                FROM (SELECT lead(a.value, 1, null) over(partition by B.instance_number, b.startup_time ORDER BY b.end_interval_time) - a.value db_time
                         AND  a.dbid = b.dbid
                         AND  a.instance_number = b.instance_number
                         AND  a.stat_name = 'DB time'
               WHERE db_time IS NOT NULL),
             2) "elapsed/dbtime",
       sqt.sql_id,
       parsing_schema_name,
       (DECODE(sqt.module, null, null, sqt.module)) module,
       nvl((SELECT dbms_lob.substr(st.sql_text, 200, 1)
            WHERE st.sql_id = sqt.sql_id
              AND  st.dbid = sqt.dbid
	      and rownum<=1),
           ('    SQL Text Not Available    ')) sql_text
  FROM (SELECT sql_id,
               a.dbid,
               a.parsing_schema_name,
               max(module || '
--' || a.action) module,
               sum(elapsed_time_delta) elap,
               sum(cpu_time_delta) cput,
               sum(executions_delta) exec,
               SUM(a.iowait_delta) iowait_delta,
               sum(a.buffer_gets_delta) buffer_gets_delta,
               sum(a.disk_reads_delta) disk_reads_delta,
               sum(a.rows_processed_delta) rows_processed_delta,
               sum(a.parse_calls_delta) parse_calls_delta
           AND  a.parsing_schema_name NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND  a.elapsed_time_delta > 0
         GROUP BY sql_id, parsing_schema_name, a.dbid) sqt 
 ORDER BY nvl(sqt.elap, -1) desc, sqt.sql_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 171 for section: prompt Notes:
hc_q_prompt_notes_171() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_171_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_elasled_lastlongsql"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>LASTIn SnapshotSQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE ON


prompt  


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● htmlSQL</b></font><hr align="left" width="450"> 

prompt  

prompt  <center>[<a class="noLink" href="#sql_elasled_lastlongsqllink"><font size=+1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:SQL</b></font></a>]</center><p>


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_elasled_lastsql_monitor"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: gv$sql_monitor,10</font></b>

CLEAR COLUMNS COMPUTES

SET DEFINE OFF

COLUMN SQL_EXEC_START   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SQL_EXEC_START&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT *
  FROM (SELECT d.INST_ID,
               d.SID,
               d.SESSION_SERIAL#,
               d.STATUS,
               d.USERNAME,
               (D.MODULE || '
--' || D.ACTION || '--' || D.PROGRAM || '--' ||D.PROCESS_NAME || '--' || D.CLIENT_IDENTIFIER || '--' ||D.CLIENT_INFO || '--' || D.SERVICE_NAME)   CLIENT_INFO,
               d.SQL_ID,
               d.SQL_TEXT,
               d.SQL_EXEC_START,
               (d.ELAPSED_TIME / 1000000) ELAPSED_TIME,
               (d.CPU_TIME / 1000000) CPU_TIME,
               (d.USER_IO_WAIT_TIME / 1000000) USER_IO_WAIT_TIME,
               d.ERROR_NUMBER || '-' || d.ERROR_FACILITY || '-' ||d.ERROR_MESSAGE ERROR,
               DENSE_RANK() over(partition by INST_ID ORDER BY d.ELAPSED_TIME desc) rank_order
          FROM gv$sql_monitor d
         WHERE D.USERNAME IS NOT NULL
           AND  d.USERNAME NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
		 )  
where rank_order <= 10;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 172 for section: prompt Notes:
hc_q_prompt_notes_172() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_172_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_elasled_lastlongsqlreport"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SQL</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 11gThis item was not checked previously, now it is included.v$sql_monitor,sql </b>

prompt  

CLEAR COLUMNS COMPUTES
SET DEFINE ON

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: SQL: SELECT dbms_sqltune.report_sql_monitor(sql_id  => &_sqlid1,type  => 'text',report_level => 'all') FROM dual; </font></b>

prompt   

SELECT '<pre style="word-wrap: break-word; white-space: pre-wrap; white-space: -moz-pre-wrap" >' ||dbms_sqltune.report_sql_monitor(sql_id => &_sqlid1,type => 'text',report_level => 'all') ||'</pre>' sql_monitor_results FROM DUAL;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 173 for section: prompt Notes:
hc_q_prompt_notes_173() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_173_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● htmlsql_monitor</b></font><hr align="left" width="450"> 

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 11g</font></b>

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: txt,Then Save Ashtml,pingdownload.oracle.com </font></b>
 
SET DEFINE ON 

SELECT '<textarea style="width:100%;font-family:Courier New;font-size:12px;overflow:auto" rows="10"> ' ||dbms_sqltune.report_sql_monitor(sql_id => &_sqlid1,type => 'active',report_level => 'all') ||'</textarea>' report_sql_monitor
  FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 174 for section: prompt Notes:
hc_q_prompt_notes_174() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_174_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sql_no_bind"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SQL</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE ON

with force_mathces as
 (select l.force_matching_signature,
         max(l.sql_id || l.child_number) max_sql_child,
         dense_rank() over(order by count(*) desc) ranking,
         count(*) counts
    from v$sql l
   where l.force_matching_signature <> 0
   and l.parsing_schema_name  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
   group by l.force_matching_signature
  having count(*) > 10)
select v.sql_id,
       v.sql_text,
       v.parsing_schema_name,
       fm.force_matching_signature,
       fm.ranking,
       fm.counts
  from force_mathces fm, v$sql v
 where fm.max_sql_child = (v.sql_id || v.child_number)
   and fm.ranking <= 50
 order by fm.ranking;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 175 for section: prompt Notes:
hc_q_prompt_notes_175() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_175_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT *
  FROM (SELECT a.PARSING_SCHEMA_NAME,
               substr(sql_text, 1, 60),
               count(1) counts,
               dense_rank() over(order by count(*) desc) ranking
          FROM v$sql a
         where a.PARSING_SCHEMA_NAME  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
         GROUP BY a.PARSING_SCHEMA_NAME, substr(sql_text, 1, 60)
        HAVING count(1) > 10)
 where ranking <= 50;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 176 for section: prompt Notes:
hc_q_prompt_notes_176() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_176_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<          >>>>>                          |

-- |                                                                            |

-- +============================================================================+

host echo "            . . ." 

prompt  <a name="link_dba_flashback_archive"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="link_dba_flashback_archiveinfo"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.CON_ID,
       a.OWNER_NAME,
       a.FLASHBACK_ARCHIVE_NAME,
       a.FLASHBACK_ARCHIVE#,
       a.RETENTION_IN_DAYS,
       a.CREATE_TIME,
       a.LAST_PURGE_TIME,
       a.STATUS
  FROM cdb_FLASHBACK_ARCHIVE a
 order by a.con_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 177 for section: prompt Notes:
hc_q_prompt_notes_177() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_177_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dba_flashback_archive_tables"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID,
       d.TABLE_NAME,
       d.OWNER_NAME,
       d.FLASHBACK_ARCHIVE_NAME,
       d.ARCHIVE_TABLE_NAME,
       d.STATUS
  FROM cdb_FLASHBACK_ARCHIVE_TABLES d
 order by d.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 178 for section: prompt Notes:
hc_q_prompt_notes_178() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_178_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dba_flashback_archive_ts"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID,
       d.FLASHBACK_ARCHIVE_NAME,
       d.FLASHBACK_ARCHIVE#,
       d.TABLESPACE_NAME,
       d.QUOTA_IN_MB
  FROM cdb_FLASHBACK_ARCHIVE_TS d
 order by d.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 179 for section: prompt Notes:
hc_q_prompt_notes_179() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_179_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<     DG     >>>>>                          |

-- |                                                                            |

-- +============================================================================+

host echo "            DG. . ." 

prompt  <a name="link_dginfo"></a>
SET DEFINE ON

prompt  <font size="+2" color="00CCFF"><b>DG( &_DGINFO2 )</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="link_dg_config"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DG</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN pname                FORMAT a75    HEADING ''    ENTMAP OFF
COLUMN instance_name_print  FORMAT a45    HEADING ''     ENTMAP OFF
COLUMN value                FORMAT a75    HEADING 'Parameter Value'             ENTMAP OFF


-- BREAK ON report ON pname

SELECT DECODE(p.isdefault,
              'FALSE',
              '<b><font color="#663300">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>',
              '<b><font color="#336699">' || SUBSTR(p.name, 0, 512) ||
              '</font></b>') pname,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || i.instance_name ||
              '</b></font>',
              i.instance_name) instance_name_print,
       DECODE(p.isdefault,
              'FALSE',
              '<font color="#663300"><b>' || SUBSTR(p.value, 0, 512) ||
              '</b></font>',
              SUBSTR(p.value, 0, 512)) value
  FROM gv$parameter p, gv$instance i
 WHERE p.inst_id = i.inst_id
   AND p.name in ('dg_broker_start','db_name','db_unique_name','log_archive_config','log_archive_dest_1','log_archive_dest_2','log_archive_dest_state_1','log_archive_dest_state_2','log_archive_max_processes','remote_login_passwordfile','db_file_name_convert','log_file_name_convert','standby_file_management','fal_server','fal_client','dg_broker_config_file1','dg_broker_config_file2')
 ORDER BY p.name, i.instance_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 180 for section: prompt Notes:
hc_q_prompt_notes_180() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_180_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dg_runinfo"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DG</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN GAP_STATUS                FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;GAP_STATUS&nbsp&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN OPEN_MODE                FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;OPEN_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN database_role                FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DATABASE_ROLE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN PROTECTION_MODE                FORMAT a160   HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PROTECTION_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN PROTECTION_LEVEL                FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PROTECTION_LEVEL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
SET DEFINE ON

SELECT d.INST_ID,
       NAME,
       LOG_MODE,
       OPEN_MODE,
       database_role,
       SWITCHOVER_STATUS,
       db_unique_name,
       flashback_on,
       PROTECTION_MODE,
       PROTECTION_LEVEL,
       REMOTE_ARCHIVE,
       SWITCHOVER#,
       DATAGUARD_BROKER,
       GUARD_STATUS,
       SUPPLEMENTAL_LOG_DATA_MIN,
       SUPPLEMENTAL_LOG_DATA_PK,
       SUPPLEMENTAL_LOG_DATA_UI,
       FORCE_LOGGING,
       SUPPLEMENTAL_LOG_DATA_FK,
       SUPPLEMENTAL_LOG_DATA_ALL,
       STANDBY_BECAME_PRIMARY_SCN,
       FS_FAILOVER_STATUS,
       FS_FAILOVER_CURRENT_TARGET,
       FS_FAILOVER_THRESHOLD,
       FS_FAILOVER_OBSERVER_PRESENT,
       FS_FAILOVER_OBSERVER_HOST 
FROM   gv$database d;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 181 for section: prompt Notes:
hc_q_prompt_notes_181() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_181_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN TARGET                FORMAT a280    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TARGET&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN DATABASE_MODE                FORMAT a100   HEADING '&nbsp;&nbsp;&nbsp;DATABASE_MODE&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN RECOVERY_MODE                FORMAT a280    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;RECOVERY_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN GAP_STATUS                FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;GAP_STATUS&nbsp;&nbsp;&nbsp;&nbsp&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN OPEN_MODE                FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;OPEN_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN database_role                FORMAT a200    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DATABASE_ROLE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN PROTECTION_MODE                FORMAT a160   HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PROTECTION_MODE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN PROTECTION_LEVEL                FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PROTECTION_LEVEL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
COLUMN ERROR                FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ERROR&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'    ENTMAP OFF
SET DEFINE ON
	
SELECT al.thread#,
       ads.dest_id,
       ads.DEST_NAME,
       (SELECT ads.TYPE || ' ' || ad.TARGET
          FROM v$archive_dest AD
         WHERE AD.DEST_ID = ADS.DEST_ID) TARGET,
       ADS.DATABASE_MODE,
       ads.STATUS,
       ads.error,
       ads.RECOVERY_MODE,
       ads.DB_UNIQUE_NAME,
       ads.DESTINATION,
       ads.GAP_STATUS,
       (SELECT MAX(sequence#) FROM v$log na WHERE na.thread# = al.thread#) Current_Seq#,
       MAX(sequence#) Last_Archived,
       max(CASE
             WHEN al.APPLIED = 'YES' AND  ads.TYPE <> 'LOCAL' THEN
              al.sequence#
           end) APPLIED_SEQ#,
       (SELECT ad.applied_scn
          FROM v$archive_dest AD
         WHERE AD.DEST_ID = ADS.DEST_ID) applied_scn
  FROM (SELECT *
          FROM v$archived_log V
         WHERE V.resetlogs_change# =
               (SELECT d.RESETLOGS_CHANGE# FROM v$database d)) al,
       v$archive_dest_status ads
 WHERE al.dest_id(+) = ads.dest_id
   AND  ads.STATUS != 'INACTIVE'
 GROUP BY al.thread#,
          ads.dest_id,
          ads.DEST_NAME,
          ads.STATUS,
          ads.error,
          ads.TYPE,
          ADS.DATABASE_MODE,
          ads.RECOVERY_MODE,
          ads.DB_UNIQUE_NAME,
          ads.DESTINATION,
          ads.GAP_STATUS
 ORDER BY al.thread#, ads.dest_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 182 for section: prompt Notes:
hc_q_prompt_notes_182() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_182_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dg_runprocessinfo"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DG</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON
col group_# format a5
col PROCESS format a8
col CLIENT_PID format a8
set line 9999 pagesize 9999
SELECT a.INST_ID,
       a.PROCESS,
       a.client_process,
       a.client_pid,
       a.STATUS,
       a.GROUP#         group_#,
       a.thread#,
       a.SEQUENCE#,
       a.DELAY_MINS,
       a.RESETLOG_ID,
       c.SID,
       c.SERIAL#,
       a.PID            spid,
       b.PNAME
  FROM gV$MANAGED_STANDBY a, gv$process b, gv$session c
 WHERE a.PID = b.SPID
   and b.ADDR = c.PADDR
   and a.INST_ID = b.INST_ID
   and b.INST_ID = c.INST_ID
order by a.INST_ID,b.PNAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 183 for section: prompt Notes:
hc_q_prompt_notes_183() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_183_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
commit;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 184 for section: prompt Notes:
hc_q_prompt_notes_184() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_184_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dg_standbylog"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>standby</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT GROUP#,
       DBID db_id,
       THREAD#,
       SEQUENCE#,
       BYTES,
       USED,
       ARCHIVED,
       STATUS,
       FIRST_CHANGE#,
       NEXT_CHANGE#,
       LAST_CHANGE#
  FROM Gv$standby_log;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 185 for section: prompt Notes:
hc_q_prompt_notes_185() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_185_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_dg_standbylog2"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DG</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON


prompt  ● gv$dataguard_config
SELECT * FROM gv$dataguard_config;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 186 for section: prompt Notes:
hc_q_prompt_notes_186() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_186_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● gv$dataguard_process
SELECT * FROM gv$dataguard_process;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 187 for section: prompt Notes:
hc_q_prompt_notes_187() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_187_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● gv$dataguard_stats
SELECT * FROM gv$dataguard_stats;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 188 for section: prompt Notes:
hc_q_prompt_notes_188() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_188_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● gv$dataguard_status
SELECT *
  FROM v$dataguard_status a
 where a.TIMESTAMP >= sysdate - 1
   and a.MESSAGE_NUM >=
       (SELECT max(MESSAGE_NUM) - 100 FROM v$dataguard_status);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 189 for section: prompt Notes:
hc_q_prompt_notes_189() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_189_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +====================================================================================================================+

-- |

-- | <<<<<          >>>>>                                                 |

-- |                                                                                                                    |

-- +====================================================================================================================+

host echo "start.... ."  


prompt  <a name="database_security"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u></u></b></font></center>

prompt  <p>


-- +----------------------------------------------------------------------------+

-- |                             - USER ACCOUNTS -                              |

-- +----------------------------------------------------------------------------+
host echo "            Database Users. . ." 

prompt  <a name="database_userinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>Database Users</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="user_accounts"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Database Users</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN username              FORMAT a75    HEAD 'Username'        ENTMAP OFF
COLUMN account_status        FORMAT a75    HEAD 'Account Status'  ENTMAP OFF
COLUMN expiry_date           FORMAT a75    HEAD 'Expire Date'     ENTMAP OFF
COLUMN default_tablespace    FORMAT a75    HEAD 'Default Tbs.'    ENTMAP OFF
COLUMN temporary_tablespace  FORMAT a75    HEAD 'Temp Tbs.'       ENTMAP OFF
COLUMN CREATED               FORMAT a75    HEAD 'CREATED On'      ENTMAP OFF
COLUMN profile               FORMAT a75    HEAD 'Profile'         ENTMAP OFF
COLUMN sysdba                FORMAT a75    HEAD 'SYSDBA'          ENTMAP OFF
COLUMN sysoper               FORMAT a75    HEAD 'SYSOPER'         ENTMAP OFF
COLUMN is_oracle_internal_user               FORMAT a25    HEAD 'is_oracle_internal_user'         ENTMAP OFF
SET DEFINE ON

SELECT A.CON_ID,'<b><font color="#336699">' || A.USERNAME || '</font></b>' USERNAME,
       DECODE(A.ACCOUNT_STATUS,
              'OPEN',
              '<div align="left"><b><font color="darkgreen">' ||
              A.ACCOUNT_STATUS || '</font></b></div>',
              '<div align="left"><b><font color="#663300">' ||
              A.ACCOUNT_STATUS || '</font></b></div>') ACCOUNT_STATUS,
       '<div nowrap align="right">' ||
       NVL(TO_CHAR(A.EXPIRY_DATE, 'yyyy-mm-dd HH24:MI:SS'), '<br>') ||
       '</div>' EXPIRY_DATE,
       A.DEFAULT_TABLESPACE DEFAULT_TABLESPACE,
       A.TEMPORARY_TABLESPACE TEMPORARY_TABLESPACE,
       '<div nowrap align="right">' ||
       TO_CHAR(A.CREATED, 'yyyy-mm-dd HH24:MI:SS') || '</div>' CREATED,
       A.PROFILE PROFILE,
       '<div nowrap align="center">' ||
       NVL(DECODE(P.SYSDBA, 'TRUE', 'TRUE', ''), '<br>') || '</div>' SYSDBA,
       '<div nowrap align="center">' ||
       NVL(DECODE(P.SYSOPER, 'TRUE', 'TRUE', ''), '<br>') || '</div>' SYSOPER, 
       (SELECT B.STATUS#
          FROM SYS.USER_ASTATUS_MAP B
         WHERE B.STATUS = A.ACCOUNT_STATUS) ACCOUNT_STATUS#,
       NVL(A.PASSWORD,
           (SELECT NB.PASSWORD FROM SYS.USER$ NB WHERE NB.NAME = A.USERNAME)) PASSWORD,
			A.COMMON
  FROM CDB_USERS A, V$PWFILE_USERS P 
 WHERE  A.USERNAME = P.USERNAME(+)
 ORDER BY A.CON_ID, A.USERNAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 190 for section: prompt Notes:
hc_q_prompt_notes_190() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_190_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                      - USERS WITH DBA PRIVILEGES -                         |

-- +----------------------------------------------------------------------------+


prompt  <a name="users_with_dba_privileges"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DBA</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN grantee        FORMAT a70   HEADING 'Grantee'         ENTMAP OFF
COLUMN granted_role   FORMAT a35   HEADING 'Granted Role'    ENTMAP OFF
COLUMN admin_option   FORMAT a75   HEADING 'Admin. Option?'  ENTMAP OFF
COLUMN default_role   FORMAT a75   HEADING 'Default Role?'   ENTMAP OFF
SET DEFINE ON

SELECT d.CON_ID,
       '<b><font color="#336699">' || grantee || '</font></b>' grantee,
       '<div align="center">' || granted_role || '</div>' granted_role,
       DECODE(admin_option,
              'YES',
              '<div align="center"><font color="darkgreen"><b>' ||
              admin_option || '</b></font></div>',
              'NO',
              '<div align="center"><font color="#990000"><b>' ||
              admin_option || '</b></font></div>',
              '<div align="center"><font color="#663300"><b>' ||
              admin_option || '</b></font></div>') admin_option,
       DECODE(default_role,
              'YES',
              '<div align="center"><font color="darkgreen"><b>' ||
              default_role || '</b></font></div>',
              'NO',
              '<div align="center"><font color="#990000"><b>' ||
              default_role || '</b></font></div>',
              '<div align="center"><font color="#663300"><b>' ||
              default_role || '</b></font></div>') default_role
  FROM cdb_role_privs d
 WHERE granted_role = 'DBA'
 ORDER BY d.CON_ID, grantee, granted_role;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 191 for section: prompt Notes:
hc_q_prompt_notes_191() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_191_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                      - USERS WITH SYSDATA -                                |

-- +----------------------------------------------------------------------------+


prompt  <a name="users_with_sys_privileges"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SYS</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT * FROM v$pwfile_users a order by a.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 192 for section: prompt Notes:
hc_q_prompt_notes_192() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_192_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                                 - ROLES -                                  |

-- +----------------------------------------------------------------------------+


prompt  <a name="roles"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

COLUMN role             FORMAT a70    HEAD 'Role Name'       ENTMAP OFF
COLUMN grantee          FORMAT a35    HEAD 'Grantee'         ENTMAP OFF
COLUMN admin_option     FORMAT a75    HEAD 'Admin Option?'   ENTMAP OFF
COLUMN default_role     FORMAT a75    HEAD 'Default Role?'   ENTMAP OFF


-- BREAK ON role

SELECT A.CON_ID,'<b><font color="#336699">' || b.role || '</font></b>' role,
       a.grantee grantee,
       DECODE(a.admin_option,
              null,
              '<br>',
              'YES',
              '<div align="center"><font color="darkgreen"><b>' ||
              a.admin_option || '</b></font></div>',
              'NO',
              '<div align="center"><font color="#990000"><b>' ||
              a.admin_option || '</b></font></div>',
              '<div align="center"><font color="#663300"><b>' ||
              a.admin_option || '</b></font></div>') admin_option,
       DECODE(a.default_role,
              null,
              '<br>',
              'YES',
              '<div align="center"><font color="darkgreen"><b>' ||
              a.default_role || '</b></font></div>',
              'NO',
              '<div align="center"><font color="#990000"><b>' ||
              a.default_role || '</b></font></div>',
              '<div align="center"><font color="#663300"><b>' ||
              a.default_role || '</b></font></div>') default_role , A.COMMON
  FROM CDB_role_privs a, CDB_roles b
 WHERE   b.role = granted_role(+)
   AND B.CON_ID = A.CON_ID(+)
	 AND B.ROLE NOT IN ('ADM_PARALLEL_EXECUTE_TASK','APPLICATION_TRACE_VIEWER','AQ_ADMINISTRATOR_ROLE','AQ_USER_ROLE','AUDIT_ADMIN','AUDIT_VIEWER','AUTHENTICATEDUSER','CAPTURE_ADMIN','CDB_DBA','CONNECT','CSW_USR_ROLE','CTXAPP','DATAPATCH_ROLE','DATAPUMP_EXP_FULL_DATABASE','DATAPUMP_IMP_FULL_DATABASE','DBA','DBFS_ROLE','DBJAVASCRIPT','DBMS_MDX_INTERNAL','DV_ACCTMGR','DV_ADMIN','DV_AUDIT_CLEANUP','DV_DATAPUMP_NETWORK_LINK','DV_GOLDENGATE_ADMIN','DV_GOLDENGATE_REDO_ACCESS','DV_MONITOR','DV_OWNER','DV_PATCH_ADMIN','DV_POLICY_OWNER','DV_PUBLIC','DV_REALM_OWNER','DV_REALM_RESOURCE','DV_SECANALYST','DV_STREAMS_ADMIN','DV_XSTREAM_ADMIN','EJBCLIENT','EM_EXPRESS_ALL','EM_EXPRESS_BASIC','EXECUTE_CATALOG_ROLE','EXP_FULL_DATABASE','GATHER_SYSTEM_STATISTICS','GDS_CATALOG_SELECT','GGSYS_ROLE','GLOBAL_AQ_USER_ROLE','GSMADMIN_ROLE','GSMUSER_ROLE','GSM_POOLADMIN_ROLE','HS_ADMIN_EXECUTE_ROLE','HS_ADMIN_ROLE','HS_ADMIN_SELECT_ROLE','IMP_FULL_DATABASE','JAVADEBUGPRIV','JAVAIDPRIV','JAVASYSPRIV','JAVAUSERPRIV','JAVA_ADMIN','JAVA_DEPLOY','JMXSERVER','LBAC_DBA','LOGSTDBY_ADMINISTRATOR','OEM_ADVISOR','OEM_MONITOR','OLAP_DBA','OLAP_USER','OLAP_XS_ADMIN','OPTIMIZER_PROCESSING_RATE','ORDADMIN','PDB_DBA','PROVISIONER','RDFCTX_ADMIN','RECOVERY_CATALOG_OWNER','RECOVERY_CATALOG_OWNER_VPD','RECOVERY_CATALOG_USER','RESOURCE','SCHEDULER_ADMIN','SELECT_CATALOG_ROLE','SODA_APP','SPATIAL_CSW_ADMIN','SYSUMF_ROLE','WM_ADMIN_ROLE','XDBADMIN','XDB_SET_INVOKER','XDB_WEBSERVICES','XDB_WEBSERVICES_OVER_HTTP','XDB_WEBSERVICES_WITH_PUBLIC','XS_CACHE_ADMIN','XS_CONNECT','XS_NAMESPACE_ADMIN','XS_SESSION_ADMIN','MGMT_USER','XDBWEBSERVICES','DELETE_CATALOG_ROLE','APEX_ADMINISTRATOR_ROLE','CWM_USER','OWB$CLIENT','OWB_DESIGNCENTER_VIEW','OWB_USER','SPATIAL_WFS_ADMIN','WFS_USR_ROLE')
 ORDER BY A.CON_ID,b.role, a.grantee;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 193 for section: prompt Notes:
hc_q_prompt_notes_193() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_193_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          - DEFAULT PASSWORDS -                             |

-- +----------------------------------------------------------------------------+


prompt  <a name="default_passwords"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

COLUMN username                      HEADING 'Username'        ENTMAP OFF
COLUMN account_status   FORMAT a75   HEADING 'Account Status'  ENTMAP OFF

SELECT d.CON_ID,
       '<b><font color="#336699">' || username || '</font></b>' username,
       DECODE(account_status,
              'OPEN',
              '<div align="left"><b><font color="darkgreen">' ||
              account_status || '</font></b></div>',
              '<div align="left"><b><font color="#663300">' ||
              account_status || '</font></b></div>') account_status
  FROM cdb_users d 
WHERE password IN (
    'E066D214D5421CCC'   
-- dbsnmp
  , '24ABAB8B06281B4C'   
-- ctxsys
  , '72979A94BAD2AF80'   
-- mdsys
  , 'C252E8FA117AF049'   
-- odm
  , 'A7A32CD03D3CE8D5'   
-- odm_mtr
  , '88A2B2C183431F00'   
-- ordplugins
  , '7EFA02EC7EA6B86F'   
-- ordsys
  , '4A3BA55E08595C81'   
-- outln
  , 'F894844C34402B67'   
-- scott
  , '3F9FBD883D787341'   
-- wk_proxy
  , '79DF7A1BD138CF11'   
-- wk_sys
  , '7C9BA362F8314299'   
-- wmsys
  , '88D8364765FCE6AF'   
-- xdb
  , 'F9DA8977092B7B81'   
-- tracesvr
  , '9300C0977D7DC75E'   
-- oas_public
  , 'A97282CE3D94E29E'   
-- websys
  , 'AC9700FD3F1410EB'   
-- lbacsys
  , 'E7B5D92911C831E1'   
-- rman
  , 'AC98877DE1297365'   
-- perfstat
  , 'D4C5016086B2DC6A'   
-- sys
  , 'D4DF7931AB130E37')  
-- system
 ORDER BY d.CON_ID, username;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 194 for section: prompt Notes:
hc_q_prompt_notes_194() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_194_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="user_size"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: ,UNDO </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT  D.CON_ID,d.owner,
       round(sum(bytes)/1024/1024,2) sizes_M
  FROM CDB_segments d
 WHERE d.segment_type NOT LIKE '%UNDO%'
   AND  not exists (SELECT 1
          FROM CDB_recyclebin nb
         WHERE nb.owner = d.owner
           AND  nb.object_name = d.segment_name
					 AND NB.CON_ID=D.CON_ID)
 GROUP BY D.CON_ID, d.owner
 ORDER BY D.CON_ID, sum(bytes) DESC
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 195 for section: prompt Notes:
hc_q_prompt_notes_195() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_195_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="user_logon_error"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Failed Login Users (Past Week)</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT * FROM (
SELECT a.dbid,
       a.sessionid,
       a.process#,
       a.entryid,
       a.userid,
       (SELECT na.lcount  FROM sys.user$  na WHERE na.name=a.userid)  lcount,
       a.userhost,
       a.terminal,
       a.action#,
       a.returncode,
       a.comment$text,
       a.spare1,
       a.ntimestamp#+8/24 login_time
  FROM sys.aud$ a
 WHERE a.returncode = 1017
 AND   a.ntimestamp#+8/24 >=sysdate-7 
 ORDER BY a.ntimestamp# desc) WHERE ROWNUM <=100;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 196 for section: prompt Notes:
hc_q_prompt_notes_196() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_196_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="user_PROFILE"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>PROFILE</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON
SELECT DP.CON_ID,
       DP.PROFILE,
       DP.RESOURCE_NAME,
       DP.RESOURCE_TYPE,
       DP.LIMIT,
       listagg(DU.USERNAME,',') within group(order by du.username)  USERNAMES	 
  FROM CDB_PROFILES DP, CDB_USERS DU
 WHERE DP.PROFILE = DU.PROFILE 
 AND DP.CON_ID=DU.CON_ID
 GROUP BY DP.PROFILE, DP.RESOURCE_NAME, DP.RESOURCE_TYPE, DP.LIMIT,DP.CON_ID
 ORDER BY DP.CON_ID,DP.PROFILE;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 197 for section: prompt Notes:
hc_q_prompt_notes_197() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_197_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |             - Users with SYSTEM as Default Tablespace         -                   |

-- +----------------------------------------------------------------------------+
host echo "            . . ." 

prompt  <a name="database_systemuserinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="users_with_default_tablespace_defined_as_system"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SYSTEM</b></font><hr align="left" width="600">

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username                 FORMAT a75    HEADING 'Username'                ENTMAP OFF
COLUMN default_tablespace       FORMAT a125   HEADING 'Default Tablespace'      ENTMAP OFF
COLUMN temporary_tablespace     FORMAT a125   HEADING 'Temporary Tablespace'    ENTMAP OFF
COLUMN CREATED                  FORMAT a75    HEADING 'CREATED'                 ENTMAP OFF
COLUMN account_status           FORMAT a75    HEADING 'Account Status'          ENTMAP OFF

SELECT d.CON_ID,
       '<font color="#336699"><b>' || username || '</font></b>' username,
       '<div align="left">' || default_tablespace || '</div>' default_tablespace,
       '<div align="left">' || temporary_tablespace || '</div>' temporary_tablespace,
       '<div align="right">' || TO_CHAR(CREATED, 'yyyy-mm-dd HH24:MI:SS') ||
       '</div>' CREATED,
       DECODE(account_status,
              'OPEN',
              '<div align="center"><b><font color="darkgreen">' ||
              account_status || '</font></b></div>',
              '<div align="center"><b><font color="#663300">' ||
              account_status || '</font></b></div>') account_status
  FROM cdb_users d
 WHERE default_tablespace = 'SYSTEM'
    AND  d.username   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 ORDER BY d.CON_ID, username;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 198 for section: prompt Notes:
hc_q_prompt_notes_198() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_198_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |          - Users with SYSTEM as Temporary Tablespace                   -            |

-- +----------------------------------------------------------------------------+


prompt  <a name="users_with_default_temporary_tablespace_as_system"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>SYSTEM</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN username                 FORMAT a75    HEADING 'Username'                ENTMAP OFF
COLUMN default_tablespace       FORMAT a125   HEADING 'Default Tablespace'      ENTMAP OFF
COLUMN temporary_tablespace     FORMAT a125   HEADING 'Temporary Tablespace'    ENTMAP OFF
COLUMN CREATED                  FORMAT a75    HEADING 'CREATED'                 ENTMAP OFF
COLUMN account_status           FORMAT a75    HEADING 'Account Status'          ENTMAP OFF

SELECT d.CON_ID,
       '<font color="#336699"><b>' || username || '</font></b>' username,
       '<div align="center">' || default_tablespace || '</div>' default_tablespace,
       '<div align="center">' || temporary_tablespace || '</div>' temporary_tablespace,
       '<div align="right">' || TO_CHAR(CREATED, 'yyyy-mm-dd HH24:MI:SS') ||
       '</div>' CREATED,
       DECODE(account_status,
              'OPEN',
              '<div align="center"><b><font color="darkgreen">' ||
              account_status || '</font></b></div>',
              '<div align="center"><b><font color="#663300">' ||
              account_status || '</font></b></div>') account_status
  FROM cdb_users d
 WHERE temporary_tablespace = 'SYSTEM'
 ORDER BY d.CON_ID, username;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 199 for section: prompt Notes:
hc_q_prompt_notes_199() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_199_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                  -                  -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="database_audit"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <a name="database_audit_parameter"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.NAME,d.VALUE,d.ISDEFAULT,d.DESCRIPTION FROM v$parameter d WHERE d.NAME='audit_trail';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 200 for section: prompt Notes:
hc_q_prompt_notes_200() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_200_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="database_audit_table_parameter"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="450">

SELECT d.CON_ID,
       d.OWNER,
       d.TABLE_NAME,
       d.TABLESPACE_NAME,
       d.PARTITIONED,
       d.NUM_ROWS,
       d.LAST_ANALYZED,
       (SELECT sum(ds.BYTES) / 1024 / 1024
          FROM cdb_segments ds
         WHERE ds.segment_name = d.TABLE_NAME
				 and ds.CON_ID=d.CON_ID) tb_size_m,
       (SELECT sum(ds.BYTES) / 1024 / 1024
          FROM cdb_segments ds, cdb_indexes di
         WHERE ds.segment_name = di.index_name
           AND di.table_name = d.TABLE_NAME
					 and ds.CON_ID=di.CON_ID
					 and ds.CON_ID=d.CON_ID) index_size_m
  FROM cdb_tables d
 WHERE d.TABLE_NAME = 'AUD$'
 order by d.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 201 for section: prompt Notes:
hc_q_prompt_notes_201() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_201_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt     


SELECT '<textarea style="width:100%;font-family:Courier New;font-size:12px;overflow:auto" rows="10"> ' || ',,SYSTEM.,AUD$,SYSTEMRisk of Exhaustion. '||'

-----10G      '||'
ALTER TABLE AUDIT$ MOVE TABLESPACE USERS;      '||'
ALTER TABLE AUDIT_ACTIONS MOVE TABLESPACE USERS;      '||'
ALTER TABLE AUD$ MOVE TABLESPACE USERS;         '||'
ALTER TABLE AUD$ MOVE LOB(SQLBIND) STORE AS SYS_IL0000000384C00041$$ (TABLESPACE USERS); '||'
ALTER TABLE AUD$ MOVE LOB(SQLTEXT) STORE AS SYS_IL0000000384C00041$$ (TABLESPACE USERS); '||'
ALTER INDEX I_AUDIT REBUILD ONLINE TABLESPACE USERS;   '||'
ALTER INDEX I_AUDIT_ACTIONS REBUILD ONLINE TABLESPACE USERS;    '||'

-----11G DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_LOCATION '||'
CONN / AS SYSDBA
BEGIN
DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_LOCATION(AUDIT_TRAIL_TYPE => DBMS_AUDIT_MGMT.AUDIT_TRAIL_DB_STD,
AUDIT_TRAIL_LOCATION_VALUE => ''USERS'');    '||'
END;  '||'
/' ||  '</textarea>' AUD$ FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 202 for section: prompt Notes:
hc_q_prompt_notes_202() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_202_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt     


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="database_audit_all"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>DB</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, action_name, count(*) cnt
  FROM cdb_audit_trail d
 GROUP BY d.CON_ID, action_name
 order by d.CON_ID, action_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 203 for section: prompt Notes:
hc_q_prompt_notes_203() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_203_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


-- +----------------------------------------------------------------------------+

-- |                  -  -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="objects_in_the_system_tablespace"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font></b>


prompt  <a name="table_sys_ts_infoall"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, '<div nowrap align="left"><font color="#336699"><b>' || owner ||'</b></font></div>' owner,
       segment_type, 
       round(SUM(bytes / 1024 / 1024 / 1024), 3) size_g,
       COUNT(1) counts
FROM   cdb_segments d
WHERE  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
AND    tablespace_name = 'SYSTEM'
group by d.CON_ID,d.owner,d.segment_type
ORDER  BY d.CON_ID,d.owner;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 204 for section: prompt Notes:
hc_q_prompt_notes_204() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_204_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="table_sys_ts_infoall"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Details</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner               FORMAT a75                   HEADING 'Owner'           ENTMAP OFF
COLUMN segment_name        FORMAT a125                  HEADING 'Segment Name'    ENTMAP OFF
COLUMN segment_type        FORMAT a75                   HEADING 'Type'            ENTMAP OFF
COLUMN tablespace_name     FORMAT a125                  HEADING 'Tablespace'      ENTMAP OFF
COLUMN bytes               FORMAT 999,999,999,999,999   HEADING 'Bytes|Alloc'     ENTMAP OFF
COLUMN extents             FORMAT 999,999,999,999,999   HEADING 'Extents'         ENTMAP OFF
COLUMN max_extents         FORMAT 999,999,999,999,999   HEADING 'Max|Ext'         ENTMAP OFF
COLUMN initial_extent      FORMAT 999,999,999,999,999   HEADING 'Initial|Ext'     ENTMAP OFF
COLUMN next_extent         FORMAT 999,999,999,999,999   HEADING 'Next|Ext'        ENTMAP OFF
COLUMN pct_increase        FORMAT 999,999,999,999,999   HEADING 'Pct|Inc'         ENTMAP OFF


-- BREAK ON report ON owner
COMPUTE count LABEL '<font color="#990000"><b>Total Count: </b></font>' OF segment_name ON report
COMPUTE sum   LABEL '<font color="#990000"><b>Total Bytes: </b></font>' OF bytes ON report

SELECT d.CON_ID,
       '<div nowrap align="left"><font color="#336699"><b>' || owner ||
       '</b></font></div>' owner,
       segment_name,
       segment_type,
       tablespace_name,
       bytes,
       extents,
       initial_extent,
       next_extent,
       pct_increase
  FROM cdb_segments d
WHERE  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
  AND  tablespace_name = 'SYSTEM'
 ORDER BY d.CON_ID, owner, segment_name, extents DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 205 for section: prompt Notes:
hc_q_prompt_notes_205() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_205_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="table_sys_ts"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, table_name, owner, tablespace_name
  FROM cdb_tables d
 WHERE tablespace_name in ('SYSTEM')
   AND    owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 206 for section: prompt Notes:
hc_q_prompt_notes_206() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_206_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="index_sys_ts"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, 
       d.owner            index_owner,
       index_name,
       d.tablespace_name  index_ts_name,
       d.table_owner,
       d.table_name,
       d.table_type,
       nb.TABLESPACE_NAME table_ts_name,
       nb.PARTITIONED     table_PARTITIONED,
       nb.TEMPORARY       table_TEMPORARY
  FROM cdb_indexes d, cdb_tables nb
 WHERE nb.OWNER = d.table_owner
   AND d.table_name = nb.TABLE_NAME 
	 and d.CON_ID=nb.CON_ID
   and d.tablespace_name in ('SYSTEM')
	 AND  d.owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 207 for section: prompt Notes:
hc_q_prompt_notes_207() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_207_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>][<a class="noLink" href="#segment_summary">Next Item</a>]</center>


-- +============================================================================+

-- |                                                                            |

-- |                     <<<<<     OBJECTS     >>>>>                            |

-- |                                                                            |

-- +============================================================================+

-- +====================================================================================================================+

-- |

-- | <<<<<          >>>>>                                                 |

-- |                                                                                                                    |

-- +====================================================================================================================+

host echo "start.... ." 

prompt  <a name="db_objects"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u></u></b></font></center>

prompt  <p>


-- +----------------------------------------------------------------------------+

-- |                            - OBJECT SUMMARY -                              |

-- +----------------------------------------------------------------------------+
host echo "            . . ." 

prompt  <a name="database_segmentsinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="object_summary"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Object Summary</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM)  </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner           FORMAT a60               HEADING 'Owner'           ENTMAP OFF
COLUMN object_type     FORMAT a25               HEADING 'Object Type'     ENTMAP OFF
COLUMN obj_count       FORMAT 999,999,999,999   HEADING 'Object Count'    ENTMAP OFF


-- BREAK ON report ON owner SKIP 2

-- compute sum label """               of obj_count on owner

-- compute sum label '<font color="#990000"><b>Grand Total: </b></font>' of obj_count on report
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF obj_count ON report

SELECT d.CON_ID, '<b><font color="#336699">' || owner || '</font></b>' owner,
       object_type object_type,
       count(*) obj_count
  FROM cdb_objects d
 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
 GROUP BY d.CON_ID,owner, object_type
 ORDER BY d.CON_ID,owner, object_type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 208 for section: prompt Notes:
hc_q_prompt_notes_208() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_208_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>][<a class="noLink" href="#database_segmentsinfo"></a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          - SEGMENT SUMMARY -                               |

-- +----------------------------------------------------------------------------+


prompt  <a name="segment_summary"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM)  </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner           FORMAT a50                    HEADING 'Owner'             ENTMAP OFF
COLUMN segment_type    FORMAT a25                    HEADING 'Segment Type'      ENTMAP OFF
COLUMN seg_count       FORMAT 999,999,999,999        HEADING 'Segment Count'     ENTMAP OFF
COLUMN bytes           FORMAT 999,999,999,999,999    HEADING 'Size (in Bytes)'   ENTMAP OFF


-- BREAK ON report ON owner SKIP 2

-- COMPUTE sum LABEL """                                                  OF seg_count bytes ON owner
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF seg_count bytes ON report

SELECT d.CON_ID, '<b><font color="#336699">' || owner || '</font></b>' owner,
       segment_type segment_type,
       count(*) seg_count,
       sum(bytes) bytes
  FROM cdb_segments d
 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
 GROUP BY  d.CON_ID,owner, segment_type
 ORDER BY  d.CON_ID,owner, segment_type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 209 for section: prompt Notes:
hc_q_prompt_notes_209() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_209_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                    - TOP 10 SEGMENTS (BY SIZE) -                          |

-- +----------------------------------------------------------------------------+
host echo "                10segments. . . ."

prompt  <a name="top_10_segments_by_size"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10segments</b></font><hr align="left" width="600">


prompt  <b><font color="#990000">●  </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner                                               HEADING 'Owner'            ENTMAP OFF
COLUMN segment_name                                        HEADING 'Segment Name'     ENTMAP OFF
COLUMN partition_name                                      HEADING 'Partition Name'   ENTMAP OFF
COLUMN segment_type                                        HEADING 'Segment Type'     ENTMAP OFF
COLUMN tablespace_name                                     HEADING 'Tablespace Name'  ENTMAP OFF
COLUMN bytes               FORMAT 999,999,999,999,999,999  HEADING 'Size (in bytes)'  ENTMAP OFF
COLUMN extents             FORMAT 999,999,999,999,999,999  HEADING 'Extents'          ENTMAP OFF


-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF bytes extents ON report

SELECT a.con_id, a.owner,
       a.segment_name,
       a.partition_name,
       a.segment_type,
       a.tablespace_name,
       a.bytes,
       (bytes) segments_size,
       a.extents
  FROM (SELECT b.CON_ID, b.owner,
               b.segment_name,
               b.partition_name,
               b.segment_type,
               b.tablespace_name,
               b.bytes,
               b.extents
          FROM cdb_segments b
	  WHERE    b.owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         ORDER BY b.bytes desc) a
 WHERE ROWNUM <= 20;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 210 for section: prompt Notes:
hc_q_prompt_notes_210() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_210_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <b><font color="#990000">●  </font> </b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF object_size_M  ON report

SELECT *
  FROM (SELECT b.CON_ID, owner,
               segment_name,
               segment_type,
               b.tablespace_name,
               round(sum(bytes) / 1024 / 1024) object_size_M
          FROM cdb_segments b
         WHERE b.owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         GROUP BY b.CON_ID,owner, segment_name, segment_type,b.tablespace_name
         ORDER BY object_size_M desc)
 WHERE ROWNUM <= 10;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 211 for section: prompt Notes:
hc_q_prompt_notes_211() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_211_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <b><font color="#990000">●  Tablespace-based analysis, showing top3</font> </b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF size_m  ON report

SELECT CON_ID,a.owner,
       a.segment_name,
       a.partition_name,
       a.segment_type,
       a.tablespace_name,
       round(a.bytes/1024/1024,2) size_m,
       (bytes) segments_size,
       a.extents
  FROM (SELECT b.CON_ID, b.owner,
               b.segment_name,
               b.partition_name,
               b.segment_type,
               b.tablespace_name,
               b.bytes,
               b.extents,
               DENSE_RANK() over(partition by b.tablespace_name ORDER BY b.bytes desc) rank_order
          FROM cdb_segments b
         WHERE b.BYTES > 10*1024*1024
           AND  b.tablespace_name NOT LIKE 'UNDO%'
           AND  b.owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
     AND  b.segment_name not in (SELECT nr.object_name FROM cdb_recyclebin nr) ) a  
 WHERE rank_order <= 3
 ORDER BY CON_ID,a.tablespace_name, a.bytes desc, a.owner;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 212 for section: prompt Notes:
hc_q_prompt_notes_212() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_212_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                      - TOP 10 SEGMENTS (BY EXTENTS) -                     |

-- +----------------------------------------------------------------------------+
host echo "                10segments. . . ."

prompt  <a name="top_10_segments_by_extents"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10segments</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner                                               HEADING 'Owner'            ENTMAP OFF
COLUMN segment_name                                        HEADING 'Segment Name'     ENTMAP OFF
COLUMN partition_name                                      HEADING 'Partition Name'   ENTMAP OFF
COLUMN segment_type                                        HEADING 'Segment Type'     ENTMAP OFF
COLUMN tablespace_name                                     HEADING 'Tablespace Name'  ENTMAP OFF
COLUMN extents             FORMAT 999,999,999,999,999,999  HEADING 'Extents'          ENTMAP OFF
COLUMN bytes               FORMAT 999,999,999,999,999,999  HEADING 'Size (in bytes)'  ENTMAP OFF


-- BREAK ON report
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' OF extents bytes ON report

SELECT a.con_id, a.owner,
       a.segment_name,
       a.partition_name,
       a.segment_type,
       a.tablespace_name,
       a.extents,
       a.bytes
  FROM (select b.CON_ID, b.owner,
               b.segment_name,
               b.partition_name,
               b.segment_type,
               b.tablespace_name,
               b.bytes,
               b.extents
          from cdb_segments b
          WHERE    b.owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         order by b.extents desc) a
 WHERE ROWNUM <= 10;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 213 for section: prompt Notes:
hc_q_prompt_notes_213() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_213_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - LOB SEGMENTS -                                 |

-- +----------------------------------------------------------------------------+
host echo "                LOB. . . ."

prompt  <a name="dba_lob_segments"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>LOB</b></font><hr align="left" width="600">
 


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) ,SELECT top 100 rows </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner              FORMAT a85        HEADING 'Owner'              ENTMAP OFF
COLUMN table_name         FORMAT a75        HEADING 'Table Name'         ENTMAP OFF
COLUMN column_name        FORMAT a75        HEADING 'Column Name'        ENTMAP OFF
COLUMN segment_name       FORMAT a125       HEADING 'LOB Segment Name'   ENTMAP OFF
COLUMN tablespace_name    FORMAT a75        HEADING 'Tablespace Name'    ENTMAP OFF
COLUMN lob_segment_bytes  FORMAT a75        HEADING 'Segment Size'       ENTMAP OFF
COLUMN index_name         FORMAT a125       HEADING 'LOB Index Name'     ENTMAP OFF
COLUMN in_row             FORMAT a75        HEADING 'In Row?'            ENTMAP OFF


-- BREAK ON report ON owner ON table_name

SELECT *
  FROM (SELECT l.CON_ID, '<div nowrap align="left"><font color="#336699"><b>' ||
               l.owner || '</b></font></div>' owner,
               '<div nowrap>' || l.table_name || '</div>' table_name,
               '<div nowrap>' || l.column_name || '</div>' column_name,
               '<div nowrap>' || l.segment_name || '</div>' segment_name,
               '<div nowrap>' || s.tablespace_name || '</div>' tablespace_name,
               '<div nowrap align="right">' ||
               TO_CHAR(s.bytes, '999,999,999,999,999') || '</div>' lob_segment_bytes,
               '<div nowrap>' || l.index_name || '</div>' index_name,
               DECODE(l.in_row,
                      'YES',
                      '<div align="center"><font color="darkgreen"><b>' ||
                      l.in_row || '</b></font></div>',
                      'NO',
                      '<div align="center"><font color="#990000"><b>' ||
                      l.in_row || '</b></font></div>',
                      '<div align="center"><font color="#663300"><b>' ||
                      l.in_row || '</b></font></div>') in_row
          FROM cdb_lobs l, cdb_segments s
         WHERE l.owner = s.owner
           AND l.segment_name = s.segment_name
					 and l.CON_ID=s.CON_ID
           and  l.owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')   
         ORDER BY s.bytes desc) t
 WHERE ROWNUM <= 100
 ORDER BY con_id, t.owner, t.table_name, t.column_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 214 for section: prompt Notes:
hc_q_prompt_notes_214() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_214_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                      -  -                          |

-- +----------------------------------------------------------------------------+


prompt  <a name="objects_unable_to_extend"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <b>Segments that cannot extend because of MAXEXTENTS or not enough space</b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner             FORMAT a75                  HEADING 'Owner'            ENTMAP OFF
COLUMN tablespace_name                               HEADING 'Tablespace Name'  ENTMAP OFF
COLUMN segment_name                                  HEADING 'Segment Name'     ENTMAP OFF
COLUMN segment_type                                  HEADING 'Segment Type'     ENTMAP OFF
COLUMN next_extent       FORMAT 999,999,999,999,999  HEADING 'Next Extent'      ENTMAP OFF
COLUMN max               FORMAT 999,999,999,999,999  HEADING 'Max. Piece Size'  ENTMAP OFF
COLUMN sum               FORMAT 999,999,999,999,999  HEADING 'Sum of Bytes'     ENTMAP OFF
COLUMN extents           FORMAT 999,999,999,999,999  HEADING 'Num. of Extents'  ENTMAP OFF
COLUMN max_extents       FORMAT 999,999,999,999,999  HEADING 'Max Extents'      ENTMAP OFF


-- BREAK ON report ON owner

SELECT ds.con_id, '<div nowrap align="left"><font color="#336699"><b>' || ds.owner || '</b></font></div>' owner,
       ds.tablespace_name tablespace_name,
       ds.segment_name segment_name,
       ds.segment_type segment_type,
       ds.next_extent next_extent,
       NVL(dfs.max, 0) max,
       NVL(dfs.sum, 0) sum,
       ds.extents extents,
       ds.max_extents max_extents
  FROM cdb_segments ds,
       (SELECT nb.CON_ID, max(bytes) max, sum(bytes) sum, tablespace_name
          FROM cdb_free_space nb
         GROUP BY  nb.CON_ID,tablespace_name) dfs
 WHERE ds.CON_ID=dfs.con_id and  (ds.next_extent > nvl(dfs.max, 0) OR ds.extents >= ds.max_extents)
   AND  ds.tablespace_name = dfs.tablespace_name(+)
   AND  ds.owner NOT IN ('SYS', 'SYSTEM','SYSAUX') 
   AND  ds.tablespace_name not in  ('SYSTEM','SYSAUX')	
 ORDER BY ds.owner, ds.tablespace_name, ds.segment_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 215 for section: prompt Notes:
hc_q_prompt_notes_215() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_215_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |               -  -                     |

-- +----------------------------------------------------------------------------+


prompt  <a name="objects_which_are_nearing_maxextents"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>1/2</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner             FORMAT a75                   HEADING 'Owner'             ENTMAP OFF
COLUMN tablespace_name   FORMAT a30                   HEADING 'Tablespace name'   ENTMAP OFF
COLUMN segment_name      FORMAT a30                   HEADING 'Segment Name'      ENTMAP OFF
COLUMN segment_type      FORMAT a20                   HEADING 'Segment Type'      ENTMAP OFF
COLUMN bytes             FORMAT 999,999,999,999,999   HEADING 'Size (in bytes)'   ENTMAP OFF
COLUMN next_extent       FORMAT 999,999,999,999,999   HEADING 'Next Extent Size'  ENTMAP OFF
COLUMN pct_increase                                   HEADING '% Increase'        ENTMAP OFF
COLUMN extents           FORMAT 999,999,999,999,999   HEADING 'Num. of Extents'   ENTMAP OFF
COLUMN max_extents       FORMAT 999,999,999,999,999   HEADING 'Max Extents'       ENTMAP OFF
COLUMN pct_util          FORMAT a35                   HEADING '% Utilized'        ENTMAP OFF

SELECT b.CON_ID, owner,
       tablespace_name,
       segment_name,
       segment_type,
       bytes,
       next_extent,
       pct_increase,
       extents,
       max_extents,
       '<div align="right">' || ROUND((extents / max_extents) * 100, 2) ||'%</div>' pct_util
  FROM cdb_segments b
 WHERE extents > max_extents / 2
   AND  max_extents != 0
   AND   b.owner   NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 ORDER BY con_id, (extents / max_extents) DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 216 for section: prompt Notes:
hc_q_prompt_notes_216() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_216_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 
 
 

-- +============================================================================+

-- |                                                                            |

-- |                   <<<<<     UNDO Segments     >>>>>                        |

-- |                                                                            |

-- +============================================================================+
 
host echo "                Undo . . . ." 

prompt  <a name="undo_Segments_info"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u>Undo </u></b></font></center>
 
 

-- +----------------------------------------------------------------------------+

-- |                       - UNDO RETENTION PARAMETERS -                        |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="undo_retention_parameters"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● UNDO Retention Parameters</b></font><hr align="left" width="450">
 

prompt  <b>undo_retention is specified in minutes</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print   FORMAT a95    HEADING 'Instance_Name'     ENTMAP OFF
COLUMN thread_number_print   FORMAT a95    HEADING 'Thread Number'     ENTMAP OFF
COLUMN name                  FORMAT a125   HEADING 'Name'              ENTMAP OFF
COLUMN value                               HEADING 'Value'             ENTMAP OFF
 

-- BREAK ON report ON instance_name_print ON thread_number_print
 
SELECT '<div align="center"><font color="#336699"><b>' || i.instance_name ||
       '</b></font></div>' instance_name_print,
       '<div align="center">' || i.thread# || '</div>' thread_number_print,
       '<div nowrap>' || p.name || '</div>' name,
       (CASE p.name
         WHEN 'undo_retention' THEN
          '<div nowrap align="right">' ||
          TO_CHAR(TO_NUMBER(p.value) / 60, '999,999,999,999,999') ||
          '</div>'
         ELSE
          '<div nowrap align="right">' || p.value || '</div>'
       END) value
  FROM gv$parameter p, gv$instance i
 WHERE p.inst_id = i.inst_id
   AND p.name LIKE 'undo%'
 ORDER BY i.instance_name, p.name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 217 for section: prompt Notes:
hc_q_prompt_notes_217() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_217_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


----------------------------------------------------------------------------------------------------------------------------------------

 

-- +----------------------------------------------------------------------------+

-- |                            - UNDO SEGMENTS -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="undo_segments"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Details</b></font><hr align="left" width="450">
 

prompt  <b>● UNDO,</b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 
COLUMN instance_name FORMAT a75              HEADING 'Instance_Name'      ENTMAP OFF
COLUMN tablespace    FORMAT a85              HEADING 'Tablspace'          ENTMAP OFF
COLUMN roll_name                             HEADING 'UNDO Segment Name'  ENTMAP OFF
COLUMN in_extents                            HEADING 'Init/Next Extents'  ENTMAP OFF
COLUMN m_extents                             HEADING 'Min/Max Extents'    ENTMAP OFF
COLUMN status                                HEADING 'Status'             ENTMAP OFF
COLUMN wraps         FORMAT 999,999,999      HEADING 'Wraps'              ENTMAP OFF
COLUMN shrinks       FORMAT 999,999,999      HEADING 'Shrinks'            ENTMAP OFF
COLUMN opt           FORMAT 999,999,999,999  HEADING 'Opt. Size'          ENTMAP OFF
COLUMN bytes         FORMAT 999,999,999,999  HEADING 'Bytes'              ENTMAP OFF
COLUMN extents       FORMAT 999,999,999      HEADING 'Extents'            ENTMAP OFF
 
CLEAR COMPUTES
 

-- BREAK ON report ON instance_name ON tablespace

-- COMPUTE sum LABEL '<font color="#990000"><b>Total:</b></font>' OF bytes extents shrinks wraps ON report
 

--SELECT * FROM v$rollname;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 218 for section: prompt Notes:
hc_q_prompt_notes_218() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_218_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT a.CON_ID,
       '<div nowrap><font color="#336699"><b>' ||
       NVL(A.INSTANCE_NUM, '<br>') || '</b></font></div>' INST_ID,
       '<div nowrap><font color="#336699"><b>' || A.TABLESPACE_NAME ||
       '</b></font></div>' TABLESPACE,
       A.OWNER,
       A.SEGMENT_NAME ROLL_NAME,
       A.INITIAL_EXTENT,
       A.SEGMENT_NAME,
       A.OWNER,
       A.SEGMENT_ID,
       A.FILE_ID,
       A.BLOCK_ID,
       A.INITIAL_EXTENT,
       A.NEXT_EXTENT,
       A.MIN_EXTENTS,
       A.MAX_EXTENTS,
       A.PCT_INCREASE,
       A.RELATIVE_FNO,
       DECODE(A.STATUS,
              'OFFLINE',
              '<div align="center"><b><font color="#990000">' || A.STATUS ||
              '</font></b></div>',
              '<div align="center"><b><font color="darkgreen">' || A.STATUS ||
              '</font></b></div>') STATUS,
       B.BYTES BYTES,
       B.EXTENTS EXTENTS,
       D.SHRINKS SHRINKS,
       D.WRAPS WRAPS,
       D.OPTSIZE OPT
  FROM cdb_ROLLBACK_SEGS A
  LEFT OUTER JOIN cdb_SEGMENTS B
    ON A.SEGMENT_NAME = B.SEGMENT_NAME
   and a.CON_ID = b.CON_ID
  LEFT OUTER JOIN V$ROLLNAME C
    ON A.SEGMENT_NAME = C.NAME and a.CON_ID=c.con_id
  LEFT OUTER JOIN V$ROLLSTAT D
    ON C.USN = D.USN  and a.CON_ID=d.con_id
 ORDER BY a.CON_ID, A.INSTANCE_NUM, A.TABLESPACE_NAME, A.SEGMENT_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 219 for section: prompt Notes:
hc_q_prompt_notes_219() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_219_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt 

prompt  <b>● Wait statistics</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN class                  HEADING 'Class'   
COLUMN ratio                  HEADING 'Wait Ratio'      
 

SELECT '<font color="#336699"><b>' || W.CLASS || '</b></font>' CLASS,
       '<div align="right">' ||
       TO_CHAR(ROUND(100 * (W.COUNT / SUM(S.VALUE)), 8)) || '%</div>' RATIO
 WHERE W.CLASS IN ('system undo header',
                   'system undo block',
                   'undo header',
                   'undo block')
   AND S.NAME IN ('db block gets', 'consistent gets')
 GROUP BY W.CLASS, W.COUNT;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 220 for section: prompt Notes:
hc_q_prompt_notes_220() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_220_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
  

-- +----------------------------------------------------------------------------+

-- |                        - TABLESPACE TO OWNER  -                            |

-- +----------------------------------------------------------------------------+


prompt  <a name="tablespace_to_owner"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font> </b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN tablespace_name  FORMAT a75                  HEADING 'Tablespace Name'  ENTMAP OFF
COLUMN owner            FORMAT a75                  HEADING 'Owner'            ENTMAP OFF
COLUMN segment_type     FORMAT a75                  HEADING 'Segment Type'     ENTMAP OFF
COLUMN bytes            FORMAT 999,999,999,999,999  HEADING 'Size (in Bytes)'  ENTMAP OFF
COLUMN seg_count        FORMAT 999,999,999,999      HEADING 'Segment Count'    ENTMAP OFF


-- BREAK ON report ON tablespace_name
COMPUTE sum LABEL '<font color="#990000"><b>Total: </b></font>' of seg_count bytes ON report

SELECT d.CON_ID, '<font color="#336699"><b>' || tablespace_name || '</b></font>' tablespace_name,
       '<div align="right">' || owner || '</div>' owner,
       '<div align="right">' || segment_type || '</div>' segment_type,
       sum(bytes) bytes,
       (sum(bytes)) bytes1,	
       count(*) seg_count
  FROM cdb_segments d
  WHERE  d.owner   NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY d.CON_ID,tablespace_name, owner, segment_type
 ORDER BY d.CON_ID,tablespace_name, owner, segment_type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 221 for section: prompt Notes:
hc_q_prompt_notes_221() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_221_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

prompt  <br/>


-- +----------------------------------------------------------------------------+

-- |           -  -

-- +----------------------------------------------------------------------------+


prompt  <a name="database_tablesallinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


-- +----------------------------------------------------------------------------+

-- |           -  -

-- +----------------------------------------------------------------------------+


prompt  <a name="tables_suffering_from_row_chaining_migration"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Tables must have statistics gathered </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner                                          HEADING 'Owner'           ENTMAP OFF
COLUMN table_name                                     HEADING 'Table Name'      ENTMAP OFF
COLUMN partition_name                                 HEADING 'Partition Name'  ENTMAP OFF
COLUMN num_rows           FORMAT 999,999,999,999,999  HEADING 'Total Rows'      ENTMAP OFF
COLUMN pct_chained_rows   FORMAT a65                  HEADING '% Chained Rows'  ENTMAP OFF
COLUMN avg_row_length     FORMAT 999,999,999,999,999  HEADING 'Avg Row Length'  ENTMAP OFF

SELECT con_id,
       owner owner,
       table_name table_name,
       '' partition_name,
       num_rows num_rows,
       '<div align="right">' || ROUND((chain_cnt / num_rows) * 100, 2) ||
       '%</div>' pct_chained_rows,
       avg_row_len avg_row_length
  FROM (select d.con_id, owner, table_name, chain_cnt, num_rows, avg_row_len
          from cdb_tables d
         where chain_cnt IS NOT NULL
           AND num_rows IS NOT NULL
           AND chain_cnt > 0
           AND num_rows > 0
           AND owner != 'SYS')
UNION ALL
SELECT con_id,
       table_owner owner,
       table_name table_name,
       partition_name partition_name,
       num_rows num_rows,
       '<div align="right">' || ROUND((chain_cnt / num_rows) * 100, 2) ||
       '%</div>' pct_chained_rows,
       avg_row_len avg_row_length
  FROM (select con_id,
               table_owner,
               table_name,
               partition_name,
               chain_cnt,
               num_rows,
               avg_row_len
          from cdb_tab_partitions
         where chain_cnt IS NOT NULL
           AND num_rows IS NOT NULL
           AND chain_cnt > 0
           AND num_rows > 0
           AND table_owner != 'SYS') b
 WHERE (chain_cnt / num_rows) * 100 > 10;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 222 for section: prompt Notes:
hc_q_prompt_notes_222() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_222_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |           - 10WTables Without Primary Key -

-- +----------------------------------------------------------------------------+


prompt  <a name="tables_10Wnopkey"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10WTables Without Primary Key</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Tables must have statistics gathered </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, D.OWNER, count(1) counts
   FROM cdb_TABLES d
  WHERE not exists (SELECT 1
           FROM cdb_constraints dc
          WHERE dc.constraint_type = 'P'
            AND  dc.table_name = d.TABLE_NAME
            AND  dc.owner = d.OWNER
						and dc.CON_ID=d.CON_ID)
    AND  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
    AND  D.NUM_ROWS >= 100000
  GROUP BY d.CON_ID,D.OWNER
  ORDER BY d.CON_ID,counts desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 223 for section: prompt Notes:
hc_q_prompt_notes_223() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_223_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 50 </font></b> 

COLUMN TEMPORARY    format  a10 HEADING 'TEMPORARY'  ENTMAP OFF
COLUMN PARTITIONED    format  a20 HEADING 'PARTITIONED'  ENTMAP OFF

SELECT * FROM (
SELECT d.con_id, D.OWNER,
       D.TABLE_NAME,
       D.TEMPORARY,
       D.PARTITIONED,/*
       D.RESULT_CACHE,*/
       D.TABLESPACE_NAME,
       D.LOGGING,
       D.ROW_MOVEMENT,
       D.NUM_ROWS,
	DENSE_RANK() over(ORDER BY D.NUM_ROWS desc) rank	
  FROM cdb_TABLES d
 WHERE not exists (SELECT 1
          FROM cdb_constraints dc
         WHERE dc.constraint_type = 'P'
           AND  dc.table_name = d.TABLE_NAME
           AND  dc.owner = d.OWNER
					 and dc.CON_ID=d.CON_ID)
   AND  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
   AND  D.NUM_ROWS >= 100000)
 WHERE rank<=50   
 ORDER BY  con_id, OWNER,  TABLE_NAME,  NUM_ROWS DESC
 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 224 for section: prompt Notes:
hc_q_prompt_notes_224() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_224_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |           -  -

-- +----------------------------------------------------------------------------+


prompt  <a name="tables_nodata"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT t.con_id,
       t.owner,
       t.table_name,
       t.partition_name,
       t.tablespace_name,
       t.logging,
       t.last_analyzed,
       t.sizes sizes_m
  FROM (
        
---------------------------------- 
        SELECT d.con_id,
                D.owner,
                D.table_name,
                '' partition_name,
                D.tablespace_name,
                D.logging,
                D.last_analyzed,
                b.sizes
          FROM cdb_tables d,
                (SELECT nb.CON_ID,
                        NB.owner,
                        NB.segment_name,
                        SUM(NB.BYTES) / 1024 / 1024 SIZES
                   FROM cdb_SEGMENTS NB
                  WHERE NB.partition_name IS NULL
                    AND nb.segment_type = 'TABLE'
                    AND nb.BYTES / nb.initial_extent > 1.1
                    AND nb.owner NOT IN ('SYS', 'SYSTEM')
                    AND nb.tablespace_name NOT IN ('SYSTEM', 'SYSAUX')
                  GROUP BY nb.CON_ID, NB.owner, NB.segment_name) B
         WHERE B.segment_name = D.table_name
           AND D.owner = B.owner
           and d.CON_ID = b.con_id
           AND d.partitioned = 'NO'
           AND D.owner NOT IN ('SYS', 'SYSTEM')
           AND D.tablespace_name NOT IN ('SYSTEM', 'SYSAUX')
           AND D.num_rows = 0
           AND B.SIZES > 10
        UNION ALL
        
------------------------------------------------------------      
        SELECT d.con_id,
                D.Table_Owner,
                D.table_name,
                d.partition_name,
                D.tablespace_name,
                D.logging,
                D.last_analyzed,
                b.sizes
          FROM cdb_TAB_PARTITIONS d,
                (SELECT nb.con_id,
                        NB.owner,
                        NB.segment_name,
                        nb.partition_name,
                        SUM(NB.BYTES) / 1024 / 1024 SIZES
                   FROM cdb_SEGMENTS NB
                  WHERE NB.partition_name IS NOT NULL
                    AND nb.segment_type = 'TABLE PARTITION'
                    AND nb.BYTES / nb.initial_extent > 1.1
                    AND nb.owner NOT IN ('SYS', 'SYSTEM')
                    AND nb.tablespace_name NOT IN ('SYSTEM', 'SYSAUX')
                  GROUP BY nb.con_id,
                           NB.owner,
                           NB.segment_name,
                           nb.partition_name) B
         WHERE B.segment_name = D.table_name
           AND D.Table_Owner = B.owner
           AND d.partition_name = b.partition_name
           and b.con_id = d.con_id
           AND D.TABLE_OWNER NOT IN ('SYS', 'SYSTEM')
           AND D.tablespace_name NOT IN ('SYSTEM', 'SYSAUX')
           AND D.num_rows = 0
           AND B.SIZES > 10) t
 WHERE t.table_name NOT LIKE '%TMP%'
   AND t.table_name NOT LIKE '%TEMP%';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 225 for section: prompt Notes:
hc_q_prompt_notes_225() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_225_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "            . . ." 

prompt  <a name="database_parttableinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="nopart_table10g"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10GB</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.con_id, owner,
       segment_name,
       segment_type,
       ROUND(sum(bytes)/1024/1024/1024,3) object_size_G
  FROM cdb_segments d
where  segment_type = 'TABLE' AND  owner  NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
group by d.con_id, owner, segment_name, segment_type
having sum(bytes) / 1024 / 1024 / 1024 >= 10
ORDER BY d.con_id,object_size_G desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 226 for section: prompt Notes:
hc_q_prompt_notes_226() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_226_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="objects_max10"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10Objects</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT *
  FROM (SELECT d.CON_ID, table_owner, table_name, count(*) cnt
          FROM cdb_tab_partitions  d
	  WHERE table_owner  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')	
         GROUP BY d.CON_ID,table_owner, table_name
         ORDER BY cnt desc)
where ROWNUM <= 10;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 227 for section: prompt Notes:
hc_q_prompt_notes_227() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_227_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="partsum100"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>100</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, table_owner, table_name, count(*) cnt
  FROM cdb_tab_partitions  d
  WHERE table_owner  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
having count(*) >= 100
group by d.CON_ID,table_owner, table_name
ORDER BY cnt desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 228 for section: prompt Notes:
hc_q_prompt_notes_228() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_228_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          -  -                               |		

-- +----------------------------------------------------------------------------+

prompt  <a name="database_invalidobjects"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="invalid_objects"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner           FORMAT a85         HEADING 'Owner'         ENTMAP OFF
COLUMN object_name     FORMAT a30         HEADING 'Object Name'   ENTMAP OFF
COLUMN object_type     FORMAT a20         HEADING 'Object Type'   ENTMAP OFF
COLUMN status          FORMAT a75         HEADING 'Status'        ENTMAP OFF


-- BREAK ON report ON owner

-- COMPUTE count LABEL '<font color="#990000"><b>Grand Total: </b></font>' OF object_name ON report

SELECT d.CON_ID,
       d.OWNER,
	   count(*) cnt
  FROM cdb_objects d
 WHERE owner not in ('PUBLIC')
   AND status <> 'VALID'  
	 group by d.con_id,d.OWNER
 ORDER BY con_id, owner;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 229 for section: prompt Notes:
hc_q_prompt_notes_229() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_229_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  200

SELECT d.CON_ID,
       '<div nowrap align="left"><font color="#336699"><b>' || owner ||
       '</b></font></div>' owner,
       object_name,
       object_type,
       DECODE(status,
              'VALID',
              '<div align="center"><font color="darkgreen"><b>' || status ||
              '</b></font></div>',
              '<div align="center"><font color="#990000"><b>' || status ||
              '</b></font></div>') status,
       'alter ' || DECODE(object_type,
                          'PACKAGE BODY',
                          'PACKAGE',
                          'TYPE BODY',
                          'TYPE',
                          object_type) || ' ' || owner || '.' ||
       object_name || ' ' ||
       DECODE(object_type, 'PACKAGE BODY', 'compile body', 'compile') || ';' hands_on
  FROM cdb_objects d
 WHERE owner not in ('PUBLIC')
   AND status <> 'VALID'
   AND rownum<=200
 ORDER BY con_id, owner, object_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 230 for section: prompt Notes:
hc_q_prompt_notes_230() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_230_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                     - PROCEDURAL OBJECT ERRORS -                           |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="procedural_object_errors"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Procedural Object Errors</b></font><hr align="left" width="450">
 

prompt  <b>All records FROM cdb_ERRORS</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner                FORMAT a85      HEAD 'Schema'        ENTMAP OFF
COLUMN name                 FORMAT a30      HEAD 'Object Name'   ENTMAP OFF
COLUMN type                 FORMAT a15      HEAD 'Object Type'   ENTMAP OFF
COLUMN sequence             FORMAT 999,999  HEAD 'Sequence'      ENTMAP OFF
COLUMN line                 FORMAT 999,999  HEAD 'Line'          ENTMAP OFF
COLUMN position             FORMAT 999,999  HEAD 'Position'      ENTMAP OFF
COLUMN text                                 HEAD 'Text'          ENTMAP OFF
SET DEFINE ON 

-- BREAK ON report ON owner
	 

SELECT d.CON_ID, d.owner, d.name, d.type, count(1) cnt
  FROM cdb_errors d
  WHERE owner  NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY d.CON_ID, d.owner, d.name, d.type
 ORDER BY d.CON_ID,d.owner, d.name, d.type, cnt desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 231 for section: prompt Notes:
hc_q_prompt_notes_231() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_231_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

SELECT d.con_id,
       '<div nowrap align="left"><font color="#336699"><b>' || owner ||
       '</b></font></div>' owner,
       name,
       type,
       sequence,
       line,
       position,
       text
  FROM cdb_errors d
 where rownum <= 10
  AND  owner  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 ORDER BY con_id,owner,name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 232 for section: prompt Notes:
hc_q_prompt_notes_232() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_232_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


prompt  <a name="UNUSABLE_index"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT t.CON_ID, t.owner index_owner,
       t.index_name,
       t.table_owner,
       t.table_name,
       blevel,
       t.num_rows,
       t.leaf_blocks,
       t.distinct_keys
  FROM cdb_indexes t
 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
   AND  status = 'UNUSABLE'
	 order by t.CON_ID,t.OWNER,t.INDEX_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 233 for section: prompt Notes:
hc_q_prompt_notes_233() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_233_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="UNUSABLE_partindex"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Invalid Partition Index</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT t2.CON_ID, t2.owner,
       t1.blevel,
       t1.leaf_blocks,
       t1.INDEX_NAME,
       t2.table_name,
       t1.PARTITION_NAME,
       t1.STATUS
  FROM cdb_ind_partitions t1, cdb_indexes t2
where t1.index_name = t2.index_name
and t1.CON_ID=t2.CON_ID
   AND  t1.STATUS = 'UNUSABLE' 
 AND  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
 order by t2.CON_ID,t2.OWNER ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 234 for section: prompt Notes:
hc_q_prompt_notes_234() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_234_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="disabled_triggers"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, '<div nowrap align="left"><font color="#336699"><b>' || owner ||'</b></font></div>' owner,
       object_name TRIGGER_NAME,
       D.OBJECT_TYPE,
       D.CREATED,
  d.status,   
       (SELECT nb.status
          FROM cdb_triggers nb
         WHERE nb.owner = d.owner
           AND  nb.trigger_name = d.OBJECT_NAME
					 and nb.CON_ID=d.CON_ID)  STATUS1  
  FROM cdb_objects D
 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
   AND  status <> 'VALID'
   AND  D.OBJECT_TYPE='TRIGGER'
 ORDER BY d.CON_ID, owner, object_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 235 for section: prompt Notes:
hc_q_prompt_notes_235() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_235_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "            . . ." 

prompt  <a name="database_indexinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="num_index_5"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>5</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 50 </font></b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT *
  FROM (SELECT d.CON_ID, owner, table_name, count(*) index_count
          FROM cdb_indexes d
         WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         GROUP BY d.CON_ID, owner, table_name
        having count(*) > 5
         ORDER BY con_id, index_count desc)
 WHERE ROWNUM <= 100;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 236 for section: prompt Notes:
hc_q_prompt_notes_236() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_236_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


prompt  <a name="size_table_2"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● 2G</b></font><hr align="left" width="450">
 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, owner,
       segment_name,
       round(bytes / 1024 / 1024 / 1024, 3) size_g,
       blocks,
       tablespace_name
FROM   cdb_segments d
WHERE  segment_type = 'TABLE'
AND    segment_name NOT IN (SELECT table_name FROM cdb_indexes)
AND    bytes / 1024 / 1024 / 1024 >= 2
and  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
ORDER  BY d.CON_ID, bytes DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 237 for section: prompt Notes:
hc_q_prompt_notes_237() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_237_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <a name="size_parttable_2"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● 2GB</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.con_id, owner,
       segment_name,
       round(SUM(bytes) / 1024 / 1024 / 1024, 3) size_g,
       SUM(blocks)
FROM   cdb_segments d
WHERE  segment_type = 'TABLE PARTITION'
AND    segment_name NOT IN (SELECT table_name FROM cdb_indexes)
and  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
GROUP  BY d.CON_ID, owner,
          segment_name
HAVING SUM(bytes) / 1024 / 1024 / 1024 >= 2
ORDER  BY d.CON_ID,SUM(bytes) DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 238 for section: prompt Notes:
hc_q_prompt_notes_238() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_238_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 

   


prompt  <a name="jxdl_index"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b> </b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Top100 </font></b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT *
  FROM (SELECT d.CON_ID, d.TABLE_OWNER,
               table_name,
               trunc(count(distinct(column_name)) / count(*), 2) cross_idx_rate
          FROM cdb_ind_columns d
         WHERE table_name NOT LIKE 'BIN$%'
and  TABLE_OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         GROUP BY con_id, TABLE_OWNER, table_name
        having count(distinct(column_name)) / count(*) < 1
         ORDER BY con_id,cross_idx_rate desc)
 WHERE ROWNUM <= 100;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 239 for section: prompt Notes:
hc_q_prompt_notes_239() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_239_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="bitmap_func_index"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Top100 </font> </b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT *
  FROM (SELECT t.CON_ID, t.owner,
               t.table_name,
               t.index_name,
               t.index_type,
               t.status,
               t.blevel,
               t.leaf_blocks,
               DENSE_RANK() over(partition by t.index_type ORDER BY t.leaf_blocks desc) rn
          FROM cdb_indexes t
         WHERE index_type in ('BITMAP', 'FUNCTION-BASED NORMAL')
           AND  owner not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND  t.leaf_blocks > 0) v
 WHERE rn <= 100
 ORDER BY v.CON_ID, v.owner, v.table_name, rn;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 240 for section: prompt Notes:
hc_q_prompt_notes_240() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_240_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                . . . ."

prompt  <a name="noindex_wjkey"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT con_id, owner,
       table_name,
       constraint_name,
       cname1 || nvl2(cname2, ',' || cname2, null) ||
       nvl2(cname3, ',' || cname3, null) ||
       nvl2(cname4, ',' || cname4, null) ||
       nvl2(cname5, ',' || cname5, null) ||
       nvl2(cname6, ',' || cname6, null) ||
       nvl2(cname7, ',' || cname7, null) ||
       nvl2(cname8, ',' || cname8, null) columns
  FROM (SELECT b.con_id, b.owner,
               b.table_name,
               b.constraint_name,
               max(DECODE(position, 1, column_name, null)) cname1,
               max(DECODE(position, 2, column_name, null)) cname2,
               max(DECODE(position, 3, column_name, null)) cname3,
               max(DECODE(position, 4, column_name, null)) cname4,
               max(DECODE(position, 5, column_name, null)) cname5,
               max(DECODE(position, 6, column_name, null)) cname6,
               max(DECODE(position, 7, column_name, null)) cname7,
               max(DECODE(position, 8, column_name, null)) cname8,
               count(*) col_cnt
          FROM (SELECT nc.con_id, substr(table_name, 1, 30) table_name,
                       substr(constraint_name, 1, 30) constraint_name,
                       substr(column_name, 1, 30) column_name,
                       position
                  FROM cdb_cons_columns nc
                 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') ) a,
               cdb_constraints b
         WHERE a.constraint_name = b.constraint_name  
				 and a.con_id=b.con_id
           AND  b.constraint_type = 'R'
           AND  b.owner not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         GROUP BY b.con_id, b.owner, b.table_name, b.constraint_name) cons
 WHERE col_cnt > ALL (SELECT count(*)
          FROM cdb_ind_columns i
         WHERE i.table_name = cons.table_name
           AND  i.column_name in (cname1,
                                 cname2,
                                 cname3,
                                 cname4,
                                 cname5,
                                 cname6,
                                 cname7,
                                 cname8)
           AND  i.column_position <= cons.col_cnt
           AND  i.index_owner not IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         GROUP BY con_id,i.index_name)
				 order by con_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 241 for section: prompt Notes:
hc_q_prompt_notes_241() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_241_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                . . . ."

prompt  <a name="big_index_never_use"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 1M,,TOP50 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

--COLUMN count_index_cols       FORMAT a75    HEADING ''       ENTMAP OFF
COLUMN CREATED   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATED&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN min_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;min_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF	
COLUMN max_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;max_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT CON_ID, TABLE_OWNER,
       TABLE_NAME,
       INDEX_OWNER,
       INDEX_NAME,
       CREATED,
       INDEX_TYPE,
       INDEX_MB,
       COUNT_INDEX_COLS,
       MIN_DATE,
       MAX_DATE
  FROM (WITH TMP1 AS (SELECT I.CON_ID, I.OWNER INDEX_OWNER,
                             I.TABLE_OWNER,
                             TABLE_NAME,
                             INDEX_NAME,
                             INDEX_TYPE,
                             (SELECT NB.CREATED
                                FROM CDB_OBJECTS NB
                               WHERE NB.OWNER = I.OWNER
                                 AND NB.OBJECT_NAME = I.INDEX_NAME
                                 AND NB.CON_ID=I.CON_ID
                                 AND NB.SUBOBJECT_NAME IS NULL
                                 AND NB.OBJECT_TYPE = 'INDEX') CREATED,
                             ROUND(SUM(S.BYTES) / 1024 / 1024, 2) INDEX_MB,
                             (SELECT COUNT(1)
                                FROM CDB_IND_COLUMNS DIC
                               WHERE DIC.INDEX_NAME = I.INDEX_NAME
                                 AND DIC.TABLE_NAME = I.TABLE_NAME
                                 AND DIC.INDEX_OWNER = I.OWNER
                                 AND DIC.CON_ID=I.CON_ID) COUNT_INDEX_COLS,
                             DENSE_RANK() OVER(ORDER BY SUM(S.BYTES) DESC) RANK_ORDER
                        FROM CDB_SEGMENTS S, CDB_INDEXES I
                       WHERE I.INDEX_NAME = S.SEGMENT_NAME
                       AND S.CON_ID=I.CON_ID
                         AND S.SEGMENT_TYPE LIKE '%INDEX%'
                         AND I.OWNER = S.OWNER
                         AND S.OWNER NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
                       GROUP BY I.CON_ID, I.OWNER,
                                I.TABLE_OWNER,
                                TABLE_NAME,
                                INDEX_NAME,
                                INDEX_TYPE
                      HAVING SUM(S.BYTES) > 1024 * 1024), 
   TMP2 AS (SELECT CON_ID, INDEX_OWNER,INDEX_NAME,
       PLAN_OPERATION,
       (SELECT MIN(TO_CHAR(NB.BEGIN_INTERVAL_TIME,
                           'YYYY-MM-DD HH24:MI:SS'))
          FROM CDB_HIST_SNAPSHOT NB
       (SELECT MAX(TO_CHAR(NB.END_INTERVAL_TIME,
                           'YYYY-MM-DD HH24:MI:SS'))
          FROM CDB_HIST_SNAPSHOT NB
       COUNTS
  FROM (SELECT D.CON_ID, D.OBJECT_OWNER INDEX_OWNER,
               D.OBJECT_NAME INDEX_NAME,
               D.OPERATION || ' ' ||
               D.OPTIONS PLAN_OPERATION,
               COUNT(1) COUNTS
          FROM CDB_HIST_SQL_PLAN D,
               CDB_HIST_SQLSTAT  H
         WHERE D.OBJECT_OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND D.OPERATION LIKE
               '%INDEX%'
           AND D.SQL_ID =H.SQL_ID
       AND D.CON_ID=H.CON_ID
           GROUP BY D.CON_ID, D.OBJECT_OWNER,D.OBJECT_NAME,D.OPERATION,D.OPTIONS) V)
         SELECT A.CON_ID, A.TABLE_OWNER,
                A.TABLE_NAME,
                A.INDEX_OWNER,
                A.INDEX_NAME,
                A.CREATED,
                A.INDEX_TYPE,
                A.INDEX_MB,
                COUNT_INDEX_COLS,
                CASE
                  WHEN MIN_DATE IS NULL THEN
                   (SELECT MIN(TO_CHAR(NB.BEGIN_INTERVAL_TIME,
                                       'YYYY-MM-DD HH24:MI:SS'))
                      FROM CDB_HIST_SNAPSHOT NB)
                  ELSE
                   MIN_DATE
                END AS MIN_DATE,
                CASE
                  WHEN MAX_DATE IS NULL THEN
                   (SELECT MAX(TO_CHAR(NB.BEGIN_INTERVAL_TIME,
                                       'YYYY-MM-DD HH24:MI:SS'))
                      FROM CDB_HIST_SNAPSHOT NB)
                  ELSE
                   MAX_DATE
                END AS MAX_DATE,
                PLAN_OPERATION,
                DENSE_RANK() OVER(ORDER BY INDEX_MB DESC) RANK_ORDER2
           FROM TMP1 A
           LEFT OUTER JOIN TMP2 B
             ON (A.INDEX_OWNER = B.INDEX_OWNER AND
                A.INDEX_NAME = B.INDEX_NAME AND A.CON_ID=B.CON_ID)
            AND RANK_ORDER <= 50)
          WHERE PLAN_OPERATION IS NULL
            AND RANK_ORDER2 <= 50
          ORDER BY  CON_ID,TABLE_OWNER, TABLE_NAME, INDEX_MB DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 242 for section: prompt Notes:
hc_q_prompt_notes_242() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_242_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                3. . . ."

prompt  <a name="index_cols_counts"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>3</b></font>[<a class="noLink" href="#index_cols_high">Next Item</a>]<hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 3,3 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

--COLUMN IND_COLS_COUNT       FORMAT a75    HEADING ''       ENTMAP OFF
COLUMN PARTITIONED       FORMAT a11    HEADING 'PARTITIONED'       ENTMAP OFF
COLUMN IS_PRIMARY_KEY       FORMAT a15    HEADING 'IS_PRIMARY_KEY'       ENTMAP OFF
COLUMN LAST_ANALYZED   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ANALYZED&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INDEX_CREATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;INDEX_CREATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT TABLE_OWNER,
       TABLE_NAME,
       INDEX_OWNER,
       INDEX_NAME,
       INDEX_TYPE,
       UNIQUENESS,
       (SELECT DECODE(nb.constraint_type, 'P', 'YES')
          FROM cdb_constraints nb
         WHERE nb.constraint_name = V.index_name
           AND nb.owner = V.INDEX_OWNER
           AND NB.CON_ID = V.CON_ID
           AND nb.constraint_type = 'P') is_primary_key,
       PARTITIONED,
       IND_COLS_COUNT,
       (SELECT round(SUM(bytes) / 1024 / 1024, 2)
          FROM CDB_segments nd  
         WHERE segment_name = index_name
           AND nd.owner = INDEX_OWNER
           AND ND.CON_ID = V.CON_ID) INDEX_SIZE_M,
       TABLESPACE_NAME,
       STATUS,
       
-- VISIBILITY,
       LAST_ANALYZED,
       DEGREE,
       NUM_ROWS,
       SELECTIVITY,
       STALE_STATS,
       ,
       Index Height,
       ,
       ,
       KEYAverage Leaf Block Count,
       KEY,
       Clustering Factor,
       COMPRESSION,
       LOGGING,
       (SELECT d.CREATED
          FROM CDB_OBJECTS d
         WHERE d.OBJECT_NAME = INDEX_NAME
           AND d.OBJECT_TYPE = 'INDEX'
           AND d.OWNER = INDEX_OWNER
           AND D.CON_ID = V.CON_ID) INDEX_CREATE
  FROM (SELECT di.con_id,
               di.owner index_owner,
               di.table_owner,
               di.table_name,
               di.index_name,
               di.index_type,
               di.uniqueness,
               di.partitioned,
               (SELECT COUNT(1)
                  FROM CDB_ind_columns dic
                 WHERE dic.index_name = di.index_name
                   AND dic.table_name = di.table_name
                   AND dic.INDEX_OWNER = di.owner
                   and dic.CON_ID = di.CON_ID) IND_COLS_COUNT,
               di.tablespace_name,
               di.status,
               
--di.visibility,
               di.last_analyzed,
               di.degree,
               di.num_rows,
               DECODE(di.num_rows,
                      0,
                      '',
                      round(di.distinct_keys / di.num_rows, 2)) selectivity,
               DIS.STALE_STATS,
               di.BLEVEL ,
               di.blevel + 1 Index Height,
               di.LEAF_BLOCKS ,
               di.DISTINCT_KEYS ,
               di.AVG_LEAF_BLOCKS_PER_KEY KEYAverage Leaf Block Count,
               di.AVG_DATA_BLOCKS_PER_KEY KEY,
               di.clustering_factor Clustering Factor,
               di.compression,
               di.logging
          FROM CDB_indexes di
          LEFT OUTER JOIN CDB_ind_statistics dis
            ON (di.owner = dis.owner AND di.index_name = dis.INDEX_NAME AND
               di.table_name = dis.TABLE_NAME AND
               di.table_owner = dis.TABLE_OWNER AND 
               di.CON_ID = dis.CON_ID and dis.OBJECT_TYPE = 'INDEX')
         WHERE di.index_type != 'LOB'
         AND  DI.owner not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND exists (SELECT 1
                  FROM CDB_segments nd
                 where segment_name = di.index_name
                   AND nd.owner = owner
                   and nd.con_id = di.con_id)) V
 WHERE IND_COLS_COUNT >= 4;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 243 for section: prompt Notes:
hc_q_prompt_notes_243() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_243_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                3. . . ."

prompt  <a name="index_cols_high"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>3</b></font><hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Index Height3

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

--COLUMN IND_COLS_COUNT11       FORMAT a75    HEADING ''       ENTMAP OFF
COLUMN PARTITIONED       FORMAT a11    HEADING 'PARTITIONED'       ENTMAP OFF
COLUMN IS_PRIMARY_KEY       FORMAT a15    HEADING 'IS_PRIMARY_KEY'       ENTMAP OFF
COLUMN LAST_ANALYZED   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ANALYZED&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INDEX_CREATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;INDEX_CREATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT TABLE_OWNER,
       TABLE_NAME,
       INDEX_OWNER,
       INDEX_NAME,
       INDEX_TYPE,
       UNIQUENESS,
       (SELECT DECODE(nb.constraint_type, 'P', 'YES')
          FROM cdb_constraints nb
         WHERE nb.constraint_name = V.index_name
           AND nb.owner = V.INDEX_OWNER
           AND NB.CON_ID = V.CON_ID
           AND nb.constraint_type = 'P') is_primary_key,
       PARTITIONED,
       IND_COLS_COUNT,
       (SELECT round(SUM(bytes) / 1024 / 1024, 2)
          FROM CDB_segments nd  
         WHERE segment_name = index_name
           AND nd.owner = INDEX_OWNER
           AND ND.CON_ID = V.CON_ID) INDEX_SIZE_M,
       TABLESPACE_NAME,
       STATUS,
       
-- VISIBILITY,
       LAST_ANALYZED,
       DEGREE,
       NUM_ROWS,
       SELECTIVITY,
       STALE_STATS,
       ,
       Index Height,
       ,
       ,
       KEYAverage Leaf Block Count,
       KEY,
       Clustering Factor,
       COMPRESSION,
       LOGGING,
       (SELECT d.CREATED
          FROM CDB_OBJECTS d
         WHERE d.OBJECT_NAME = INDEX_NAME
           AND d.OBJECT_TYPE = 'INDEX'
           AND d.OWNER = INDEX_OWNER
           AND D.CON_ID = V.CON_ID) INDEX_CREATE
  FROM (SELECT di.con_id,
               di.owner index_owner,
               di.table_owner,
               di.table_name,
               di.index_name,
               di.index_type,
               di.uniqueness,
               di.partitioned,
               (SELECT COUNT(1)
                  FROM CDB_ind_columns dic
                 WHERE dic.index_name = di.index_name
                   AND dic.table_name = di.table_name
                   AND dic.INDEX_OWNER = di.owner
                   and dic.CON_ID = di.CON_ID) IND_COLS_COUNT,
               di.tablespace_name,
               di.status,
               
--di.visibility,
               di.last_analyzed,
               di.degree,
               di.num_rows,
               DECODE(di.num_rows,
                      0,
                      '',
                      round(di.distinct_keys / di.num_rows, 2)) selectivity,
               DIS.STALE_STATS,
               di.BLEVEL ,
               di.blevel + 1 Index Height,
               di.LEAF_BLOCKS ,
               di.DISTINCT_KEYS ,
               di.AVG_LEAF_BLOCKS_PER_KEY KEYAverage Leaf Block Count,
               di.AVG_DATA_BLOCKS_PER_KEY KEY,
               di.clustering_factor Clustering Factor,
               di.compression,
               di.logging
          FROM CDB_indexes di
          LEFT OUTER JOIN CDB_ind_statistics dis
            ON (di.owner = dis.owner AND di.index_name = dis.INDEX_NAME AND
               di.table_name = dis.TABLE_NAME AND
               di.table_owner = dis.TABLE_OWNER AND 
               di.CON_ID = dis.CON_ID and dis.OBJECT_TYPE = 'INDEX')
         WHERE di.index_type != 'LOB'
         AND  DI.owner not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND exists (SELECT 1
                  FROM CDB_segments nd
                 where segment_name = di.index_name
                   AND nd.owner = owner
                   and nd.con_id = di.con_id)) V
 WHERE Index Height >= 4;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 244 for section: prompt Notes:
hc_q_prompt_notes_244() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_244_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                . . . ."

prompt  <a name="index_cols_STALE_STATS"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font>[<a class="noLink" href="#database_parallelinfo">Next Item</a>]<hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN STALE_STATS       FORMAT a11    HEADING 'STALE_STATS'       ENTMAP OFF
COLUMN PARTITIONED       FORMAT a11    HEADING 'PARTITIONED'       ENTMAP OFF
COLUMN IS_PRIMARY_KEY       FORMAT a15    HEADING 'IS_PRIMARY_KEY'       ENTMAP OFF
COLUMN LAST_ANALYZED   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_ANALYZED&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN INDEX_CREATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;INDEX_CREATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT TABLE_OWNER,
       TABLE_NAME,
       INDEX_OWNER,
       INDEX_NAME,
       INDEX_TYPE,
       UNIQUENESS,
       (SELECT DECODE(nb.constraint_type, 'P', 'YES')
          FROM cdb_constraints nb
         WHERE nb.constraint_name = V.index_name
           AND nb.owner = V.INDEX_OWNER
           AND NB.CON_ID = V.CON_ID
           AND nb.constraint_type = 'P') is_primary_key,
       PARTITIONED,
       IND_COLS_COUNT,
       (SELECT round(SUM(bytes) / 1024 / 1024, 2)
          FROM CDB_segments nd  
         WHERE segment_name = index_name
           AND nd.owner = INDEX_OWNER
           AND ND.CON_ID = V.CON_ID) INDEX_SIZE_M,
       TABLESPACE_NAME,
       STATUS,
       
-- VISIBILITY,
       LAST_ANALYZED,
       DEGREE,
       NUM_ROWS,
       SELECTIVITY,
       STALE_STATS,
       ,
       Index Height,
       ,
       ,
       KEYAverage Leaf Block Count,
       KEY,
       Clustering Factor,
       COMPRESSION,
       LOGGING,
       (SELECT d.CREATED
          FROM CDB_OBJECTS d
         WHERE d.OBJECT_NAME = INDEX_NAME
           AND d.OBJECT_TYPE = 'INDEX'
           AND d.OWNER = INDEX_OWNER
           AND D.CON_ID = V.CON_ID) INDEX_CREATE
  FROM (SELECT di.con_id,
               di.owner index_owner,
               di.table_owner,
               di.table_name,
               di.index_name,
               di.index_type,
               di.uniqueness,
               di.partitioned,
               (SELECT COUNT(1)
                  FROM CDB_ind_columns dic
                 WHERE dic.index_name = di.index_name
                   AND dic.table_name = di.table_name
                   AND dic.INDEX_OWNER = di.owner
                   and dic.CON_ID = di.CON_ID) IND_COLS_COUNT,
               di.tablespace_name,
               di.status,
               
--di.visibility,
               di.last_analyzed,
               di.degree,
               di.num_rows,
               DECODE(di.num_rows,
                      0,
                      '',
                      round(di.distinct_keys / di.num_rows, 2)) selectivity,
               DIS.STALE_STATS,
               di.BLEVEL ,
               di.blevel + 1 Index Height,
               di.LEAF_BLOCKS ,
               di.DISTINCT_KEYS ,
               di.AVG_LEAF_BLOCKS_PER_KEY KEYAverage Leaf Block Count,
               di.AVG_DATA_BLOCKS_PER_KEY KEY,
               di.clustering_factor Clustering Factor,
               di.compression,
               di.logging
          FROM CDB_indexes di
          LEFT OUTER JOIN CDB_ind_statistics dis
            ON (di.owner = dis.owner AND di.index_name = dis.INDEX_NAME AND
               di.table_name = dis.TABLE_NAME AND
               di.table_owner = dis.TABLE_OWNER AND 
               di.CON_ID = dis.CON_ID and dis.OBJECT_TYPE = 'INDEX')
         WHERE di.index_type != 'LOB'
         AND  DI.owner not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND exists (SELECT 1
                  FROM CDB_segments nd
                 where segment_name = di.index_name
                   AND nd.owner = owner
                   and nd.con_id = di.con_id)) V
 WHERE STALE_STATS ='YES';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 245 for section: prompt Notes:
hc_q_prompt_notes_245() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_245_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                              -  -                               |

-- +----------------------------------------------------------------------------+

host echo "            Degree of Parallelism. . ." 

prompt  <a name="database_parallelinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>Degree of Parallelism</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="table_parallel"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Degree of Parallelism</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT t.CON_ID, t.owner, t.table_name, degree
  FROM cdb_tables t
where (trim(t.degree) >'1' or trim(t.degree)='DEFAULT')
AND owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
order by t.CON_ID, t.owner, t.table_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 246 for section: prompt Notes:
hc_q_prompt_notes_246() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_246_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="index_parallel"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Degree of Parallelism</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT t.con_id, t.owner, t.table_name, index_name, degree, status
  FROM cdb_indexes t
where (trim(t.degree) >'1' or trim(t.degree)='DEFAULT')
AND owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
order by  t.con_id ,t.owner, t.table_name
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 247 for section: prompt Notes:
hc_q_prompt_notes_247() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_247_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "            . . ." 

prompt  <a name="database_othersobjects"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>

host echo "                . . . ." 

prompt  <a name="link_alert_log"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

SET DEFINE OFF
SET DEFINE ON

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: :&_ALERTLOG_PATH </font> </b>

prompt 


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● View200</b></font>[<a class="noLink" href="#altet_100">Next Item</a>]<hr align="left" width="450">


--SELECT '<textarea cols="120" rows="10"> ' || message_text || '</textarea>'  message_text FROM T_ALERT_CHECKHELTH_CLOB_LHR;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 248 for section: prompt Notes:
hc_q_prompt_notes_248() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_248_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SET DEFINE OFF
COLUMN alert_date   FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;alert_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN message_text   FORMAT a300    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;message_text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;              '  ENTMAP OFF
SET DEFINE ON

SELECT *
  FROM (SELECT a.CON_ID,
               
--a.CONTAINER_NAME,
               to_char(originating_timestamp, 'YYYY-MM-DD HH24:MI:SS') alert_date,
               message_text,
               
--a.ADR_HOME,
               a.HOST_ID,
               a.HOST_ADDRESS,
               a.PROCESS_ID,
               a.RECORD_ID,
               a.FILENAME,
               DENSE_RANK() OVER(PARTITION BY a.CON_ID ORDER BY a.RECORD_ID DESC) RN
          from v$diag_alert_ext a
         where trim(a.COMPONENT_ID) = 'rdbms'
           AND A.FILENAME =
               (SELECT D.VALUE ||
                       (SELECT CASE
                                 WHEN D.PLATFORM_NAME LIKE '%Microsoft%' THEN
                                  CHR(92)
                                 ELSE
                                  CHR(47)
                               END PLATFORM
                          FROM V$DATABASE D) || 'log.xml'
                  FROM V$DIAG_INFO D
                 WHERE D.NAME = 'Diag Alert')
           and originating_timestamp >= sysdate - 7
           and trim(a.MESSAGE_TEXT) IS NOT NULL)
 where rn <= 200
 order by record_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 249 for section: prompt Notes:
hc_q_prompt_notes_249() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_249_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-------View100

prompt   

prompt  <a name="altet_100"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● View100(),</b></font><hr align="left" width="450">

SET DEFINE OFF
COLUMN alert_date   FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;alert_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN message_text   FORMAT a300    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;message_text&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;              '  ENTMAP OFF
SET DEFINE ON

SELECT b.*
  FROM (SELECT a.con_id,
               to_char(originating_timestamp, 'YYYY-MM-DD HH24:MI:SS') alert_date,
               message_text,
               
--a.ADR_HOME,
               a.HOST_ID,
               a.HOST_ADDRESS,
               a.PROCESS_ID,
               a.RECORD_ID,
               a.FILENAME,
               DENSE_RANK() over(partition by con_id ORDER BY RECORD_ID desc) rank_order
          from v$diag_alert_ext a
         where trim(a.COMPONENT_ID) = 'rdbms'
           AND A.FILENAME =
               (SELECT D.VALUE ||
                       (SELECT CASE
                                 WHEN D.PLATFORM_NAME LIKE '%Microsoft%' THEN
                                  CHR(92)
                                 ELSE
                                  CHR(47)
                               END PLATFORM
                          FROM V$DATABASE D) || 'log.xml'
                  FROM V$DIAG_INFO D
                 WHERE D.NAME = 'Diag Alert')
           and originating_timestamp >= SYSDATE - 15
           and message_text NOT LIKE '%advanced to log sequence%'
           AND message_text NOT LIKE '  Current log#%'
           AND message_text NOT LIKE 'Archived Log entry%'
           AND message_text NOT LIKE
               'LNS: Standby redo logfile selected for thread %') b
 WHERE b.rank_order <= 100
 order by record_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 250 for section: prompt Notes:
hc_q_prompt_notes_250() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_250_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                           - DIRECTORIES -                                  |

-- +----------------------------------------------------------------------------+


prompt  <a name="dba_directories"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Database Directory Overview</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner             FORMAT a75  HEADING 'Owner'             ENTMAP OFF
COLUMN directory_name    FORMAT a75  HEADING 'Directory Name'    ENTMAP OFF
COLUMN directory_path                HEADING 'Directory Path'    ENTMAP OFF


-- BREAK ON report ON owner

SELECT d.CON_ID,d.ORIGIN_CON_ID,d.OWNER,d.DIRECTORY_NAME,d.DIRECTORY_PATH
  FROM CDB_DIRECTORIES d
 ORDER BY d.CON_ID,OWNER, DIRECTORY_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 251 for section: prompt Notes:
hc_q_prompt_notes_251() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_251_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                              - RECYCLE BIN -                               |

-- +----------------------------------------------------------------------------+


prompt  <a name="dba_recycle_bin"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


-- BREAK ON report ON owner

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Size of Recycle Bin Objects</b></font><hr align="left" width="450">

SELECT a.CON_ID,
       nvl(a.owner, '') owner,
       round(SUM(a.space *
                 (SELECT value FROM v$parameter WHERE name = 'db_block_size')) / 1024 / 1024,
             3) recyb_size,
       count(1) recyb_cnt
  FROM cdb_recyclebin a
 GROUP BY a.CON_ID, ROLLUP(a.owner);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 252 for section: prompt Notes:
hc_q_prompt_notes_252() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_252_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● 10Objects</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner               FORMAT a85                   HEADING 'Owner'           ENTMAP OFF
COLUMN original_name                                    HEADING 'original_name'   ENTMAP OFF
COLUMN type                                             HEADING 'Object|Type'     ENTMAP OFF
COLUMN object_name                                      HEADING 'object_name'     ENTMAP OFF
COLUMN ts_name                                          HEADING 'Tablespace'      ENTMAP OFF
COLUMN operation                                        HEADING 'Operation'       ENTMAP OFF
COLUMN createtime                                       HEADING 'createtime'     ENTMAP OFF
COLUMN droptime                                         HEADING 'droptime'       ENTMAP OFF
COLUMN can_undrop                                       HEADING 'Can|Undrop?'     ENTMAP OFF
COLUMN can_purge                                        HEADING 'Can|Purge?'      ENTMAP OFF
COLUMN bytes               FORMAT 999,999,999,999,999   HEADING 'Bytes'           ENTMAP OFF

SELECT *
  FROM (SELECT r.CON_ID, '<div nowrap align="left"><font color="#336699"><b>' || owner ||
               '</b></font></div>' owner,
               original_name,
               type,
               object_name,
               ts_name,
               operation,
               '<div nowrap align="right">' || NVL(createtime, '<br>') ||
               '</div>' createtime,
               '<div nowrap align="right">' || NVL(droptime, '<br>') ||
               '</div>' droptime,
               DECODE(can_undrop,
                      null,
                      '<BR>',
                      'YES',
                      '<div align="center"><font color="darkgreen"><b>' ||
                      can_undrop || '</b></font></div>',
                      'NO',
                      '<div align="center"><font color="#990000"><b>' ||
                      can_undrop || '</b></font></div>',
                      '<div align="center"><font color="#663300"><b>' ||
                      can_undrop || '</b></font></div>') can_undrop,
               DECODE(can_purge,
                      null,
                      '<BR>',
                      'YES',
                      '<div align="center"><font color="darkgreen"><b>' ||
                      can_purge || '</b></font></div>',
                      'NO',
                      '<div align="center"><font color="#990000"><b>' ||
                      can_purge || '</b></font></div>',
                      '<div align="center"><font color="#663300"><b>' ||
                      can_purge || '</b></font></div>') can_purge,
               (space * p.blocksize) bytes
          FROM cdb_recyclebin r,
               (SELECT value blocksize
                  FROM v$parameter
                 WHERE name = 'db_block_size') p
         ORDER BY r.droptime)
 WHERE ROWNUM <= 10
 ORDER BY con_id, owner, object_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 253 for section: prompt Notes:
hc_q_prompt_notes_253() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_253_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                              - DB LINKS -                                  |

-- +----------------------------------------------------------------------------+


prompt  <a name="db_links"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN owner        FORMAT a75    HEADING 'Owner'           ENTMAP OFF
COLUMN db_link      FORMAT a75    HEADING 'DB Link Name'    ENTMAP OFF
COLUMN username                   HEADING 'Username'        ENTMAP OFF
COLUMN host                       HEADING 'Host'            ENTMAP OFF
COLUMN CREATED   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATED&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF


-- BREAK ON owner

SELECT a.CON_ID,
       '<b><font color="#336699">' || owner || '</font></b>' owner,
       db_link,
       username,
       host,
       '<div nowrap align="right">' ||
       TO_CHAR(CREATED, 'yyyy-mm-dd HH24:MI:SS') || '</div>' CREATED
  FROM cdb_db_links a
 ORDER BY a.CON_ID, owner, db_link;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 254 for section: prompt Notes:
hc_q_prompt_notes_254() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_254_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="link_external_tables"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.CON_ID,
       a.OWNER,
       a.TABLE_NAME,
       a.TYPE_OWNER,
       a.TYPE_NAME,
       a.DEFAULT_DIRECTORY_OWNER,
       a.DEFAULT_DIRECTORY_NAME,
       a.REJECT_LIMIT,
       a.ACCESS_TYPE,
       a.ACCESS_PARAMETERS,
       a.PROPERTY
  FROM cdb_external_tables a
 order by con_id, owner;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 255 for section: prompt Notes:
hc_q_prompt_notes_255() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_255_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 
 
 


--------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------------------------

prompt  <a name="all_triggers_show"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt   

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF
 

SELECT d.CON_ID, OWNER, count(1)  cnt
  FROM cdb_triggers d
 GROUP BY d.CON_ID, owner
 ORDER BY d.CON_ID, cnt desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 256 for section: prompt Notes:
hc_q_prompt_notes_256() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_256_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ,,10</b></font><hr align="left" width="450">

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM)</font> </b>
SELECT *
  FROM (SELECT d.CON_ID, OWNER,
               TRIGGER_NAME,
               d.trigger_type,
               d.triggering_event,
               d.table_owner,
               d.base_object_type,
               TABLE_NAME,
               STATUS,
               d.when_clause,
               DENSE_RANK() over(partition by d.owner, d.trigger_type ORDER BY d.trigger_name) rank_order
          FROM cdb_triggers d
         WHERE  d.owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
        ) wd
 WHERE rank_order <= 10
 ORDER BY wd.con_id, wd.owner, wd.status;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 257 for section: prompt Notes:
hc_q_prompt_notes_257() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_257_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● database</b></font><hr align="left" width="450">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font></b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, OWNER,
       TRIGGER_NAME,
       d.trigger_type,
       d.triggering_event,
       d.table_owner,
       d.base_object_type,
       TABLE_NAME,
       STATUS,
       d.when_clause 
FROM   cdb_triggers  d
WHERE  d.owner   NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
and  d.base_object_type like 'DATABASE%'
ORDER BY  d.CON_ID,d.owner,d.status ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 258 for section: prompt Notes:
hc_q_prompt_notes_258() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_258_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● DISABLED</b></font><hr align="left" width="450">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font></b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.CON_ID, OWNER,
       TRIGGER_NAME,
       TABLE_NAME,
       STATUS,
       (SELECT nb.status
          FROM cdb_objects nb
         WHERE nb.OWNER = d.owner
           AND  nb.OBJECT_NAME = d.trigger_name
					 and nb.CON_ID=d.CON_ID)  STATUS1
  FROM cdb_triggers d
 WHERE owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')   
   AND  d.status <> 'ENABLED'
 ORDER BY d.CON_ID, d.owner, d.status;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 259 for section: prompt Notes:
hc_q_prompt_notes_259() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_259_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="sequence_cache_20"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>cacheless than20</b></font><hr align="left" width="600"> 

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● cacheless than20,,1000,20Too Small</b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


prompt   ● 
SELECT t.CON_ID, sequence_owner, count(1) cnt
  FROM cdb_sequences t
 WHERE cache_size < 20
   AND  sequence_owner NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY t.CON_ID, t.sequence_owner
 ORDER BY cnt desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 260 for section: prompt Notes:
hc_q_prompt_notes_260() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_260_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   ●  

COLUMN order_flag FORMAT a10             HEADING 'order_flag'      ENTMAP OFF 
SELECT t.CON_ID,
       sequence_owner,
       sequence_name,
       cache_size,
       t.order_flag,
       'alter sequence ' || t.sequence_owner || '.' || t.sequence_name ||
       ' cache 1000;' alter_sequence
  FROM cdb_sequences t
 WHERE cache_size < 20   
   AND  sequence_owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 order by t.CON_ID, t.SEQUENCE_OWNER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 261 for section: prompt Notes:
hc_q_prompt_notes_261() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_261_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: AUDSES$, </font></b>
SELECT * FROM cdb_sequences d WHERE d.sequence_name ='AUDSES$' order by con_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 262 for section: prompt Notes:
hc_q_prompt_notes_262() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_262_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt    

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ,cache </b></font><hr align="left" width="450">


prompt   ●  

SELECT WB.*,
       'ALTER SEQUENCE  ' || WB.USERNAME || '.' || WB.SEQUENCE_NAME ||
       '  CACHE 1000;' alter_sequence
  FROM (SELECT DISTINCT d.CON_ID, D.EVENT,
                        D.P2,
                        A.USERNAME,
                        (SELECT DO.OBJECT_NAME
                           FROM cdb_OBJECTS DO
                          WHERE DO.OBJECT_ID = D.P2
													and do.CON_ID=d.CON_ID) SEQUENCE_NAME,
                        (SELECT DS.CACHE_SIZE
                           FROM cdb_OBJECTS DO, cdb_SEQUENCES DS
                          WHERE DO.OBJECT_ID = D.P2
                            AND DS.SEQUENCE_NAME = DO.OBJECT_NAME
                            AND DS.SEQUENCE_OWNER = DO.OWNER
														and do.CON_ID=ds.CON_ID
														and do.CON_ID=d.CON_ID) SEQUENCE_CACHE
          FROM cdb_HIST_ACTIVE_SESS_HISTORY D, cdb_USERS A
         WHERE D.USER_ID = A.USER_ID   
				 and d.CON_ID=a.CON_ID
           AND USERNAME NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND D.EVENT LIKE 'enq: SQ%') WB
					 order by CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 263 for section: prompt Notes:
hc_q_prompt_notes_263() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_263_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   ● Details(200)

SELECT *
  FROM (SELECT d.CON_ID, TO_CHAR(D.SAMPLE_TIME, 'YYYY-MM-DD HH24:MI:SS') SAMPLE_TIME,
               D.SAMPLE_ID,
               D.SESSION_ID,
               D.SESSION_SERIAL#,
               D.SESSION_TYPE,
               D.BLOCKING_SESSION,
               D.BLOCKING_SESSION_SERIAL#,
               D.EVENT,
               D.P2,
               A.USERNAME,
               (SELECT DO.OBJECT_NAME
                  FROM cdb_OBJECTS DO
                 WHERE DO.OBJECT_ID = D.P2
								 and do.CON_ID=d.CON_ID) SEQUENCE_NAME,
               (SELECT DS.CACHE_SIZE
                  FROM cdb_OBJECTS DO, cdb_SEQUENCES DS
                 WHERE DO.OBJECT_ID = D.P2
                   AND DS.SEQUENCE_NAME = DO.OBJECT_NAME
                   AND DS.SEQUENCE_OWNER = DO.OWNER
									 and do.CON_ID=ds.CON_ID
									 and d.CON_ID=d.CON_ID) SEQUENCE_CACHE,
               DENSE_RANK() OVER(PARTITION BY D.P2 ORDER BY D.SAMPLE_TIME DESC) AS DRANK
          FROM cdb_HIST_ACTIVE_SESS_HISTORY D, cdb_USERS A
         WHERE D.USER_ID = A.USER_ID   
				 and d.CON_ID=a.CON_ID
           AND USERNAME NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND D.EVENT LIKE 'enq: SQ%')
 WHERE DRANK <= 2
   AND ROWNUM <= 200
   order by con_id, SAMPLE_TIME desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 264 for section: prompt Notes:
hc_q_prompt_notes_264() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_264_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

-- +----------------------------------------------------------------------------+

-- |                          - MATERIALIZED VIEWS -                            |

-- +----------------------------------------------------------------------------+

prompt  <a name="dba_mviews_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT d.NAME,
       d.VALUE,
       d.ISDEFAULT,
       d.ISSES_MODIFIABLE,
       d.ISSYS_MODIFIABLE,
       d.DESCRIPTION
  FROM v$parameter d
 WHERE upper(d.NAME) in ('JOB_QUEUE_PROCESSES',
                         'QUERY_REWRITE_ENABLED',
                         'QUERY_REWRITE_INTEGRITY',
                         'OPTIMIZER_MODE')
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 265 for section: prompt Notes:
hc_q_prompt_notes_265() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_265_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font><hr align="left" width="450">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 500 </font> </b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.con_id,
       a.OWNER,
       a.MVIEW_NAME,
       
--a.QUERY,
       a.REWRITE_ENABLED,
       a.REFRESH_MODE,
       a.REFRESH_METHOD,
       a.BUILD_MODE,
       c.comments,
       e.log_table,
       f.last_refresh
  FROM cdb_mviews a
  LEFT OUTER JOIN CDB_refresh b
    on (a.OWNER = b.ROWNER AND a.MVIEW_NAME = b.RNAME and
       a.CON_ID = b.CON_ID)
  LEFT OUTER JOIN CDB_mview_comments c
    on (a.OWNER = c.OWNER AND a.MVIEW_NAME = c.MVIEW_NAME and
       a.CON_ID = c.CON_ID)
  LEFT OUTER JOIN CDB_mview_detail_relations d
    on (a.OWNER = d.OWNER AND a.MVIEW_NAME = d.MVIEW_NAME and
       d.MVIEW_NAME = b.RNAME and a.CON_ID = d.CON_ID)
  LEFT OUTER JOIN CDB_mview_logs e
    on (a.OWNER = d.OWNER AND d.detailobj_name = e.master and
       a.CON_ID = e.CON_ID)
  LEFT OUTER JOIN CDB_mview_refresh_times f
    on (a.OWNER = f.OWNER AND e.master = f.master and a.CON_ID = f.CON_ID)
  WHERE a.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 order by a.con_id, a.owner;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 266 for section: prompt Notes:
hc_q_prompt_notes_266() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_266_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

prompt  <a name="dba_olap_materialized_views"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Materialized Views</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner                FORMAT a75     HEADING 'Owner'               ENTMAP OFF
COLUMN mview_name           FORMAT a75     HEADING 'MView|Name'          ENTMAP OFF
COLUMN master_link          FORMAT a75     HEADING 'Master|Link'         ENTMAP OFF
COLUMN updatable            FORMAT a75     HEADING 'Updatable?'          ENTMAP OFF
COLUMN update_log           FORMAT a75     HEADING 'Update|Log'          ENTMAP OFF
COLUMN rewrite_enabled      FORMAT a75     HEADING 'Rewrite|Enabled?'    ENTMAP OFF
COLUMN refresh_mode         FORMAT a75     HEADING 'Refresh|Mode'        ENTMAP OFF
COLUMN refresh_method       FORMAT a75     HEADING 'Refresh|Method'      ENTMAP OFF
COLUMN build_mode           FORMAT a75     HEADING 'Build|Mode'          ENTMAP OFF
COLUMN fast_refreshable     FORMAT a75     HEADING 'Fast|Refreshable'    ENTMAP OFF
COLUMN last_refresh_type    FORMAT a75     HEADING 'Last Refresh|Type'   ENTMAP OFF
COLUMN last_refresh_date    FORMAT a75     HEADING 'Last Refresh|Date'   ENTMAP OFF
COLUMN staleness            FORMAT a75     HEADING 'Staleness'           ENTMAP OFF
COLUMN compile_state        FORMAT a75     HEADING 'Compile State'       ENTMAP OFF
 

-- BREAK ON owner
 
SELECT m.con_id, '<div align="left"><font color="#336699"><b>' || m.owner ||
       '</b></font></div>' owner,
       m.mview_name mview_name,
       m.master_link master_link,
       '<div align="center">' || NVL(m.updatable, '<br>') || '</div>' updatable,
       update_log update_log,
       '<div align="center">' || NVL(m.rewrite_enabled, '<br>') || '</div>' rewrite_enabled,
       m.refresh_mode refresh_mode,
       m.refresh_method refresh_method,
       m.build_mode build_mode,
       m.fast_refreshable fast_refreshable,
       m.last_refresh_type last_refresh_type,
       '<div nowrap align="right">' ||
       TO_CHAR(m.last_refresh_date, 'mm/dd/yyyy HH24:MI:SS') || '</div>' last_refresh_date,
       m.staleness staleness,
       DECODE(m.compile_state,
              'VALID',
              '<div align="center"><font color="darkgreen"><b>' ||
              m.compile_state || '</b></font></div>',
              '<div align="center"><font color="#990000"><b>' ||
              m.compile_state || '</b></font></div>') compile_state
  FROM cdb_mviews m
WHERE  m.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
 ORDER BY m.con_id, owner, mview_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 267 for section: prompt Notes:
hc_q_prompt_notes_267() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_267_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                        - MATERIALIZED VIEW LOGS -                          |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_olap_materialized_view_logs"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Materialized View Logs</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN log_owner            FORMAT a75     HEADING 'Log Owner'            ENTMAP OFF
COLUMN log_table            FORMAT a75     HEADING 'Log Table'            ENTMAP OFF
COLUMN master               FORMAT a75     HEADING 'Master'               ENTMAP OFF
COLUMN log_trigger          FORMAT a75     HEADING 'Log Trigger'          ENTMAP OFF
COLUMN rowids               FORMAT a75     HEADING 'Rowids?'              ENTMAP OFF
COLUMN primary_key          FORMAT a75     HEADING 'Primary Key?'         ENTMAP OFF
COLUMN object_id            FORMAT a75     HEADING 'Object ID?'           ENTMAP OFF
COLUMN filter_columns       FORMAT a75     HEADING 'Filter Columns?'      ENTMAP OFF
COLUMN sequence             FORMAT a75     HEADING 'Sequence?'            ENTMAP OFF
COLUMN include_new_values   FORMAT a75     HEADING 'Include New Values?'  ENTMAP OFF
 

-- BREAK ON log_owner
 
SELECT ml.con_id,
       '<div align="left"><font color="#336699"><b>' || ml.log_owner ||
       '</b></font></div>' log_owner,
       ml.log_table log_table,
       ml.master master,
       ml.log_trigger log_trigger,
       '<div align="center">' || NVL(ml.rowids, '<br>') || '</div>' rowids,
       '<div align="center">' || NVL(ml.primary_key, '<br>') || '</div>' primary_key,
       '<div align="center">' || NVL(ml.object_id, '<br>') || '</div>' object_id,
       '<div align="center">' || NVL(ml.filter_columns, '<br>') || '</div>' filter_columns,
       '<div align="center">' || NVL(ml.sequence, '<br>') || '</div>' sequence,
       '<div align="center">' || NVL(ml.include_new_values, '<br>') ||
       '</div>' include_new_values
  FROM cdb_mview_logs ml
 ORDER BY ml.con_id, ml.log_owner, ml.master;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 268 for section: prompt Notes:
hc_q_prompt_notes_268() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_268_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                   - MATERIALIZED VIEW REFRESH GROUPS -                     |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_olap_materialized_view_refresh_groups"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Materialized View Refresh Groups</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner         FORMAT a75   HEADING 'Owner'        ENTMAP OFF
COLUMN name          FORMAT a75   HEADING 'Name'         ENTMAP OFF
COLUMN broken        FORMAT a75   HEADING 'Broken?'      ENTMAP OFF
COLUMN next_date   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;next_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN interval      FORMAT a75   HEADING 'Interval'     ENTMAP OFF
SET DEFINE ON


-- BREAK ON report ON owner

SELECT d.con_id,
       '<div nowrap align="left"><font color="#336699"><b>' || rowner ||
       '</b></font></div>' owner,
       '<div align="left">' || rname || '</div>' name,
       '<div align="center">' || broken || '</div>' broken,
       '<div nowrap align="right">' ||
       NVL(TO_CHAR(next_date, 'mm/dd/yyyy HH24:MI:SS'), '<br>') || '</div>' next_date,
       '<div nowrap align="right">' || interval || '</div>' interval
  FROM cdb_refresh d
 ORDER BY d.con_id, rowner, rname;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 269 for section: prompt Notes:
hc_q_prompt_notes_269() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_269_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 

 
 
 

-- +----------------------------------------------------------------------------+

-- |                               - TYPES -                                    |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_types_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Types</b></font><hr align="left" width="600">
  

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM) </font> </b>

 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner              FORMAT a75        HEADING 'Owner'              ENTMAP OFF
COLUMN type_name          FORMAT a75        HEADING 'Type Name'          ENTMAP OFF
COLUMN typecode           FORMAT a75        HEADING 'Type Code'          ENTMAP OFF
COLUMN attributes         FORMAT a75        HEADING 'Num. Attributes'    ENTMAP OFF
COLUMN methods            FORMAT a75        HEADING 'Num. Methods'       ENTMAP OFF
COLUMN predefined         FORMAT a75        HEADING 'Predefined?'        ENTMAP OFF
COLUMN incomplete         FORMAT a75        HEADING 'Incomplete?'        ENTMAP OFF
COLUMN final              FORMAT a75        HEADING 'Final?'             ENTMAP OFF
COLUMN instantiable       FORMAT a75        HEADING 'Instantiable?'      ENTMAP OFF
COLUMN supertype_owner    FORMAT a75        HEADING 'Super Owner'        ENTMAP OFF
COLUMN supertype_name     FORMAT a75        HEADING 'Super Name'         ENTMAP OFF
COLUMN local_attributes   FORMAT a75        HEADING 'Local Attributes'   ENTMAP OFF
COLUMN local_methods      FORMAT a75        HEADING 'Local Methods'      ENTMAP OFF
 

-- BREAK ON report ON owner
 
SELECT t.CON_ID,
       '<div nowrap align="left"><font color="#336699"><b>' || t.owner ||
       '</b></font></div>' owner,
       '<div nowrap>' || t.type_name || '</div>' type_name,
       '<div nowrap>' || t.typecode || '</div>' typecode,
       '<div nowrap align="right">' || TO_CHAR(t.attributes, '999,999') ||
       '</div>' attributes,
       '<div nowrap align="right">' || TO_CHAR(t.methods, '999,999') ||
       '</div>' methods,
       '<div nowrap align="center">' || t.predefined || '</div>' predefined,
       '<div nowrap align="center">' || t.incomplete || '</div>' incomplete,
       '<div nowrap align="center">' || t.final || '</div>' final,
       '<div nowrap align="center">' || t.instantiable || '</div>' instantiable,
       '<div nowrap align="left">' || NVL(t.supertype_owner, '<br>') ||
       '</div>' supertype_owner,
       '<div nowrap align="left">' || NVL(t.supertype_name, '<br>') ||
       '</div>' supertype_name,
       '<div nowrap align="right">' ||
       NVL(TO_CHAR(t.local_attributes, '999,999'), '<br>') || '</div>' local_attributes,
       '<div nowrap align="right">' ||
       NVL(TO_CHAR(t.local_methods, '999,999'), '<br>') || '</div>' local_methods
  FROM cdb_types t
WHERE t.owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
 
-- ORDER BY t.CON_ID, t.owner, t.TYPE_NAME
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 270 for section: prompt Notes:
hc_q_prompt_notes_270() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_270_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 

 
 

-- +----------------------------------------------------------------------------+

-- |                             - TYPE METHODS -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_type_methods"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Type Methods</b></font><hr align="left" width="450">
 

prompt  <b>Excluding all internal system schemas (i.e. CTXSYS, MDSYS, SYS, SYSTEM)</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner              FORMAT a75        HEADING 'Owner'              ENTMAP OFF
COLUMN type_name          FORMAT a75        HEADING 'Type Name'          ENTMAP OFF
COLUMN typecode           FORMAT a75        HEADING 'Type Code'          ENTMAP OFF
COLUMN method_name        FORMAT a75        HEADING 'Method Name'        ENTMAP OFF
COLUMN method_type        FORMAT a75        HEADING 'Method Type'        ENTMAP OFF
COLUMN num_parameters     FORMAT a75        HEADING 'Num. Parameters'    ENTMAP OFF
COLUMN results            FORMAT a75        HEADING 'Results'            ENTMAP OFF
COLUMN final              FORMAT a75        HEADING 'Final?'             ENTMAP OFF
COLUMN instantiable       FORMAT a75        HEADING 'Instantiable?'      ENTMAP OFF
COLUMN overriding         FORMAT a75        HEADING 'Overriding?'        ENTMAP OFF
COLUMN inherited          FORMAT a75        HEADING 'Inherited?'         ENTMAP OFF
 

-- BREAK ON report ON owner ON type_name ON typecode
 
SELECT t.con_id,'<div nowrap align="left"><font color="#336699"><b>' || t.owner ||
       '</b></font></div>' owner,
       '<div nowrap>' || t.type_name || '</div>' type_name,
       '<div nowrap>' || t.typecode || '</div>' typecode,
       '<div nowrap>' || m.method_name || '</div>' method_name,
       '<div nowrap>' || m.method_type || '</div>' method_type,
       '<div nowrap align="right">' || TO_CHAR(m.parameters, '999,999') ||
       '</div>' num_parameters,
       '<div nowrap align="right">' || TO_CHAR(m.results, '999,999') ||
       '</div>' results,
       '<div nowrap align="center">' || m.final || '</div>' final,
       '<div nowrap align="center">' || m.instantiable || '</div>' instantiable,
       '<div nowrap align="center">' || m.overriding || '</div>' overriding,
       DECODE(m.inherited,
              'YES',
              '<div align="center"><font color="darkgreen"><b>' ||
              m.inherited || '</b></font></div>',
              'NO',
              '<div align="center"><font color="#990000"><b>' || m.inherited ||
              '</b></font></div>',
              '<div align="center"><font color="#663300"><b>' || m.inherited ||
              '</b></font></div>') inherited
  FROM cdb_types t, cdb_type_methods m
 WHERE t.owner = m.owner
   AND t.type_name = m.type_name
   and t.con_id = m.con_id
   AND  t.owner  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 
--ORDER BY t.con_id, t.owner, t.type_name, t.typecode, m.method_no
 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 271 for section: prompt Notes:
hc_q_prompt_notes_271() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_271_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 
 
 
 

-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<     DATA PUMP     >>>>>                         |

-- |                                                                            |

-- +============================================================================+
 
 

prompt  <a name="data_pump_jobs_info"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u>Data Pump()</u></b></font></center>
 
 

-- +----------------------------------------------------------------------------+

-- |                           - DATA PUMP JOBS -                               |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="data_pump_jobs"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Data Pump Jobs</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner_name         FORMAT a75            HEADING 'Owner Name'         ENTMAP OFF
COLUMN job_name           FORMAT a75            HEADING 'Job Name'           ENTMAP OFF
COLUMN operation          FORMAT a75            HEADING 'Operation'          ENTMAP OFF
COLUMN job_mode           FORMAT a75            HEADING 'Job Mode'           ENTMAP OFF
COLUMN state              FORMAT a75            HEADING 'State'              ENTMAP OFF
COLUMN degree             FORMAT 999,999,999    HEADING 'Degree'             ENTMAP OFF
COLUMN attached_sessions  FORMAT 999,999,999    HEADING 'Attached Sessions'  ENTMAP OFF

col owner_name for a10
col job_name for a25 
col operation for a10
col job_mode for a10 
col state for a15 
col job_mode for a10  
col state for a15 
col osuser for a10
col "degree|attached|datapump" for a25
col session_info for a20  
SELECT dj.CON_ID,
       s.inst_id,
       dj.owner_name,
       dj.job_name,
       dj.operation,
       dj.job_mode,
       dj.state,
       dj.degree || ',' || dj.attached_sessions || ',' ||
       dj.datapump_sessions "degree|attached|datapump",
       ds.session_type,
       s.osuser,
       (SELECT s.SID || ',' || s.SERIAL# || ',' || p.SPID
          FROM gv$process p
         WHERE s.paddr = p.addr
           AND  s.inst_id = p.inst_id
					 and p.con_id=dj.con_id) session_info
  FROM CDB_DATAPUMP_JOBS dj 
--gv$datapump_job  
  full outer join CDB_datapump_sessions ds 
--gv$datapump_session
    on (dj.job_name = ds.job_name AND  dj.owner_name = ds.owner_name AND DJ.CON_ID=DS.CON_ID)
  LEFT OUTER JOIN gv$session s
    on (s.saddr = ds.saddr AND DJ.CON_ID=S.CON_ID)
 ORDER BY dj.owner_name, dj.job_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 272 for section: prompt Notes:
hc_q_prompt_notes_272() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_272_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                          - DATA PUMP SESSIONS -                            |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="data_pump_sessions"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Data Pump Sessions</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print  FORMAT a75            HEADING 'Instance_Name'    ENTMAP OFF
COLUMN owner_name           FORMAT a75            HEADING 'Owner Name'       ENTMAP OFF
COLUMN job_name             FORMAT a75            HEADING 'Job Name'         ENTMAP OFF
COLUMN session_type         FORMAT a75            HEADING 'Session Type'     ENTMAP OFF
COLUMN sid                                        HEADING 'SID'              ENTMAP OFF
COLUMN serial_no                                  HEADING 'Serial#'          ENTMAP OFF
COLUMN oracle_username      FORMAT a75            HEADING 'Oracle Username'  ENTMAP OFF
COLUMN os_username          FORMAT a75            HEADING 'O/S Username'     ENTMAP OFF
COLUMN os_pid                                     HEADING 'O/S PID'          ENTMAP OFF
 

-- BREAK ON report ON instance_name_print ON owner_name ON job_name
 
SELECT '<div align="center"><font color="#336699"><b>' || i.instance_name ||
       '</b></font></div>' instance_name_print,
       dj.owner_name owner_name,
       dj.job_name job_name,
       ds.type session_type,
       s.sid sid,
       s.serial# serial_no,
       s.username oracle_username,
       s.osuser os_username,
       p.spid os_pid
  FROM gv$datapump_job     dj,
       gv$datapump_session ds,
       gv$session          s,
       gv$instance         i,
       gv$process          p
 WHERE s.inst_id = i.inst_id
   AND s.inst_id = p.inst_id
   AND ds.inst_id = i.inst_id
   AND dj.inst_id = i.inst_id
   AND s.saddr = ds.saddr
   AND s.paddr = p.addr(+)
   AND dj.job_id = ds.job_id
 ORDER BY i.instance_name, dj.owner_name, dj.job_name, ds.type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 273 for section: prompt Notes:
hc_q_prompt_notes_273() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_273_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                        - DATA PUMP JOB PROGRESS -                          |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="data_pump_job_progress"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Data Pump Job Progress</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print  FORMAT a75                 HEADING 'Instance_Name'           ENTMAP OFF
COLUMN owner_name           FORMAT a75                 HEADING 'Owner Name'              ENTMAP OFF
COLUMN job_name             FORMAT a75                 HEADING 'Job Name'                ENTMAP OFF
COLUMN session_type         FORMAT a75                 HEADING 'Session Type'            ENTMAP OFF
COLUMN START_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;START_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN time_remaining       FORMAT 9,999,999,999,999   HEADING 'Time Remaining (min.)'   ENTMAP OFF
COLUMN sofar                FORMAT 9,999,999,999,999   HEADING 'Bytes Completed So Far'  ENTMAP OFF
COLUMN totalwork            FORMAT 9,999,999,999,999   HEADING 'Total Bytes for Job'     ENTMAP OFF
COLUMN pct_completed                                   HEADING '% Completed'             ENTMAP OFF
SET DEFINE ON


-- BREAK ON report ON instance_name_print ON owner_name ON job_name
 
SELECT
    '<div align="center"><font color="#336699"><b>' || i.instance_name  || '</b></font></div>'   instance_name_print
  , dj.owner_name                                                                                owner_name
  , dj.job_name                                                                                  job_name
  , ds.type                                                                                      session_type
  , '<div align="center" nowrap>' || TO_CHAR(sl.START_TIME,'mm/dd/yyyy HH24:MI:SS') || '</div>'  START_TIME
  , ROUND(sl.time_remaining/60,0)                                                                time_remaining
  , sl.sofar                                                                                     sofar
  , sl.totalwork                                                                                 totalwork
  , '<div align="right">' || TRUNC(ROUND((sl.sofar/sl.totalwork) * 100, 1)) || '%</div>'         pct_completed
FROM
    gv$datapump_job         dj
  , gv$datapump_session     ds
  , gv$session              s
  , gv$instance             i
  , gv$session_longops      sl
WHERE s.inst_id  = i.inst_id
  AND  ds.inst_id = i.inst_id
  AND  dj.inst_id = i.inst_id
  AND  sl.inst_id = i.inst_id
  AND  s.saddr    = ds.saddr
  AND  dj.job_id  = ds.job_id
  AND  sl.sid     = s.sid
  AND  sl.serial# = s.serial#
  AND  ds.type    = 'MASTER'
ORDER BY
    i.instance_name
  , dj.owner_name
  , dj.job_name
  , ds.type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 274 for section: prompt Notes:
hc_q_prompt_notes_274() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_274_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


-- +----------------------------------------------------------------------------+

-- |                             -  -                                 |

-- +----------------------------------------------------------------------------+


-- +============================================================================+

-- |                                                                            |

-- |        <<<<<     AUTOMATIC WORKLOAD REPOSITORY - (AWR)     >>>>>           |

-- |                                                                            |

-- +============================================================================+


-- +====================================================================================================================+

-- |

-- | <<<<<         >>>>>                                              |

-- |                                                                                                                    |

-- +====================================================================================================================+

 
host echo start.... . 


prompt  <a name="database_performacefenxi"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u></u></b></font></center>

prompt  <p>

host echo "            AWR. . ." 


prompt  <a name="database_AWRINFO"></a>

prompt  <font size="+2" color="00CCFF"><b>AWR</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="awr_performance_analyze"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWR</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_number     FORMAT a100                    HEADING '|'      ENTMAP OFF
COLUMN snap_time        	 FORMAT a22                    HEADING ''        ENTMAP OFF
COLUMN mem_read            FORMAT 999,999,999,999,999    HEADING '(MB)'     ENTMAP OFF
COLUMN disk_read           FORMAT 999,999,999,999,999    HEADING '(MB)'         ENTMAP OFF
COLUMN disk_write          FORMAT 999,999,999,999,999    HEADING '(KB)'         ENTMAP OFF
COLUMN log_account          FORMAT 999,999,999,999,999    HEADING '(KB)'         ENTMAP OFF
COLUMN hard_parse          FORMAT 999,999,999,999,999    HEADING '()'         ENTMAP OFF
COLUMN total_parse         FORMAT 999,999,999,999,999    HEADING '()'     ENTMAP OFF
COLUMN trans               FORMAT 999,999,999,999,999    HEADING ''        ENTMAP OFF
COLUMN cpu_time            FORMAT 999,999,999,999,999    HEADING 'CPU()'         ENTMAP OFF


-- BREAK ON report ON instance_number

       snap_time,
       instance_number,
       stat_name AS name,
       value
  FROM (SELECT cast(c.end_interval_time AS date) snap_time,
               a.instance_number,
               b.stat_name,
               a.value
          FROM sys.wrh$_sysstat a, sys.wrh$_stat_name b, sys.WRM$_SNAPSHOT C
         WHERE a.dbid = b.dbid
           AND  a.stat_id = b.stat_id
           AND  a.dbid = c.dbid
           AND  a.instance_number = c.instance_number
           AND  b.stat_name in
               ('session logical reads', 'physical reads', 'execute count',
                'redo size', 'parse count (hard)', 'parse count (total)',
                'physical writes', 'user commits', 'user rollbacks',
                'CPU used by this session')
                AND  c.end_interval_time>sysdate -7)
)
SELECT  '<div nowrap align="left"><font color="#336699"><b>' || instance_number || '</b></font></div>'   instance_number,
       TO_CHAR(snap_time,'yyyy-mm-dd hh24:mi:ss') snap_time,
       round(sum(DECODE(name, 'session logical reads', value, 0)) * 8 / 1024) mem_read ,
       round(sum(DECODE(name, 'physical reads', value, 0)) * 8 / 1024) disk_read ,
       round(sum(DECODE(name, 'physical writes', value, 0)) * 8) disk_write ,
       round(sum(DECODE(name, 'redo size', value, 0)) / 1024) log_account ,
       round(sum(DECODE(name, 'parse count (hard)', value, 0))) hard_parse ,
       round(sum(DECODE(name, 'parse count (total)', value, 0))) total_parse ,
       round(sum(DECODE(name,
                        'user commits',
                        value,
                        'user rollbacks',
                        value,
                        0)))  trans,
       round(sum(DECODE(name,
                        'CPU used by this session',
                        value * bet_time / 100,
                        0))) cpu_time
               b.snap_time,
               b.instance_number,
               b.name,
               round(b.value - a.value) /
               ((b.snap_time - a.snap_time) * 24 * 60 * 60) value,
               (b.snap_time - a.snap_time) * 24 * 60 * 60 bet_time
          FROM (SELECT row_no + 1 rowno,
                       instance_number,
                       snap_time,
                       name,
                       value
                  FROM pv) a,
               (SELECT row_no rowno,
                       instance_number,
                       snap_time,
                       name,
                       value
                  FROM pv) b
         WHERE a.rowno = b.rowno
           AND  a.name = b.name
           AND  a.instance_number = b.instance_number
 )
 GROUP BY instance_number, TO_CHAR(snap_time,'yyyy-mm-dd hh24:mi:ss') 
 ORDER BY instance_number, snap_time desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 275 for section: prompt Notes:
hc_q_prompt_notes_275() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_275_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWR</b></font><hr align="left" width="600">


prompt  <font face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● </b></font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> Use the DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS procedure to modify the interval </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> of the snapshot generation AND  how long the snapshots are retained in the Workload Repository. The </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> default interval is 60 minutes AND  can be set to a value between 10 minutes AND  5,256,000 (1 year). </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> The default retention period is 10,080 minutes (7 days) AND  can be set to a value between </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> 1,440 minutes (1 day) AND  52,560,000 minutes (100 years). </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> AWR3: </font>

prompt  <font face="Courier New,Helvetica,Geneva,sans-serif"> ① STATISTICS_LEVELTYPICAL ALL </font>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN dbbid           FORMAT a75    HEAD 'Database ID'          ENTMAP OFF
COLUMN dbb_name        FORMAT a75    HEAD 'Database Name'        ENTMAP OFF
COLUMN snap_interval   FORMAT a75    HEAD 'Snap Interval'        ENTMAP OFF
COLUMN retention       FORMAT a75    HEAD 'Retention Period'     ENTMAP OFF
COLUMN topnsql         FORMAT a75    HEAD 'Top N SQL'            ENTMAP OFF

SELECT '<div align="left"><font color="#336699"><b>' || s.dbid ||
       '</b></font></div>' dbbid,
       d.name dbb_name,
       s.snap_interval snap_interval,
       s.retention retention,
       s.topnsql
  FROM cdb_hist_wr_control s, v$database d
 WHERE s.dbid = d.dbid
 ORDER BY dbbid;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 276 for section: prompt Notes:
hc_q_prompt_notes_276() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_276_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt 

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● (7days of snapshots, showing top50)</b></font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN instance_name_print  FORMAT a75               HEADING 'Instance_Name'          ENTMAP OFF
COLUMN end_interval_time   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;End_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN begin_interval_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Begin_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN startup_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;startup_time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN elapsed_time         FORMAT 999,999,999.99    HEADING 'Elapsed_Time_(min) '     ENTMAP OFF
COLUMN db_time              FORMAT 999,999,999.99    HEADING 'DB_Time (min) '          ENTMAP OFF
COLUMN pct_db_time          FORMAT a75               HEADING '&nbsp;&nbsp;% DB_Time&nbsp;&nbsp;'              ENTMAP OFF
COLUMN cpu_time             FORMAT 999,999,999.99    HEADING '&nbsp;&nbsp;CPU Time (min)&nbsp;&nbsp;'         ENTMAP OFF
COLUMN RETENTION          FORMAT a100               HEADING '&nbsp;&nbsp;&nbsp;&nbsp;RETENTION&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN awr_report          FORMAT a500               HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;awr_report&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
SET DEFINE ON 
 

-- BREAK ON instance_name_print ON startup_time

SELECT con_id,
       '<div align="center"><font color="#336699"><b>' || instance_name ||
       '</b></font></div>' instance_name_print,
       '<div nowrap align="right">' || startup_time || '</div>' startup_time,
       '<div nowrap align="right">' || begin_interval_time || '</div>' begin_interval_time,
       '<div nowrap align="right">' || end_interval_time || '</div>' end_interval_time,
       elapsed_time,
       db_time,
       '<div align="right">' || pct_db_time || ' %</div>' pct_db_time,
       snap_interval,
       retention,
       topnsql,
       flush_elapsed,
       snap_level,
       error_count,
       awr_report
  FROM (SELECT s.con_id,
               i.instance_name,
               TO_CHAR(s.startup_time, 'YYYY-MM-DD HH24:MI:SS') startup_time,
               TO_CHAR(s.begin_interval_time, 'YYYY-MM-DD HH24:MI:SS') begin_interval_time,
               TO_CHAR(s.end_interval_time, 'YYYY-MM-DD HH24:MI:SS') end_interval_time,
               ROUND(EXTRACT(DAY FROM
                             s.end_interval_time - s.begin_interval_time) * 1440 +
                     EXTRACT(HOUR FROM
                             s.end_interval_time - s.begin_interval_time) * 60 +
                     EXTRACT(MINUTE FROM
                             s.end_interval_time - s.begin_interval_time) +
                     EXTRACT(SECOND FROM
                             s.end_interval_time - s.begin_interval_time) / 60,
                     2) elapsed_time,
               ROUND((e.value - b.value) / 1000000 / 60, 2) db_time,
               ROUND(((((e.value - b.value) / 1000000 / 60) /
                     (EXTRACT(DAY FROM
                                s.end_interval_time - s.begin_interval_time) * 1440 +
                     EXTRACT(HOUR FROM
                                s.end_interval_time - s.begin_interval_time) * 60 +
                     EXTRACT(MINUTE FROM
                                s.end_interval_time - s.begin_interval_time) +
                     EXTRACT(SECOND FROM
                                s.end_interval_time - s.begin_interval_time) / 60)) * 100),
                     2) pct_db_time,
               (SELECT (nb.snap_interval) FROM CDB_hist_wr_control nb where nb.CON_ID=s.con_id) snap_interval,
               (SELECT (nb.retention) FROM CDB_hist_wr_control nb where nb.CON_ID=s.con_id) retention,
               (SELECT nb.topnsql FROM CDB_hist_wr_control nb where nb.CON_ID=s.con_id) topnsql,
               
--TO_CHAR(s.startup_time, 'YYYY-MM-DD HH24:MI:SS.ff') startup_time,
               
--  TO_CHAR(s.begin_interval_time, 'YYYY-MM-DD HH24:MI:SS.ff') begin_interval_time,
               
--  TO_CHAR(s.end_interval_time, 'YYYY-MM-DD HH24:MI:SS.ff') end_interval_time,
               s.flush_elapsed flush_elapsed,
               s.snap_level,
               s.error_count,
               
--d.snap_flag, 
               'SELECT * FROM table(dbms_workload_repository.awr_report_html(' ||
               (DENSE_RANK() OVER(partition by s.instance_number order by
                                  s.instance_number,
          FROM CDB_hist_snapshot s
          LEFT OUTER JOIN gv$instance i
            on (i.instance_number = s.instance_number)
          LEFT OUTER JOIN CDB_hist_sys_time_model e
               e.instance_number = s.instance_number and
               s.CON_ID = e.CON_ID AND e.stat_name = 'DB time')
          LEFT OUTER JOIN CDB_hist_sys_time_model b
               e.instance_number = b.instance_number and
               s.con_id = b.con_id)
         WHERE s.end_interval_time > sysdate - 7) nv
 WHERE rk <= 50


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">


prompt  <center>[<a class="noLink" href="#awr_host_info"><font size=+1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="awr_loadprofile"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWRin the viewload profile</b></font><hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 7AWRin the viewload profile </font> </b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN snap_date   FORMAT a100    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;snap_date&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN cpu_time            FORMAT 999,999,999.99    HEADING 'CPU Time (min)'         ENTMAP OFF
COLUMN snap_time_range     FORMAT a340  HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SNAP_TIME_RANGE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'         ENTMAP OFF
COLUMN end_interval_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;End_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN startup_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;startup_time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

		

with tmp_s as
 (SELECT curr_redo - last_redo redosize,
         curr_logicalreads - last_logicalreads logicalreads,
         curr_physicalreads - last_physicalreads physicalreads,
         curr_executes - last_executes executes,
         curr_parse - last_parse parse,
         curr_hardparse - last_hardparse hardparse,
         DECODE((curr_transactions - last_transactions),
                0,
                NULL,
                (curr_transactions - last_transactions)) transactions,
         round(((currtime + 0) - (lasttime + 0)) * 3600 * 24, 0) seconds,
         TO_CHAR(currtime, 'yyyy-mm-dd') snap_date,
         TO_CHAR(currtime, 'hh24:mi') currtime,
         TO_CHAR(lasttime, 'YYYY-MM-DD HH24:MI') || '~' ||
         TO_CHAR(currtime, 'YYYY-MM-DD HH24:MI') snap_time_range,
         TO_CHAR(startup_time, 'yyyy-mm-dd hh24:mi:ss') startup_time,
         sessions || '~' || currsessions sessions,
         Cursors1 || '~' || currCursors Cursors2,
         instance_number
    FROM (SELECT a.redo last_redo,
                 a.logicalreads last_logicalreads,
                 a.physicalreads last_physicalreads,
                 a.executes last_executes,
                 a.parse last_parse,
                 a.hardparse last_hardparse,
                 a.transactions last_transactions,
                 a.sessions,
                 trunc(a.Cursors / a.sessions, 2) Cursors1,
                 lead(a.redo, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_redo,
                 lead(a.logicalreads, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_logicalreads,
                 lead(a.physicalreads, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_physicalreads,
                 lead(a.executes, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_executes,
                 lead(a.parse, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_parse,
                 lead(a.hardparse, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_hardparse,
                 lead(a.transactions, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) curr_transactions,
                 b.end_interval_time lasttime,
                 lead(b.end_interval_time, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) currtime,
                 lead(a.sessions, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) currsessions,
                 lead(trunc(a.Cursors / a.sessions, 2), 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) currCursors,
                 b.startup_time,
                 b.instance_number
                         dbid,
                         instance_number,
                         SUM(DECODE(stat_name, 'redo size', VALUE, 0)) redo,
                         SUM(DECODE(stat_name,
                                    'session logical reads',
                                    VALUE,
                                    0)) logicalreads,
                         SUM(DECODE(stat_name, 'physical reads', VALUE, 0)) physicalreads,
                         SUM(DECODE(stat_name, 'execute count', VALUE, 0)) executes,
                         SUM(DECODE(stat_name, 'parse count (total)', VALUE, 0)) parse,
                         SUM(DECODE(stat_name, 'parse count (hard)', VALUE, 0)) hardparse,
                         SUM(DECODE(stat_name,
                                    'user rollbacks',
                                    VALUE,
                                    'user commits',
                                    VALUE,
                                    0)) transactions,
                         SUM(DECODE(stat_name, 'logons current', VALUE, 0)) sessions,
                         SUM(DECODE(stat_name,
                                    'opened cursors current',
                                    VALUE,
                                    0)) Cursors
                   WHERE stat_name IN ('redo size',
                                       'session logical reads',
                                       'physical reads',
                                       'execute count',
                                       'user rollbacks',
                                       'user commits',
                                       'parse count (hard)',
                                       'parse count (total)',
                                       'logons current',
                                       'opened cursors current')
             AND  a.dbid = b.dbid
             AND  a.instance_number = b.instance_number
             AND  b.end_interval_time > SYSDATE - 7
           ORDER BY end_interval_time)),
tmp_t as
 (SELECT lead(a.value, 1, NULL) over(PARTITION BY b.instance_number, b.startup_time ORDER BY b.end_interval_time) - a.value db_time,
         b.instance_number
     AND  a.dbid = b.dbid
     AND  a.instance_number = b.instance_number
     AND  a.stat_name = 'DB time'),
tmp_ash as
    FROM (SELECT n.instance_number inst_id,
                 n.session_id,
                 n.session_serial#
           GROUP BY n.instance_number,
                    n.session_id,
                    n.session_serial#) nt
SELECT s.snap_date,
       s.instance_number inst_id,
       snap_time_range,
       DECODE(s.redosize, NULL, '
--shutdown or end--', s.currtime) "TIME",
       startup_time,
       TO_CHAR(round(s.seconds / 60, 2)) "Elapsed(min)",
       round(t.db_time / 1000000 / 60, 2) "DB_time(min)",
       s.sessions,
       (SELECT counts
          FROM tmp_ash nnt
         WHERE s.instance_number = nnt.inst_id
       (SELECT counts
          FROM tmp_ash nnt
         WHERE s.instance_number = nnt.inst_id
       s.Cursors2 "Cursors/Session",
       s.redosize redo,
       round(s.redosize / s.seconds, 2) "redo/s",
       round(s.redosize / s.transactions, 2) "redo/t",
       s.logicalreads logical,
       round(s.logicalreads / s.seconds, 2) "logical/s",
       round(s.logicalreads / s.transactions, 2) "logical/t",
       physicalreads physical,
       round(s.physicalreads / s.seconds, 2) "phy/s",
       round(s.physicalreads / s.transactions, 2) "phy/t",
       s.executes execs,
       round(s.executes / s.seconds, 2) "execs/s",
       round(s.executes / s.transactions, 2) "execs/t",
       s.parse,
       round(s.parse / s.seconds, 2) "parse/s",
       round(s.parse / s.transactions, 2) "parse/t",
       s.hardparse,
       round(s.hardparse / s.seconds, 2) "hardparse/s",
       round(s.hardparse / s.transactions, 2) "hardparse/t",
       s.transactions trans,
       round(s.transactions / s.seconds, 2) "trans/s"
  FROM tmp_s s, tmp_t t
   AND  t.instance_number = s.instance_number


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="awr_new_lastone"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWR</b></font><hr align="left" width="600">

SET DEFINE ON

prompt  

prompt  <center>[<a class="noLink" href="#awr_new_lastone_link"><font size=+1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:AWR</b></font></a>]</center><p>


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

-- +----------------------------------------------------------------------------+

-- |                      - AWR SNAPSHOT SIZE ESTIMATES -                       |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="awr_snapshot_size_estimates"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWR Snapshot Size Estimates</b></font><hr align="left" width="300">

SET DEFINE ON

DECLARE
 
    CURSOR get_instances IS
        SELECT COUNT(DISTINCT instance_number)
        FROM sys.wrm$_database_instance;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 277 for section: prompt Notes:
hc_q_prompt_notes_277() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_277_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CURSOR get_wr_control_info IS
        SELECT snapint_num, retention_num
        FROM sys.wrm$_wr_control;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 278 for section: prompt Notes:
hc_q_prompt_notes_278() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_278_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CURSOR get_snaps IS
        SELECT
            SUM(all_snaps)
          , SUM(good_snaps)
          , SUM(today_snaps)
          , SYSDATE - MIN(begin_interval_time)
        FROM
            (SELECT
                  1 AS all_snaps
                , (CASE WHEN s.status = 0 THEN 1 ELSE 0 END) AS good_snaps
                , (CASE WHEN (s.end_interval_time > SYSDATE - 1) THEN 1 ELSE 0 END) AS today_snaps
                , CAST(s.begin_interval_time AS DATE) AS begin_interval_time
             FROM sys.wrm$_snapshot s
             );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 279 for section: prompt Notes:
hc_q_prompt_notes_279() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_279_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CURSOR sysaux_occ_usage IS
        SELECT
            occupant_name
          , schema_name
          , space_usage_kbytes/1024 space_usage_mb
        FROM
            v$sysaux_occupants
        ORDER BY
            space_usage_kbytes DESC
          , occupant_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 280 for section: prompt Notes:
hc_q_prompt_notes_280() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_280_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
mb_format           CONSTANT  VARCHAR2(30)  := '99,999,990.0';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 281 for section: prompt Notes:
hc_q_prompt_notes_281() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_281_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
kb_format           CONSTANT  VARCHAR2(30)  := '999,999,990';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 282 for section: prompt Notes:
hc_q_prompt_notes_282() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_282_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
pct_format          CONSTANT  VARCHAR2(30)  := '990.0';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 283 for section: prompt Notes:
hc_q_prompt_notes_283() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_283_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
snapshot_interval   NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 284 for section: prompt Notes:
hc_q_prompt_notes_284() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_284_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
retention_interval  NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 285 for section: prompt Notes:
hc_q_prompt_notes_285() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_285_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
all_snaps           NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 286 for section: prompt Notes:
hc_q_prompt_notes_286() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_286_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
awr_size            NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 287 for section: prompt Notes:
hc_q_prompt_notes_287() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_287_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
snap_size           NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 288 for section: prompt Notes:
hc_q_prompt_notes_288() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_288_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
awr_average_size    NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 289 for section: prompt Notes:
hc_q_prompt_notes_289() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_289_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
est_today_snaps     NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 290 for section: prompt Notes:
hc_q_prompt_notes_290() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_290_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
awr_size_past24     NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 291 for section: prompt Notes:
hc_q_prompt_notes_291() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_291_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
good_snaps          NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 292 for section: prompt Notes:
hc_q_prompt_notes_292() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_292_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
today_snaps         NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 293 for section: prompt Notes:
hc_q_prompt_notes_293() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_293_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
num_days            NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 294 for section: prompt Notes:
hc_q_prompt_notes_294() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_294_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
num_instances       NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 295 for section: prompt Notes:
hc_q_prompt_notes_295() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_295_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
BEGIN
 
    OPEN get_instances;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 296 for section: prompt Notes:
hc_q_prompt_notes_296() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_296_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
FETCH get_instances INTO num_instances;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 297 for section: prompt Notes:
hc_q_prompt_notes_297() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_297_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLOSE get_instances;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 298 for section: prompt Notes:
hc_q_prompt_notes_298() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_298_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
OPEN get_wr_control_info;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 299 for section: prompt Notes:
hc_q_prompt_notes_299() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_299_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
FETCH get_wr_control_info INTO snapshot_interval, retention_interval;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 300 for section: prompt Notes:
hc_q_prompt_notes_300() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_300_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLOSE get_wr_control_info;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 301 for section: prompt Notes:
hc_q_prompt_notes_301() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_301_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
OPEN get_snaps;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 302 for section: prompt Notes:
hc_q_prompt_notes_302() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_302_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
FETCH get_snaps INTO all_snaps, good_snaps, today_snaps, num_days;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 303 for section: prompt Notes:
hc_q_prompt_notes_303() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_303_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLOSE get_snaps;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 304 for section: prompt Notes:
hc_q_prompt_notes_304() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_304_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
FOR occ_rec IN sysaux_occ_usage
    LOOP
        IF (occ_rec.occupant_name = 'SM/AWR') THEN
            awr_size := occ_rec.space_usage_mb;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 305 for section: prompt Notes:
hc_q_prompt_notes_305() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_305_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END IF;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 306 for section: prompt Notes:
hc_q_prompt_notes_306() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_306_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END LOOP;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 307 for section: prompt Notes:
hc_q_prompt_notes_307() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_307_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
snap_size := awr_size/all_snaps;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 308 for section: prompt Notes:
hc_q_prompt_notes_308() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_308_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
awr_average_size := snap_size*86400/snapshot_interval;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 309 for section: prompt Notes:
hc_q_prompt_notes_309() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_309_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
today_snaps := today_snaps / num_instances;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 310 for section: prompt Notes:
hc_q_prompt_notes_310() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_310_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
IF (num_days < 1) THEN
        est_today_snaps := ROUND(today_snaps / num_days);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 311 for section: prompt Notes:
hc_q_prompt_notes_311() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_311_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
ELSE
        est_today_snaps := today_snaps;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 312 for section: prompt Notes:
hc_q_prompt_notes_312() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_312_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END IF;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 313 for section: prompt Notes:
hc_q_prompt_notes_313() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_313_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
awr_size_past24 := snap_size * est_today_snaps;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 314 for section: prompt Notes:
hc_q_prompt_notes_314() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_314_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<table width="60%" border="1" bordercolor="#000000" cellspacing="0px" style="border-collapse:collapse">');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 315 for section: prompt Notes:
hc_q_prompt_notes_315() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_315_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="center" colspan="3">Estimates based on ' || ROUND(snapshot_interval/60) || ' minute snapshot intervals</th></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 316 for section: prompt Notes:
hc_q_prompt_notes_316() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_316_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/day</td><td align="right">'
                            || TO_CHAR(awr_average_size, mb_format)
                            || ' MB</td><td align="right">(' || TRIM(TO_CHAR(snap_size*1024, kb_format)) || ' K/snap * '
                            || ROUND(86400/snapshot_interval) || ' snaps/day)</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 317 for section: prompt Notes:
hc_q_prompt_notes_317() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_317_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/wk</td><td align="right">'
                            || TO_CHAR(awr_average_size * 7, mb_format)
                            || ' MB</td><td align="right">(size_per_day * 7) per instance</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 318 for section: prompt Notes:
hc_q_prompt_notes_318() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_318_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
IF (num_instances > 1) THEN
        DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/wk</td><td align="right">'
                            || TO_CHAR(awr_average_size * 7 * num_instances, mb_format)
                            || ' MB</td><td align="right">(size_per_day * 7) per database</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 319 for section: prompt Notes:
hc_q_prompt_notes_319() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_319_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END IF;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 320 for section: prompt Notes:
hc_q_prompt_notes_320() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_320_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><th align="center" colspan="3">Estimates based on ' || ROUND(today_snaps) || ' snaps in past 24 hours</th></tr>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 321 for section: prompt Notes:
hc_q_prompt_notes_321() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_321_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/day</td><td align="right">'
                            || TO_CHAR(awr_size_past24, mb_format)
                            || ' MB</td><td align="right">('
                            || TRIM(TO_CHAR(snap_size*1024, kb_format)) || ' K/snap AND  '
                            || ROUND(today_snaps) || ' snaps in past '
                            || ROUND(least(num_days*24,24),1) || ' hours)</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 322 for section: prompt Notes:
hc_q_prompt_notes_322() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_322_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/wk</td><td align="right">'
                            || TO_CHAR(awr_size_past24 * 7, mb_format)
                            || ' MB</td><td align="right">(size_per_day * 7) per instance</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 323 for section: prompt Notes:
hc_q_prompt_notes_323() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_323_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
IF (num_instances > 1) THEN
        DBMS_OUTPUT.PUT_LINE('<tr><td>AWR size/wk</td><td align="right">'
                            || TO_CHAR(awr_size_past24 * 7 * num_instances, mb_format)
                            || ' MB</td><td align="right">(size_per_day * 7) per database</td></tr>' );
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 324 for section: prompt Notes:
hc_q_prompt_notes_324() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_324_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END IF;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 325 for section: prompt Notes:
hc_q_prompt_notes_325() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_325_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DBMS_OUTPUT.PUT_LINE('</table>');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 326 for section: prompt Notes:
hc_q_prompt_notes_326() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_326_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 327 for section: prompt Notes:
hc_q_prompt_notes_327() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_327_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
/
 

prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                              - AWR BASELINES -                             |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="awr_baselines"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>AWR Baselines</b></font><hr align="left" width="450">
 

prompt  Use the <b>DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE</b> procedure to create a named baseline.

prompt  A baseline (also known AS a preserved snapshot set) is a pair of AWR snapshots that represents a

prompt  specific period of database usage. The Oracle database server will exempt the AWR snapshots

prompt  assigned to a specific baseline FROM the automated purge routine. The main purpose of a baseline

prompt  is to preserve typical run-time statistics in the AWR repository which can then be compared to

prompt  current performance or similar periods in the past.
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN dbbid            FORMAT a75    HEAD 'Database ID'              ENTMAP OFF
COLUMN dbb_name         FORMAT a75    HEAD 'Database Name'            ENTMAP OFF
COLUMN baseline_id                    HEAD 'Baseline ID'              ENTMAP OFF
COLUMN baseline_name    FORMAT a75    HEAD 'Baseline Name'            ENTMAP OFF
COLUMN start_snap_time  FORMAT a75    HEAD 'Beginning Snapshot Time'  ENTMAP OFF
COLUMN end_snap_time    FORMAT a75    HEAD 'Ending Snapshot Time'     ENTMAP OFF

SET DEFINE ON

SELECT '<div align="left"><font color="#336699"><b>' || b.dbid ||
       '</b></font></div>' dbbid,
       d.name dbb_name,
       b.baseline_id baseline_id,
       baseline_name baseline_name,
       '<div nowrap align="right">' ||
       TO_CHAR(b.start_snap_time, 'mm/dd/yyyy HH24:MI:SS') || '</div>' start_snap_time,
       '<div nowrap align="right">' ||
       TO_CHAR(b.end_snap_time, 'mm/dd/yyyy HH24:MI:SS') || '</div>' end_snap_time
 WHERE b.dbid = d.dbid
 ORDER BY dbbid, b.baseline_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 328 for section: prompt Notes:
hc_q_prompt_notes_328() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_328_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                            - ENABLED TRACES -                              |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_enabled_traces"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Enabled Traces</b></font><hr align="left" width="450">
 

prompt  <b><u>End-to-End Application Tracing FROM View DBA_ENABLED_TRACES.</u></b>

prompt    <li> <b>Trace Type:</b> Possible values are CLIENT_ID, SESSION, SERVICE, SERVICE_MODULE, SERVICE_MODULE_ACTION, AND  DATABASE, based on the type of tracing enabled.

prompt    <li> <b>Primary ID:</b> Specific client identifier (username) or service name.

prompt  <p>
 

prompt  <b><u>Application tracing is enabled using the DBMS_MONITOR package AND  the following procedures:</u></b>

prompt    <li> <b>CLIENT_ID_TRACE_ENABLE:</b> Enable tracing based on client identifier (username).

prompt    <li> <b>CLIENT_ID_TRACE_DISABLE:</b> Disable client identifier tracing.

prompt    <li> <b>SESSION_TRACE_ENABLE:</b> Enable tracing based on SID AND  SERIAL# of V$SESSION.

prompt    <li> <b>SESSION_TRACE_DISABLE:</b> Disable session tracing.

prompt    <li> <b>SERV_MOD_ACT_TRACE_ENABLE:</b> Enable tracing for a given combination of service name, module, AND  action.

prompt    <li> <b>SERV_MOD_ACT_TRACE_DISABLE:</b> Disable service, module, AND  action tracing.

prompt    <li> <b>DATABASE_TRACE_ENABLE:</b> Enable tracing for the entire database.

prompt    <li> <b>DATABASE_TRACE_DISABLE:</b> Disable database tracing.

prompt  <p>
 

prompt  <b><font color="#ff0000">Hint</font>:</b> In a shared environment WHERE you have more than one session to trace, it is

prompt  possible to end up with many trace files WHEN tracing is enabled (i.e. connection pools).

prompt  Oracle10<i>g</i> introduces the <b>trcsess</b> command-line utility to combine all the relevant

prompt  trace files based on a session or client identifier or the service name, module name, and

prompt  action name hierarchy combination. The output trace file FROM the trcsess command can then be

prompt  sent to tkprof for a formatted output. Type trcsess at the command-line without any arguments to

prompt  show the parameters AND  usage.
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN trace_type           FORMAT a75    HEADING 'Trace Type'         ENTMAP OFF
COLUMN primary_id           FORMAT a75    HEADING 'Primary ID'         ENTMAP OFF
COLUMN qualifier_id1        FORMAT a75    HEADING 'Module Name'        ENTMAP OFF
COLUMN qualifier_id2        FORMAT a75    HEADING 'Action Name'        ENTMAP OFF
COLUMN waits                FORMAT a75    HEADING 'Waits?'             ENTMAP OFF
COLUMN binds                FORMAT a75    HEADING 'Binds?'             ENTMAP OFF
COLUMN instance_name_print  FORMAT a75    HEADING 'Instance_Name'      ENTMAP OFF
 
SELECT con_id,'<div align="left"><font color="#336699"><b>' || trace_type ||
       '</b></font></div>' trace_type,
       '<div align="left">' || NVL(primary_id, '<br>') || '</div>' primary_id,
       '<div align="left">' || NVL(qualifier_id1, '<br>') || '</div>' qualifier_id1,
       '<div align="left">' || NVL(qualifier_id2, '<br>') || '</div>' qualifier_id2,
       '<div align="center">' || waits || '</div>' waits,
       '<div align="center">' || binds || '</div>' binds,
       '<div align="left">' || NVL(instance_name, '<br>') || '</div>' instance_name_print
  FROM cdb_enabled_traces
 ORDER BY con_id,trace_type, primary_id, qualifier_id1, qualifier_id2;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 329 for section: prompt Notes:
hc_q_prompt_notes_329() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_notes_329_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                         - ENABLED AGGREGATIONS -                           |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="dba_enabled_aggregations"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Enabled Aggregations</b></font><hr align="left" width="450">
 

prompt  <b><u>Statistics Aggregation FROM View DBA_ENABLED_AGGREGATIONS.</u></b>

prompt    <li> <b>Aggregation Type:</b> Possible values are CLIENT_ID, SERVICE_MODULE, AND  SERVICE_MODULE_ACTION, based on the type of statistics being gathered.

prompt    <li> <b>Primary ID:</b> Specific client identifier (username) or service name.

prompt  <p>
 

prompt  <b><u>Statistics aggregation is enabled using the DBMS_MONITOR package AND  the following procedures.</u></b>
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt Notes:
hc_section_prompt_notes() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt Notes:"
  hc_q_prompt_notes_01 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_02 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_03 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_04 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_05 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_06 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_07 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_08 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_09 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_10 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_11 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_12 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_13 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_14 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_15 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_16 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_17 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_18 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_19 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_20 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_21 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_22 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_23 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_24 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_25 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_26 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_27 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_28 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_29 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_30 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_31 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_32 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_33 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_34 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_35 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_36 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_37 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_38 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_39 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_40 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_41 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_42 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_43 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_44 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_45 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_46 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_47 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_48 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_49 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_50 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_51 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_52 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_53 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_54 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_55 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_56 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_57 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_58 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_59 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_60 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_61 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_62 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_63 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_64 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_65 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_66 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_67 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_68 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_69 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_70 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_71 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_72 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_73 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_74 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_75 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_76 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_77 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_78 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_79 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_80 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_81 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_82 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_83 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_84 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_85 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_86 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_87 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_88 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_89 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_90 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_91 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_92 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_93 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_94 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_95 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_96 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_97 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_98 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_99 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_100 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_101 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_102 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_103 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_104 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_105 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_106 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_107 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_108 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_109 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_110 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_111 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_112 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_113 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_114 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_115 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_116 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_117 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_118 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_119 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_120 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_121 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_122 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_123 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_124 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_125 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_126 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_127 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_128 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_129 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_130 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_131 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_132 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_133 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_134 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_135 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_136 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_137 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_138 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_139 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_140 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_141 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_142 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_143 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_144 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_145 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_146 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_147 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_148 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_149 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_150 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_151 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_152 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_153 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_154 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_155 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_156 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_157 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_158 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_159 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_160 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_161 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_162 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_163 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_164 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_165 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_166 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_167 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_168 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_169 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_170 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_171 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_172 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_173 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_174 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_175 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_176 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_177 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_178 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_179 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_180 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_181 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_182 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_183 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_184 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_185 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_186 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_187 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_188 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_189 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_190 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_191 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_192 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_193 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_194 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_195 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_196 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_197 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_198 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_199 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_200 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_201 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_202 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_203 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_204 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_205 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_206 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_207 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_208 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_209 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_210 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_211 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_212 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_213 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_214 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_215 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_216 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_217 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_218 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_219 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_220 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_221 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_222 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_223 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_224 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_225 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_226 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_227 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_228 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_229 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_230 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_231 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_232 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_233 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_234 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_235 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_236 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_237 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_238 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_239 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_240 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_241 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_242 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_243 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_244 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_245 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_246 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_247 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_248 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_249 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_250 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_251 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_252 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_253 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_254 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_255 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_256 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_257 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_258 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_259 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_260 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_261 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_262 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_263 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_264 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_265 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_266 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_267 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_268 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_269 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_270 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_271 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_272 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_273 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_274 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_275 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_276 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_277 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_278 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_279 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_280 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_281 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_282 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_283 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_284 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_285 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_286 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_287 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_288 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_289 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_290 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_291 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_292 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_293 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_294 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_295 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_296 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_297 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_298 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_299 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_300 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_301 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_302 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_303 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_304 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_305 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_306 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_307 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_308 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_309 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_310 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_311 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_312 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_313 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_314 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_315 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_316 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_317 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_318 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_319 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_320 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_321 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_322 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_323 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_324 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_325 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_326 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_327 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_328 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_notes_329 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  AND  restarts.

prompt    <li> <b>CLIENT_ID_STAT_ENABLE:</b> Enable statistics gathering based on client identifier (username).

prompt    <li> <b>CLIENT_ID_STAT_DISABLE:</b> Disable client identifier statistics gathering.

prompt    <li> <b>SERV_MOD_ACT_STAT_ENABLE:</b> Enable statistics gathering for a given combination of service name, module, AND  action.

prompt    <li> <b>SERV_MOD_ACT_STAT_DISABLE:</b> Disable service, module, AND  action statistics gathering.

prompt  <p>
 

prompt  <b><font color="#ff0000">Hint</font>:</b> While the DBA_ENABLED_AGGREGATIONS provides global statistics for currently enabled

prompt  statistics, several other views can be used to query statistics aggregation values: V$CLIENT_STATS,

prompt  V$SERVICE_STATS, V$SERV_MOD_ACT_STATS, AND  V$SERVICEMETRIC.
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN aggregation_type     FORMAT a75    HEADING 'Aggregation Type'   ENTMAP OFF
COLUMN primary_id           FORMAT a75    HEADING 'Primary ID'         ENTMAP OFF
COLUMN qualifier_id1        FORMAT a75    HEADING 'Module Name'        ENTMAP OFF
COLUMN qualifier_id2        FORMAT a75    HEADING 'Action Name'        ENTMAP OFF
 
SELECT con_id,'<div align="left"><font color="#336699"><b>' || aggregation_type ||
       '</b></font></div>' aggregation_type,
       '<div align="left">' || NVL(primary_id, '<br>') || '</div>' primary_id,
       '<div align="left">' || NVL(qualifier_id1, '<br>') || '</div>' qualifier_id1,
       '<div align="left">' || NVL(qualifier_id2, '<br>') || '</div>' qualifier_id2
  FROM cdb_enabled_aggregations
 ORDER BY con_id,aggregation_type, primary_id, qualifier_id1, qualifier_id2;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 02 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_02() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_02_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 


-- +----------------------------------------------------------------------------+

-- |                          - ASH SNAPSHOT SETTINGS -                         |

-- +----------------------------------------------------------------------------+


prompt  <a name="ash_snapshot_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASH</b></font><hr align="left" width="600">


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● (7)</b></font>

 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN instance_name_print  FORMAT a75               HEADING 'Instance_Name'          ENTMAP OFF 
COLUMN end_interval_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;End_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN begin_interval_time   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Begin_Interval_Time&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN startup_time   FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;STARTUP_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN elapsed_time         FORMAT 999,999,999.99    HEADING 'Elapsed Time (min)'     ENTMAP OFF
COLUMN db_time              FORMAT 999,999,999.99    HEADING 'DB Time (min)'          ENTMAP OFF
COLUMN pct_db_time          FORMAT a75               HEADING '% DB Time'              ENTMAP OFF
COLUMN cpu_time             FORMAT 999,999,999.99    HEADING 'CPU Time (min)'         ENTMAP OFF
COLUMN RETENTION          FORMAT a140               HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;RETENTION&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
COLUMN ash_report          FORMAT a500               HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ash_report&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'              ENTMAP OFF
SET DEFINE ON

 
SELECT *
  FROM (SELECT d.INSTANCE_NUMBER inst_id,
               d.dbid,
               (SELECT (nb.snap_interval)
               (SELECT (nb.retention)
               TO_CHAR(d.startup_time, 'YYYY-MM-DD HH24:MI:SS.ff') startup_time,
               TO_CHAR(d.begin_interval_time, 'YYYY-MM-DD HH24:MI:SS.ff') begin_interval_time,
               TO_CHAR(d.end_interval_time, 'YYYY-MM-DD HH24:MI:SS.ff') end_interval_time,
               (d.flush_elapsed) flush_elapsed,
               d.snap_level,
               d.error_count,
               d.snap_flag,
               'SELECT * FROM table(dbms_workload_repository.ash_report_html(' ||
               d.dbid || ',' || d.instance_number ||
               ',  (SELECT a.end_interval_time
               ') , (SELECT a.end_interval_time
               
               (DENSE_RANK()
                OVER(partition by instance_number ORDER BY d.instance_number,
         WHERE d.end_interval_time > sysdate - 7
 WHERE t.rk <= 50


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="ash_lastone_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ASH</b></font><hr align="left" width="600">

SET DEFINE ON


prompt 

prompt  <center>[<a class="noLink" href="#ASH_new_lastone"><font size=+1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>Data Reference:ASH</b></font></a>]</center><p>


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                          - ADDM SNAPSHOT SETTINGS -                         |

-- +----------------------------------------------------------------------------+


prompt  <a name="ADDM_snapshot_info"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ADDM</b></font><hr align="left" width="600"> 
alter session set nls_language='SIMPLIFIED CHINESE';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 03 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_03() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_03_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
DECLARE
  task_name VARCHAR2(50) := 'HEALTH_CHECK_BY_LHR';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 04 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_04() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_04_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
task_desc VARCHAR2(50) := 'HEALTH_CHECK_BY_LHR';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 05 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_05() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_05_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
task_id   NUMBER;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 06 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_06() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_06_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
begin
  begin
    dbms_advisor.delete_task(task_name);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 07 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_07() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_07_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
exception
    WHEN others then
      null;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 08 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_08() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_08_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
end;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 09 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_09() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_09_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
dbms_advisor.create_task('ADDM', task_id, task_name, task_desc, null);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 10 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_10() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_10_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
dbms_advisor.set_task_parameter(task_name, 'INSTANCE', &_instance_number);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 11 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_11() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_11_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
dbms_advisor.set_task_parameter(task_name, 'DB_ID', &_dbid);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 12 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_12() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_12_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
dbms_advisor.execute_task(task_name);
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 13 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_13() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_13_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
exception
  WHEN others then
    null;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 14 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_14() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_14_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
END;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 15 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_15() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_15_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
/


prompt  

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: SQL: SELECT dbms_advisor.get_task_report('HEALTH_CHECK_BY_LHR', 'TEXT', 'ALL') addm_results  FROM DUAL; </font></b>
SELECT  '<textarea style="width:100%;font-family:Courier New;font-size:12px;overflow:auto" rows="10"> ' || dbms_advisor.get_task_report('HEALTH_CHECK_BY_LHR', 'TEXT', 'ALL') ||'</textarea>' addm_results  FROM DUAL;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 16 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_16() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_16_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
alter session set nls_language='&_nls_language';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 17 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_17() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_17_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: ADDM </font></b>  [<a class="noLink" href="#hot_blocks_summary">Next Item</a>] [<a class="noLink" href="#directory">BACK</a>]<p>

alter session set nls_language='AMERICAN';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 18 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_18() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_18_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT '<pre style="font-family:Courier New; word-wrap: break-word; white-space: pre-wrap; white-space: -moz-pre-wrap" >' || dbms_advisor.get_task_report('HEALTH_CHECK_BY_LHR', 'TEXT', 'ALL') || '</pre>' addm_results FROM DUAL;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 19 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_19() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_19_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
alter session set nls_language='&_nls_language';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 20 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_20() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_20_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● (,)</b></font> 
SELECT /*+rule */ distinct e.con_id,e.owner, e.segment_name, e.segment_type, dbablk,b.tch
          FROM cdb_extents e,
               (SELECT *
                  FROM (SELECT con_id,addr, ts#, file#, dbarfil, dbablk, tch
                          FROM SYS.X$BH
                         ORDER BY tch DESC)
                 WHERE ROWNUM <= 10) b
         WHERE e.con_id=b.con_id and  e.relative_fno = b.dbarfil
           AND  e.block_id <= b.dbablk
           AND  e.block_id + e.blocks > b.dbablk
	   AND  e.owner   NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
ORDER BY e.con_id, tch desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 21 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_21() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_21_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "            . . ." 


prompt  

prompt  <a name="database_tjxinxiinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="statics_gatherflag"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  ● Oracle 10g:106,8;(106).

prompt  ● Oracle 11gand its:102,4;62,62,20.

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN NEXT_START_DATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NEXT_START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF  
COLUMN LAST_START_DATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LAST_START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT C.* FROM CDB_AUTOTASK_CLIENT C ORDER BY C.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 22 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_22() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_22_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● 

SELECT A.CON_ID,
       A.WINDOW_NAME,
       TO_CHAR(WINDOW_NEXT_TIME, 'YYYY-MM-DD HH24:MI:SS') WINDOW_NEXT_TIME,
       WINDOW_ACTIVE,
       AUTOTASK_STATUS,
       OPTIMIZER_STATS,
       SEGMENT_ADVISOR,
       SQL_TUNE_ADVISOR,
       
--HEALTH_MONITOR,
       B.REPEAT_INTERVAL,
       B.DURATION,
       B.ENABLED,
       B.RESOURCE_PLAN
  FROM CDB_AUTOTASK_WINDOW_CLIENTS A,
       (SELECT T1.CON_ID,
               T1.WINDOW_NAME,
               T1.REPEAT_INTERVAL,
               T1.DURATION,
               T1.ENABLED,
               T1.RESOURCE_PLAN
          FROM CDB_SCHEDULER_WINDOWS T1, CDB_SCHEDULER_WINGROUP_MEMBERS T2
         WHERE T1.WINDOW_NAME = T2.WINDOW_NAME
           AND T1.CON_ID = T2.CON_ID
           AND T2.WINDOW_GROUP_NAME IN
               ('MAINTENANCE_WINDOW_GROUP', 'BSLN_MAINTAIN_STATS_SCHED')) B
 WHERE A.WINDOW_NAME = B.WINDOW_NAME
   AND A.CON_ID = B.CON_ID
	 ORDER BY A.CON_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 23 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_23() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_23_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  ● JOB

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN ACTUAL_START_DATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ACTUAL_START_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF  
COLUMN LOG_DATE   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOG_DATE&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN RUN_DURATION FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;RUN_DURATION&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT *
  FROM (SELECT n.CON_ID,
               JRD.LOG_ID,
               JRD.JOB_NAME,
               N.JOB_CLASS,
               TO_CHAR(JRD.ACTUAL_START_DATE, 'YYYY-MM-DD HH24:MI:SS') ACTUAL_START_DATE,
               TO_CHAR(JRD.LOG_DATE, 'YYYY-MM-DD HH24:MI:SS') LOG_DATE,
               JRD.STATUS,
               JRD.ERROR#,
               JRD.RUN_DURATION,
               JRD.ADDITIONAL_INFO
          FROM cdb_SCHEDULER_JOB_LOG N, cdb_SCHEDULER_JOB_RUN_DETAILS JRD
         WHERE N.LOG_ID = JRD.LOG_ID
           and n.CON_ID = jrd.CON_ID
           AND N.JOB_NAME LIKE 'ORA$AT_OS_OPT_%'
					 and JRD.ACTUAL_START_DATE>=sysdate-15 
					 and jrd.STATUS<>'SUCCEEDED'
         ORDER BY  jrd.log_id DESC)
 WHERE ROWNUM <= 50;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 24 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_24() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_24_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

 

-- +----------------------------------------------------------------------------+

-- |                     - OBJECTS WITHOUT STATISTICS -                         |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="objects_without_statistics"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Objects Without Statistics</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN owner            FORMAT a95                HEAD 'Owner'            ENTMAP OFF
COLUMN object_type      FORMAT a20                HEAD 'Object Type'      ENTMAP OFF
COLUMN count            FORMAT 999,999,999,999    HEAD 'Count'            ENTMAP OFF
 

-- BREAK ON report ON owner
COMPUTE count LABEL '<font color="#990000"><b>Total: </b></font>' OF object_name ON report
 
SELECT a.con_id, '<div nowrap align="left"><font color="#336699"><b>' || owner ||'</b></font></div>' owner,
       'Table' object_type,
       count(*) count1
  FROM cdb_tables a
 WHERE last_analyzed IS NULL
   AND  partitioned = 'NO'
   AND   owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY a.con_id,owner, 'Table'
UNION  all
SELECT a.con_id, '<div nowrap align="left"><font color="#336699"><b>' || owner ||'</b></font></div>' owner,
       'Index' object_type,
       count(*) count1
  FROM cdb_indexes  a
 WHERE last_analyzed IS NULL
   AND   owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
   AND  partitioned = 'NO'
 GROUP BY a.con_id,a.con_id,owner, 'Index'
UNION all
SELECT a.con_id, '<div nowrap align="left"><font color="#336699"><b>' || table_owner ||'</b></font></div>' owner,
       'Table Partition' object_type,
       count(*) count1
  FROM cdb_tab_partitions   a
 WHERE last_analyzed IS NULL
   AND   table_owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY a.con_id,table_owner, 'Table Partition'
UNION  all
SELECT a.con_id, '<div nowrap align="left"><font color="#336699"><b>' || index_owner ||'</b></font></div>' owner,
       'Index Partition' object_type,
       count(*) count1
  FROM cdb_ind_partitions  a
 WHERE last_analyzed IS NULL
   AND   index_owner   NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 GROUP BY a.con_id,index_owner, 'Index Partition'
 ORDER BY con_id, owner, object_type,count1;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 25 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_25() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_25_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 


prompt  <a name="statics_gatherfla_table"></a> 

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font> [<a class="noLink" href="#statics_gatherfla_tmptable">Next Item</a>] <hr align="left" width="600">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 1 </font></b>

prompt   

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>●  </b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


-- BREAK ON report
COMPUTE SUM label '<font color="#990000"><b>Total:</b></font>'   OF counts never_analyze expired_analyze ON report

SELECT CON_ID,OWNER,
       count(1) counts,
       sum(case
             WHEN d.last_analyzed is null then
              1
             else
              0
           end) never_analyze,
       
       sum(case
             WHEN d.last_analyzed IS NOT NULL then
              1
             else
              0
           end) expired_analyze
  FROM (SELECT CON_ID,owner,
               table_name,
               PARTITION_NAME,
               OBJECT_TYPE,
               GLOBAL_STATS,
               last_analyzed
          FROM (SELECT t.con_id, owner,
                       table_name,
                       t.PARTITION_NAME,
                       t.OBJECT_TYPE,
                       t.GLOBAL_STATS,
                       t.last_analyzed,
                       DENSE_RANK() over(ORDER BY last_analyzed) rn
                  FROM cdb_tab_statistics t
                 WHERE (t.last_analyzed is null or
                       t.last_analyzed < SYSDATE - 15)
                   AND  table_name NOT LIKE 'BIN$%'
                   AND  table_name NOT LIKE '%TMP%'
                   AND  owner NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
                   AND  t.SUBPARTITION_NAME is null
                   AND  (t.con_id,t.OWNER, t.TABLE_NAME) in
                       (SELECT dtm.con_id, dtm.table_owner, dtm.table_name
                          FROM cdb_tab_modifications dtm
  WHERE dtm.inserts > 100
                    or dtm.updates > 100
                    or dtm.deletes > 100))
         WHERE (rn <= 50 or LAST_ANALYZED is null)
         ORDER BY OWNER, table_name, PARTITION_NAME) d
 GROUP BY CON_ID,OWNER
 ORDER BY CON_ID,OWNER,counts desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 26 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_26() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_26_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>●  </b></font><hr align="left" width="450">


prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: 1100,</font></b>
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

column GLOBAL_STATS format a15
SELECT CON_ID,owner,
       table_name,
       PARTITION_NAME,
       OBJECT_TYPE,
       GLOBAL_STATS,
       last_analyzed
  FROM (SELECT CON_ID, owner,
               table_name,
               t.PARTITION_NAME,
               t.OBJECT_TYPE,
               t.GLOBAL_STATS,
               t.last_analyzed,
               DENSE_RANK() over(ORDER BY last_analyzed) rn
          FROM CDB_tab_statistics t
         WHERE (t.last_analyzed is null or t.last_analyzed < SYSDATE - 15)
           AND  table_name NOT LIKE 'BIN$%'
           AND  table_name NOT LIKE '%TMP%'
           AND  owner NOT IN  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
           AND  t.SUBPARTITION_NAME is null
           AND  (T.CON_ID,t.OWNER, t.TABLE_NAME) in
               (SELECT DTM.CON_ID,dtm.table_owner, dtm.table_name
                  FROM CDB_tab_modifications dtm
                 WHERE dtm.inserts > 100
                    or dtm.updates > 100
                    or dtm.deletes > 100))
 WHERE (rn <= 100 or LAST_ANALYZED is null)
 ORDER BY CON_ID,OWNER, table_name, PARTITION_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 27 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_27() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_27_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="statics_gatherfla_tmptable"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font>[<a class="noLink" href="#statics_gatherfla_table"></a>]</center><p><hr align="left" width="600"> 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT CON_ID,owner, table_name, t.last_analyzed, t.num_rows, t.blocks
  FROM CDB_tables t
where t.temporary = 'Y'
   AND  last_analyzed is  null 
   AND   owner   NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
   ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 28 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_28() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_28_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="statics_gatherlock"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font>[<a class="noLink" href="#statics_gatherfla_table"></a>]</center><p><hr align="left" width="600"> 


prompt   

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>●  </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT CON_ID, T.OWNER index_owner, T.TABLE_OWNER, T.OBJECT_TYPE, COUNT(1) COUNTS
  FROM (SELECT CON_ID,D.OWNER,
               D.INDEX_NAME,
               D.TABLE_OWNER,
               D.TABLE_NAME,
               D.PARTITION_NAME,
               D.SUBPARTITION_NAME,
               D.OBJECT_TYPE
          FROM CDB_IND_STATISTICS D
         WHERE STATTYPE_LOCKED = 'ALL'
        AND D.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
        UNION ALL
        SELECT CON_ID,'',
               '',
               D.OWNER,
               D.TABLE_NAME,
               D.PARTITION_NAME,
               D.SUBPARTITION_NAME,
               D.OBJECT_TYPE
          FROM CDB_TAB_STATISTICS D
         WHERE STATTYPE_LOCKED = 'ALL'
       AND D.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
        ) T
 GROUP BY CON_ID,T.OWNER, T.TABLE_OWNER, T.OBJECT_TYPE
 ORDER BY CON_ID,T.OBJECT_TYPE, COUNTS DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 29 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_29() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_29_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt   

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>●  </b></font><hr align="left" width="450">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT * FROM ( 
SELECT CON_ID,D.OWNER,
       D.INDEX_NAME,
       D.TABLE_OWNER,
       D.TABLE_NAME,
       D.PARTITION_NAME,
       D.SUBPARTITION_NAME,
       D.OBJECT_TYPE,
			 DENSE_RANK() OVER(PARTITION BY TABLE_OWNER ORDER BY d.num_rows DESC) RN
  FROM CDB_IND_STATISTICS D
 WHERE STATTYPE_LOCKED = 'ALL'
 AND D.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 

UNION ALL
SELECT CON_ID,'',
       '',
       D.OWNER,
       D.TABLE_NAME,
       D.PARTITION_NAME,
       D.SUBPARTITION_NAME,
       D.OBJECT_TYPE,
			 DENSE_RANK() OVER(PARTITION BY OWNER ORDER BY d.num_rows DESC) RN
  FROM CDB_TAB_STATISTICS D
 WHERE STATTYPE_LOCKED = 'ALL'
AND D.OWNER NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
) WHERE rn<=5;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 30 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_30() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_30_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<     SESSIONS    >>>>>                           |

-- |                                                                            |

-- +============================================================================+

host echo "            . . ." 

prompt  <a name="database_sessionsinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


-- +----------------------------------------------------------------------------+

-- |                          - CURRENT SESSIONS -                              |

-- +----------------------------------------------------------------------------+


prompt  <a name="current_sessions"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>Session Overview()</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name_print  FORMAT a45    HEADING 'Instance_Name'              ENTMAP OFF
COLUMN thread_number_print  FORMAT a45    HEADING 'Thread Number'              ENTMAP OFF
COLUMN count                FORMAT a45    HEADING 'Current No. of Processes'   ENTMAP OFF
COLUMN value                FORMAT a45    HEADING 'Max No. of Processes'       ENTMAP OFF
COLUMN pct_usage            FORMAT a45    HEADING '% Usage'                    ENTMAP OFF

SELECT '<div align="center"><font color="#336699"><b>' || a.instance_name ||
       '</b></font></div>' instance_name_print,
       '<div align="center">' || a.thread# || '</div>' thread_number_print,
       '<div align="center">' || TO_CHAR(a.count) || '</div>' count,
       '<div align="center">' || b.value || '</div>' value,
       '<div align="center">' ||
       TO_CHAR(ROUND(100 * (a.count / b.value), 2)) || '%</div>' pct_usage
  FROM (SELECT count(*) count, a1.inst_id, a2.instance_name, a2.thread#
          FROM gv$session a1, gv$instance a2
         WHERE a1.inst_id = a2.inst_id
         GROUP BY a1.inst_id, a2.instance_name, a2.thread#) a,
       (SELECT value, inst_id FROM gv$parameter WHERE name = 'processes') b
 WHERE a.inst_id = b.inst_id
 ORDER BY a.instance_name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 31 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_31() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_31_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +----------------------------------------------------------------------------+

-- |                        - USER SESSION MATRIX -                             |

-- +----------------------------------------------------------------------------+


prompt  <a name="user_session_matrix"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>()</b></font><hr align="left" width="600">


prompt  <b>User sessions (excluding SYS AND  background processes)</b>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN instance_name_print  FORMAT a75               HEADING 'Instance_Name'            ENTMAP OFF
COLUMN thread_number_print  FORMAT a75               HEADING 'Thread Number'            ENTMAP OFF
COLUMN username             FORMAT a79               HEADING 'Oracle User'              ENTMAP OFF
COLUMN num_user_sess        FORMAT 999,999,999,999   HEADING 'Total Number of Logins'   ENTMAP OFF
COLUMN count_a              FORMAT 999,999,999       HEADING 'Active Logins'            ENTMAP OFF
COLUMN count_i              FORMAT 999,999,999       HEADING 'Inactive Logins'          ENTMAP OFF
COLUMN count_k              FORMAT 999,999,999       HEADING 'Killed Logins'            ENTMAP OFF
SET DEFINE ON


-- BREAK ON report ON instance_name_print ON thread_number_print

SELECT '<div align="center"><font color="#336699"><b>' || i.instance_name ||'</b></font></div>' instance_name_print,
       '<div align="center"><font color="#336699"><b>' || i.thread# ||'</b></font></div>' thread_number_print,
       '<div align="left"><font color="#000000">' ||NVL(sess.username, '[B.G. Process]') || '</font></div>' username,
       count(*) num_user_sess,
       NVL(act.count, 0) count_a,
       NVL(inact.count, 0) count_i,
       NVL(killed.count, 0) count_k
  FROM gv$session sess,
       gv$instance i,
       (SELECT count(*) count,
               NVL(username, '[B.G. Process]') username,
               inst_id
          FROM gv$session
         WHERE status = 'ACTIVE'
         GROUP BY username, inst_id) act,
       (SELECT count(*) count,
               NVL(username, '[B.G. Process]') username,
               inst_id
          FROM gv$session
         WHERE status = 'INACTIVE'
         GROUP BY username, inst_id) inact,
       (SELECT count(*) count,
               NVL(username, '[B.G. Process]') username,
               inst_id
          FROM gv$session
         WHERE status = 'KILLED'
         GROUP BY username, inst_id) killed
 WHERE sess.inst_id = i.inst_id
   AND  (NVL(sess.username, '[B.G. Process]') = act.username(+) AND
       sess.inst_id = act.inst_id(+))
   AND  (NVL(sess.username, '[B.G. Process]') = inact.username(+) AND
       sess.inst_id = inact.inst_id(+))
   AND  (NVL(sess.username, '[B.G. Process]') = killed.username(+) AND
       sess.inst_id = killed.inst_id(+))
   AND  sess.username NOT IN ('SYS')
 GROUP BY i.instance_name,
          i.thread#,
          sess.username,
          act.count,
          inact.count,
          killed.count
 ORDER BY i.instance_name, i.thread#, sess.username;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 32 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_32() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_32_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "                ACTIVE. . . ." 

prompt  <a name="user_session_active_his"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ACTIVE </b></font><hr align="left" width="600">


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ACTIVE() </b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

  FROM (SELECT n.con_id,
               n.instance_number inst_id,
               n.session_id,
               n.session_serial#,
               TO_CHAR(n.sample_time, 'YYYY-MM-DD') TIME
          FROM CDB_hist_active_sess_history n
         WHERE n.sample_time >= sysdate - 7
         GROUP BY n.con_id,
                  n.instance_number,
                  n.session_id,
                  n.session_serial#,
                  TO_CHAR(n.sample_time, 'YYYY-MM-DD')) t


prompt 

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ACTIVE() </b></font><hr align="left" width="450">

 

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT con_id,
       a.inst_id inst_id,
       SUBSTR(SAMPLE_TIME, 1, 10) Day,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '00', 1, 0)) H00,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '01', 1, 0)) H01,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '02', 1, 0)) H02,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '03', 1, 0)) H03,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '04', 1, 0)) H04,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '05', 1, 0)) H05,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '06', 1, 0)) H06,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '07', 1, 0)) H07,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '08', 1, 0)) H08,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '09', 1, 0)) H09,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '10', 1, 0)) H10,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '11', 1, 0)) H11,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '12', 1, 0)) H12,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '13', 1, 0)) H13,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '14', 1, 0)) H14,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '15', 1, 0)) H15,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '16', 1, 0)) H16,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '17', 1, 0)) H17,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '18', 1, 0)) H18,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '19', 1, 0)) H19,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '20', 1, 0)) H20,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '21', 1, 0)) H21,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '22', 1, 0)) H22,
       sum(DECODE(SUBSTR(SAMPLE_TIME, -2, 2), '23', 1, 0)) H23,
       COUNT(*) TOTAL
  FROM (SELECT n.con_id,
               n.instance_number inst_id,
               n.session_id,
               n.session_serial#,
               TO_CHAR(SAMPLE_TIME, 'YYYY-MM-DD HH24') SAMPLE_TIME
          FROM cdb_hist_active_sess_history n
         WHERE N.SAMPLE_TIME >= SYSDATE - 30
         GROUP BY con_id,
                  n.instance_number,
                  n.session_id,
                  n.session_serial#,
                  TO_CHAR(SAMPLE_TIME, 'YYYY-MM-DD HH24')) a
 GROUP BY con_id, inst_id, SUBSTR(SAMPLE_TIME, 1, 10)
 ORDER BY con_id, inst_id, SUBSTR(SAMPLE_TIME, 1, 10) desc;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 33 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_33() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_33_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="session_long_run"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10</b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="long_nofanying"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>10</b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

COLUMN LOGON_TIME  FORMAT a140               HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOGON_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'            ENTMAP OFF
COLUMN kill_session  FORMAT a300             HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;KILL_SESSION_SQL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'            ENTMAP OFF 	
SET DEFINE ON

SELECT A.INST_ID,
       A.USERNAME,
       A.LOGON_TIME,
       A.STATUS,
       A.SID,
       A.SERIAL#,
       (SELECT NB.SPID
          FROM GV$PROCESS NB
         WHERE NB.ADDR = A.PADDR
           AND NB.INST_ID = A.INST_ID) SPID,
       (SELECT TRUNC(NB.PGA_USED_MEM / 1024 / 1024)
          FROM GV$PROCESS NB
         WHERE NB.ADDR = A.PADDR
           AND NB.INST_ID = A.INST_ID) PGA_USED_MEM,
       (A.MODULE || '
--' || A.ACTION || '--' || A.PROGRAM || '--' ||
       A.CLIENT_IDENTIFIER || '
--' || A.CLIENT_INFO || '--' ||
       A.SERVICE_NAME) SESSION_TYPE,
       A.OSUSER,
       ROUND(A.LAST_CALL_ET / 60 / 60, 2) TOTAL_H,
       'ALTER SYSTEM  DISCONNECT SESSION ''' || A.SID || ',' || A.SERIAL# ||
       ''' IMMEDIATE' KILL_SESSION
  FROM GV$SESSION A
 WHERE A.STATUS IN ('INACTIVE')
   AND A.USERNAME IS NOT NULL
   AND A.USERNAME NOT IN ('SYS')
   AND A.LAST_CALL_ET >= 60 * 60 * 10
 ORDER BY A.INST_ID, A.LAST_CALL_ET DESC, A.USERNAME, A.LOGON_TIME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 34 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_34() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_34_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="session_commit_max"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT *
  FROM (SELECT T1.INST_ID,
               T1.SID,
               T1.VALUE,
               T2.NAME,
               DENSE_RANK() OVER(ORDER BY T1.VALUE DESC) RANK_ORDER
          FROM GV$SESSTAT T1, GV$STATNAME T2
         WHERE T2.NAME LIKE '%user commits%'
           AND T1.STATISTIC# = T2.STATISTIC#
           AND T1.INST_ID = T2.INST_ID
           AND VALUE >= 10000)
 WHERE RANK_ORDER <= 20
 ORDER BY INST_ID, VALUE DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 35 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_35() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_35_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="long_cpuwait"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>30CPU</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT t.*, s.sid, s.serial#, s.machine, s.program, s.osuser
  FROM (SELECT b.con_id, b.INST_ID,
               c.USERNAME,
               a.event,
               TO_CHAR(a.cnt) AS seconds,
               a.sql_id,
               
--dbms_lob.substr(b.sql_fulltext, 100, 1) sqltext ,
               b.SQL_TEXT
          FROM (SELECT ROWNUM rn, t.*
                  FROM (SELECT s.con_id, s.INST_ID,
                               DECODE(s.session_state,
                                      'WAITING',
                                      s.event,
                                      'Cpu + Wait For Cpu') Event,
                               s.sql_id,
                               s.user_id,
                               COUNT(*) CNT
                         WHERE sample_time > SYSDATE - 15 / 1440
                         GROUP BY s.con_id, INST_ID,
                                  s.user_id,
                                  DECODE(s.session_state,
                                         'WAITING',
                                         s.event,
                                         'Cpu + Wait For Cpu'),
                                  s.sql_id
                         ORDER BY CNT DESC) t
                 WHERE ROWNUM < 20) a,
               gv$sqlarea b,
               cdb_users c
         WHERE a.sql_id = b.sql_id
           AND  a.user_id = c.user_id
           AND  a.INST_ID = b.INST_ID
					 and b.con_id=c.con_id   
					 and a.con_id=b.con_id
           AND  c.username NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         ORDER BY CNT DESC) t,
       gv$session s
 WHERE t.sql_id = s.sql_id(+)
   AND  t.INST_ID = s.INST_ID(+)
	 and t.con_id=s.con_id(+)
 ORDER BY t.con_id,t.INST_ID
;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 36 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_36() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_36_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="database_lockinfoall"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="look_lock"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>ViewLOCK</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT /*+ RULE */
 o.con_id,
 INST_ID,
 LS.OSUSER OS_USER_NAME,
 LS.USERNAME USER_NAME,
 DECODE(LS.TYPE,
        'RW',
        'Row wait enqueue lock',
        'TM',
        'DML enqueue lock',
        'TX',
        'Transaction enqueue lock',
        'UL',
        'User supplied lock') LOCK_TYPE,
 O.OBJECT_NAME OBJECT,
 DECODE(LS.LMODE,
        1,
        NULL,
        2,
        'Row Share',
        3,
        'Row Exclusive',
        4,
        'Share',
        5,
        'Share Row Exclusive',
        6,
        'Exclusive',
        NULL) LOCK_MODE,
 O.OWNER,
 LS.SID,
 LS.SERIAL# SERIAL_NUM,
 LS.ID1,
 LS.ID2
FROM   cdb_OBJECTS O,
       (SELECT s.con_id, s.INST_ID,
               S.OSUSER,
               S.USERNAME,
               L.TYPE,
               L.LMODE,
               S.SID,
               S.SERIAL#,
               L.ID1,
               L.ID2
        FROM   gV$SESSION S,
               gV$LOCK     L
        WHERE  S.SID = L.SID
   AND  s.INST_ID=l.INST_ID
	 and s.con_id=l.con_id) LS  
WHERE  O.OBJECT_ID = LS.ID1
and o.con_id=ls.con_id
AND    O.OWNER <> 'SYS'
ORDER  BY o.con_id, INST_ID,
          O.OWNER,
          O.OBJECT_NAME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 37 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_37() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_37_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="look_lock_whowho"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>View</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT /*+no_merge(a) no_merge(b) */
 a.INST_ID,
 b.INST_ID,
 (SELECT username FROM v$session WHERE sid = a.sid) blocker,
 a.sid,
 'is blocking',
 (SELECT username FROM v$session WHERE sid = b.sid) blockee,
 b.sid
FROM   gv$lock a,
       gv$lock b
WHERE  a.block = 1
AND    b.request > 0
AND    a.id1 = b.id1
AND    a.id2 = b.id2
ORDER  BY a.sid;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 38 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_38() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_38_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● v$SESSION</b></font><hr align="left" width="450">

prompt  <font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: DBA_DML_LOCKS,DBA_DDL_LOCKS,V$LOCK,DBA_LOCK,V$LOCKED_OBJECT.V$LOCKED_OBJECTDML,DDL.V$LOCKDBA_LOCKSDBA_LOCK,DBA_LOCKSDBA_LOCK synonym. </font>

SELECT A.CON_ID,
       A.INST_ID,
       A.TADDR,
       A.LOCKWAIT,
       A.ROW_WAIT_OBJ#,
       A.ROW_WAIT_FILE#,
       A.ROW_WAIT_BLOCK#,
       A.ROW_WAIT_ROW#,
       (SELECT D.OWNER || '|' || D.OBJECT_NAME || '|' || D.OBJECT_TYPE
          FROM CDB_OBJECTS D
         WHERE D.OBJECT_ID = A.ROW_WAIT_OBJ#
				 AND D.CON_ID=A.CON_ID
           AND ROWNUM <= 1) OBJECT_NAME,
       A.EVENT,
       A.P1,
       A.P2,
       A.P3,
       CHR(BITAND(P1, -16777216) / 16777215) ||
       CHR(BITAND(P1, 16711680) / 65535) "LOCK",
       BITAND(P1, 65535) "MODE",
       TRUNC(P2 / POWER(2, 16)) AS XIDUSN,
       BITAND(P2, TO_NUMBER('FFFF', 'XXXX')) + 0 AS XIDSLOT,
       P3 XIDSQN,
       A.SID,
       A.BLOCKING_SESSION,
       A.SADDR,
       DBMS_ROWID.ROWID_CREATE(1, 77669, 8, 2799, 0) REQUEST_ROWID,
       (SELECT B.SQL_TEXT
          FROM GV$SQL B
         WHERE B.SQL_ID = NVL(A.SQL_ID, A.PREV_SQL_ID)
				 AND B.CON_ID=A.CON_ID
           AND ROWNUM <= 1) SQL_TEXT
  FROM GV$SESSION A
 WHERE A.BLOCKING_SESSION IS NOT NULL
 ORDER BY A.CON_ID, A.INST_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 39 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_39() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_39_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="open_cursor_details"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT D.CON_ID, d.INST_ID, sid, COUNT(*) cnt
  FROM gv$open_cursor d
 GROUP BY D.CON_ID,d.INST_ID, sid
HAVING COUNT(*) >= 1000
 ORDER BY D.CON_ID, d.INST_ID, cnt DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 40 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_40() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_40_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="spid_completeinfo"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT sl.INST_ID,
       s.client_info,
       sl.message,
       sl.sid,
       sl.serial#,
       p.spid,
       round(sl.sofar / sl.totalwork * 100, 2) "% Complete"
FROM   gv$session_longops sl,
       gv$session         s,
       gv$process         p
WHERE  p.addr = s.paddr
AND    sl.sid = s.sid
AND    sl.serial# = s.serial#
AND    sl.INST_ID = s.INST_ID
AND    sl.INST_ID = p.INST_ID
AND    opname LIKE 'RMAN%'
AND    opname NOT LIKE '%aggregate%'
AND    totalwork != 0
AND    sofar <> totalwork;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 41 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_41() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_41_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="database_memoryinfo"></a>

prompt  <font size="+2" color="00CCFF"><b>Memory Usage</b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="rate_db_object_cache"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT count(*) ,round(sum(sharable_mem)/1024/1024,2) sharable_mem_M FROM  v$db_object_cache  a;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 42 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_42() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_42_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


prompt  <a name="pga_max_spid"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>PGATop Consuming Processes</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN LOGON_TIME   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;LOGON_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN kill_session   FORMAT a500    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;kill_session&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF

SET DEFINE ON

SELECT *
  FROM (SELECT p.INST_ID,
               p.spid,
               p.pid,
               s.sid,
               s.serial#,
               s.status,
               trunc(p.pga_alloc_mem/1024/1024) pga_alloc_mem_m,
               s.username,
               s.osuser,
               s.program,
               s.SQL_ID
          FROM gv$process p, gv$session s
         WHERE s.paddr(+) = p.addr
           AND  p.INST_ID = s.INST_ID
           AND  s.USERNAME not in ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
         ORDER BY p.pga_alloc_mem DESC)
 WHERE ROWNUM < 21
 ORDER BY INST_ID, pga_alloc_mem_m DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 43 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_43() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_43_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT a.INST_ID,
       A.USERNAME,
       A.LOGON_TIME,
       A.STATUS,
       A.SID,
       A.SERIAL#,
       SPID,
       PGA_USED_MEM PGA_USED_MEM,
       (A.MODULE || '
--' || A.ACTION || '--' || A.PROGRAM || '--' ||
       a.CLIENT_IDENTIFIER || '
--' || a.CLIENT_INFO || '--' ||
       a.SERVICE_NAME) session_type,
       A.OSUSER,
       round(a.LAST_CALL_ET / 60 / 60, 2) total_h,
       'ALTER SYSTEM  DISCONNECT SESSION ''' || a.SID || ',' || a.serial# ||
       ''' IMMEDIATE' kill_session
  FROM gv$session A,
       (SELECT NNB.ADDR,
               NNB.INST_ID,
               trunc(PGA_USED_MEM / 1024 / 1024) PGA_USED_MEM,
               NNB.BACKGROUND,
               nnb.spid,
               DENSE_RANK() OVER(ORDER BY NNB.PGA_USED_MEM DESC) rank_order
          FROM gv$process NNB
         WHERE NNB.BACKGROUND is null) B
 WHERE B.ADDR = a.PADDR
   AND  B.INST_ID = a.INST_ID
   AND  B.PGA_USED_MEM > 1
   AND  rank_order <= 10
   AND  a.USERNAME not in  ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG') 
 ORDER BY a.INST_ID, rank_order DESC, a.USERNAME, a.LOGON_TIME;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 44 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_44() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_44_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="db_ratiosssa"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="buffer_cache_ratiosss"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>buffer cache </b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT A.INST_ID,
       sum(physical_reads) physical_reads,
       sum(db_block_gets) db_block_gets,
       TO_CHAR(sum(consistent_gets)) consistent_gets,
       round(DECODE(DECODE((sum(db_block_gets) + sum(consistent_gets)),
                           0,
                           0,
                           (sum(physical_reads) /
                           (sum(db_block_gets) + sum(consistent_gets)))),
                    0,
                    0,
                    1 -
                    DECODE((sum(db_block_gets) + sum(consistent_gets)),
                           0,
                           0,
                           (sum(physical_reads) /
                           (sum(db_block_gets) + sum(consistent_gets))))),
             4) * 100 || '%' "Hit Ratio"
  FROM Gv$buffer_pool_statistics A
	GROUP BY A.INST_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 45 for section: prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_45() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_45_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="library_cache_ratiosss"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>librarycache</b></font><hr align="left" width="600">
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt Note that statistics gathering is global for the database AND  is persistent across instance starts
hc_section_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt Note that statistics gathering is global for the database AND  is persistent across instance starts"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_01 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_02 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_03 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_04 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_05 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_06 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_07 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_08 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_09 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_10 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_11 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_12 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_13 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_14 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_15 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_16 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_17 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_18 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_19 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_20 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_21 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_22 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_23 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_24 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_25 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_26 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_27 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_28 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_29 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_30 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_31 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_32 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_33 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_34 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_35 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_36 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_37 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_38 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_39 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_40 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_41 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_42 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_43 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_44 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts_45 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT a.inst_id, sum(gets) gets,
       sum(gethits) gethits,
       round(sum(gethits) * 100 / sum(gets),2) gets_Hit_Ratio,
       sum(pins) pins,
       sum(pinhits) pinhits,
       round(sum(pinhits) *100 / sum(pins),2) Pins_Hit_Ratio
  FROM gv$librarycache a
	group by a.inst_id;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 02 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_02() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_02_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT a.inst_id,namespace ,
       sum(gets) gets,
       sum(gethits) gethits,
       round(DECODE(sum(gets),0,0,sum(gethits)*100 / sum(gets)),2)  gets_Hit_Ratio,
       sum(pins) pins,
       sum(pinhits) pinhits,
       round(DECODE(sum(pins),0,0,sum(pinhits)*100 / sum(pins)),2)  Pins_Hit_Ratio,
       sum(RELOADS) RELOADS,
       sum(INVALIDATIONS) INVALIDATIONS
  FROM gv$librarycache a
  GROUP BY a.inst_id,namespace ORDER BY namespace;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 03 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_03() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_03_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="buffer_cache_ratiosss"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT A.INST_ID, ROUND((SUM(GETS-GETMISSES-USAGE-FIXED))/SUM(GETS)*100,2) DATA_DICTIONARY_CACHE FROM GV$ROWCACHE A GROUP BY A.INST_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 04 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_04() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_04_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT A.INST_ID, parameter
     , sum(gets)
     , sum(getmisses)
     , 100*sum(gets - getmisses) / sum(gets)  pct_succ_gets
     , sum(modifications)                     updates
  FROM GV$ROWCACHE A
 WHERE gets > 10
 GROUP BY A.INST_ID, parameter;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 05 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_05() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_05_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="lach_ratiopace"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>latch</b></font><hr align="left" width="600">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF

SELECT A.INST_ID,
       sum(gets),
       sum(misses),
       round(1 - sum(misses) / sum(gets), 4)
  FROM Gv$latch A
 GROUP BY A.INST_ID;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 06 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_06() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_06_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>

host echo "            . . ." 

prompt  <a name="database_waitallinfo"></a>

prompt  <font size="+2" color="00CCFF"><b></b></font><hr align="left" width="800">

prompt  <p>


prompt  <a name="wait_event_current"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● Wait Events (Current)</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON

SELECT a.INST_ID,
       a.WAIT_CLASS#,
       a.WAIT_CLASS,
       a.EVENT,
       COUNT(1) counts
FROM   gv$session a
WHERE  a.WAIT_CLASS <> 'Idle'
GROUP  BY a.INST_ID,
          a.WAIT_CLASS#,
          a.WAIT_CLASS,
          a.EVENT
ORDER  BY a.INST_ID,
          counts DESC;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 07 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_07() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_07_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● (cdb_hist_active_sess_history)</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN END_INTERVAL_TIME   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;END_INTERVAL_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN BEGIN_INTERVAL_TIME   FORMAT a140    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BEGIN_INTERVAL_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN STARTUP_TIME   FORMAT a160    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;STARTUP_TIME&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN EVENT   FORMAT a300    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;EVENT&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
COLUMN SESSION_INFO   FORMAT a300    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SESSION_INFO&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON

SELECT V.CON_ID,
       V.INSTANCE_NUMBER,
       TO_CHAR(S.BEGIN_INTERVAL_TIME, 'YYYY-MM-DD HH24:MI:SS') BEGIN_INTERVAL_TIME,
       TO_CHAR(S.END_INTERVAL_TIME, 'YYYY-MM-DD HH24:MI:SS') END_INTERVAL_TIME,
       TO_CHAR(S.STARTUP_TIME, 'YYYY-MM-DD HH24:MI:SS') STARTUP_TIME,
       EVENT,
       WAIT_CLASS,
       SESSION_STATE,
       SESSION_TYPE,
       SESSION_INFO,
       SQL_ID,
       COUNTS
  FROM (SELECT D.CON_ID,
               D.INSTANCE_NUMBER,
               D.EVENT,
               D.WAIT_CLASS,
               D.SESSION_STATE,
               D.SESSION_TYPE,
               D.PROGRAM || '
--' || D.MODULE || '--' || D.ACTION SESSION_INFO,
               D.SQL_ID,
               COUNT(1) COUNTS,
               DENSE_RANK() OVER(PARTITION BY D.INSTANCE_NUMBER ORDER BY COUNT(1) DESC) RN
          FROM CDB_HIST_ACTIVE_SESS_HISTORY D
         WHERE D.EVENT IS NOT NULL
           AND D.WAIT_CLASS <> 'Idle'
           AND D.SQL_ID IS NOT NULL
         GROUP BY D.CON_ID,
                  D.INSTANCE_NUMBER,
                  D.EVENT,
                  D.WAIT_CLASS,
                  D.SESSION_STATE,
                  D.SESSION_TYPE,
                  D.SQL_ID,
                  (D.PROGRAM || '
--' || D.MODULE || '--' || D.ACTION)) V,
       CDB_HIST_SNAPSHOT S
 WHERE V.INSTANCE_NUMBER = S.INSTANCE_NUMBER
   AND RN <= 20
   AND COUNTS > 20


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


prompt  <a name="wait_event_history"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ()</b></font><hr align="left" width="450">

CLEAR COLUMNS COMPUTES
SET DEFINE OFF


prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>


-- +============================================================================+

-- |                                                                            |

-- |                     <<<<<     NETWORKING    >>>>>                          |

-- |                                                                            |

-- +============================================================================+
 
 

prompt  <a name="Networking_info_all"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u>Networking</u></b></font></center>
 
 

-- +----------------------------------------------------------------------------+

-- |                     - MTS DISPATCHER STATISTICS -                          |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="mts_dispatcher_statistics"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>MTS Dispatcher Statistics</b></font><hr align="left" width="600">
 

prompt  <b>Dispatcher rate</b>
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN name                    HEADING 'Name'                  ENTMAP OFF
COLUMN avg_loop_rate           HEADING 'Avg|Loop|Rate'         ENTMAP OFF
COLUMN avg_event_rate          HEADING 'Avg|Event|Rate'        ENTMAP OFF
COLUMN avg_events_per_loop     HEADING 'Avg|Events|Per|Loop'   ENTMAP OFF
COLUMN avg_msg_rate            HEADING 'Avg|Msg|Rate'          ENTMAP OFF
COLUMN avg_svr_buf_rate        HEADING 'Avg|Svr|Buf|Rate'      ENTMAP OFF
COLUMN avg_svr_byte_rate       HEADING 'Avg|Svr|Byte|Rate'     ENTMAP OFF
COLUMN avg_svr_byte_per_buf    HEADING 'Avg|Svr|Byte|Per|Buf'  ENTMAP OFF
COLUMN avg_clt_buf_rate        HEADING 'Avg|Clt|Buf|Rate'      ENTMAP OFF
COLUMN avg_clt_byte_rate       HEADING 'Avg|Clt|Byte|Rate'     ENTMAP OFF
COLUMN avg_clt_byte_per_buf    HEADING 'Avg|Clt|Byte|Per|Buf'  ENTMAP OFF
COLUMN avg_buf_rate            HEADING 'Avg|Buf|Rate'          ENTMAP OFF
COLUMN avg_byte_rate           HEADING 'Avg|Byte|Rate'         ENTMAP OFF
COLUMN avg_byte_per_buf        HEADING 'Avg|Byte|Per|Buf'      ENTMAP OFF
COLUMN avg_in_connect_rate     HEADING 'Avg|In|Connect|Rate'   ENTMAP OFF
COLUMN avg_out_connect_rate    HEADING 'Avg|Out|Connect|Rate'  ENTMAP OFF
COLUMN avg_reconnect_rate      HEADING 'Avg|Reconnect|Rate'    ENTMAP OFF
 
SELECT name,
       avg_loop_rate,
       avg_event_rate,
       avg_events_per_loop,
       avg_msg_rate,
       avg_svr_buf_rate,
       avg_svr_byte_rate,
       avg_svr_byte_per_buf,
       avg_clt_buf_rate,
       avg_clt_byte_rate,
       avg_clt_byte_per_buf,
       avg_buf_rate,
       avg_byte_rate,
       avg_byte_per_buf,
       avg_in_connect_rate,
       avg_out_connect_rate,
       avg_reconnect_rate
  FROM v$dispatcher_rate
 ORDER BY name;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 08 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_08() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_08_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN protocol           HEADING 'Protocol'         ENTMAP OFF
COLUMN total_busy_rate    HEADING 'Total Busy Rate'  ENTMAP OFF
 

prompt  <b>Dispatcher busy rate</b>
 
SELECT
    a.network protocol
  , (SUM(a.BUSY) / (SUM(a.BUSY) + SUM(a.IDLE))) total_busy_rate
FROM
    v$dispatcher a
GROUP BY
    a.network;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 09 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_09() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_09_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |             - MTS DISPATCHER RESPONSE QUEUE WAIT STATS -                   |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="mts_dispatcher_response_queue_wait_stats"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● MTS Dispatcher Response Queue Wait Stats</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF

 
COLUMN type        HEADING 'Type'                         ENTMAP OFF
COLUMN avg_wait    HEADING 'Avg Wait Time Per Response'   ENTMAP OFF
 
SELECT a.type,
       DECODE(SUM(a.totalq),
              0,
              'NO RESPONSES',
              SUM(a.wait) / SUM(a.totalq) || ' HUNDREDTHS OF SECONDS') avg_wait
  FROM v$queue a
 WHERE a.type = 'DISPATCHER'
 GROUP BY a.type;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 10 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_10() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_10_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 
 

-- +----------------------------------------------------------------------------+

-- |                  - MTS SHARED SERVER WAIT STATISTICS -                     |

-- +----------------------------------------------------------------------------+
 

prompt  <a name="mts_shared_server_wait_statistics"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● MTS Shared Server Wait Statistics</b></font><hr align="left" width="450">
 
CLEAR COLUMNS COMPUTES
SET DEFINE ON

 
COLUMN avg_wait   HEADING 'Average Wait Time Per Request'  ENTMAP OFF
 
SELECT DECODE(a.totalq,
              0,
              'No Requests',
              a.wait / a.totalq || ' HUNDREDTHS OF SECONDS') avg_wait
  FROM v$queue a
 WHERE a.type = 'COMMON';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 11 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_11() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_11_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 
 
 


-- +============================================================================+

-- |                                                                            |

-- |                      <<<<<         >>>>>                   |

-- |                                                                            |

-- +============================================================================+
 
 


prompt  <a name="health_check_summary_info"></a>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b><u></u></b></font></center>
 
 

prompt  <a name="health_check_summary_info_details"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b></b></font><hr align="left" width="600">
 
CLEAR COLUMNS COMPUTES
SET DEFINE OFF
SET DEFINE ON
 

SELECT '<div align="center">' || rownuM || '</div>' ID,
       '<div align="center">' || WARING_LEVEL || '</div>' WARING_LEVEL,
       v.CHECK_TYPE,
       v.CHECK_MESSAGE,
       v.CHECK_MESSAGE_DETAIL_LINK
  FROM (select SUBSTR(health_check_results,
                      instr(health_check_results, '|', 1) + 1,
                      1) WARING_LEVEL,
               SUBSTR(health_check_results,
                      instr(health_check_results, '|', 1, 2) + 1,
                      INSTR(health_check_results, '|', 1, 3) -
                      instr(health_check_results, '|', 1, 2) - 1) CHECK_TYPE,
               SUBSTR(health_check_results,
                      INSTR(health_check_results, '|', 1, 3) + 1,
                      INSTR(health_check_results, '|', 1, 4) -
                      INSTR(health_check_results, '|', 1, 3) - 1) CHECK_MESSAGE,
               SUBSTR(health_check_results,
                      INSTR(health_check_results, '|', 1, 4) + 1) CHECK_MESSAGE_DETAIL_LINK
          from (select case
                         when (SELECT COUNT(1)
                                 FROM V$PARAMETER D
                                WHERE D.NAME = 'spfile'
                                  AND D.VALUE IS NOT NULL) = 0 then
                          (select 1 || '|' || 5 || '|' || 'Inspection Service Summary.' || '|' ||
                                  'spfilefile (creation strongly recommended)spfile' || '|' ||
                                  '<center>[<a class="noLink" href="#initialization_parameters"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end AS health_check_results
                  from dual
                UNION ALL
                select case
                         when (SELECT SUM(COUNTS)
                                 FROM (SELECT COUNT(1) COUNTS
                                         FROM CDB_DATA_FILES D
                                        WHERE D.ONLINE_STATUS = 'OFFLINE'
                                       UNION ALL
                                       SELECT COUNT(1)
                                         FROM CDB_TEMP_FILES D
                                        WHERE D.STATUS = 'OFFLINE')) > 0 then
                          (select 2 || '|' || 1 || '|' || 'Inspection Service Summary..' || '|' ||
                                  'OFFLINEhas datafiles in bad state; immediate fix recommended' || '|' ||
                                  '<center>[<a class="noLink" href="#data_files"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>Reference: Datafile Status</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT COUNT(1)
                                 FROM V$ASM_DISKGROUP DI
                                WHERE (DI.TOTAL_MB - DI.FREE_MB) / DI.TOTAL_MB >= 0.95) > 0 then
                          (select 3 || '|' || 3 || '|' || 'Inspection Service Summary.ASM' || '|' ||
                                  'ASM' || '|' ||
                                  '<center>[<a class="noLink" href="#asm_diskgroup"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:ASM</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT SUM(COUNTS)
                                 FROM (SELECT COUNT(1) COUNTS
                                         FROM CDB_SCHEDULER_JOB_LOG D
                                        WHERE D.OWNER NOT like '%SYS%'
                                          AND D.STATUS <> 'SUCCEEDED'
                                          AND D.LOG_DATE >= SYSDATE - 15
                                       UNION ALL
                                       SELECT COUNT(1)
                                         FROM CDB_JOBS D
                                        WHERE D.SCHEMA_USER NOT like '%SYS%'
                                          AND D.FAILURES > 0
                                          AND D.LAST_DATE >= SYSDATE - 15)) > 0 then
                          (select 4 || '|' || 5 || '|' || 'Inspection Service Summary.JOB' || '|' ||
                                  'Within the Past MonthJOB,JOB' || '|' ||
                                  '<center>[<a class="noLink" href="#jobs_info"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT count(1) FROM v$backup_set) < 2 then
                          (select 5 || '|' || 2 || '|' || 'Inspection.RMAN' || '|' ||
                                  'RMAN,' || '|' ||
                                  '<center>[<a class="noLink" href="#database_rmanbackinfo"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:RMAN</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (select count(*)
                                 from (select l.force_matching_signature,
                                              max(l.sql_id || l.child_number) max_sql_child,
                                              dense_rank() over(order by count(*) desc) ranking,
                                              count(*) counts
                                         from gv$sql l
                                        where l.force_matching_signature <> 0
                                          and l.parsing_schema_name  NOT IN ('SYS','SYSTEM','PUBLIC','MDSYS','DBSNMP','SCOTT','LHR','LHR2','DB_MONITOR','OUTLN','MGMT_VIEW','FLOWS_FILES','ORDSYS','EXFSYS','WMSYS','APPQOSSYS','APEX_030200','OWBSYS_AUDIT','ORDDATA','CTXSYS','ANONYMOUS','SYSMAN','XDB','ORDPLUGINS','OWBSYS','SI_INFORMTN_SCHEMA','OLAPSYS','ORACLE_OCM','XS$NULL','BI','PM','MDDATA','IX','SH','DIP','OE','APEX_PUBLIC_USER','HR','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','APEX_040200','DVSYS','LBACSYS','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','SYS$UMF','GGSYS','DBSFWUSER','DVF','GSMCATUSER','SYSBACKUP','REMOTE_SCHEDULER_AGENT','GSMUSER','SYSRAC','SYSKM','SYSDG')
                                        group by l.force_matching_signature
                                       having count(*) > 10)) > 0 then
                          (select 6 || '|' || 2 || '|' ||
                                  'Inspection.SQL.SQL' || '|' ||
                                  'SQLlibrarycache,' || '|' ||
                                  '<center>[<a class="noLink" href="#sql_no_bind"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>Reference: Unbound SQL StatementsSQL</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                
                UNION ALL
                select case
                         when (SELECT COUNT(*)
                                 FROM (SELECT AL.THREAD#,
                                              ADS.DEST_ID,
                                              ADS.DEST_NAME,
                                              MAX((SELECT ADS.TYPE || ' ' ||
                                                         AD.TARGET
                                                    FROM V$ARCHIVE_DEST AD
                                                   WHERE AD.DEST_ID =
                                                         ADS.DEST_ID)) TARGET,
                                              ADS.DATABASE_MODE,
                                              ADS.STATUS,
                                              ADS.ERROR,
                                              ADS.RECOVERY_MODE,
                                              ADS.DB_UNIQUE_NAME,
                                              ADS.DESTINATION,
                                              (SELECT MAX(SEQUENCE#)
                                                 FROM V$LOG NA
                                                WHERE NA.THREAD# = AL.THREAD#) CURRENT_SEQ#,
                                              MAX(SEQUENCE#) LAST_ARCHIVED,
                                              MAX(CASE
                                                    WHEN AL.APPLIED = 'YES' AND
                                                         ADS.TYPE <> 'LOCAL' THEN
                                                     AL.SEQUENCE#
                                                  END) APPLIED_SEQ#,
                                              '' APPLIED_SCN
                                         FROM (SELECT *
                                                 FROM V$ARCHIVED_LOG V
                                                WHERE V.RESETLOGS_CHANGE# =
                                                      (SELECT D.RESETLOGS_CHANGE#
                                                         FROM V$DATABASE D)) AL,
                                              V$ARCHIVE_DEST_STATUS ADS
                                        WHERE AL.DEST_ID(+) = ADS.DEST_ID
                                          AND ADS.STATUS != 'INACTIVE'
                                        GROUP BY AL.THREAD#,
                                                 ADS.DEST_ID,
                                                 ADS.DEST_NAME,
                                                 ADS.STATUS,
                                                 ADS.ERROR,
                                                 ADS.TYPE,
                                                 ADS.DATABASE_MODE,
                                                 ADS.RECOVERY_MODE,
                                                 ADS.DB_UNIQUE_NAME,
                                                 ADS.DESTINATION)
                                WHERE TARGET NOT LIKE '%LOCAL%'
                                  AND (ERROR IS NOT NULL OR STATUS <> 'VALID' OR
                                      CURRENT_SEQ# > APPLIED_SEQ# + 2)) > 0 then
                          (select 7 || '|' || 2 || '|' || 'Inspection.DG' || '|' ||
                                  'DG,ViewDGDetails' || '|' ||
                                  '<center>[<a class="noLink" href="#link_dginfo"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:DG</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                
                UNION ALL
                select case
                         when (SELECT COUNT(1)
                                 FROM CDB_OBJECTS
                                WHERE OWNER NOT IN ('PUBLIC')
                                  AND STATUS <> 'VALID') > 0 then
                          (select 8 || '|' || 4 || '|' || '.' || '|' ||
                                  ',' || '|' ||
                                  '<center>[<a class="noLink" href="#database_invalidobjects"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>Reference: Invalid Objects</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                
                UNION ALL
                select case
                         when (SELECT COUNT(1)
                                 FROM (SELECT ROUND((SUM(A.SPACE *
                                                         (SELECT VALUE
                                                            FROM V$PARAMETER
                                                           WHERE NAME =
                                                                 'db_block_size'))) / 1024 / 1024,
                                                    2) SIZE_M
                                         FROM CDB_RECYCLEBIN A)
                                WHERE SIZE_M > 1024) > 0 then
                          (select 9 || '|' || 4 || '|' || '..' || '|' ||
                                  '' || '|' ||
                                  '<center>[<a class="noLink" href="#dba_recycle_bin"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT COUNT(1)
                                 FROM CDB_HIST_ACTIVE_SESS_HISTORY D,
                                      CDB_USERS                    A
                                WHERE D.USER_ID = A.USER_ID
                                  AND D.CON_ID=A.CON_ID
                                  AND USERNAME NOT LIKE '%SYS%'
                                  AND D.EVENT LIKE 'enq: SQ%') > 0 then
                          (select 10 || '|' || 2 || '|' ||
                                  '..cacheless than20' || '|' ||
                                  'cacheless than20,enq: SQ - contention' || '|' ||
                                  '<center>[<a class="noLink" href="#sequence_cache_20"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>cacheless than20</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT COUNT(1)
                                 FROM gv$session A
                                WHERE A.STATUS IN ('INACTIVE')
                                  AND A.USERNAME IS NOT NULL
                                  AND A.USERNAME not in ('SYS')
                                  AND A.LAST_CALL_ET >= 60 * 60 * 10) > 0 then
                          (select 11 || '|' || 2 || '|' ||
                                  '..10' || '|' ||
                                  '10kill' || '|' ||
                                  '<center>[<a class="noLink" href="#long_nofanying"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:10</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (select count(*) from (SELECT g.inst_id,sum(pinhits) / sum(pins) FROM Gv$librarycache g group by g.inst_id having sum(pinhits) / sum(pins)<0.95)) >0 then
                          (select 12 || '|' || 2 || '|' || '.Memory Usage.' || '|' ||
                                  ' 95%,,or Adjust Database Parametersshared_pool_size' || '|' ||
                                  '<center>[<a class="noLink" href="#library_cache_ratiosss"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:librarycache </b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT count(1)
  FROM (SELECT TABLESPACE_NAME,d.CON_ID, SUM(BYTES) all_bytes
          FROM cdb_data_files d
         GROUP BY TABLESPACE_NAME,d.CON_ID) a,
       (SELECT TABLESPACE_NAME,d.CON_ID,SUM(BYTES) FREESIZ
          FROM cdb_free_space d
         GROUP BY TABLESPACE_NAME,d.CON_ID) b
 where a.TABLESPACE_NAME = b.TABLESPACE_NAME
 and a.con_id=b.con_id
 and round((a.all_bytes - b.FREESIZ) / a.all_bytes, 2) > 0.98) > 0 then
                          (select 13 || '|' || 1 || '|' ||
                                  'Inspection Service Summary..' || '|' ||
                                  'If tablespace usage exceeds98%,consider increasing tablespace size' || '|' ||
                                  '<center>[<a class="noLink" href="#tablespaces_info"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                UNION ALL
                select case
                         when (SELECT SUM(COUNTS)
                                 FROM (SELECT COUNT(1) COUNTS
                                         FROM CDB_AUTOTASK_CLIENT D
                                        WHERE CLIENT_NAME ='auto optimizer stats collection'
                                       UNION ALL
                                       SELECT COUNT(1)
                                         FROM (SELECT A.WINDOW_NAME,
                                                      TO_CHAR(WINDOW_NEXT_TIME,'YYYY-MM-DD HH24:MI:SS') WINDOW_NEXT_TIME,
                                                      WINDOW_ACTIVE,
                                                      AUTOTASK_STATUS,
                                                      OPTIMIZER_STATS,
                                                      SEGMENT_ADVISOR,
                                                      SQL_TUNE_ADVISOR,
                                                      B.REPEAT_INTERVAL,
                                                      B.DURATION,
                                                      B.ENABLED,
                                                      B.RESOURCE_PLAN
                                                 FROM CDB_AUTOTASK_WINDOW_CLIENTS A,
                                                      (SELECT T1.CON_ID, T1.WINDOW_NAME,
                                                              T1.REPEAT_INTERVAL,
                                                              T1.DURATION,
                                                              T1.ENABLED,
                                                              T1.RESOURCE_PLAN
                                                         FROM CDB_SCHEDULER_WINDOWS          T1,
                                                              CDB_SCHEDULER_WINGROUP_MEMBERS T2
                                                        WHERE T1.WINDOW_NAME=T2.WINDOW_NAME    
                                                          AND T1.CON_ID=T2.CON_ID
                                                          AND T2.WINDOW_GROUP_NAME IN
                                                              ('MAINTENANCE_WINDOW_GROUP',
                                                               'BSLN_MAINTAIN_STATS_SCHED')) B
                                                WHERE A.WINDOW_NAME = B.WINDOW_NAME AND A.CON_ID = B.CON_ID) AA
                                        WHERE AA.AUTOTASK_STATUS = 'ENABLED')) <> (SELECT count(*)*8 FROM v$containers a WHERE a.NAME<>'PDB$SEED'  AND A.OPEN_MODE='READ WRITE' ) then
                          (select 14 || '|' || 2 || '|' ||
                                  '..' || '|' ||
                                  ',' || '|' ||
                                  '<center>[<a class="noLink" href="#statics_gatherflag"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
                
                UNION ALL
                select case
                         when (SELECT COUNT(*)
                                 FROM v$diag_alert_ext T
                                WHERE T.MESSAGE_TEXT LIKE '%ORA-%'
                                  AND trim(t.COMPONENT_ID) = 'rdbms'
                                  and t.FILENAME LIKE '%' ||sys_context('USERENV', 'INSTANCE_NAME') || '%'
                                  AND t.ORIGINATING_TIMESTAMP >= sysdate - 7) > 0 then
                          (select 15 || '|' || 2 || '|' || '..' || '|' ||
                                  'ora,' || '|' ||
                                  '<center>[<a class="noLink" href="#link_alert_log"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
				  UNION ALL
                select case
                         when (SELECT COUNT(*) FROM v$pdbs a where a.OPEN_MODE in ('MOUNTED') or a.RESTRICTED='YES') > 0 then
                          (select 16 || '|' || 2 || '|' || '..PDB' || '|' ||
                                  'PDB' || '|' ||
                                  '<center>[<a class="noLink" href="#pdb_overview"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:PDB</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
				  UNION ALL 
                select case
                         when (SELECT COUNT(*) FROM V$CONTROLFILE a) < 2 then
                          (select 17 || '|' || 2 || '|' || 'Inspection Service Summary..Control File' || '|' ||
                                  'Control File,Control File' || '|' ||
                                  '<center>[<a class="noLink" href="#control_files"><font size=1 face="Courier New,Helvetica,sans-serif" color="#336699"><b>:Control File</b></font></a>]</center><p>' CHECK_MESSAGE_DETAIL_LINK
                             from dual)
                       end
                  from dual
				  )
         where SUBSTR(health_check_results,
                      instr(health_check_results, '|', 1) + 1,
                      1) is not null) V;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 12 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_12() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_12_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <center>[<a class="noLink" href="#directory">BACK</a>][<a class="noLink" href="#sqlscripts_errors"></a>]</center><p>
 
 
 

host echo AWR....


-------------------------------------------------------------------------------------------------------------------------

------------------------------   AWR  ------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------

set termout       off
set echo          off
set feedback      off
set verify        off
set wrap          on
set trimspool     on
set serveroutput  off
set escape        off
set sqlblanklines off

  


 
set linesize 4000 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 13 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_13() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_13_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set pagesize 0 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 14 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_14() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_14_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set newpage 1 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 15 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_15() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_15_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set feed off;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 16 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_16() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_16_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set heading off


prompt  <hr>

prompt  <hr>

prompt  <a name="awr_new_lastone_link"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● AWR </b></font><hr align="left" width="800">


prompt             


prompt             


prompt  <center>[<a class="noLink" href="#directory">BACK</a>][<a class="noLink" href="#awr_new_lastone">AWR</a>]</center><p>

host echo ASH....


-------------------------------------------------------------------------------------------------------------------------

------------------------------   ASH  ------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------

set termout       off
set echo          off
set feedback      off
set verify        off
set wrap          on
set trimspool     on
set serveroutput  off
set escape        off
set sqlblanklines off

  


 
set linesize 4000 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 17 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_17() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_17_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set pagesize 0 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 18 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_18() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_18_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set newpage 1 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 19 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_19() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_19_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set feed off;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 20 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_20() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_20_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set heading off


prompt  <hr>

prompt  <hr>

prompt  <a name="ASH_new_lastone"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● ASH </b></font><hr align="left" width="800">

 

prompt             

SELECT *
  FROM table(dbms_workload_repository.ash_report_html(&_dbid,
                                                      &_instance_number,
                                                      (SELECT a.end_interval_time
                                                          AND  a.INSTANCE_NUMBER =
                                                              &_instance_number),
                                                      (SELECT a.end_interval_time
                                                          AND  a.INSTANCE_NUMBER =
                                                              &_instance_number)));
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 21 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_21() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_21_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt             


prompt  <center>[<a class="noLink" href="#directory">BACK</a>] [<a class="noLink" href="#ash_lastone_info">ASH</a>]</center><p>

host echo SQL....


-------------------------------------------------------------------------------------------------------------------------

------------------------------   SQL  ------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------

set termout       off
set echo          off
set feedback      off
set verify        off
set wrap          on
set trimspool     on
set serveroutput  off
set escape        off
set sqlblanklines off

  


 
set linesize 4000 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 22 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_22() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_22_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set pagesize 0 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 23 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_23() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_23_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set newpage 1 ;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 24 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_24() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_24_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set feed off;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 25 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_25() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_25_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set heading off


prompt  <hr>

prompt  <hr>

prompt  <a name="sql_elasled_lastlongsqllink"></a>

prompt  <font size="+1" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b>● SQL </b></font><hr align="left" width="800">


prompt             


prompt             

prompt  <center>[<a class="noLink" href="#directory">BACK</a>] [<a class="noLink" href="#sql_elasled_lastlongsql">SQL</a>]</center><p>

host echo ....


-------------------------------------------------------------------------------------------------------------------------

------------------------------     ------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------

COLUMN date_time_end NEW_VALUE _date_time_end NOPRINT
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') date_time_end FROM dual;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 26 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_26() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_26_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size=+2 color=darkgreen><b></b></font><hr>

prompt  <center><font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#663300"><b>Inspection</b></font></center>


prompt 

prompt  <b><font face="Courier New"><font face="Courier New,Helvetica,sans-serif" color="#990000">NOTE</font>: :&_date_time_end </font> </b>

prompt 


prompt  <a name="html_bottom_link"></a>

prompt  <center>[<a class="noLink" href="#directory">BACK</a>]</center><p>
 


-- +----------------------------------------------------------------------------+

-- |                            - Error Checks in Report -                               |

-- +----------------------------------------------------------------------------+


prompt  <hr>

prompt  <hr>

set termout       off
set echo          off
set feedback      off
set heading       off
set verify        off
set wrap          on
set trimspool     on
set serveroutput  on
set escape        on
set sqlblanklines on
set ARRAYSIZE  500

set pagesize 50000
set linesize 32767
set numwidth 18
set long     2000000000 LONGCHUNKSIZE 100000

clear buffer computes columns
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24:mi:ss';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 27 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_27() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_27_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
set termout off

set heading on

head ' -
  <title>&_dbname1 Inspection</title> -
  <style type="text/css"> -
    body              {font:11px Courier New,Helvetica,sans-serif; color:black; background:White;} -
    p                 {font:11px Courier New,Helvetica,sans-serif; color:black; background:White;} -
    table,tr,td       {font:11px Courier New,Helvetica,sans-serif; color:Black; background:#FFFFCC; padding:0px 0px 0px 0px; margin:0px 0px 0px 0px;} -
    th                {font:bold 11px Courier New,Helvetica,sans-serif; color:White; background:#0066cc; padding:0px 0px 0px 0px;} -
    h1                {font:bold 12pt Courier New,Helvetica,Geneva,sans-serif; color:White; background-color:White; border-bottom:1px solid #cccc99; margin-top:0pt; margin-bottom:0pt; padding:0px 0px 0px 0px;} -
    h2                {font:bold 11pt Courier New,Helvetica,Geneva,sans-serif; color:White; background-color:White; margin-top:4pt; margin-bottom:0pt;} -
    a                 {font:11px Courier New,Helvetica,sans-serif; color:#663300; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.link            {font:11px Courier New,Helvetica,sans-serif; color:#663300; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.noLink          {font:11px Courier New,Helvetica,sans-serif; color:#663300; text-decoration: none; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.noLinkBlue      {font:11px Courier New,Helvetica,sans-serif; color:#0000ff; text-decoration: none; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.noLinkDarkBlue  {font:11px Courier New,Helvetica,sans-serif; color:#000099; text-decoration: none; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.noLinkRed       {font:11px Courier New,Helvetica,sans-serif; color:#ff0000; text-decoration: none; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -
    a.noLinkDarkRed   {font:11px Courier New,Helvetica,sans-serif; color:#990000; text-decoration: none; margin-top:0pt; margin-bottom:0pt; vertical-align:top;} -  
    a.info:hover {background:#eee;color:#000000; position:relative;} -
    a.info span {display: none; } -
    a.info:hover span {font-size:11px!important; color:#000000; display:block;position:absolute;top:30px;left:40px;width:150px;border:1px solid #ff0000; background:#FFFF00; padding:1px 1px;text-align:left;word-wrap: break-word; white-space: pre-wrap; white-space: -moz-pre-wrap} -
  </style>' -
body   'BGCOLOR="#C0C0C0"'



prompt  <a name="sqlscripts_errors"></a>

prompt  <font size="+2" face="Courier New,Helvetica,Geneva,sans-serif" color="#336699"><b><hr align="left" width="450">

prompt  <font size="1" face="Courier New,Helvetica,Geneva,sans-serif" color="#990000">NOTE: ,,</font>

CLEAR COLUMNS COMPUTES
SET DEFINE OFF
COLUMN username            FORMAT a10  HEADING 'username'   ENTMAP OFF
COLUMN timestamp   FORMAT a180    HEADING '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;timestamp&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'  ENTMAP OFF
SET DEFINE ON
SELECT d.username,
       to_char(d.timestamp,'YYYY-MM-DD HH24:MI:SS') timestamp,
       D.SCRIPT,
       d.identifier,
       D.MESSAGE,
       D.STATEMENT
  FROM  SPERRORLOG d
  WHERE identifier='LHR_DB_HEALTHCHECK';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 28 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_28() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_28_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
prompt  <font size="+0.5"><center>[<a class="noLink" href="#directory">BACK</a>][<a class="noLink" href="#health_check_summary_info_details"></a>]</center><p></font>


set errorlogging off
delete from sperrorlog where identifier='LHR_DB_HEALTHCHECK';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 29 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_29() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_29_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COMMIT;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 30 for section: prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_30() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_30_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SET TERMOUT ON



prompt  

prompt  Inspection(OS): &_reporttitle..html

prompt  Inspection!

exit
EXIT
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size
hc_section_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "prompt NOTE: If less than95%,,or Adjust Database Parametersshared_pool_size"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_01 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_02 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_03 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_04 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_05 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_06 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_07 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_08 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_09 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_10 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_11 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_12 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_13 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_14 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_15 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_16 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_17 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_18 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_19 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_20 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_21 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_22 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_23 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_24 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_25 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_26 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_27 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_28 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_29 "$db_name" "$scan" "$service" "$f"
  hc_q_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size_30 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: Cluster Nodes Status (GV$INSTANCE)
hc_q_cluster_nodes_status_gv_instance_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_cluster_nodes_status_gv_instance_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN inst_id FORMAT 99
COLUMN instance_name FORMAT A20
COLUMN host_name FORMAT A20
COLUMN status FORMAT A10
SELECT inst_id, instance_name, host_name, status FROM gv$instance;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): Cluster Nodes Status (GV$INSTANCE)
hc_section_cluster_nodes_status_gv_instance() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "Cluster Nodes Status (GV$INSTANCE)"
  hc_q_cluster_nodes_status_gv_instance_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: ASM Disk Group Usage (if using ASM)
hc_q_asm_disk_group_usage_if_using_asm_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_asm_disk_group_usage_if_using_asm_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN name FORMAT A20
COLUMN state FORMAT A10
COLUMN type FORMAT A10
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): ASM Disk Group Usage (if using ASM)
hc_section_asm_disk_group_usage_if_using_asm() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "ASM Disk Group Usage (if using ASM)"
  hc_q_asm_disk_group_usage_if_using_asm_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: RAC Interconnect Usage (GV$GES_BLOCKING_ENQUEUE)
hc_q_rac_interconnect_usage_gv_ges_blocking_enqueue_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_rac_interconnect_usage_gv_ges_blocking_enqueue_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT inst_id, resource_name, requesting_session_id, blocking_session_id
FROM gv$ges_blocking_enqueue;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): RAC Interconnect Usage (GV$GES_BLOCKING_ENQUEUE)
hc_section_rac_interconnect_usage_gv_ges_blocking_enqueue() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "RAC Interconnect Usage (GV$GES_BLOCKING_ENQUEUE)"
  hc_q_rac_interconnect_usage_gv_ges_blocking_enqueue_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: PDB Status (CDB$PDBS)
hc_q_pdb_status_cdb_pdbs_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_pdb_status_cdb_pdbs_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN pdb_name FORMAT A20
SELECT pdb_name, status FROM cdb_pdbs;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): PDB Status (CDB$PDBS)
hc_section_pdb_status_cdb_pdbs() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "PDB Status (CDB$PDBS)"
  hc_q_pdb_status_cdb_pdbs_01 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: PGA/SGA Summary per Instance
hc_q_pga_sga_summary_per_instance_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_pga_sga_summary_per_instance_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN name FORMAT A30
SELECT inst_id, name, value
FROM gv$pgastat
WHERE name IN ('aggregate PGA target parameter', 'total PGA allocated');
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Query 02 for section: PGA/SGA Summary per Instance
hc_q_pga_sga_summary_per_instance_02() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_pga_sga_summary_per_instance_02_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
SELECT inst_id, component, current_size/1024/1024 AS current_MB
FROM gv$sga_dynamic_components
WHERE current_size > 0;
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): PGA/SGA Summary per Instance
hc_section_pga_sga_summary_per_instance() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "PGA/SGA Summary per Instance"
  hc_q_pga_sga_summary_per_instance_01 "$db_name" "$scan" "$service" "$f"
  hc_q_pga_sga_summary_per_instance_02 "$db_name" "$scan" "$service" "$f"
}}

# Query 01 for section: Invalid Database Objects
hc_q_invalid_database_objects_01() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  local conn="${SYS_USER}/${SYS_PASSWORD}@${scan}/${service} as sysdba"
  local tmp="/tmp/hc_q_invalid_database_objects_01_$$_$(date +%s).sql"
  cat > "$tmp" <<'SQL'
SET PAGESIZE 1000
SET LINESIZE 200
SET VERIFY OFF FEEDBACK OFF HEADING ON
SET MARKUP HTML ON ENTMAP OFF PREFORMAT OFF
COLUMN owner FORMAT A15
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A15
COLUMN status FORMAT A10

SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE status = 'INVALID';
SQL
  "${ORACLE_HOME}/bin/sqlplus" -s "$conn" @"$tmp" >> "$f" 2>/dev/null
}}

# Section (exact label): Invalid Database Objects
hc_section_invalid_database_objects() {{
  local db_name="$1"; local scan="$2"; local service="$3"; local f="$4"
  hc_html_section "$f" "Invalid Database Objects"
  hc_q_invalid_database_objects_01 "$db_name" "$scan" "$service" "$f"
}}

################################################################################
# Orchestrator: perform_db_health_check
# Generates HTML report using section/individual query functions
################################################################################
perform_db_health_check() {
  local db_name="$1"; local scan="$2"; local service="$3"

  log_message "INFO" "HealthCheck (fine-grained inline): db={${db_name}} scan={${scan}} service={${service}}"

  if command -v test_db_connection >/dev/null 2>&1; then
    if ! test_db_connection "$scan" "$service"; then
      log_message "ERROR" "Cannot connect to $db_name at $scan/$service"
      echo "ERROR: Cannot connect to $db_name"
      return 1
    fi
  fi

  local ts="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "${REPORT_BASE_DIR}"
  local report_raw="${REPORT_BASE_DIR}/healthcheck_${db_name}_${ts}_raw.html"
  local report="${REPORT_BASE_DIR}/healthcheck_${db_name}_${ts}.html"

  hc_html_begin "$report_raw" "$db_name" "$scan" "$service" "$ts"
  hc_section_prompt_note1_session_information_for_health_check "$db_name" "$scan" "$service" "$report_raw"
  hc_section_prompt_note2_database_recycle_bin_status "$db_name" "$scan" "$service" "$report_raw"
  hc_section_prompt_note_do_not_modify_any_inspection_results "$db_name" "$scan" "$service" "$report_raw"
  hc_section_prompt_notes "$db_name" "$scan" "$service" "$report_raw"
  hc_section_prompt_note_that_statistics_gathering_is_global_for_the_database_and_is_persistent_across_instance_starts "$db_name" "$scan" "$service" "$report_raw"
  hc_section_prompt_note_if_less_than95_or_adjust_database_parametersshared_pool_size "$db_name" "$scan" "$service" "$report_raw"
  hc_section_cluster_nodes_status_gv_instance "$db_name" "$scan" "$service" "$report_raw"
  hc_section_asm_disk_group_usage_if_using_asm "$db_name" "$scan" "$service" "$report_raw"
  hc_section_rac_interconnect_usage_gv_ges_blocking_enqueue "$db_name" "$scan" "$service" "$report_raw"
  hc_section_pdb_status_cdb_pdbs "$db_name" "$scan" "$service" "$report_raw"
  hc_section_pga_sga_summary_per_instance "$db_name" "$scan" "$service" "$report_raw"
  hc_section_invalid_database_objects "$db_name" "$scan" "$service" "$report_raw"

  hc_html_end "$report_raw"

  # sanitize duplicate html tags, write final
  awk 'BEGIN{seen=0} /<html>/{ if (seen) next; seen=1 } {print $0}' "$report_raw" > "$report"

  if [[ -s "$report" ]]; then
    log_message "SUCCESS" "Health check report generated: $report"
    echo "Report: $report"
    return 0
  else
    log_message "ERROR" "Report generation failed"
    echo "ERROR: Report generation failed"
    return 1
  fi
}
