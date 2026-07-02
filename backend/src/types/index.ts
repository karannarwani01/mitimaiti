import { Request } from 'express';

// ─── Enums ────────────────────────────────────────────────────────────────────

export type Gender = 'man' | 'woman' | 'non-binary';
export type Intent = 'casual' | 'open' | 'marriage';
export type ShowMe = 'men' | 'women' | 'everyone';
export type ActionType = 'like' | 'pass';
export type MsgType = 'text' | 'photo' | 'voice' | 'gif' | 'icebreaker' | 'system';
export type ReportReason = 'fake' | 'harassment' | 'spam' | 'photos' | 'underage' | 'safety';
export type ReportPriority = 'P0' | 'P1' | 'P2';
export type AdminAction = 'dismiss' | 'warn' | 'suspend' | 'ban';
export type ModerationAction = AdminAction;
export type CulturalBadge = 'gold' | 'green' | 'orange' | 'none';
export type KundliTier = 'excellent' | 'good' | 'challenging';
export type FamilyRole = 'mom' | 'dad' | 'sibling' | 'grandparent' | 'uncle_aunt' | 'other';
export type SindhiFluency = 'native' | 'fluent' | 'conversational' | 'basic' | 'learning' | 'none';
export type Dietary = 'veg' | 'non-veg' | 'vegan' | 'jain' | 'eggetarian' | 'vegetarian' | 'non_vegetarian';
export type FamilyInvolvement = 'very' | 'moderate' | 'independent';
export type FamilyValues = 'traditional' | 'moderate' | 'liberal';
export type FoodPreference = 'vegetarian' | 'non_vegetarian' | 'vegan' | 'jain' | 'eggetarian';
export type MatchStatus = 'pending_first_message' | 'active' | 'expired' | 'unmatched' | 'dissolved';
export type MessageStatus = 'sending' | 'sent' | 'delivered' | 'read';

// ─── Auth ─────────────────────────────────────────────────────────────────────

export interface AuthUser {
  id: string;
  authId: string;
  phone: string;
  role?: 'user' | 'admin';
}

export interface AuthenticatedRequest extends Request {
  user: AuthUser;
}

// ─── Notification Types (18) ──────────────────────────────────────────────────

export type NotificationType =
  | 'like_received'
  | 'likes_batch'
  | 'match_created'
  | 'new_match'
  | 'message_received'
  | 'new_message'
  | 'voice_message'
  | 'photo_received'
  | 'expiry_warning'
  | 'match_expiring'
  | 'match_dissolved'
  | 'incoming_call'
  | 'family_joined'
  | 'family_suggestion'
  | 'suggestion_reviewed'
  | 'access_revoked'
  | 'profile_verified'
  | 'snooze_ended'
  | 'deletion_reminder'
  | 'profile_nudge'
  | 'strike_issued'
  | 'appeal_resolved';

export interface NotificationPayload {
  type: NotificationType;
  userId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

// Safety notification types that bypass throttle
export const SAFETY_NOTIFICATION_TYPES: NotificationType[] = [
  'strike_issued',
  'match_dissolved',
  'appeal_resolved',
];

// ─── Cultural Scoring ─────────────────────────────────────────────────────────

export interface CulturalBreakdown {
  family_values: number;
  language: number;
  festivals: number;
  food: number;
  diaspora: number;
  intent: number;
}

export interface CulturalScoreResult {
  total: number;
  badge: CulturalBadge;
  breakdown: CulturalBreakdown;
}

// ─── Kundli ───────────────────────────────────────────────────────────────────

export interface KundliBreakdown {
  varna: number;
  vashya: number;
  tara: number;
  yoni: number;
  graha_maitri: number;
  gana: number;
  bhakoot: number;
  nadi: number;
}

export interface KundliResult {
  total: number;
  max: 36;
  tier: KundliTier;
  breakdown: KundliBreakdown;
}

export interface NakshatraInfo {
  name: string;
  index: number;
  rashi: string;
}

// ─── Moderation ──────────────────────────────────────────────────────────────

export interface PhotoScreenResult {
  pass: boolean;
  score: number;
}

export interface TextScreenResult {
  pass: boolean;
  reason: string;
}

export interface ProfileTextScreenResult {
  pass: boolean;
  score: number;
}

// ─── Feed Card ────────────────────────────────────────────────────────────────

export interface FeedCard {
  id: string;
  first_name: string;
  display_name: string;
  age: number;
  city: string;
  state: string | null;
  country: string | null;
  bio: string | null;
  intent: Intent;
  is_verified: boolean;
  profile_completeness: number;
  photos: { url: string; url_thumb: string; url_medium: string; is_primary: boolean; sort_order: number; is_verified: boolean; is_video: boolean }[];
  about_me: string | null;
  prompts: any[];
  interests: string[];
  voice_intro_url?: string | null;
  cultural_score: number;
  cultural_badge: CulturalBadge;
  cultural_breakdown: CulturalBreakdown | null;
  kundli_score: number | null;
  kundli_tier: KundliTier | null;
  kundli_breakdown: KundliBreakdown | null;
  common_interests: number;
  daily_prompt_answer: string | null;
  distance_km: number | null;
  is_online: boolean;
  last_active: string | null;
  // Sindhi identity
  sindhi_fluency: SindhiFluency | null;
  family_values: FamilyValues | null;
  food_preference: FoodPreference | null;
  // Basics
  height_cm: number | null;
  education: string | null;
  occupation: string | null;
  company: string | null;
  religion: string | null;
  smoking: string | null;
  drinking: string | null;
  exercise: string | null;
}

// ─── Socket Events ────────────────────────────────────────────────────────────

export interface SocketSendMessage {
  matchId: string;
  content?: string;
  mediaUrl?: string;
  msgType: MsgType;
}

export interface SocketTypingEvent {
  matchId: string;
}

export interface SocketEnterChat {
  matchId: string;
}

// ─── Icebreaker ─────────────────────────────────────────────────────────

export interface Icebreaker {
  id: number;
  category: 'sindhi' | 'general' | 'fun' | 'deep';
  question: string;
}

// ─── Family Permissions ───────────────────────────────────────────────────────

export interface FamilyPermissions {
  canViewProfile: boolean;
  canViewPhotos: boolean;
  canViewBasics: boolean;
  canViewSindhi: boolean;
  canViewMatches: boolean;
  canSuggest: boolean;
  canViewCulturalScore: boolean;
  canViewKundli: boolean;
}

// Legacy permission mapping for backward compatibility
export const LEGACY_PERMISSION_MAP: Record<string, keyof FamilyPermissions> = {
  photos: 'canViewPhotos',
  bio: 'canViewProfile',
  education: 'canViewBasics',
  chatti: 'canViewSindhi',
  kundli: 'canViewKundli',
  prompts: 'canViewProfile',
  voice: 'canViewProfile',
  cultural_badges: 'canViewCulturalScore',
};
