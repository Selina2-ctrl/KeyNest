# KeyNest

KeyNest is a property-management app I built to bring everyday rental operations into one place. It gives property managers and their teams a shared view of properties, reservations, guests, payments, staff access, and cleaning work after checkout.

## What the app does

- **Dashboard:** Shows revenue, occupancy, active bookings, today’s check-ins and check-outs, and recent activity.
- **Properties:** Lists rental units, rates, capacity, availability, and cleaning regions.
- **Bookings:** Tracks reservations through pending, confirmed, checked-in, and checked-out states, with search by guest, property, booking ID, or email.
- **Guests:** Keeps guest contact details and stay history searchable.
- **Payments:** Records transactions and balances, with a guest-name search in the ledger.
- **Users and profiles:** Supports user roles, sign-up, invitations, and profile details.
- **Audit trail:** Shows searchable activity records.
- **Housekeeping:** Creates a cleaning task when a booking is checked out, assigns it to a cleaner in the matching region, and gives the cleaner five hours to mark the room clean and upload photos.

## How it is built

The app interface is a static HTML page in `index.html`. It does not include a custom application server or a backend API maintained in this repository. The browser connects directly to Supabase for authentication, database reads and writes, and housekeeping photo storage. Supabase applies the access rules and database triggers.

This means the interface can be hosted locally or on GitHub Pages without a Node/Express server or a build step. It does **not** run fully offline or without a backend service: sign-in, shared records, invitations, and photo uploads require an internet connection and a configured Supabase project.

## Run the interface locally

1. Clone the repository and open a terminal in the project folder.
2. Start a static file server. For example, if Python is installed:

   ```powershell
   python -m http.server 8000
   ```

3. Open [http://localhost:8000](http://localhost:8000) in a browser.

This only serves the static files; it does not run KeyNest application logic on the server. The browser still connects to Supabase. To use a different Supabase project, set its project URL and **publishable** key in the Supabase connection section of `index.html`. Add `http://localhost:8000` to that project's allowed Auth redirect URLs, and make sure its schema, row-level security policies, and Storage bucket are configured.

Do not put a Supabase service-role key in `index.html`. It grants elevated access and must remain on the server side.

## Supabase setup and deployment

The Supabase-specific code lives here:

```text
supabase/migrations/                        Database schema and policies
supabase/functions/invite-user/index.ts     Admin-protected invitation function
supabase/config.toml                         CLI configuration (created by `supabase init`)
```

Install Node.js 20 or later, then install the Supabase CLI from the project folder:

```powershell
npm install --save-dev supabase
```

If `supabase/config.toml` does not exist yet, initialize it from the project folder:

```powershell
npx supabase init
```

Connect and deploy the migration and Edge Function:

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase functions deploy invite-user
```

Find the project ref in the Supabase Dashboard URL: `https://supabase.com/dashboard/project/YOUR_PROJECT_REF`.

The housekeeping migration adds region fields, cleaning tasks, checkout assignment, five-hour deadlines, completion tracking, row-level security, and a private `cleaning-photos` bucket. The invitation function checks that the caller is an admin before inviting a user. It uses Supabase’s server-side service-role credential; that credential must never be added to the browser code or committed to GitHub.

## Configure authentication and regions

In the Supabase Dashboard, set the production Site URL and allowed redirect URLs under **Authentication → URL Configuration**. Include your local URL when developing locally. Enable email sign-ups if users should register from the login page, and configure email delivery for sign-up confirmations, password resets, and invitations. Password reset links return to the current app URL, so add the GitHub Pages URL and any local URL you use to the allowed redirect URLs.

For cleaner assignment, give each property a region and each housekeeper the same region. Matching ignores capitalization and surrounding spaces. Existing property and cleaner records need their regions set once. When a booking changes to **Checked Out**, Supabase creates a task and assigns it to an available housekeeper in that region. If no matching cleaner is available, an admin can assign the task to a housekeeper in the same region. Completion requires one or more room photos; the task records whether it was completed within five hours.

## GitHub Pages

KeyNest has no build step. To host it on GitHub Pages, configure the repository’s **Settings → Pages** to publish the `main` branch from the repository root. Pushing changes to `index.html` publishes the interface; Supabase migrations and Edge Functions must be deployed separately with the CLI commands above.

## Troubleshooting

- **`supabase` is not recognized:** This project uses a local CLI install. Run commands as `npx supabase ...`.
- **Cleaning tasks do not appear:** Apply the database migration with `npx supabase db push`.
- **A checkout task is unassigned:** Check that the property has a region and that at least one Housekeeping user has the same region.
- **Invitations fail:** Deploy `invite-user`, sign in as an admin, and check Supabase Auth email delivery settings.
- **Registration fails:** Check that email sign-ups are enabled and the Supabase project creates a profile with the app’s expected role and access policies.
