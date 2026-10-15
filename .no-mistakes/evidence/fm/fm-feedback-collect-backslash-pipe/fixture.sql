CREATE TABLE repos (id TEXT PRIMARY KEY, upstream_url TEXT);
CREATE TABLE runs (id TEXT PRIMARY KEY, repo_id TEXT, branch TEXT, status TEXT, pr_url TEXT, pr_state TEXT, pr_state_observed_at INTEGER, created_at INTEGER, updated_at INTEGER);
CREATE TABLE step_results (id TEXT PRIMARY KEY, run_id TEXT, step_name TEXT, status TEXT, approval_reason TEXT, override_reason TEXT, skip_reason TEXT, completed_at INTEGER);
CREATE TABLE step_rounds (id TEXT PRIMARY KEY, step_result_id TEXT, round INTEGER, trigger_type TEXT, selection_source TEXT, selected_finding_ids TEXT, findings_json TEXT, user_findings_json TEXT, created_at INTEGER);
INSERT INTO repos VALUES ('r1','https://github.com/o/app.git');
INSERT INTO runs VALUES ('landed-1','r1','fm/a','cancelled',NULL,'none',NULL,1789984800,1789984800);
INSERT INTO step_results VALUES ('s1','landed-1','review','completed',NULL,NULL,NULL,1789984800);
INSERT INTO step_rounds VALUES ('rd1','s1',1,'initial','user_declined','[]',
 '{"findings":[{"id":"A","severity":"warning","file":"a\\|b.md","description":"x"},{"id":"B","severity":"warning","file":"c|d.md","description":"x"},{"id":"C","severity":"warning","file":"e\\f.md","description":"x"},{"id":"D","severity":"warning","file":"g\\\\|h.md","description":"x"},{"id":"E","severity":"warning","file":"trail\\","description":"x"}]}','{}',1789984800);
