#!/usr/bin/env bash
# Drives bin/fm-predecessor-recap.sh with a real Claude transcript and real terminal captures.
RECAP=$1; D=$(mktemp -d); WT=$D/wt; mkdir -p "$WT"
enc=$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g'); P=$D/claude/projects/$enc; mkdir -p "$P"
cmd() { jq -cn --arg c "$1" --arg id "$2" --arg wt "$WT" '{type:"assistant",cwd:$wt,timestamp:"2026-10-12T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'
        jq -cn --arg id "$2" --arg wt "$WT" '{type:"user",cwd:$wt,timestamp:"2026-10-12T00:00:01Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"ok"}]}}'; }
{ cmd 'mysql -uroot -phunter2 appdb' a1
  cmd 'mysqladmin -u root -pS3cr3t! status' a2
  cmd 'mysqldump -uroot -pdumppw db > db.sql' a3
  cmd 'find . -name "*.sh" -print' a4
  cmd 'git add -p; ls -p; grep -P "x+" f; tar -pxf a.tar; mkdir -p out' a5
  cmd 'mysql --password x -p y' a6
} > "$P/s1.jsonl"
echo "=== harness=claude transcript ==="
"$RECAP" --harness claude --worktree "$WT" --claude-root "$D/claude" --since 1 --count 20 </dev/null
printf '%s\n' '$ mysql -uroot -pcap1pass db' '• Ran mysql -uroot -psecretA db' 'user@host:~/x$ mysql -psecret3' '❯ mysql -psecret4' '$ mysql \' '>   -u root \' '>   -pcontpw db' '$ git add -p' 'diff --git a/x b/x' '$ find . -print' './a' '$ ls -p' 'src/' > "$D/cap"
echo "=== harness=codex scrollback ==="
"$RECAP" --harness codex --worktree "$WT" --scrollback "$D/cap" </dev/null
rm -rf "$D"
