# Text model matrix

| Task | 0.5B | 1.5B | 3B |
| --- | ---: | ---: | ---: |
| Routing | 20/31 | 27/31 | 29/31 |
| Conversation | 10/12 | 11/12 | 12/12 |
| Tool narration · development | 4/6 | 5/6 | 6/6 |
| Tool narration · holdout | 7/10 | 9/10 | 8/10 |
| Titles | 4/5 | 4/5 | 3/5 |
| Visit summary · development | 7/35 | 23/35 | 28/35 |
| Visit summary · holdout | 4/20 | 11/20 | 12/20 |

Counts are engineering-case agreement, not clinical accuracy. The primary chat rows use Standard effort and greedy sampling. Summary rows use focused model passes with source validation and no missing-fact recovery. See [results and limitations](results.md) for effort, temperature, fact counts and provenance.
