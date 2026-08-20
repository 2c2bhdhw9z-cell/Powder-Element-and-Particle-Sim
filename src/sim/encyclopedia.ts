export type Lore = {
  melt?: string;
  boil?: string;
  eats: string;
  note: string;
};

const LORE: Record<number, Lore> = {
  0: { eats: "Nothing. Air. Pressure leaks into it.", note: "Empty cell." },
  1: { melt: "1710°C", eats: "Nothing. Sinks in water, stacks, melts to glass beside lava.", note: "Silica grains. The default pile." },
  2: { melt: "0°C", boil: "100°C", eats: "Puts out fire. Boils on lava. Freezes beside ice. Carves sand.", note: "Seeks downhill. Lightning prefers it. Erodes dirt/sand." },
  3: { melt: "—", eats: "Burns. Feeds fire and plants’ opposite.", note: "Fuel. High flammability." },
  4: { melt: "—", eats: "Wood, oil, plant, gunpowder, hydrogen, coal, wax.", note: "Dies to water and lack of fuel." },
  5: { melt: "—", eats: "Nothing. Rises. Follows fans.", note: "Combustion leftover." },
  6: { melt: "700°C solidify", boil: "—", eats: "Water → steam + obsidian. Melts sand/stone when hot.", note: "Wins or loses by temperature, not by volume." },
  7: { melt: "~1200°C", eats: "Blocks most flow.", note: "Barrier rock." },
  8: { melt: "—", eats: "Most solids except glass and bedrock.", note: "Eats on contact." },
  9: { melt: "—", boil: "burns", eats: "Floats on water. Burns hard.", note: "Fuel layer." },
  10: { melt: "—", eats: "Detonates from fire, spark, laser.", note: "Keep it away from the rod." },
  11: { melt: "—", eats: "Drinks water, burns.", note: "Grows toward moisture." },
  12: { melt: "~1400°C", eats: "Acid-proof. Brittle to laser/lava.", note: "Melted sand." },
  13: { melt: "0°C", eats: "Freezes nearby water.", note: "Dam material." },
  14: { melt: "—", boil: "condenses < 90°C", eats: "Nothing. Rises, then rains. Sealed rooms rupture.", note: "Steam. Lightning will still chase the wet left behind." },
  15: { melt: "—", eats: "Everything in a radius when sparked.", note: "Don’t wire this to copper." },
  16: { melt: "—", eats: "Seeks water and metal, then ignites fuel.", note: "Pathfinding arc. Not a decoration." },
  17: { melt: "~1500°C", eats: "Carries spark and some heat.", note: "Wire. Use copper if you want a heat pipe." },
  18: { melt: "—", eats: "Converts neighboring solids.", note: "Keep it off the ant farm." },
  19: { melt: "—", eats: "Crawls dirt and sand, avoids water.", note: "Colony grain." },
  20: { melt: "never", eats: "Deletes anything that touches it. Sucks pressure.", note: "Vacuum well." },
  21: { melt: "—", eats: "Copies the first neighbor it sees.", note: "Don’t clone C4 next to spark." },
  22: { melt: "—", eats: "Teleports matter to Portal B.", note: "Pair them." },
  23: { melt: "—", eats: "Exit for Portal A.", note: "Pair them." },
  24: { melt: "—", eats: "Falls up.", note: "Negative gravity sand." },
  25: { melt: "~60°C", eats: "Melts, then can burn.", note: "Candle logic." },
  26: { melt: "—", eats: "Burns through almost anything once lit.", note: "Thermite." },
  27: { melt: "—", boil: "100°C", eats: "Better conductor than fresh water.", note: "Lightning loves this." },
  28: { melt: "—", eats: "Detonates. Shock + fire.", note: "Liquid boom." },
  29: { melt: "never", eats: "Nothing. Immune.", note: "World edge." },
  30: { melt: "—", eats: "Bounces kinetic hits.", note: "Soft wall." },
  31: { melt: "—", eats: "Feeds fire, boom with spark.", note: "Oxidizer." },
  32: { melt: "—", eats: "Ignites and melts.", note: "Superheated gas." },
  33: { melt: "—", eats: "Burns along its length, then spark.", note: "Timer." },
  34: { melt: "—", eats: "Slow pour. Burns if you try.", note: "Viscous." },
  35: { melt: "—", eats: "Rises. Can boom.", note: "Lighter than air." },
  36: { melt: "—", eats: "Boils water, ignites fuel, melts sand.", note: "Beam." },
  37: { melt: "801°C", eats: "Turns water into salt water.", note: "NaCl." },
  38: { melt: "0°C", eats: "Compacts toward ice.", note: "Light water." },
  39: { melt: "—", eats: "Drinks water → mud. Erodes.", note: "Soil." },
  40: { melt: "—", eats: "Becomes plant with water.", note: "Start a farm." },
  41: { melt: "—", eats: "Burns long.", note: "Carbon." },
  42: { melt: "—", eats: "Cured wet mix. Barrier.", note: "The set stone." },
  43: { melt: "—", eats: "Boom with spark or fire.", note: "Lightest fuel." },
  44: { melt: "-39°C", boil: "357°C", eats: "Dense. Conducts. Sinks through water.", note: "Don’t drink it." },
  45: { melt: "—", eats: "Dirt + water. Slow.", note: "Slurry." },
  46: { melt: "high", eats: "Won’t remelt easily.", note: "Quenched lava." },
  47: { melt: "1085°C", eats: "Moves heat, not mass. Conducts spark.", note: "Heat pipe. Line it from lava to ice." },
  48: { melt: "—", eats: "Pushes gas and light powder along gravity-right.", note: "Pressure without a blast." },
  49: { melt: "—", eats: "Pours, then becomes concrete.", note: "Wait. Don’t freeze it." },
};

export function loreFor(id: number): Lore {
  return (
    LORE[id] || {
      eats: "See density and flammability on the palette.",
      note: "No extra card yet.",
    }
  );
}