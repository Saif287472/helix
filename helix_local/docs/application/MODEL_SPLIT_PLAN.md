# Model Split Plan

Status: Stage 5 foundation.

`lib/domain/models.dart` remains the compatibility source during early Stage 5.
The target is to split it by bounded context and add explicit mappers.

## Target Contexts

- `domain/peer`
- `domain/conversation`
- `domain/session`
- `domain/transfer`
- `domain/group`
- `domain/call`
- `domain/trust`

## Mapper Rules

- Protocol DTO to domain entity.
- Database row to and from domain entity.
- Domain entity to presentation view model.
- No class should serve as protocol DTO, database row, domain entity, and UI
  view model at the same time.

## First Moves

1. Extract peer value objects.
2. Extract conversation/message entities.
3. Extract transfer entities.
4. Extract group entities after election engine is isolated.
5. Add mapper tests with each extraction.
