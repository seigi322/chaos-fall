# Jokers Chaos - Project Analysis

## Project Overview
**Jokers Chaos** is a Godot 4.5 game that combines poker mechanics with a chaos management system. Players spin cards on a 5×4 grid, form poker hands in rows, and manage increasing chaos levels while collecting powerful joker cards.

## Core Architecture

### Main Systems

#### 1. **Game Controller** (`scripts/core/game.gd`)
- Central coordinator for all game systems
- Manages joker activation, hand evaluation, chaos updates
- Tracks spin count, locked cards, and game state
- Signals: `hand_evaluated`, `spins_exhausted`, `run_ended`, `jokers_changed`, `spin_breakdown`

#### 2. **Board System** (`scripts/core/board.gd`)
- Manages 5×4 grid (20 slots total)
- Handles card placement and locking mechanics
- Provides row/column access for poker evaluation
- Tracks locked slots separately from card data

#### 3. **Run State** (`scripts/core/run_state.gd`)
- Manages level, XP, chips, spins, chaos, and lock charges
- Chaos system: 0-100 (game ends at 100)
- Lock charges: Start with 10, max 3 (can exceed max)
- Spins: 10 per level, refill on level up

#### 4. **Card System**
- **Card** (`scripts/core/card.gd`): Standard playing cards (1-13, 4 suits)
- **JokerCard** (`scripts/core/joker_card.gd`): Visual representation on board
- **BoardItem** (`scripts/core/board_item.gd`): Base class for board items

#### 5. **Poker Evaluation** (`scripts/core/combo_eval.gd`)
- Evaluates poker hands per **ROW** (5 cards, left→right)
- Hand types: High Card, Pair, Two Pair, Three of a Kind, Straight, Flush, Full House, Four of a Kind, Straight Flush, Royal Flush
- Scoring: 0 (High Card) to 500 (Royal Flush) per row
- Returns matching cards for visual highlighting

#### 6. **Spin Resolver** (`scripts/core/spin_resolver.gd`)
- Handles card drawing and board updates
- Creates/shuffles 52-card deck each spin
- Fills unlocked slots with random cards
- At Chaos ≥60: 25% chance locked cards ignore lock

#### 7. **Joker System**
- **Base Class** (`scripts/core/joker.gd`): Resource-based joker system
- **Jokers** (`scripts/core/jokers/`):
  - **Joker 1 (Entropy Engine)**: Score × (1 + Chaos/100), Priority 5
  - **Joker 2 (Ritual Blade)**: Stacking +0.2× per spin, +2 chaos per spin, Priority 4
  - **Joker 3 (Pressure Valve)**: Cancels first chaos effect per spin, Priority 6 (excluded from spawns until implementation complete)
  - **Joker 4 (The Final Joke)**: Grants final spin at Chaos 100 with ×2 score, Priority 10
  - **Joker 5 (Steady Hand)**: One locked card stays locked for extra spin, Priority 3 (trigger: requires locked cards)

### Game Flow

1. **Initial Deal**: Board fills with random cards (no evaluation)
2. **Spin Cycle**:
   - Player locks cards (consumes charges on spin press)
   - Press spin → consume lock charges for locked cards
   - Collect jokers from grid → add to owned
   - Draw new cards to unlocked slots
   - Evaluate poker hands (rows only)
   - Activate jokers based on trigger conditions
   - Apply joker bonuses/multipliers
   - Update chaos (+5 base, +5 if failed spin, +1 if chaos ≥90)
   - Check for stabilization moments (chaos reduction)
   - Clear all locks
   - Emit breakdown data

3. **Joker Appearance**:
   - Spin 3, 6, 9: Random joker (1 or 2) appears on grid
   - Chaos ≥90: The Final Joke (Joker 4) appears on grid
   - Jokers persist on grid until collected (except Final Joke which stays)

4. **Joker Activation**:
   - Jokers activate based on `should_trigger()` conditions
   - Priority system: Higher priority jokers activate first
   - Cap: Up to 5 jokers can be active per spin
   - Jokers on grid are also checked for activation

5. **Game End Conditions**:
   - Chaos reaches 100 (unless Final Joke grants extra spin)
   - Spins exhausted (can level up to continue)

