# Ti:Hi Shipment Builder

Pallet and truck load planner with company accounts. It's a static site (`index.html`) that uses Supabase for sign-up, email verification, and each company's private item library.

## How accounts work
- People sign up with **username, company, company email and password**. Supabase emails them a verification link.
- The company is matched by **email domain**. The first person from `@acme.com` creates "Acme" as a *pending* company and becomes its company admin. Later sign-ups from `@acme.com` join Acme automatically.
- Personal email domains (gmail.com, yahoo.com, ...) are refused, because they can't identify a company. The list is in the `blocked_domains` table.
- A **site admin** (you) approves each new company from the **Approve companies** button. Until then, its users see a "waiting for approval" screen.
- Saved items (name, L × W × H, weight) belong to one company. Database row level security makes other companies' items unreadable, even to someone calling the API directly.
- **Roles** decide which pages someone sees. **User** (the default for new sign-ups): Shipment builder only. **Packaging engineer**: also Compare box sizes, Shipping Comparison and Box finder. **Admin** (the company's first sign-up): every page, plus the **Admin** button, where they set the role of anyone in their company. Site admins can set anyone's role. Roles are changed through a database function that checks the caller is an admin, so people can't promote themselves.
- The box inventory reaches the browser only through the `box-inventory` Supabase function, which checks the viewer's role first. The sheet's link is a Supabase secret, so it isn't in this repo or the page.
- Users sign in with their email and password. Passwords are stored and hashed by Supabase Auth and never touch this site's tables.

## Setup
1. **Database:** in Supabase, open the SQL Editor, paste `supabase/schema.sql`, and run it.
2. **Auth settings** (Authentication > Providers > Email): keep **Confirm email** on.
   Under Authentication > URL Configuration, set **Site URL** to the address where the site is hosted (`https://jlichner-hat.github.io/tihi-builder/`) and add the same address to **Redirect URLs**.
3. **Email sending:** Supabase's built-in email only sends a few messages per hour and is meant for testing. Before real users sign up, add your own SMTP (Authentication > Emails > SMTP Settings), for example Resend, SendGrid, or your company mail server.
4. **Keys:** `config.js` already has this project's URL and public anon key. The anon key is meant to be public, and the access rules protect the data.
5. **Hosting (GitHub Pages):** push this folder to the repo, then in GitHub go to Settings > Pages and choose "Deploy from a branch", `main`, `/ (root)`.
6. **Roles on an existing database:** if the database was set up before roles were added, run `supabase/roles.sql` once in the SQL Editor.
7. **Make yourself site admin:** sign up on the site and verify your email. Then run this in the SQL editor:
   ```sql
   insert into public.app_admins(user_id)
   select id from auth.users where email = 'you@yourcompany.com';
   ```
   If you want to use a personal address for the admin account, first run `delete from public.blocked_domains where domain = 'gmail.com';` and sign up, then add it back.

## Files
- `index.html`: the app (planner, box size comparison, sign-in, sign-up, approvals). In the Shipment builder, **Commingle items on pallets** (Step 2) builds every pallet from layers of several items, spread evenly, instead of one item per pallet with only leftovers mixed. Its **Even quantities on every pallet** option puts the same count of each item on every pallet (within one), using the fewest pallets that hold that mix. The **Compare box sizes** page (`index.html#compare`) puts two or more box sizes for the same item on one pallet and ranks them by units per pallet and cube utilization. Its **Download PDF report** button saves the comparison as a PDF. The **Shipping Comparison** page (`index.html#ship`) takes those same box sizes, three or more estimated item order quantities (each compared separately) and an estimated pallet location shipping fee and a pallet location storage fee (per pallet per month, times months in storage), and shows how many pallet locations each box needs to ship from China to HAT and the estimated cost savings against a chosen box. Every report page has **Download PDF report** and **Print report** buttons; Print opens the browser print dialog with the same PDF. Box finder has a **Report** button: it opens the requested size and the closest boxes in a new window laid out for a 4 × 6 label, with Print and Copy image (copies a PNG to paste into a message).
- The **Box finder** page (`index.html#boxes`) takes a product's L × W × H and lists the 3 to 5 smallest boxes from the company box inventory that it fits inside, in any orientation (or with the height kept up). Optional extra room per side allows for padding. It also lists the closest **Uline** boxes, with part numbers linked to Uline, from `uline-boxes.csv` (212 of Uline's standard 200 lb test sizes, inside dimensions). Add rows to that file (Item, Description, Length, Width, Height, Link) to cover more Uline sizes. A **By cubic volume** search lists the smallest boxes with at least a given inside volume (cu ft or cu in).
- `config.js`: Supabase URL and anon key

## Box inventory (Google Sheet)
The Box finder reads the sheet through the `box-inventory` Supabase function (`supabase/functions/box-inventory/index.ts`). It only answers signed-in Packaging engineers, Admins and site admins, and it keeps the sheet's link secret.
1. **Make the sheet's link private.** A published sheet can be read by anyone who has its link, and the old link was in this public repo. Make a copy of the sheet (File > Make a copy) and use the copy from now on. Then turn off publishing on the old sheet (File > Share > Publish to web > Stop publishing).
2. In the copy, go to File > Share > Publish to web, choose the box tab and **Comma-separated values (.csv)**, and click Publish. Don't put this link anywhere public.
3. **Deploy the function:** in Supabase, open Edge Functions > Deploy a new function > Via editor, name it `box-inventory`, paste `supabase/functions/box-inventory/index.ts`, and deploy (keep "Verify JWT" on). With the Supabase CLI: `supabase functions deploy box-inventory`.
4. **Add the link:** Edge Functions > Secrets, add `BOX_INVENTORY_CSV_URL` with the link from step 2.

Edits to the sheet show up within a few minutes (Google refreshes published sheets on its own schedule).
The sheet needs a header row with **Length**, **Width** and **Height** columns (names like "Inside L" or "Length (in)" work too), or one **Dimensions** column like `12 x 10 x 8`. A column called Box, Name, Item or SKU is used as the box name. Every other column (quantity, location, cost...) is shown on the result cards. Fractions like `12 1/2` are fine.
Under "Use a different list" on the page, someone can still paste a different link or open a CSV file of their own.
- `supabase/schema.sql`: tables, sign-up trigger, roles and access rules
- `supabase/functions/box-inventory/index.ts`: serves the box inventory to engineers and admins only
- `supabase/roles.sql`: adds the Packaging engineer role and role changes to a database set up before roles existed
