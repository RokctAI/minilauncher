# API Reference: tender-checklist

Source file: `tender/nextjs/templates/control/components/custom/tender-checklist.tsx`

## Whitelisted API Endpoints

### `function DeadlineChip({ closingDate }: { closingDate?: string | null })`

*No documentation provided (generation failed).*

### `function BidStatusSelect`

```typescript
function BidStatusSelect(
  { bidName, status, onChanged, }: { bidName: string; status: string;
      onChanged?: (status: string
)
```

*No documentation provided (generation failed).*

### `function TenderChecklist`

```typescript
function TenderChecklist({
  slug,
  closingDate,
  initialBid,
  }: { slug: string; closingDate?: string | null; initialBid: TenderBid | null;,
})
```

Interactive checklist for an entitled subscriber. Starts from either an
existing bid (with checklist rows) or an unclaimed state with a
"Track this tender" button that claims it.
