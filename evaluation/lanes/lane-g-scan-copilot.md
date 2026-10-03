# lane-g — scan copilot (#272)

Protocol revision: **v1** (initial scaffold)

Compare: (1) existing deterministic guidance; (2) improved deterministic priority/rules + localized copy; (3) fresh task-scoped Foundation Models suggestion.

Metrics: expected allowed-action agreement; structured-output validity; hallucinated IDs; deterministic validator rejection rate; accepted unsafe movement actions (must be zero); accepted inappropriate completion actions (must be zero); repetition/noise; operator task time/movement; context/token overflow; locale/model-unavailable fallback; latency/resource cost.

If deterministic guidance performs equivalently, do not ship the LLM path.
