# IC10 -> StationeersLua Mapping

References:
- https://stationeers-wiki.com/IC10
- https://stationeers-wiki.com/IC10/instructions

For comprehensive API documentation covering networking, events, persistence, debugging, and more, see [`GUIDE.MD`](GUIDE.MD).

## Terminology (IC10 -> StationeersLua)

- **`r0..r15` (IC10 registers)**
  - In Lua: use local variables, tables, or `ic.mem_read/ic.mem_write` if you specifically want chip memory.

- **`d0..d5` and `db` (IC10 device registers)**
  - In Lua: use **device indices** (integers) for `read/write/...`.
  - `db` in IC10 means "the device the chip is mounted on". In Lua, you can usually access that by reading/writing the **base unit index** if applicable:
    - `ic.const.BASE_UNIT_INDEX`

- **`sp` / `ra` (IC10 special registers)**
  - In Lua: you usually don't need these (Lua has functions, calls, and its own VM stack).
  - If you want equivalent IC10-style behavior, StationeersLua exposes:
    - `stack_get_sp`, `stack_set_sp`, `stack_get_ra`, `stack_set_ra`

- **`deviceHash` and `nameHash` (IC10 batch addressing)**
  - In Lua: use `batch_*` functions. Hash values can be generated using `hash("SomeString")`.
  - `prefab_name(prefabHash)` returns the prefab name string for known prefab hashes, or `nil` if unknown.
  - `device_name(deviceIndex[, networkIndex])` returns the current live display name for a wired device, or `nil` if not found.
  - `namehash_name(deviceHash, nameHash[, networkIndex])` resolves a `nameHash` by scanning visible devices and returns the first matching device's live display name, or `nil` if not found.

- **`logicType` / `logicSlotType` enums**
  - In Lua:
    - `ic.enums.LogicType.*`
    - `ic.enums.LogicSlotType.*`

- **`batchMode` (Average/Sum/Minimum/Maximum)**
  - In Lua: `ic.enums.LogicBatchMethod.*`

- **Network / channel addressing (`d0:0 Channel0`)**
  - In Lua: most `read/write` variants accept an **optional** `networkIndex` argument.

## IC10 instruction mapping

### Utility

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `alias` | name a register/device | Lua (language) | `local name = ...` | Use variables/functions/tables; no special instruction needed |
| `define` | define constant | Lua (language) | `local PI = 3.14159` | Use locals or module-level constants |
| `hcf` | halt and catch fire | StationeersLua API | `hcf()` | Stops execution |
| `sleep` | pause for seconds | StationeersLua API | `sleep(seconds)` | Coroutine suspension; resumes when the timer elapses |
| `yield` | pause for 1 tick | StationeersLua API | `yield()` | Coroutine suspension; resumes on the next tick |

Notes:
- Lua chip scripts will not compile/init or tick while hosted in an IC housing that is switched off or unpowered.

### Mathematical

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `abs` | absolute value | Lua (language) | `math.abs(x)` | |
| `add` | addition | Lua (language) | `a + b` | |
| `ceil` | ceil | Lua (language) | `math.ceil(x)` | |
| `div` | divide | Lua (language) | `a / b` | |
| `pow` | power | Lua (language) | `a ^ b` or `math.pow(a,b)` | Lua 5.2 uses `^` for number exponentiation |
| `exp` | exponent | Lua (language) | `math.exp(x)` | |
| `floor` | floor | Lua (language) | `math.floor(x)` | |
| `log` | natural log | Lua (language) | `math.log(x)` | |
| `max` | maximum | Lua (language) | `math.max(a,b)` | |
| `min` | minimum | Lua (language) | `math.min(a,b)` | |
| `mod` | remainder | Lua (language) | `math.fmod(a,b)` | IC10 mod is *not* Lua's `%` semantics; `math.fmod` matches "truncate-quotient remainder" |
| `move` | assignment/copy | Lua (language) | `dst = src` | |
| `mul` | multiply | Lua (language) | `a * b` | |
| `rand` | random | Lua (language) | `math.random()` | `math.randomseed` exists too |
| `round` | round | Lua (language) | implement helper | IC10 tie-breaking isn't stated on wiki; define your own `round()` helper to match desired behavior |
| `sqrt` | sqrt | Lua (language) | `math.sqrt(x)` | |
| `sub` | subtract | Lua (language) | `a - b` | |
| `trunc` | truncate | Lua (language) | `x >= 0 and math.floor(x) or math.ceil(x)` | Lua has no built-in `math.trunc` |
| `lerp` | linear interpolation | Lua (language) | `a + (b-a)*t` | IC10 clamps `t` to 0..1 per wiki; clamp if you want identical behavior |

