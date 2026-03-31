-- ============================================================
-- QUICK QUERIES FOR JANK DEBUGGING
-- Use with: ./query_trace.sh <trace_file> "$(cat quick_queries.sql)"
-- Or copy individual queries to use with query_trace.sh
-- ============================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │ 1. ALL JANKY FRAMES — sorted by severity               │
-- │    Change LIKE '%settings%' to your target app          │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     a.name as frame_id,
--     a.dur / 1000000 as dur_ms,
--     a.jank_type,
--     a.jank_tag,
--     a.present_type
-- FROM actual_frame_timeline_slice a
-- JOIN process_track pt ON a.track_id = pt.id
-- JOIN process p ON pt.upid = p.upid
-- WHERE p.name LIKE '%settings%'
--   AND a.jank_type != 'None'
-- ORDER BY a.dur DESC


-- ┌─────────────────────────────────────────────────────────┐
-- │ 2. MAIN THREAD CALL STACK during a specific time range  │
-- │    Get the timestamp (ts) from janky frame details      │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     s.ts,
--     s.dur / 1000000.0 as dur_ms,
--     s.name,
--     s.depth
-- FROM slice s
-- JOIN thread_track tt ON s.track_id = tt.id
-- JOIN thread t ON tt.utid = t.utid
-- WHERE t.tid = <MAIN_THREAD_TID>
--   AND s.ts >= <START_TS> AND s.ts <= <END_TS>
--   AND s.dur > 500000
-- ORDER BY s.ts


-- ┌─────────────────────────────────────────────────────────┐
-- │ 3. WHAT WAS BLOCKING A THREAD (scheduling states)       │
-- │    Shows Running/Sleeping/Blocked/Runnable states       │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     ts,
--     dur / 1000.0 as dur_us,
--     CASE state
--         WHEN 'R' THEN 'Runnable (waiting for CPU)'
--         WHEN 'R+' THEN 'Runnable (preempted by higher-prio)'
--         WHEN 'S' THEN 'Sleeping (waiting for event/lock)'
--         WHEN 'D' THEN 'Uninterruptible Sleep (disk I/O)'
--         WHEN 'T' THEN 'Stopped'
--         ELSE state
--     END as state_desc,
--     blocked_function,
--     io_wait
-- FROM thread_state
-- WHERE utid = (SELECT utid FROM thread WHERE tid = <TID> LIMIT 1)
--   AND ts >= <START_TS> AND ts <= <END_TS>
-- ORDER BY ts


-- ┌─────────────────────────────────────────────────────────┐
-- │ 4. BINDER CALL TRACE — follow a binder call from       │
-- │    client to server and back                            │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     s.ts,
--     s.dur / 1000000.0 as dur_ms,
--     s.name,
--     t.name as thread,
--     p.name as process,
--     s.depth
-- FROM slice s
-- JOIN thread_track tt ON s.track_id = tt.id
-- JOIN thread t ON tt.utid = t.utid
-- JOIN process p ON t.upid = p.upid
-- WHERE (s.name = 'binder transaction' OR s.name = 'binder reply')
--   AND s.ts >= <START_TS> AND s.ts <= <END_TS>
--   AND s.dur > 1000000
-- ORDER BY s.ts


-- ┌─────────────────────────────────────────────────────────┐
-- │ 5. FIND ALL PROCESSES — get PIDs/TIDs for your queries  │
-- └─────────────────────────────────────────────────────────┘
-- SELECT pid, name FROM process WHERE name LIKE '%settings%'
-- SELECT tid, name, is_main_thread FROM thread
--   WHERE upid = (SELECT upid FROM process WHERE name LIKE '%settings%' LIMIT 1)


-- ┌─────────────────────────────────────────────────────────┐
-- │ 6. FRAME-BY-FRAME TIMELINE — see expected vs actual     │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     e.name as frame_id,
--     e.ts as expected_start,
--     e.dur / 1000000.0 as expected_ms,
--     a.dur / 1000000.0 as actual_ms,
--     a.jank_type,
--     a.on_time_finish
-- FROM expected_frame_timeline_slice e
-- JOIN actual_frame_timeline_slice a ON e.name = a.name AND e.upid = a.upid
-- JOIN process_track pt ON a.track_id = pt.id
-- JOIN process p ON pt.upid = p.upid
-- WHERE p.name LIKE '%settings%'
-- ORDER BY e.ts
-- LIMIT 100


-- ┌─────────────────────────────────────────────────────────┐
-- │ 7. SURFACEFLINGER WORK — check if SF is the bottleneck  │
-- └─────────────────────────────────────────────────────────┘
-- SELECT
--     s.ts,
--     s.dur / 1000000.0 as dur_ms,
--     s.name
-- FROM slice s
-- JOIN thread_track tt ON s.track_id = tt.id
-- JOIN thread t ON tt.utid = t.utid
-- JOIN process p ON t.upid = p.upid
-- WHERE p.name = '/system/bin/surfaceflinger'
--   AND s.dur > 2000000
--   AND s.depth = 0
-- ORDER BY s.dur DESC
-- LIMIT 20
