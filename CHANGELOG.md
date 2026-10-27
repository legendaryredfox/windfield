# Changelog

## unreleased

### Baseline performance (before the foundations work)

LÖVE 11.5 under xvfb, median of 3 runs, `sh tests/bench/run.sh --table`. Run to run noise is roughly 20 percent on the create row.

| scenario | unit | raw love.physics | windfield | windfield + polling enter() |
| --- | --- | --- | --- | --- |
| create time | ms per 2000 | 4.903 | 95.859 | 59.411 |
| create memory | KB per collider | 0.071 | 12.762 | 12.730 |
| idle time | ms per update | 0.180 | 4.945 | 5.143 |
| idle garbage | KB per update | 0.000 | 531.695 | 531.695 |
| pile time | ms per update | 1.420 | 9.912 | 9.871 |
| pile garbage | KB per update | 0.000 | 122.778 | 127.141 |
| query time | ms per 2000 rect queries | 6.456 | 469.119 | 418.421 |
| ray time | ms per 2000 rays | 6.152 | 27.060 | 40.078 |
| churn time | ms per frame (300 create + 300 destroy) | 0.906 | 10.237 | 9.373 |
| churn garbage | KB per frame | 60.320 | 4320.423 | 4320.487 |
| movers time | ms per frame (300 movers, 300 obstacles) | 0.241 | 1.871 | n/a |
| movers garbage | KB per frame | 0.000 | 165.884 | n/a |