### Mathematical / Trigonometric

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `acos` | arccos | Lua (language) | `math.acos(x)` | |
| `asin` | arcsin | Lua (language) | `math.asin(x)` | |
| `atan` | arctan | Lua (language) | `math.atan(x)` | |
| `atan2` | arctan2 | Lua (language) | `math.atan(y, x)` | Lua's `math.atan(y, x)` is atan2 |
| `cos` | cosine | Lua (language) | `math.cos(x)` | |
| `sin` | sine | Lua (language) | `math.sin(x)` | |
| `tan` | tangent | Lua (language) | `math.tan(x)` | |

### Stack

Stack/memory in practice includes:
- Chip stack/memory (`sp`/`ra`, 512 values)
- Device memory (some devices expose their own stack/memory)

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `push` | push to chip stack | StationeersLua API | `stack_push(value)` | Uses chip's internal stack memory |
| `pop` | pop from chip stack | StationeersLua API | `stack_pop()` | Returns popped value |
| `peek` | read chip stack top | StationeersLua API | `stack_peek()` | Does not change `sp` |
| `poke` | write chip stack at address | StationeersLua API | `stack_poke(address, value)` | Direct write to chip memory address |
| `get` | read device memory | StationeersLua API | `mem_get(deviceIndex, address[, networkIndex])` | Device memory (not chip stack) |
| `put` | write device memory | StationeersLua API | `mem_put(deviceIndex, address, value[, networkIndex])` | |
| `clr` | clear device memory | StationeersLua API | `mem_clear_device(deviceIndex[, networkIndex])` | |
| `getd` | read device memory by id | StationeersLua API | `mem_get_id(deviceId, address[, networkIndex])` | ReferenceId variant |
| `putd` | write device memory by id | StationeersLua API | `mem_put_id(deviceId, address, value[, networkIndex])` | |
| `clrd` | clear device memory by id | StationeersLua API | `mem_clear_id(deviceId[, networkIndex])` | |

### Slot / Logic

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `l` | load logic value | StationeersLua API | `read(deviceIndex, logicType[, networkIndex])` | returns `nil` on "not found/out of bounds/no housing" cases |
| `s` | store logic value | StationeersLua API | `write(deviceIndex, logicType, value[, networkIndex])` | may throw if device is missing or type not writable |
| `ls` | load slot value | StationeersLua API | `read_slot(deviceIndex, slotIndex, logicSlotType[, networkIndex])` | |
| `ss` | store slot value | StationeersLua API | `write_slot(deviceIndex, slotIndex, logicSlotType, value[, networkIndex])` | |
| `lr` | load reagent | StationeersLua API | `read_reagent(deviceIndex, reagentMode, reagentHash[, networkIndex])` | see `ic.enums.LogicReagentMode` |
| `rmap` | reagent hash -> prefab hash map | StationeersLua API | `rmap(deviceIndex[, networkIndex])` | returns a table/map |

### Slot/Logic (Batched)

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `lb` | batch load by prefab hash | StationeersLua API | `batch_read(prefabHash, logicType, batchMethod[, networkIndex])` | Batch method is `ic.enums.LogicBatchMethod.*` |
| `lbn` | batch load by prefab+name hash | StationeersLua API | `batch_read_name(prefabHash, nameHash, logicType, batchMethod[, networkIndex])` | |
| `lbs` | batch load slot | StationeersLua API | `batch_read_slot(prefabHash, slotIndex, logicSlotType, batchMethod[, networkIndex])` | |
| `lbns` | batch load slot + name | StationeersLua API | `batch_read_slot_name(prefabHash, nameHash, slotIndex, logicSlotType, batchMethod[, networkIndex])` | |
| `sb` | batch store by prefab hash | StationeersLua API | `batch_write(prefabHash, logicType, value[, networkIndex])` | |
| `sbn` | batch store by prefab+name hash | StationeersLua API | `batch_write_name(prefabHash, nameHash, logicType, value[, networkIndex])` | |
| `sbs` | batch store slot | StationeersLua API | `batch_write_slot(prefabHash, slotIndex, logicSlotType, value[, networkIndex])` | |

 Notes:
 - The optional `networkIndex` argument on `batch_*` functions is a **StationeersLua extension**.
 - Vanilla IC10 batch instructions (`lb/lbn/lbs/lbns/sb/sbn/sbs/...`) do **not** support selecting a network; they always use the circuit holder's device list.

