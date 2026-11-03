SWARM-K JSON Database — illustrative starter dataset

Each .json file is a logical collection containing an array of JSON documents. IDs and sample measurements are illustrative, not validated scientific metric definitions. Timestamps use ISO 8601 UTC. Keep IDs stable and validate incoming documents through the API.

[! NO IMAGE](./images/mermaid-diagram.png)

The logic is as follows:
- A swarm can have multiple agents.
- A swarm can execute multiple episodes.
- An episode can contain multiple interactions.
- An episode can produce multiple decisions.
- An episode can be evaluated using multiple metrics.
- A metric definition can be used across many episodes.
- An experiment can group together multiple episodes and swarms.