### Chaos System

**Thresholds:**
- < 30: Stable (no disruption)
- ≥ 30: Instability (minor disruption)
- ≥ 60: Interference (25% lock ignore chance)
- ≥ 90: Collapse Warning (+1 extra chaos per spin)
- = 100: Collapse (Game Over)

**Chaos Gain:**
- Base: +5 per spin
- Failed spin (no poker hand): +5 additional
- Chaos ≥90: +1 extra
- Joker 2 (Ritual Blade): +2 when active

**Chaos Reduction:**
- Same combo 3 times in a row: -1
- Locked card survives 5 spins: -2

### Lock System

- **Lock Charges**: Start with 10, max display 3 (can exceed)
- **Locking**: Click cards to lock (no immediate charge cost)
- **Charge Consumption**: 1 charge per locked card when spin is pressed
- **Restoration**: +1 charge if score > 30 per spin
- **Unlocking**: Always free (no charge cost)
- **Expiration**: All locks clear after each spin

### Scoring System

1. **Base Score**: Sum of all row poker hand scores
2. **Joker Bonuses**: Flat bonuses added to base score
3. **Joker Multipliers**: Applied to chips earned
   - Entropy Engine: ×(1 + Chaos/100)
   - Ritual Blade: ×(1 + spins_active × 0.2)
   - Final Joke: ×2 on final spin
4. **Final Chips**: Base + bonuses, then multiplied
5. **XP**: 1 XP per chip earned

### UI System

**Main Components:**
- `main_ui.gd`: Main UI controller, deck panel management
- `board_view.gd`: Visual representation of board
- `card_view.gd`: Individual card display
- `spin_button.gd`: Spin button handler
- `spin_breakdown_panel.gd`: Shows detailed spin results
- `active_effect_panel.gd`: Displays active jokers
- `deck_panel.gd`: Deck viewer
- `notification.gd`: In-game notifications

**Scenes:**
- `Main.tscn`: Main game scene
- `startup.tscn`: Startup scene
- UI scenes in `scenes/ui/`

### File Structure

```
jokers-chaos/
├── assets/              # Card textures (24 PNGs)
├── scenes/              # Godot scene files
│   ├── Main.tscn       # Main game scene
│   └── ui/             # UI scene files
├── scripts/
│   ├── core/           # Core game logic
│   │   ├── game.gd     # Main game controller
│   │   ├── board.gd    # Board management
│   │   ├── run_state.gd # Game state
│   │   ├── card.gd     # Card class
│   │   ├── joker.gd    # Joker base class
│   │   ├── combo_eval.gd # Poker evaluation
│   │   ├── spin_resolver.gd # Card drawing
│   │   └── jokers/     # Individual joker implementations
│   └── ui/             # UI scripts
├── project.godot       # Godot project config
└── export_presets.cfg  # Export settings
```

### Key Design Patterns

1. **Signal-Based Communication**: Game systems communicate via signals
2. **Resource-Based Jokers**: Jokers are Resources, not Nodes
3. **State Management**: Centralized in `RunState` class
4. **Grid-Based Board**: 1D array representing 2D grid (row × col)
5. **Priority System**: Jokers activate by priority when cap is reached

### Technical Details

- **Engine**: Godot 4.5 (Forward Plus renderer)
- **Language**: GDScript
- **Resolution**: 1920×1080 (fullscreen)
- **Rendering**: GL Compatibility mode

### Known Limitations

1. **Joker 3 (Pressure Valve)**: Excluded from random spawns (spins 3, 6, 9) until implementation complete, but code exists
2. **Chaos.gd**: Currently empty (may be legacy code)
3. **Joker 5 (Steady Hand)**: Implemented but may need integration with lock persistence system

### Startup System

- **Startup Scene** (`startup.tscn`): Auto-transitions to main game after 2 seconds
- **Startup Script** (`scripts/ui/startup.gd`): Handles scene transition

### Game Balance Notes

- Starting chaos: 10 (avoids early game boredom)
- Lock charges: Start with 10 (generous early game)
- Spins per level: 10
- XP scaling: 100 × 1.5^(level-1)
- Score threshold for lock restoration: 30 chips

---

*Analysis generated from codebase inspection*
