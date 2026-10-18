116:Before adding a helper, search for an existing one and name the one you reused, or the search that found none, as answer (d) of your landing note.
117-Before the `done:` line that finishes this task - the ready report - write `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.1Hatba/data/t-local-only/landing-note.md` with four short answers:
118-- (a) what this change made harder to change next;
119-- (b) the one structure-only tidy you would do next, under about one hour and with no behaviour change, naming its files, or `none`;
120-- (c) one fact you needed that this brief or the project's `AGENTS.md` did not give you, or `none`.
121-- (d) the existing helper you reused, or the search that found none.
122-That note is task material outside your worktree: never commit it.
123-When this task fixes a bug, first add a test that reproduces the bug and fails, and commit it on its own before any fix; then fix the code, not the test.
124-   Never edit, weaken, skip, or delete that test to make it pass; if the test itself turns out to be wrong, append `blocked [at=<epoch>]: {why the bug test is wrong}` and stop instead of changing it.
