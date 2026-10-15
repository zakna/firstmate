#!/usr/bin/env bash
# Adversarial: a command that embeds the internal \u0001 marker before the password, in transcript and scrollback.
R=$1; T=$(mktemp -d); WT=$T/wt; mkdir -p $WT; ROOT=$T/claude; P=$ROOT/projects/$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p $P
jq -cn --arg wt "$WT" '{type:"assistant",cwd:$wt,message:{content:[{type:"tool_use",id:"m1",name:"Bash",input:{command:"mysql -p\u0001hunter2 db"}}]}}' > $P/s.jsonl
"$R" --harness claude --worktree "$WT" --since 1 --claude-root $ROOT </dev/null | tail -1 | od -c | head -3
printf 'mysql -p\001scrollpw db\n' > $T/cap
"$R" --harness codex --worktree "$WT" --scrollback $T/cap </dev/null | tail -1
rm -rf $T
