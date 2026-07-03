import { describe, it, expect } from 'vitest';
import {
  computeGunMilan,
  getNakshatraInfo,
  getNakshatraIndex,
  getAllNakshatras,
  getAllRashis,
} from '../src/services/kundli';

// Traditional Ashtakoota maxima per koota — table corruption or an
// off-by-one in the lookup logic shows up here immediately.
const KOOTA_MAX: Record<string, number> = {
  varna: 1,
  vashya: 2,
  tara: 3,
  yoni: 4,
  graha_maitri: 5,
  gana: 6,
  bhakoot: 7,
  nadi: 8,
};

describe('computeGunMilan invariants (all 27x27 nakshatra pairs)', () => {
  it('every pair stays within per-koota and total bounds, and total = sum', () => {
    for (let boy = 0; boy < 27; boy++) {
      for (let girl = 0; girl < 27; girl++) {
        const r = computeGunMilan(boy, girl);
        let sum = 0;
        for (const [koota, max] of Object.entries(KOOTA_MAX)) {
          const v = (r.breakdown as unknown as Record<string, number>)[koota];
          expect(v, `${koota} for ${boy}/${girl}`).toBeGreaterThanOrEqual(0);
          expect(v, `${koota} for ${boy}/${girl}`).toBeLessThanOrEqual(max);
          sum += v;
        }
        expect(r.total, `total for ${boy}/${girl}`).toBe(sum);
        expect(r.total).toBeGreaterThanOrEqual(0);
        expect(r.total).toBeLessThanOrEqual(36);
        expect(r.max).toBe(36);
      }
    }
  });

  it('assigns tiers at the documented thresholds', () => {
    for (let boy = 0; boy < 27; boy++) {
      for (let girl = 0; girl < 27; girl++) {
        const r = computeGunMilan(boy, girl);
        const expected = r.total >= 28 ? 'excellent' : r.total >= 18 ? 'good' : 'challenging';
        expect(r.tier).toBe(expected);
      }
    }
  });

  it('is deterministic', () => {
    expect(computeGunMilan(3, 17)).toEqual(computeGunMilan(3, 17));
  });
});

describe('nakshatra helpers', () => {
  it('exposes exactly 27 nakshatras and 12 rashis', () => {
    expect(getAllNakshatras()).toHaveLength(27);
    expect(getAllRashis()).toHaveLength(12);
  });

  it('name -> index -> info round-trips for every nakshatra', () => {
    for (const name of getAllNakshatras()) {
      const idx = getNakshatraIndex(name);
      expect(idx).toBeGreaterThanOrEqual(0);
      expect(idx).toBeLessThanOrEqual(26);
      expect(getNakshatraInfo(idx).name).toBe(name);
    }
  });

  it('clamps out-of-range indices instead of crashing', () => {
    expect(() => getNakshatraInfo(-5)).not.toThrow();
    expect(() => getNakshatraInfo(99)).not.toThrow();
    expect(getNakshatraInfo(-5).name).toBe(getNakshatraInfo(0).name);
    expect(getNakshatraInfo(99).name).toBe(getNakshatraInfo(26).name);
  });
});
