# InventoryHub

**InventoryHub** is a full-stack dynamic inventory management platform built with **Ruby on Rails 8** and **PostgreSQL**. It allows teams and individuals to define custom schemas per inventory, generate structured composite Custom IDs, collaborate with granular access controls, and search records using native PostgreSQL full-text indexing.

**Live Application:** https://inventory-hub-pj8h.onrender.com  
**Repository:** https://github.com/robiultechie-dotcom/inventory_hub

---

## Key Features

* **Authentication & Role-Based Access Control**
  * Dual OAuth 2.0 social login via **Google** and **GitHub** (OmniAuth 2.0).
  * Email registration with Rails 8 cryptographic signed confirmation tokens (24-hour expiration) and BCrypt password hashing.
  * **Guest (Read-Only)** browsing, **Public / Private** inventory write permissions with user autocomplete, and a dedicated **Admin Panel** (bulk user management, block/unblock, and role control).
* **Dynamic Custom Fields & Custom IDs**
  * Unlimited customizable fields per inventory (Single-Line Text, Multi-Line Text, Numeric, Document/Image Link, True/False, and One From List) with configurable validations (min/max length, numeric bounds, regex patterns) and table visibility toggles.
  * Configurable sequential & formatted Custom IDs (`CustomIdGenerator`) enforced for format and per-inventory uniqueness.
* **Concurrency Safety & Data Integrity**
  * **Optimistic Locking** (`lock_version`) on both `Inventory` and `Item` records to detect and prevent concurrent lost updates.
* **PostgreSQL Full-Text Search & Discovery**
  * Native PostgreSQL GIN-indexed full-text search across inventory titles, descriptions, tags, comments, item field values, and hyphenated Custom IDs, complemented by live search suggestions and a Tag Cloud.
* **Media, Collaboration & Reporting**
  * Direct signed cloud image uploads via **Cloudinary** (image bytes upload directly from the browser without proxying through the Rails server).
  * Inventory discussions (comments), per-item likes, SQL-aggregated inventory statistics, and one-click **CSV** / **Excel (`.xlsx`)** exports.
* **Internationalization & Theming**
  * Full **English (`EN`)** and **Spanish (`ES`)** localization alongside **Light / Dark** theme persistence.

---

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| **Framework** | Ruby on Rails 8.1 (Ruby 3.3) |
| **Database** | PostgreSQL (Native Full-Text Search & GIN Indexes) |
| **Frontend** | ERB, Bootstrap 5, Hotwire (Turbo & Stimulus), Importmap |
| **Authentication** | OmniAuth 2.0 (`omniauth-google-oauth2`, `omniauth-github`), BCrypt |
| **Media & Exports** | Cloudinary Direct Signed Uploads, CSV & XLSX Export |
| **Quality & CI/CD** | GitHub Actions (`Brakeman`, `Importmap Audit`, `RuboCop`, `Minitest`), Render |

---

## Local Setup

### Prerequisites
* Ruby 3.3+
* PostgreSQL 14+
* Bundler

### Installation

```bash
git clone [https://github.com/robiultechie-dotcom/inventory_hub.git](https://github.com/robiultechie-dotcom/inventory_hub.git)
cd inventory_hub
bundle install
```

### Configuration

Set the required environment variables (see `render.yaml` for the full list):

* **Database:** `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST` (or `DATABASE_URL` in production)
* **OAuth Providers:** `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`
* **Admin & Services:** `ADMIN_EMAIL`, Cloudinary credentials (for direct signed uploads), and SMTP credentials (for email confirmation)

### Database & Server

```bash
bin/rails db:prepare
bin/rails server
```

Visit `http://localhost:3000`.

---

## Testing & Quality Checks

```bash
# Prepare test database and run model & integration tests
bundle exec rails db:test:prepare
bundle exec rails test

# Code style check
bundle exec rubocop

# Static security analysis
bundle exec brakeman --no-pager
```