### StationeersLua Extensions (no IC10 equivalent)

| Purpose | Coverage | Lua function | Notes |
| --- | --- | --- | --- |
| List all network devices | StationeersLua API | `device_list([networkIndex])` | Returns a Lua array of `{ref_id, prefab_hash, name_hash, display_name}` tables |
| Load library module | StationeersLua API | `require(modname [, reload])` | Loads a module from a library chip on the same data cable network |

### Bitwise

StationeersLua exposes 53-bit-safe bitwise operations (matching the IC10 "53-bit integer payload" reality).

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `and` | bitwise and | StationeersLua API | `bit_and(a, b)` | |
| `or` | bitwise or | StationeersLua API | `bit_or(a, b)` | |
| `xor` | bitwise xor | StationeersLua API | `bit_xor(a, b)` | |
| `nor` | bitwise nor | StationeersLua API | `bit_nor(a, b)` | |
| `not` | bitwise not | StationeersLua API | `bit_not(a)` | |
| `sll` | shift left | StationeersLua API | `bit_sll(a, shift)` | |
| `sla` | shift left arithmetic | StationeersLua API | `bit_sll(a, shift)` | Same as left shift in this context |
| `srl` | shift right logical | StationeersLua API | `bit_srl(a, shift)` | |
| `sra` | shift right arithmetic | StationeersLua API | `bit_sra(a, shift)` | |
| `ext` | extract field | StationeersLua API | `bit_ext(value, pos, len)` | 53-bit payload bounds enforced |
| `ins` | insert field | StationeersLua API | `bit_ins(dst, src, pos, len)` | |

### Comparison

IC10 has many "set-if" comparison instructions. In Lua:
- Use standard comparisons and return `1` / `0` as needed.
- Use `value ~= value` to detect NaN.

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `select` | conditional select | Lua (language) | `cond ~= 0 and a or b` | |
| `seq` | a == b | Lua (language) | `(a == b) and 1 or 0` | |
| `seqz` | a == 0 | Lua (language) | `(a == 0) and 1 or 0` | |
| `sne` | a != b | Lua (language) | `(a ~= b) and 1 or 0` | |
| `snez` | a != 0 | Lua (language) | `(a ~= 0) and 1 or 0` | |
| `sge` | a >= b | Lua (language) | `(a >= b) and 1 or 0` | |
| `sgez` | a >= 0 | Lua (language) | `(a >= 0) and 1 or 0` | |
| `sgt` | a > b | Lua (language) | `(a > b) and 1 or 0` | |
| `sgtz` | a > 0 | Lua (language) | `(a > 0) and 1 or 0` | |
| `sle` | a <= b | Lua (language) | `(a <= b) and 1 or 0` | |
| `slez` | a <= 0 | Lua (language) | `(a <= 0) and 1 or 0` | |
| `slt` | a < b | Lua (language) | `(a < b) and 1 or 0` | |
| `sltz` | a < 0 | Lua (language) | `(a < 0) and 1 or 0` | |
| `snan` | is NaN | Lua (language) | `(x ~= x) and 1 or 0` | NaN is the only value where `x ~= x` |
| `snanz` | is not NaN | Lua (language) | `(x == x) and 1 or 0` | |
| `sap/sna/sapz/snaz` | approx compare | Lua (language) | implement helper | The wiki defines these; implement tolerance logic in Lua if you need bit-for-bit equivalence |

### Branching

IC10 branching/jumps are "assembly language" control flow. In Lua you use native control flow.

| IC10 | Purpose | Coverage | Lua equivalent | Notes |
| --- | --- | --- | --- | --- |
| `j` | unconditional jump | Lua (language) | `while true do ... end` / `goto` | Prefer structured control flow |
| `jal` | call + set `ra` | Lua (language) | functions | Use `function foo() ... end` and call it |
| `jr` / `j ra` | return | Lua (language) | `return` | |
| `beq/bne/bgt/...` | conditional branch | Lua (language) | `if ... then ... end` | |
| `bdns/bdnvl/...` | branch on device/pin validity | StationeersLua API + Lua | `if read(...) == nil then ... end` | StationeersLua returns `nil` for many "device missing" reads; writes may throw, so use `pcall` if needed |
