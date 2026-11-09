// Supabase connection for Ti:Hi Builder.
// The anon key is meant to be public; data is protected by the database's row level security.
window.TIHI_CONFIG = {
  url: "https://wtriymwqiuihqxkdjgco.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0cml5bXdxaXVpaHF4a2RqZ2NvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5NzQwODksImV4cCI6MjEwOTU1MDA4OX0.spyWSi1GE6MtMON8QkZpq8RtqBigst4GPn7XRtHiUbE"
};

// Box inventory for the Box finder page: the Google Sheet's "Publish to web" CSV link.
// Leave empty to show a sample list. Currently: the "2025 Box List" tab.
window.TIHI_CONFIG.boxInventoryCsv = "https://docs.google.com/spreadsheets/d/e/2PACX-1vTphlguvWk0ySfPXgR-cbPTjpjltnBVUULFp_VOzhmnqOFIw_GkJs0akClrZrMs-FA58G7XPho-z27g/pub?gid=569861441&single=true&output=csv";
