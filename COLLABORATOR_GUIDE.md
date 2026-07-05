# MitiMaiti - Collaborator Development Guide

## Project Overview

**MitiMaiti** is a Sindhi community matrimony & dating web app built with:
- **Frontend**: Next.js 14 + Tailwind CSS (hosted on Vercel)
- **Backend**: Node.js + Express + TypeScript (hosted on Render)
- **Database**: Supabase (PostgreSQL) in Mumbai region
- **Repo**: https://github.com/techygarry/mitimaiti

### Live URLs
| Service | URL |
|---------|-----|
| Frontend | https://web-one-henna-44.vercel.app |
| Backend API | https://mitimaiti-backend.onrender.com |
| GitHub | https://github.com/techygarry/mitimaiti |

---

## PART 1: Setup for New Collaborator (Claude Code CLI)

### Step 1: Install Prerequisites

```bash
# Install Node.js 20+ (if not installed)
brew install node

# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Verify installations
node --version    # Should be 20+
claude --version
```

### Step 2: Clone the Repository

```bash
cd ~/Documents
git clone https://github.com/techygarry/mitimaiti.git
cd mitimaiti
```

### Step 3: Install Dependencies

```bash
# Install frontend dependencies
cd web && npm install && cd ..

# Install backend dependencies
cd backend && npm install && cd ..
```

### Step 4: Set Up Environment Variables

```bash
# Frontend (.env.local in web/)
cp .env.example web/.env.local
```

Edit `web/.env.local`:
```
NEXT_PUBLIC_SUPABASE_URL=https://hkrqyxybxorofaafneao.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<ask project owner for key>
NEXT_PUBLIC_API_URL=http://localhost:4000
```

Edit `backend/.env`:
```
SUPABASE_URL=https://hkrqyxybxorofaafneao.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<ask project owner for key>
REDIS_URL=<optional, can skip for local dev>
PORT=4000
NODE_ENV=development
FRONTEND_URL=http://localhost:3000
CORS_ORIGINS=http://localhost:3000
```

### Step 5: Run Locally

```bash
# Terminal 1: Start backend
cd backend && npm run dev

# Terminal 2: Start frontend
cd web && npm run dev
```

- Frontend: http://localhost:3000
- Backend: http://localhost:4000

---

## PART 2: Making Changes with Claude Code CLI

### Starting Claude Code

```bash
# Navigate to the project
cd ~/Documents/mitimaiti

# Start Claude Code
claude
```

### Example Prompts for Common Tasks

#### Changing UI / Design
```
Change the welcome page hero gradient from rose to blue
```
```
Make the discovery cards wider and add a shadow effect
```
```
Update the navbar logo text to say "MitiMaiti Beta"
```

#### Adding Features
```
Add a "Favorites" tab to the inbox page between Liked You and Matches
```
```
Add dark mode support to the entire app
```
```
Create a new /about page with information about MitiMaiti
```

#### Fixing Bugs
```
The OTP input is not auto-advancing to the next field, fix it
```
```
The profile completeness ring is showing wrong percentage, fix the SVG calculation
```

#### Backend Changes
```
Add a new endpoint GET /v1/stats that returns total user count
```
```
Update the cultural scoring to weigh language at 25 points instead of 20
```

#### Database Changes
```
Add a "hobbies" TEXT[] column to the user_basics table
```

### Workflow: Edit → Test → Push → Auto-Deploy

```bash
# 1. Open Claude Code
claude

# 2. Ask Claude to make changes
> Update the premium page pricing to show USD instead of INR

# 3. Claude edits the files. Test locally:
> Run the dev server and check if it works

# 4. Exit Claude Code (Ctrl+C or type /exit)

# 5. Push changes
git add -A
git commit -m "Update premium pricing to USD"
git push

# 6. Auto-deploy happens:
#    - Vercel rebuilds frontend (~30 seconds)
#    - Render rebuilds backend (~2-3 minutes)
```

### Useful Claude Code Commands

| Command | What it does |
|---------|-------------|
| `/help` | Show all available commands |
| `/clear` | Clear conversation context |
| `/cost` | Show token usage |
| `Ctrl+C` | Cancel current operation |
| `/exit` or `Ctrl+D` | Exit Claude Code |

### Tips for Effective Claude Code Usage

1. **Be specific**: "Change the button color on the welcome page to blue" is better than "make it look different"
2. **Reference files**: "Update web/src/app/discover/page.tsx to add a filter button" helps Claude find the right file
3. **One change at a time**: Make one change, test, commit. Don't batch 10 changes.
4. **Ask Claude to test**: "Run npm run build to check for errors" before pushing
5. **Read before edit**: Ask Claude to "show me the current discover page code" before making changes

---

## PART 3: Project Structure Reference

