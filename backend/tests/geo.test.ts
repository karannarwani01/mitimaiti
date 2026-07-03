import { describe, it, expect } from 'vitest';
import { getCityCoords, cityDistance } from '../src/utils/geo';

describe('getCityCoords', () => {
  it('resolves exact city names case-insensitively', () => {
    expect(getCityCoords('Dubai')).not.toBeNull();
    expect(getCityCoords('dubai')).not.toBeNull();
    expect(getCityCoords('  Mumbai  ')).not.toBeNull();
  });

  it('resolves compound names containing a known city as a whole word', () => {
    expect(getCityCoords('Navi Mumbai')).toEqual(getCityCoords('Mumbai'));
    expect(getCityCoords('Bur Dubai')).toEqual(getCityCoords('Dubai'));
    expect(getCityCoords('Dubai Marina, Dubai')).toEqual(getCityCoords('Dubai'));
  });

  it('REGRESSION: no bidirectional substring false matches', () => {
    // "York" used to resolve to New York, "Sur" to Surat — corrupting
    // distance-based feed ranking with confidently wrong coordinates.
    expect(getCityCoords('York')).toBeNull();
    expect(getCityCoords('Sur')).toBeNull();
  });

  it('returns null for unknown or empty cities', () => {
    expect(getCityCoords('')).toBeNull();
    expect(getCityCoords('Atlantis')).toBeNull();
  });
});

describe('cityDistance', () => {
  it('is 0 for the same city and positive for different cities', () => {
    expect(cityDistance('Dubai', 'dubai')).toBe(0);
    const d = cityDistance('Dubai', 'Mumbai');
    expect(d).not.toBeNull();
    expect(d!).toBeGreaterThan(1000);
    expect(d!).toBeLessThan(3000);
  });

  it('is null when either city is unknown', () => {
    expect(cityDistance('Dubai', 'Atlantis')).toBeNull();
  });
});
