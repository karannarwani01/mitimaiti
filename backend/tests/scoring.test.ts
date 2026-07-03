import { describe, it, expect } from 'vitest';
import {
  scoreFamilyValues,
  scoreLanguage,
  scoreFestivals,
  scoreFood,
  scoreDiaspora,
  scoreIntent,
  assignBadge,
} from '../src/services/scoring';

describe('scoreFamilyValues (max 25)', () => {
  it('scores the documented tiers', () => {
    expect(scoreFamilyValues('very', 'very')).toBe(25);
    expect(scoreFamilyValues('very', 'moderate')).toBe(15);
    expect(scoreFamilyValues('moderate', 'moderate')).toBe(15);
    expect(scoreFamilyValues('very', 'independent')).toBe(10);
    expect(scoreFamilyValues(null, 'very')).toBe(0);
  });
});

describe('scoreLanguage (max 20)', () => {
  it('keeps the original high-fluency tiers', () => {
    expect(scoreLanguage('native', 'native')).toBe(20);
    expect(scoreLanguage('native', 'fluent')).toBe(18);
    expect(scoreLanguage('fluent', 'fluent')).toBe(16);
    expect(scoreLanguage('basic', 'native')).toBe(8);
    expect(scoreLanguage('basic', 'basic')).toBe(8);
  });

  it('REGRESSION: conversational/learning speakers no longer score 0', () => {
    // Two conversational Sindhi speakers used to score the same (0) as two
    // people with no Sindhi at all.
    expect(scoreLanguage('conversational', 'conversational')).toBe(10);
    expect(scoreLanguage('conversational', 'native')).toBe(12);
    expect(scoreLanguage('conversational', 'fluent')).toBe(12);
    expect(scoreLanguage('learning', 'native')).toBe(8);
    expect(scoreLanguage('learning', 'learning')).toBe(6);
  });

  it('none or missing on either side scores 0', () => {
    expect(scoreLanguage('none', 'native')).toBe(0);
    expect(scoreLanguage('none', 'none')).toBe(0);
    expect(scoreLanguage(null, 'native')).toBe(0);
  });

  it('never exceeds the 20-point dimension cap and stays monotonic-ish', () => {
    const levels = ['native', 'fluent', 'conversational', 'basic', 'learning', 'none'] as const;
    for (const a of levels) {
      for (const b of levels) {
        const s = scoreLanguage(a, b);
        expect(s).toBeGreaterThanOrEqual(0);
        expect(s).toBeLessThanOrEqual(20);
        // symmetry
        expect(scoreLanguage(b, a)).toBe(s);
      }
    }
  });
});

describe('scoreFestivals (max 20, Jaccard)', () => {
  it('scores identical sets 20 and disjoint sets 0', () => {
    expect(scoreFestivals(['Diwali', 'Cheti Chand'], ['diwali', 'CHETI CHAND '])).toBe(20);
    expect(scoreFestivals(['Diwali'], ['Holi'])).toBe(0);
  });

  it('scores partial overlap proportionally', () => {
    // intersection 1, union 3 -> 1/3 * 20 = 6.67 -> 7
    expect(scoreFestivals(['Diwali', 'Holi'], ['Diwali', 'Cheti Chand'])).toBe(7);
  });

  it('handles empty/missing lists', () => {
    expect(scoreFestivals([], ['Diwali'])).toBe(0);
    expect(scoreFestivals(null, ['Diwali'])).toBe(0);
  });
});

describe('scoreFood (max 15)', () => {
  it('scores same diet 15, compatible 10, opposed 5', () => {
    expect(scoreFood('veg', 'veg')).toBe(15);
    expect(scoreFood('veg', 'jain')).toBe(10);
    expect(scoreFood('veg', 'non-veg')).toBe(5);
    expect(scoreFood(null, 'veg')).toBe(0);
  });

  it('REGRESSION: alias spellings are normalized', () => {
    // 'vegetarian' + 'veg' used to score 5 (treated as strangers).
    expect(scoreFood('vegetarian', 'veg')).toBe(15);
    expect(scoreFood('non_vegetarian', 'non-veg')).toBe(15);
    expect(scoreFood('vegetarian', 'jain')).toBe(10);
    expect(scoreFood('eggetarian', 'veg')).toBe(10);
    expect(scoreFood('eggetarian', 'eggetarian')).toBe(15);
  });

  it('is symmetric', () => {
    expect(scoreFood('non-veg', 'eggetarian')).toBe(scoreFood('eggetarian', 'non-veg'));
  });
});

describe('scoreDiaspora (max 10)', () => {
  it('scores generation distance', () => {
    expect(scoreDiaspora(2, 2)).toBe(10);
    expect(scoreDiaspora(1, 2)).toBe(6);
    expect(scoreDiaspora(1, 4)).toBe(2);
    expect(scoreDiaspora(null, 2)).toBe(0);
  });
});

describe('scoreIntent (max 10)', () => {
  it('scores the documented tiers', () => {
    expect(scoreIntent('marriage', 'marriage')).toBe(10);
    expect(scoreIntent('casual', 'casual')).toBe(10);
    expect(scoreIntent('open', 'marriage')).toBe(7);
    expect(scoreIntent('casual', 'marriage')).toBe(2);
    expect(scoreIntent(null, 'marriage')).toBe(0);
  });
});

describe('assignBadge', () => {
  it('maps totals to badges at the documented thresholds', () => {
    expect(assignBadge(85)).toBe('gold');
    expect(assignBadge(84)).toBe('green');
    expect(assignBadge(65)).toBe('green');
    expect(assignBadge(64)).toBe('orange');
    expect(assignBadge(40)).toBe('orange');
    expect(assignBadge(39)).toBe('none');
  });
});
