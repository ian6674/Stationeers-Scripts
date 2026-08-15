--@module gas
-- LibraryModule_Gas.lua
-- Gas properties, ideal gas law, and mixing helpers for Stationeers.
-- Other Lua chips on the same data network load this via: local gas = require("gas")
--
-- HOW TO USE:
--   1. Put this script on a Lua chip and insert it into an IC Housing.
--   2. The housing must be powered and on the same data cable network as consumer chips.
--   3. Any chip on the same network can call: local gas = require("gas")
--
-- FEATURES:
--   - Stationeers gas type enum values and specific heat constants
--   - Ideal gas law calculations (PV = nRT)
--   - Mole/ratio/partial-pressure helpers
--   - Safe atmosphere composition targets

local gas                = {}

-- ── Universal Constants (from Chemistry.cs) ──────────────────────────────────
gas.R                    = 8.3144 -- Universal gas constant J/(mol*K) - Chemistry.R
gas.KELVIN_OFFSET        = 273.15

-- ── Stationeers Gas Types (from Chemistry.GasType, [Flags] enum) ──────────────
-- These are bit-flag values (powers of 2), NOT sequential indices.
gas.TYPE                 = {
    Oxygen                 = 1,
    Nitrogen               = 2,
    CarbonDioxide          = 4,
    Methane                = 8, -- C# enum renamed Volatiles→Methane in v0.2.6217
    Pollutant              = 16,
    Water                  = 32,
    NitrousOxide           = 64,
    LiquidNitrogen         = 128,
    LiquidOxygen           = 256,
    LiquidMethane          = 512, -- C# enum renamed LiquidVolatiles→LiquidMethane
    Steam                  = 1024,
    LiquidCarbonDioxide    = 2048,
    LiquidPollutant        = 4096,
    LiquidNitrousOxide     = 8192,
    Hydrogen               = 16384,
    LiquidHydrogen         = 32768,
    PollutedWater          = 65536,
    -- New gases added in v0.2.6217
    Hydrazine              = 131072,
    LiquidHydrazine        = 262144,
    LiquidAlcohol          = 524288,
    Helium                 = 1048576,
    LiquidSodiumChloride   = 2097152,
    Silanol                = 4194304,
    LiquidSilanol          = 8388608,
    HydrochloricAcid       = 16777216,
    LiquidHydrochloricAcid = 33554432,
    Ozone                  = 67108864,
    LiquidOzone            = 134217728,
}
-- Backwards-compat aliases (game renamed Volatiles→Methane in v0.2.6217)
gas.TYPE.Volatiles       = gas.TYPE.Methane
gas.TYPE.LiquidVolatiles = gas.TYPE.LiquidMethane

-- ── Specific Heat Capacities (J/(mol*K)) - from Mole.GetSpecificHeat() ───────
-- Keyed by GasType flag value. Liquid forms share the same Cv as their gas.
gas.SPECIFIC_HEAT        = {
    [1]         = 21.1,  -- Oxygen
    [2]         = 20.6,  -- Nitrogen
    [4]         = 28.2,  -- CarbonDioxide
    [8]         = 20.4,  -- Methane (formerly Volatiles)
    [16]        = 24.8,  -- Pollutant
    [32]        = 72.0,  -- Water
    [64]        = 37.2,  -- NitrousOxide
    [128]       = 20.6,  -- LiquidNitrogen
    [256]       = 21.1,  -- LiquidOxygen
    [512]       = 20.4,  -- LiquidMethane (formerly LiquidVolatiles)
    [1024]      = 72.0,  -- Steam
    [2048]      = 28.2,  -- LiquidCarbonDioxide
    [4096]      = 24.8,  -- LiquidPollutant
    [8192]      = 37.2,  -- LiquidNitrousOxide
    [16384]     = 20.4,  -- Hydrogen
    [32768]     = 20.4,  -- LiquidHydrogen
    [65536]     = 64.0,  -- PollutedWater (Mole.SpecificHeat returns 64.0)
    -- New gases added in v0.2.6217
    [131072]    = 48.4,  -- Hydrazine
    [262144]    = 48.4,  -- LiquidHydrazine
    [524288]    = 33.0,  -- LiquidAlcohol (Ethanol)
    [1048576]   = 20.8,  -- Helium
    [2097152]   = 130.0, -- LiquidSodiumChloride
    [4194304]   = 101.0, -- Silanol
    [8388608]   = 101.0, -- LiquidSilanol
    [16777216]  = 37.0,  -- HydrochloricAcid
    [33554432]  = 37.0,  -- LiquidHydrochloricAcid
    [67108864]  = 38.6,  -- Ozone
    [134217728] = 38.6,  -- LiquidOzone
}

