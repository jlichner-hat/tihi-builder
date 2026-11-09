# Ti:Hi Shipment Builder

Pallet and truck load planner with company accounts. It's a static site (`index.html`) that uses Supabase for sign-up, email verification, and each company's private item library.

## How accounts work
- People sign up with **username, company, company email and password**. Supabase emails them a verification link.
- The company is matched by **email domain**. The first person from `@acme.com` creates "Acme" as a *pending* company and becomes its company admin. Later sign-ups from `@acme.com` join Acme automatically.
- Personal email domains (gmail.com, yahoo.com, ...) are refused, because they can't identify a company. The list is in the `blocked_domains` table.
- A **site admin** (you) approves each new company from the **Approve companies** button. Until then, its users see a "waiting for approval" screen.
- Saved items (name, L × W × H, weight) belong to one company. Database row level security makes other companies' items unreadable, even to someone calling the API directly.
- Users sign in with their email and password. Passwords are stored and hashed by Supabase Auth and never touch this site's tables.

## Setup
1. **Database:** in Supabase, open the SQL Editor, paste `supabase/schema.sql`, and run it.
2. **Auth settings** (Authentication > Providers > Email): keep **Confirm email** on.
   Under Authentication > URL Configuration, set **Site URL** to the address where the site is hosted (`https://jlichner-hat.github.io/tihi-builder/`) and add the same address to **Redirect URLs**.
3. **Email sending:** Supabase's built-in email only sends a few messages per hour and is meant for testing. Before real users sign up, add your own SMTP (Authentication > Emails > SMTP Settings), for example Resend, SendGrid, or your company mail server.
4. **Keys:** `config.js` already has this project's URL and public anon key. The anon key is meant to be public, and the access rules protect the data.
5. **Hosting (GitHub Pages):** push this folder to the repo, then in GitHub go to Settings > Pages and choose "Deploy from a branch", `main`, `/ (root)`.
6. **Make yourself site admin:** sign up on the site and verify your email. Then run this in the SQL editor:
   ```sql
   insert into public.app_admins(user_id)
   select id from auth.users where email = 'you@yourcompany.com';
   ```
   If you want to use a personal address for the admin account, first run `delete from public.blocked_domains where domain = 'gmail.com';` and sign up, then add it back.

## Files
- `index.html`: the app (planner, box size comparison, sign-in, sign-up, approvals). The **Compare box sizes** page (`index.html#compare`) puts two or more box sizes for the same item on one pallet and ranks them by units per pallet and cube utilization. Its **Download PDF report** button saves the comparison as a PDF.
- The **Box finder** page (`index.html#boxes`) takes a product's L × W × H and lists the 3 to 5 smallest boxes from the company box inventory that it fits inside, in any orientation (or with the height kept up). Optional extra room per side allows for padding. It also suggests the closest whole-inch size to look up on Uline. A **By cubic volume** search lists the smallest boxes with at least a given inside volume (cu ft or cu in).
- `config.js`: Supabase URL and anon key, plus `boxInventoryCsv`, the box inventory link

## Box inventory (Google Sheet)
1. In the Google Sheet, go to File > Share > Publish to web, choose the tab with the boxes and **Comma-separated values (.csv)**, and click Publish.
2. Paste the link into `boxInventoryCsv` in `config.js`. Edits to the sheet show up on the site within a few minutes (Google refreshes published sheets on its own schedule).
3. The sheet needs a header row with **Length**, **Width** and **Height** columns (names like "Inside L" or "Length (in)" work too), or one **Dimensions** column like `12 x 10 x 8`. A column called Box, Name, Item or SKU is used as the box name. Every other column (quantity, location, cost...) is shown on the result cards. Fractions like `12 1/2` are fine.
Until the link is set the page shows a sample list. Anyone can also paste a different link or open a CSV file under "Use a different list" on the page.
- `supabase/schema.sql`: tables, sign-up trigger, and access rules
