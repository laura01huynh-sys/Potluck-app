# Smart Ingredient Entry System - User Flow Guide

## Screen 1: Entry Gate (AddIngredientScreen)

### Visual Layout
```
┌─────────────────────────────────────────┐
│                                         │
│   Add Items to Your Pantry              │
│   Choose how you would like to add items│
│                                         │
│   ┌───────────────────────────────────┐ │
│   │                                   │ │
│   │         📷  Scan Fridge           │ │
│   │            Take a Photo            │ │
│   │                                   │ │
│   └───────────────────────────────────┘ │
│                                         │
│   ┌───────────────────────────────────┐ │
│   │                                   │ │
│   │        🖼️  Upload Image            │ │
│   │           From Gallery             │ │
│   │                                   │ │
│   └───────────────────────────────────┘ │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │ ℹ️  Our AI will automatically    │   │
│   │    detect your items and group  │   │
│   │    them by department           │   │
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### Features
- Large rounded buttons with clear icons
- Descriptive text under each button
- Informational banner about AI capabilities
- Centered, spacious layout

---

## Screen 2: Confirmation (ConfirmDetectedItemsScreen)

### Visual Layout - Successful Detection

```
┌─────────────────────────────────────────┐
│ ← Confirm Items                         │
├─────────────────────────────────────────┤
│ PRODUCE                                 │
│ ┌──────────┐  ┌──────────┐              │
│ │ Garlic (2)│  │ Tomatoes (3)│          │
│ └──────────┘  └──────────┘              │
│                                         │
│ DAIRY & REFRIGERATED                    │
│ ┌──────────┐  ┌──────────┐              │
│ │  Milk (1) │  │ Cheese (1)│            │
│ └──────────┘  └──────────┘              │
│                                         │
│ PANTRY ESSENTIALS                       │
│ ┌──────────┐  ┌──────────┐              │
│ │ Pasta (1) │  │Olive Oil (1)│          │
│ └──────────┘  └──────────┘              │
│                                         │
│ [           + Add More Ingredients    ] │
│                                         │
├─────────────────────────────────────────┤
│     [  Confirm & Save (7 items)  ]      │
└─────────────────────────────────────────┘
```

### Interaction Flow

1. **Tapping a Chip**
   ```
   User taps "Garlic (2)" chip
            ↓
   Bottom sheet appears with:
   - Name: "Garlic"
   - Quantity controls: [−] 2 [+]
   - Unit: "units"
   - Buttons: [Cancel] [Save]
            ↓
   User adjusts quantity
            ↓
   Taps [Save] → Chip updates with new quantity
   ```

2. **Adding Manual Item**
   ```
   User taps FAB (+)
            ↓
   Modal bottom sheet appears with:
   - Text field: "Ingredient Name"
   - Dropdown: "Category" (7 options)
   - Dropdown: "Unit" (units, grams, etc.)
   - Buttons: [Cancel] [Add]
            ↓
   User fills in and taps [Add]
            ↓
   Item added to categorized list
   ```

3. **Confirming All Items**
   ```
   User reviews all items and quantities
            ↓
   Taps "Confirm & Save (7 items)" button
            ↓
   Items saved to PantryProvider
            ↓
   Navigation pops back to Pantry screen
            ↓
   Success SnackBar: "Added 7 items to pantry"
   ```

---

## Category Organization

The 7 categories appear in this order:

1. **Produce** 🥬
   - Vegetables, fruits, fresh herbs
   - Default category for uncertain items

2. **Dairy & Refrigerated** 🥛
   - Milk, cheese, yogurt, butter, eggs
   - Refrigerated items

3. **Meat & Seafood** 🥩
   - Chicken, beef, fish, seafood
   - Requires refrigeration

4. **Pantry Essentials** 🥫
   - Oils, vinegars, grains, pasta
   - Shelf-stable staples

5. **Spices & Seasonings** 🧂
   - Salt, pepper, herbs, spice blends
   - Flavor enhancers

6. **Baking** 🧁
   - Flour, sugar, baking powder, chocolate
   - Baking-specific items

7. **Frozen** ❄️
   - Frozen vegetables, meats, ice cream
   - Freezer items

---

## Empty State Handling

```
┌─────────────────────────────────────────┐
│ ← Confirm Items                         │
├─────────────────────────────────────────┤
│                                         │
│              ⓘ                          │
│     No items detected in the image      │
│                                         │
│   Try a different image or add items   │
│              manually                  │
│                                         │
│ [           + Add More Ingredients    ] │
│                                         │
├─────────────────────────────────────────┤
│  [  Confirm & Save (disabled)  ]        │
└─────────────────────────────────────────┘
```

- "Confirm & Save" button is **disabled** when empty
- User can only proceed after adding at least one item
- FAB always available for manual entry

---

## Loading State

```
┌─────────────────────────────────────────┐
│ ← Processing Image                      │
├─────────────────────────────────────────┤
│                                         │
│         ↻  (spinning circle)           │
│     Detecting ingredients...            │
│                                         │
│          (appears 2-5 seconds)          │
│                                         │
└─────────────────────────────────────────┘
```

---

## Data Cleaning Example

**Raw AI Output:**
```
"Garlic (fresh, minced)"
"Tomatoes (cherry, vine-ripe)"
"Pasta (dried, long noodles)"
```

**After Regex Clean (RegExp r'\(.*?\)' removed):**
```
"Garlic"
"Tomatoes"
"Pasta"
```

---

## Navigation Stack

```
MainNavigation (Tab System)
    │
    └─→ Tab 2: AddIngredientScreen (Entry Gate)
           │
           ├─→ [Camera Button] → ImagePicker → Process
           │                          │
           │                          ↓
           │              ConfirmDetectedItemsScreen
           │                    (Full Screen)
           │                          │
           │                          ├─→ [Chip] → Bottom Sheet (Qty)
           │                          ├─→ [FAB] → Modal (Manual)
           │                          └─→ [Confirm] → Save & Pop
           │                                 │
           │                                 ↓
           │                        Back to Tab 2
           │                                 │
           │                                 ↓
           │                        Back to Pantry
           │
           └─→ [Gallery Button] → ImagePicker → Process → (same flow)