-- ── Human-readable Gas Names (keyed by GasType flag) ─────────────────────────
gas.NAMES                = {
    [1]        = "Oxygen",
    [2]        = "Nitrogen",
    [4]        = "Carbon Dioxide",
    [8]        = "Methane",
    [16]       = "Pollutant",
    [32]       = "Water",
    [64]       = "Nitrous Oxide",
    [1024]     = "Steam",
    [16384]    = "Hydrogen",
    [65536]    = "Polluted Water",
    -- New gases added in v0.2.6217
    [131072]   = "Hydrazine",
    [524288]   = "Ethanol",
    [1048576]  = "Helium",
    [2097152]  = "Sodium Chloride",
    [4194304]  = "Silanol",
    [16777216] = "Hydrochloric Acid",
    [67108864] = "Ozone",
}

-- ── Short Labels (keyed by GasType flag) ─────────────────────────────────────
gas.LABELS               = {
    [1]        = "O2",
    [2]        = "N2",
    [4]        = "CO2",
    [8]        = "CH4",
    [16]       = "X",
    [32]       = "H2O",
    [64]       = "NOS",
    [1024]     = "STM",
    [16384]    = "H2",
    [65536]    = "XH2O",
    -- New gases added in v0.2.6217
    [131072]   = "HZ",
    [524288]   = "Al",
    [1048576]  = "HE",
    [2097152]  = "NaCl",
    [4194304]  = "Sil",
    [16777216] = "HCl",
    [67108864] = "O3",
}

