# Family sync (shared-sync branch)

## What was built

The chore app still saves everything in `localStorage` so it works offline. This branch adds an optional Supabase sync layer on top of that cache so every phone (and later a wall tablet) shares the same chores, check-offs, balances, goals, history, and parent PIN.

Nothing is live yet. This work is only on the `shared-sync` branch. GitHub Pages still deploys from `main`, so https://mdalfin819.github.io/Kids-chores/ is unchanged.

While placeholders are empty, the app behaves exactly as it does today. After the Supabase project exists and the URL plus anon key are filled in, Settings gains a Family sync screen, and a banner guides the first setup:

1. On the phone that already has the real data, generate (or enter) a long family code and tap **Upload this phone's data**. That seeds the database and will not overwrite a row that already exists.
2. On every other phone, enter the same code and tap **Use family data on this phone**. Those phones adopt the remote copy instead of uploading their own, so a mostly empty phone cannot wipe the real data.
3. After a phone is linked, each change is written locally first, then pushed. Other devices update live over a Realtime broadcast, and also poll every 15 seconds and on app resume as a fallback.

Conflict handling is last-write-wins on the row's `updated_at`, with a simple merge when two phones change data before either has seen the other's write: history entries and goals are merged by id (including local deletes), and kids, chore lists, and the PIN take the side that actually changed. Switching the selected kid or collapsing a section stays on that phone and is not synced.

The service worker was also restored and bumped to `chore-tracker-v8`. On `main` it is currently an empty file (emptied in the Nov 12 price-change commit). Phones will pick up the new worker once this branch is deployed.

## Security model

The public anon key is used in the browser. There is no service role key in the app, and there should never be one.

The table `family_state` has row-level security turned on and **no policies** for the `anon` or `authenticated` roles. Direct select, insert, update, and delete are revoked. The only access is three `SECURITY DEFINER` RPCs (`get_family_state`, `seed_family_state`, `push_family_state`) that require the full family id and reject anything shorter than 24 characters.

That family id is a 32-byte random value (64 hex characters), not a guessable name. Knowing it is what authorizes read and write. The simplest way to keep it reasonably private on this public GitHub repo and public Pages site is to leave the `FAMILY_ID` placeholder blank and type or generate the code on each phone, where it is stored only in `localStorage`. Hard-coding it in `index.html` works, but then anyone who can see the repo or view-source on the live site would have the code.

This is not a login system. Anyone who has the family code can read and change the family chores. It is strong against random guessing and against listing other families. It is not strong against someone who obtains the code, or against committing the code to a public repository.

## Steps to finish once the Supabase project exists

Do not put the service role key, the family code, or any other secret in chat.

1. Create a free Supabase project (the account itself still needs Motty's approval; this branch does not create one).
2. In the Supabase SQL Editor, paste and run `supabase/family_sync.sql`.
3. From Project Settings → API, copy the project URL and the **anon public** key (not the service role key).
4. On this `shared-sync` branch, set the placeholders in `index.html`:

   ```js
   const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJ...anon public key...';
   const FAMILY_ID = ''; // leave blank; generate the code in the app
   ```

5. Commit those two public values on `shared-sync`, then merge to `main` only when you are ready to deploy. Merging is what publishes the live Pages site.
6. After the deploy, open the app on Motty's phone, pull to refresh (or delete the home-screen icon and re-add it) so `chore-tracker-v8` is installed.
7. Settings → Family sync → **Generate a new family code**. Copy that code somewhere private (a text to his wife is fine). Then tap **Upload this phone's data**.
8. On his wife's phone (and later a tablet): same Settings screen, paste the code, **Save code on this phone**, then **Use family data on this phone**. If that phone has leftover test check-offs, export a backup first.
9. Realtime broadcast is on by default for new projects. If live updates do not appear, confirm Realtime is enabled in the Supabase dashboard. Polling will still keep phones in sync within about 15 seconds.

## Risks

- **Do not merge or push this branch to `main` until the URL and anon key are filled in and you are ready for phones to update.** An empty-placeholder deploy is harmless (sync stays off) but the service worker bump to v8 will still roll out.
- If the family code is committed to this public repo, treat it as public and generate a new one, stored only on the phones.
- Two people editing the same chore list or PIN at the same moment can still lose one of those edits. Two different check-offs or goals are merged and should both be kept.
- Goal photos live inside the saved JSON. A lot of large photos could approach Supabase's row size limit and also fill phone storage.
- The parent PIN syncs with the rest of the data. Once Motty's phone uploads a PIN, the other phones will prompt for it before editing.
- `seed_family_state` never overwrites an existing row. Replacing family data later is a deliberate Settings action with a confirm prompt.
- The live site today serves an empty `sw.js`. That is a pre-existing issue on `main` and is only fixed on this branch.
