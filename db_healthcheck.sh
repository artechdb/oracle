SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL rac_alert_errors.html

PROMPT <h2>ORA- Errors from All RAC Instances (Last 24 Hours)</h2>

SELECT
    inst_id,
    TO_CHAR(originating_timestamp, 'DD.MM.YYYY HH24:MI:SS') AS message_time,
    host_id,
    adr_home,
    message_text
FROM
    TABLE(gv$(CURSOR(
        SELECT
            originating_timestamp,
            host_id,
            adr_home,
            message_text
        FROM
            v$diag_alert_ext
        WHERE
            originating_timestamp > SYSDATE - 1
            AND component_id = 'rdbms'
            AND message_text LIKE '%ORA-%'
    )))
ORDER BY
    originating_timestamp DESC;

SPOOL OFF;
SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL open_cursor_stats.html

PROMPT <h2>Open Cursor Statistics per RAC Instance</h2>

SELECT
    inst_id,
    TO_CHAR(execute_count, '999G999G999G999') AS "SQL Execution",
    TO_CHAR(parse_count, '999G999G999G999') AS "Parse Count",
    TO_CHAR(cursor_hits, '999G999G999G999') AS "Cursor Hits",
    ROUND((parse_count / NULLIF(execute_count, 0)) * 100, 2) AS "Parse % Total",
    ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) AS "Cursor Cache % Total",
    CASE
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 90 THEN 'OK'
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 80 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS status
FROM (
    SELECT
        inst_id,
        MAX(CASE WHEN name = 'execute count' THEN value END) AS execute_count,
        MAX(CASE WHEN name = 'parse count (total)' THEN value END) AS parse_count,
        MAX(CASE WHEN name = 'session cursor cache hits' THEN value END) AS cursor_hits
    FROM
        gv$sysstat
    WHERE
        name IN ('execute count', 'parse count (total)', 'session cursor cache hits')
    GROUP BY
        inst_id
)
ORDER BY
    inst_id;

SPOOL OFF;
##
SELECT
    inst_id,
    ROUND(COUNT(*) / (24 * 60 * 60), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time >= SYSDATE - 1
GROUP BY
    inst_id
ORDER BY
    inst_id;
SELECT
    inst_id,
    ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                      EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                      EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                      EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
         ), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time BETWEEN TO_DATE('2025-06-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
                    AND TO_DATE('2025-06-01 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
GROUP BY
    inst_id
ORDER BY
    inst_id;