```
mitimaiti/
├── web/                          # Next.js 14 Frontend
│   ├── src/
│   │   ├── app/                  # Pages (file-based routing)
│   │   │   ├── welcome/          # Landing page
│   │   │   ├── auth/             # Phone + OTP login
│   │   │   ├── onboarding/       # 8-step onboarding
│   │   │   ├── discover/         # Main discovery feed
│   │   │   ├── inbox/            # Likes + Matches
│   │   │   ├── chat/[matchId]/   # Chat screen
│   │   │   ├── profile/          # Profile + Edit
│   │   │   ├── settings/         # Settings
│   │   │   ├── family/           # Family Mode
│   │   │   └── premium/          # Premium upgrade
│   │   ├── components/
│   │   │   ├── ui/               # Reusable UI (Button, Card, Modal, etc.)
│   │   │   └── onboarding/       # OnboardingShell
│   │   ├── lib/                  # API client, Supabase, mock data
│   │   ├── hooks/                # useAuth, useApi
│   │   └── types/                # TypeScript interfaces
│   └── tailwind.config.ts        # Theme colors & config
│
├── backend/                      # Express.js API
│   └── src/
│       ├── server.ts             # Main app entry
│       ├── config/               # Supabase + Redis clients
│       ├── middleware/            # Auth, rate limit, validation
│       ├── routes/               # 9 route files (auth, profile, etc.)
│       ├── services/             # Scoring, Kundli, Notifications
│       ├── data/                 # Icebreakers, Kundli tables
│       ├── socket.ts             # Socket.io real-time chat
│       └── cron.ts               # 7 scheduled jobs
│
├── supabase/
│   └── migrations/               # SQL schema (23 tables)
│
└── render.yaml                   # Render deployment config
```

### Key Theme Colors (Tailwind)
| Name | Hex | Usage |
|------|-----|-------|
| rose | #B5336A | Primary buttons, accents |
| roseDark | #8A1A4A | Hover states |
| roseLight | #E8A0BE | Backgrounds |
| gold | #D4A853 | Premium, special |
| charcoal | #2D2426 | Headings |
| textMain | #3D2B33 | Body text |
| textLight | #7A6670 | Secondary text |
| cream | #FFF8F0 | Page backgrounds |

---

## PART 4: Using Claude Mobile App for Quick Edits

You can use the **Claude mobile app** (iOS/Android) to plan and generate code snippets, then paste them into the project.

### How to Use Claude Mobile for Code Changes

#### 1. Ask Claude to generate a component

Open Claude app and type:

```
I'm working on MitiMaiti, a Next.js 14 matrimony app with Tailwind CSS.
The color theme uses: rose (#B5336A), gold (#D4A853), charcoal (#2D2426), cream (#FFF8F0).

Generate a new "Testimonials" section component for my landing page.
It should show 3 testimonial cards with photo, name, quote, and city.
Use 'use client' directive, framer-motion animations, and Tailwind classes.
Export as default function TestimonialsSection.
```

#### 2. Copy the generated code

Claude will generate the full component. Copy it.

#### 3. Add to project

Option A - Via GitHub web editor:
1. Go to https://github.com/techygarry/mitimaiti
2. Navigate to the file you want to edit
3. Click the pencil icon (Edit)
4. Paste the code
5. Commit directly → Auto-deploys

Option B - Via Claude Code CLI later:
1. Open Claude Code on your computer
2. Say: "Create a new file web/src/components/TestimonialsSection.tsx with this code: [paste]"

#### 4. Useful Mobile Prompts

**Generate a new page:**
```
Generate a Next.js 14 page for /about that shows the MitiMaiti team.
Use Tailwind CSS with these colors: rose #B5336A, charcoal #2D2426, cream #FFF8F0.
Import AppShell from @/components/ui/AppShell and wrap the content in it.
Make it responsive and modern.
```

**Fix a bug (describe and get solution):**
```
In my Next.js app, the OTP page has 6 input fields for digits.
Currently when I type a digit it doesn't auto-focus the next input.
Here's my current code: [paste code]
Fix the auto-advance logic.
```

**Design review:**
```
Here's my current discover page code: [paste code]
Suggest 5 UI improvements to make it look more like leading dating apps.
Give me the updated code for each change.
```

**Plan a feature:**
```
I want to add a "Stories" feature to MitiMaiti (like Instagram stories
but for sharing cultural moments). What files would I need to create
in my Next.js 14 app? Give me the implementation plan.
```

---

## PART 5: Quick Reference Commands

### Daily Development
```bash
cd ~/Documents/mitimaiti
git pull                          # Get latest changes
cd web && npm run dev             # Start frontend
# In another terminal:
cd backend && npm run dev         # Start backend
claude                            # Start Claude Code for AI-assisted editing
```

### Deploying Changes
```bash
git add -A
git commit -m "your change description"
git push
# Auto-deploys to Vercel + Render
```

### Checking Deployment Status
```bash
# Frontend (Vercel)
vercel ls

# Backend (Render)
# Check: https://dashboard.render.com
```

### Running Build Check Before Pushing
```bash
cd web && npx next build          # Check for TypeScript/build errors
cd ../backend && npx tsc --noEmit # Check backend TypeScript
```

---

## Need Help?

- **Claude Code issues**: https://github.com/anthropics/claude-code/issues
- **Project issues**: Create an issue on the GitHub repo
- **Supabase docs**: https://supabase.com/docs
- **Next.js docs**: https://nextjs.org/docs
- **Tailwind docs**: https://tailwindcss.com/docs
