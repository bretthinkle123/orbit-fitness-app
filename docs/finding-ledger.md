# Finding ledger (U-10)

Every escaped finding gets exactly one decision. A row's `action` MUST be one of:
`new efficacy question` / `new planted eval defect` / `new deterministic check` /
`accepted:<reason>`. An escape with no decision is itself a defect.

Append a row for every verifier-CONFIRMED /code-review finding the human defers at
diff approval, and for any production incident later triaged (see
pipeline-orchestration step 7).

| # | Finding | Class | Escaped because | Action |
|---|---------|-------|-----------------|--------|
