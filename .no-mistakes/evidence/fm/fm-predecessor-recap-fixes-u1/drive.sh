#!/usr/bin/env bash
# Drives fm-predecessor-recap.sh (given as $1) with scrollback and transcript fixtures.
R=$1; T=$(mktemp -d); WT=$T/wt; mkdir -p $WT
echo "### Scrollback (codex harness, --scrollback)"
printf '%s\n' '$ mysql -u root \\\\' '$ find . -print' '$ mysql \' '>   -pcontsecret1 db' '$ echo four \\\\\\\\' '$ ls' '$ mysql -h x \\\\\\' '  -pSIXeven db' '$ mysql -h y \\\' '  -pTHREEodd db' > $T/cap
echo "--- input:"; cat $T/cap; echo "--- output:"
"$R" --harness codex --worktree "$WT" --scrollback $T/cap </dev/null
echo; echo "### Claude transcript (claude harness)"
ROOT=$T/claude; P=$ROOT/projects/$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p $P
i=0
for cmd in 'mysql -p[redacted]hunter2 db' 'mysql -p[redacted] db' 'mysql -psecret; echo after' 'mysqldump -pbackup>dump.sql' 'mysql -pa1 | tee out & mysql -pb2 < in.sql' 'mysql -pq1&&echo ok' "mysql -p'quoted;pw' db" 'mysql -pplain db'; do
  i=$((i+1)); jq -cn --arg c "$cmd" --arg wt "$WT" --arg id t$i '{type:"assistant",cwd:$wt,message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'
  echo "input command $i: $cmd" >&2
done > $P/s.jsonl 2>$T/inputs
cat $T/inputs; echo "--- output:"
"$R" --harness claude --worktree "$WT" --since 1 --claude-root $ROOT --count 20 </dev/null
rm -rf $T
