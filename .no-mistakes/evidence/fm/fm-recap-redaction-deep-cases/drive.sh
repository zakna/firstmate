#!/usr/bin/env bash
# drive.sh <recap-script> <tmpdir>: builds a real Claude transcript and runs the recap CLI.
set -u
R=$1; D=$2/case; rm -rf "$D"; mkdir -p "$D/wt"
enc=$(printf '%s' "$D/wt" | sed 's/[^A-Za-z0-9]/-/g'); P="$D/claude/projects/$enc"; mkdir -p "$P"
deep='MYSQL_PASSWORD='; for i in $(seq 30); do deep="$deep\$(echo "; done; deep="${deep}dna dnb"; for i in $(seq 30); do deep="$deep dnc$i)"; done; deep="$deep mysql db"
cmds=(
 "$deep"
 'mysql --password=$(cat <(echo psa psb)) db && API_TOKEN=$(tee >(cat psc psd)) run'
 'API_TOKEN=`cat bka bkb``cat bkc bkd` run && mysql -p `cat bke``cat bkf bkg` db'
 $'mysql -p $(cat \\\n  ena enb) db && PASSWORD=`cat \\\n  enc end1` run'
 'PASSWORD=${X:-gpa gpb} run && PASSWORDS=(gpc gpd gpe) go'
 'TOKEN=$(echo "a)b" ) after && SECRET=$(echo $(echo $(echo zz1 zz2))) tail'
)
texts=(
 'I set `API_KEY=foo` in the env, then ran `make test` and it passed.'
 'Run `export TOKEN=$(cat ~/.tok)` first, then run `make test` and it passes.'
 'Set `API_KEY="abc"` in .env, then run `make` to build it all.'
)
{ n=0; for c in "${cmds[@]}"; do n=$((n+1))
  jq -cn --arg cwd "$D/wt" --arg c "$c" --arg id "c$n" '{type:"assistant",cwd:$cwd,isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'
  jq -cn --arg cwd "$D/wt" --arg id "c$n" '{type:"user",cwd:$cwd,isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"ok"}]}}'
 done
 for x in "${texts[@]}"; do jq -cn --arg cwd "$D/wt" --arg x "$x" '{type:"assistant",cwd:$cwd,isSidechain:false,message:{role:"assistant",content:[{type:"text",text:$x}]}}'; done
} > "$P/s1.jsonl"
"$R" --harness claude --worktree "$D/wt" --claude-root "$D/claude" --since 1 --count 40 </dev/null
echo "----- scrollback path (harness=codex) -----"
printf '%s\n' "${cmds[@]}" > "$D/scroll.txt"
"$R" --harness codex --worktree "$D/wt" --scrollback "$D/scroll.txt" </dev/null
