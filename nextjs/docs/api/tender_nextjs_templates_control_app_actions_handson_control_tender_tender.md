# API Reference: tender

Source file: `tender/nextjs/templates/control/app/actions/handson/control/tender/tender.ts`

## Whitelisted API Endpoints

### `function getTenderControlSettings()`

*No documentation provided (generation failed).*

### `function getGeneratedTenderTasks()`

*No documentation provided (generation failed).*

### `function getTenderWorkflowTasks()`

*No documentation provided (generation failed).*

### `function getTenderWorkflowTemplates()`

*No documentation provided (generation failed).*

### `function getIntelligentTaskSets()`

*No documentation provided (generation failed).*

### `function updateTenderControlSettings(data: any)`

*No documentation provided (generation failed).*

### `function createGeneratedTenderTask`

```typescript
function createGeneratedTenderTask(
  taskSet: string,
  data: { subject: string; due_date_offset_days: number }
)
```

*No documentation provided (generation failed).*

### `function updateGeneratedTenderTask`

```typescript
function updateGeneratedTenderTask(taskSet: string, rowName: string, data: any)
```

*No documentation provided (generation failed).*

### `function deleteGeneratedTenderTask(taskSet: string, rowName: string)`

*No documentation provided (generation failed).*

### `function createTenderWorkflowTask`

```typescript
function createTenderWorkflowTask(
  template: string,
  data: { subject: string; due_date_offset_days: number }
)
```

*No documentation provided (generation failed).*

### `function updateTenderWorkflowTask`

```typescript
function updateTenderWorkflowTask(template: string, rowName: string, data: any)
```

*No documentation provided (generation failed).*

### `function deleteTenderWorkflowTask(template: string, rowName: string)`

*No documentation provided (generation failed).*

### `function createTenderWorkflowTemplate(data: any)`

*No documentation provided (generation failed).*

### `function updateTenderWorkflowTemplate(name: string, data: any)`

*No documentation provided (generation failed).*

### `function deleteTenderWorkflowTemplate(name: string)`

*No documentation provided (generation failed).*

### `function createIntelligentTaskSet(data: any)`

*No documentation provided (generation failed).*

### `function updateIntelligentTaskSet(name: string, data: any)`

*No documentation provided (generation failed).*

### `function deleteIntelligentTaskSet(name: string)`

*No documentation provided (generation failed).*