```

---

## Success Flow

1. User presses Tab 2 (Add) → AddIngredientScreen displays
2. User selects Camera or Gallery → Image selected
3. App shows loading spinner → AI processes for 2-5 seconds
4. ConfirmDetectedItemsScreen displays with categorized items
5. User reviews and adjusts quantities as needed
6. User adds any manual items via FAB
7. User taps "Confirm & Save (X items)"
8. Items saved to PantryProvider
9. Navigation pops back 2 screens
10. Success notification: "Added X items to pantry"
11. Items appear in Pantry screen

---

## Error Recovery

### Image Selection Fails
```
Error: "Error selecting image: [error message]"
       ↓
User dismisses SnackBar
       ↓
Back at AddIngredientScreen
       ↓
User tries again with different image source
```

### Detection Fails
```
Spinner shows "Detecting ingredients..."
       ↓
No items detected (empty list)
       ↓
ConfirmDetectedItemsScreen shows empty state
       ↓
User can add items manually via FAB
       ↓
User can go back and try different image
```

---

## Quantity Adjustment Detail

```
┌─────────────────────────────────────────┐
│                                         │
│  Garlic                                 │
│                                         │
│     [−] 2 [+]                          │
│         units                           │
│                                         │
│  [Cancel] [Save]                       │
│                                         │
└─────────────────────────────────────────┘
```

- **Minus button** (−): Decreases quantity, disabled at 0
- **Display**: Current quantity with unit name
- **Plus button** (+): Increases quantity without limit
- **Units** show type (units, grams, cloves, boxes, etc.)

---

## Color Reference

| Element | Color | Hex Code |
|---------|-------|----------|
| Primary Text | Deep Forest Green | #335D50 |
| Accent/Chips | Sage Green | #87A96B |
| Info Banner | Muted Gold | #C3B362 |
| Background | Bone Creame | #EFE5CB |
| Secondary Text | Soft Slate Gray | #4F6D7A |
| Borders | Sage Green (40% opacity) | #87A96B66 |
| Buttons | Deep Forest Green | #335D50 |

