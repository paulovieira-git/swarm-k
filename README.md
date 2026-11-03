# swram-k

## 1. Overview



The SWARM-API connects the main components of the SWARM-KIT:



- \*\*SWARM-C:\*\* A structured corpus of collective intelligence episodes, including agents, interactions, communication protocols, reasoning processes, decisions, outcomes and experimental scenarios.

- \*\*SWARM-M:\*\* A collection of metrics designed to characterise and evaluate swarm systems and collective intelligence.

- \*\*SWARM-API:\*\* A RESTful interface providing programmatic access to the corpus and metrics.



### Architecture



```mermaid

flowchart TD

&#x20;   A\[External Applications]

&#x20;   B\[SWARM-API]

&#x20;   C\[SWARM-C]

&#x20;   D\[SWARM-M]



&#x20;   A --> B

&#x20;   B --> C

&#x20;   B --> D

&#x20;   C --> D



&#x20;   D --> E\[Evaluation Results]

&#x20;   C --> F\[Collective Intelligence Data]



&#x20;   E --> B

&#x20;   F --> B

&#x20;   B --> A

```

