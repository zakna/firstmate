# Targeted test evidence: firstmate skill review rule

Base: `23f572abb3b20f189c5ca3884557d97a57b477f5`
Target: `8bf26522834af2654c2e9ae9870eb235976eb3bf5`

The focused repository contract test completed successfully:

```text
$ bash tests/fm-nm-test-contract.test.sh
ok - no-mistakes does not configure commands.test
```

A normalized Ruby YAML load of `.no-mistakes.yaml` also completed successfully. It verified that the `review.path_instructions` value has the two expected one-level paths (`.agents/skills/*/SKILL.md` and `skills/*/SKILL.md`), identical non-empty instructions, and the required forge, delivery, worker-harness, runtime-backend, multi-project-home, repeated-validation, and branch-reuse variant families.

The end-to-end scenarios remain untested in this assigned phase. Their consumer is the trusted default-branch no-mistakes Review step; starting or controlling another pipeline is forbidden by the phase boundary, and the feature branch cannot self-authorize its own Review configuration. A post-merge disposable skill-file PR through the normal Review step is required for live prompt-delivery and path-matcher evidence.
