# Resource Data Pipeline

```mermaid
# Resource Data Pipeline

The project uses a data-driven approach where gameplay logic is decoupled from data.

```mermaid
graph TD
    A[BattlerStats.tres] --> B[AllyPartyMember.tres]
    B --> C[PartyData.tres]
    D[EnemyStats.tres] --> E[Battler Scene]
    F[CardData.tres] --> G[DeckResource.tres]
    G --> B
    H[EnemyAttackConfig.tres] --> D
    I[Item.tres] --> J[Inventory System]
```
```