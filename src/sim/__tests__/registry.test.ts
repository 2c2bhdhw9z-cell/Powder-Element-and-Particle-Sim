import { describe, expect, it } from "vitest";
import { ElementRegistry, EMPTY_ELEMENT_ID, CORE_ELEMENTS } from "@/sim/element-registry";

describe("ElementRegistry", () => {
  it("has unique built-in element IDs with air at 0", () => {
    const ids = CORE_ELEMENTS.map((e) => e.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(CORE_ELEMENTS[0].id).toBe(EMPTY_ELEMENT_ID);
    for (const id of ids) expect(id).toBeGreaterThanOrEqual(0);
    expect(Math.max(...ids)).toBeLessThan(100);
  });

  it("falls back to the empty element for unknown IDs", () => {
    const r = new ElementRegistry();
    expect(r.getElement(999).id).toBe(EMPTY_ELEMENT_ID);
  });

  it("registers, resolves and deletes custom elements", () => {
    const r = new ElementRegistry();
    const custom = {
      id: 50,
      name: "Testium",
      category: "Custom" as const,
      state: "solid_movable" as const,
      color: "#123456",
      density: 20,
    };
    expect(r.registerElement(custom)).toBe(true);
    expect(r.getElement(50).name).toBe("Testium");
    expect(r.isBuiltIn(50)).toBe(false);
    expect(r.deleteCustomElement(50)).toBe(true);
    expect(r.getElement(50).id).toBe(EMPTY_ELEMENT_ID);
  });

  it("rejects custom elements outside the reserved 50–99 range", () => {
    const r = new ElementRegistry();
    const bad = {
      id: 5,
      name: "Nope",
      category: "Custom" as const,
      state: "solid_movable" as const,
      color: "#000000",
      density: 1,
    };
    expect(r.registerElement(bad)).toBe(false);
  });

  it("palette excludes empty and category lookup works", () => {
    const r = new ElementRegistry();
    expect(r.getPaletteElements().every((e) => e.id !== 0)).toBe(true);
    const liquids = r.getElementsByCategory("Liquids");
    expect(liquids.length).toBeGreaterThan(0);
    expect(liquids.every((e) => e.state === "liquid")).toBe(true);
  });
});
