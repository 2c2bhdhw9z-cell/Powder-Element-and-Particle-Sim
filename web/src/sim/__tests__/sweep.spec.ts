import { describe, expect, it } from "vitest";
import { sweepsRightward } from "../powder-engine";

/**
 * The direction each row of the powder world is swept in, which the native engine works out
 * identically. The pattern below is pinned in both suites (`PowderHourglassTests` natively), so
 * the two cannot drift apart without both failing.
 */
describe("row sweep direction", () => {
  it("matches the native engine bit for bit", () => {
    let pattern = "";
    for (let moment = 0; moment < 4; moment++) {
      for (let row = 0; row < 16; row++) pattern += sweepsRightward(row, moment) ? "1" : "0";
    }
    expect(pattern).toBe("1101010000011010111100111100010100000100110011000011000111100100");
    expect(sweepsRightward(5000, 2147483647)).toBe(true);
    expect(sweepsRightward(7, 4294967299)).toBe(true);
    expect(sweepsRightward(123, 99999999)).toBe(true);
  });

  it("favours neither side, and has no rhythm on alternate ticks", () => {
    let rightward = 0;
    for (let moment = 0; moment < 200; moment++) {
      for (let row = 0; row < 200; row++) if (sweepsRightward(row, moment)) rightward++;
    }
    expect(Math.abs(rightward - 20000)).toBeLessThan(400);
    let even = 0;
    for (let moment = 0; moment < 4000; moment += 2) if (sweepsRightward(40, moment)) even++;
    expect(Math.abs(even - 1000)).toBeLessThan(100);
  });
});