-- ── LogicType Ratio Fields (keyed by GasType flag) ───────────────────────────
-- Maps gas type to the LogicType enum name for reading molar ratios.
-- Use with ic.read(pin, LT[gas.RATIO_FIELD[type]]) to read gas ratios.
-- Values verified against LogicType.cs enum.
gas.RATIO_FIELD          = {
    [1]        = "RatioOxygen",               -- LogicType 14
    [2]        = "RatioNitrogen",             -- LogicType 16
    [4]        = "RatioCarbonDioxide",        -- LogicType 15
    [8]        = "RatioMethane",              -- LogicType 18 (C# enum name is Methane, not Volatiles)
    [16]       = "RatioPollutant",            -- LogicType 17
    [32]       = "RatioWater",                -- LogicType 19
    [64]       = "RatioNitrousOxide",         -- LogicType 83
    [128]      = "RatioLiquidNitrogen",       -- LogicType 177
    [256]      = "RatioLiquidOxygen",         -- LogicType 183
    [512]      = "RatioLiquidMethane",        -- LogicType 188
    [1024]     = "RatioSteam",                -- LogicType 193
    [2048]     = "RatioLiquidCarbonDioxide",  -- LogicType 199
    [4096]     = "RatioLiquidPollutant",      -- LogicType 204
    [8192]     = "RatioLiquidNitrousOxide",   -- LogicType 209
    [16384]    = "RatioHydrogen",             -- LogicType 252
    [32768]    = "RatioLiquidHydrogen",       -- LogicType 253
    [65536]    = "RatioPollutedWater",        -- LogicType 254
    -- New gases added in v0.2.6217
    [131072]   = "RatioHydrazine",            -- LogicType 283
    [262144]   = "RatioLiquidHydrazine",      -- LogicType 284
    [524288]   = "RatioLiquidAlcohol",        -- LogicType 285
    [1048576]  = "RatioHelium",               -- LogicType 286
    [2097152]  = "RatioLiquidSodiumChloride", -- LogicType 287
    [4194304]  = "RatioSilanol",              -- LogicType 288
    [8388608]  = "RatioLiquidSilanol",        -- LogicType 289
    [16777216] = "RatioHydrochloricAcid",     -- LogicType 290
    [33554432] = "RatioLiquidHydrochloricAcid", -- LogicType 291
    [67108864] = "RatioOzone",                -- LogicType 292
    [134217728] = "RatioLiquidOzone",         -- LogicType 293
}

-- ── Safe Atmosphere Targets (from Chemistry.cs, Lungs.cs) ────────────────────
gas.SAFE                 = {
    -- Chemistry.cs constants
    o2_partial_min  = 16.0,    -- kPa, MinimumOxygenPartialPressure
    pressure_1atm   = 101.325, -- kPa, ONE_ATMOSPHERE
    armstrong_limit = 6.3,     -- kPa, ArmstrongLimit (vacuum damage)
    -- Lungs.cs TemperatureMin/Max (ZeroDegrees +/- offset)
    temp_min        = 263.15,  -- K (-10 C), ZeroDegrees - 10
    temp_ideal      = 293.15,  -- K (20 C), TwentyDegrees
    temp_max        = 323.15,  -- K (50 C), ZeroDegrees + 50
}

-- ── Ideal Gas Law Helpers ──────────────────────────────────────────────────────

--- Calculate pressure from moles, temperature, and volume.
-- P = nRT / V
-- @param moles  Total moles of gas
-- @param temp_k Temperature in Kelvin
-- @param volume Volume in liters
-- @return pressure in kPa
function gas.pressure(moles, temp_k, volume)
    if volume <= 0 then return 0 end
    return (moles * gas.R * temp_k) / volume
end

--- Calculate moles from pressure, temperature, and volume.
-- n = PV / RT
-- @param pressure_kpa Pressure in kPa
-- @param temp_k       Temperature in Kelvin
-- @param volume       Volume in liters
-- @return moles
function gas.moles(pressure_kpa, temp_k, volume)
    if temp_k <= 0 then return 0 end
    return (pressure_kpa * volume) / (gas.R * temp_k)
end

--- Calculate volume from moles, temperature, and pressure.
-- V = nRT / P
function gas.volume(moles, temp_k, pressure_kpa)
    if pressure_kpa <= 0 then return 0 end
    return (moles * gas.R * temp_k) / pressure_kpa
end

--- Calculate temperature from moles, pressure, and volume.
-- T = PV / nR
function gas.temperature(pressure_kpa, volume, moles)
    if moles <= 0 then return 0 end
    return (pressure_kpa * volume) / (moles * gas.R)
end

-- ── Partial Pressure / Ratio Helpers ───────────────────────────────────────────

--- Calculate partial pressure of a gas from its molar ratio and total pressure.
-- @param ratio        Molar ratio (0..1)
-- @param total_kpa    Total pressure in kPa
-- @return partial pressure in kPa
function gas.partial_pressure(ratio, total_kpa)
    return ratio * total_kpa
end

--- Calculate molar ratio from partial pressure and total pressure.
function gas.ratio(partial_kpa, total_kpa)
    if total_kpa <= 0 then return 0 end
    return partial_kpa / total_kpa
end

--- Calculate moles of a specific gas from its ratio and total moles.
function gas.moles_of(ratio, total_moles)
    return ratio * total_moles
end

-- ── Energy Calculations ────────────────────────────────────────────────────────

--- Calculate thermal energy stored in a gas mixture.
-- E = sum(moles_i * Cv_i * T)
-- @param gas_moles  Table of {[gas_type_index] = moles}
-- @param temp_k     Temperature in Kelvin
-- @return energy in Joules
function gas.thermal_energy(gas_moles, temp_k)
    local energy = 0
    for gas_type, moles in pairs(gas_moles) do
        local cv = gas.SPECIFIC_HEAT[gas_type] or 20.0
        energy = energy + moles * cv * temp_k
    end
    return energy
end

--- Calculate the equilibrium temperature when two gas mixtures combine.
-- @param moles_a   Table of {[gas_type] = moles} for mixture A
-- @param temp_a    Temperature of mixture A in Kelvin
-- @param moles_b   Table of {[gas_type] = moles} for mixture B
-- @param temp_b    Temperature of mixture B in Kelvin
-- @return equilibrium temperature in Kelvin
function gas.equilibrium_temp(moles_a, temp_a, moles_b, temp_b)
    local energy_a = gas.thermal_energy(moles_a, temp_a)
    local energy_b = gas.thermal_energy(moles_b, temp_b)

    local total_heat_capacity = 0
    -- Combine heat capacities from both mixtures
    local all_types = {}
    for t, m in pairs(moles_a) do all_types[t] = (all_types[t] or 0) + m end
    for t, m in pairs(moles_b) do all_types[t] = (all_types[t] or 0) + m end

    for gas_type, moles in pairs(all_types) do
        local cv = gas.SPECIFIC_HEAT[gas_type] or 20.0
        total_heat_capacity = total_heat_capacity + moles * cv
    end

    if total_heat_capacity <= 0 then return 0 end
    return (energy_a + energy_b) / total_heat_capacity
end

-- ── Utility ────────────────────────────────────────────────────────────────────

--- Convert Kelvin to Celsius.
function gas.k_to_c(k) return k - 273.15 end

--- Convert Celsius to Kelvin.
function gas.c_to_k(c) return c + 273.15 end

--- Clamp a value.
function gas.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

return gas
