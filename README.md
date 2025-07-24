# Marine Traffic Scraper

![Python](https://img.shields.io/badge/Python-3.9+-blue?logo=python)
![SQLite](https://img.shields.io/badge/SQLite-embedded-lightgrey?logo=sqlite)
![Web Scraping](https://img.shields.io/badge/Web%20Scraping-Playwright-informational?logo=github)
![Jupyter](https://img.shields.io/badge/Jupyter-Notebook-orange?logo=jupyter)


Collect AIS-like vessel positions, persist them in SQLite, and analyze them with practical SQL. This repo contains:

* A Python/Jupyter workflow that scrapes ship position data
* A normalized SQLite database (`ships.db`) + schema SQL (`ships_db.sql`)
* A library of ready‑to‑run analytical queries (freshness checks, most‑active ships, common destinations, etc.)
* Examples for exporting the latest positions to Excel/CSV for mapping

> **Why this exists:** I wanted a lightweight pipeline (no external DB server) to experiment with real‑time maritime data and practice SQL/analytics. Everything here runs locally.

---

## 📑 Table of Contents

1. [Architecture at a Glance](#architecture-at-a-glance)
2. [Repository Structure](#repository-structure)
3. [Setup & Quick Start](#setup--quick-start)
4. [Database Schema](#database-schema)
5. [Key SQL Queries](#key-sql-queries)
6. [Data Freshness & Monitoring](#data-freshness--monitoring)
7. [Exporting & Visualizing Positions](#exporting--visualizing-positions)
8. [Scheduling / Automation Ideas](#scheduling--automation-ideas)
9. [Roadmap / Future Ideas](#roadmap--future-ideas)

---

## Architecture at a Glance

```text
Scraper (Python / Playwright / requests) → Clean/Normalize → SQLite (ships.db)
                                                     ↓
                                            SQL Analytics / Dashboards
                                                     ↓
                                     CSV/Excel export → Maps (Excel/Tableau/etc.)
```

* **Scraping Layer:** Implemented in `Marine_Traffic_Scraper_Notebook.ipynb` (can be refactored into a CLI script).
* **Storage:** SQLite for simplicity; `.sql` dump allows easy rebuild.
* **Analytics:** Pure SQL (compatible with DBeaver, DB Browser for SQLite, etc.).
* **Visualization:** Export latest ship positions to plot in Excel/Power BI/Tableau, or generate static maps in Python.

---

## Repository Structure

```
├─ Marine_Traffic_Scraper_Notebook.ipynb   # Jupyter notebook scraper & EDA
├─ ships_db.sql                            # Schema + (optionally) seed data
├─ ships.db                                # SQLite database with positions & vessels
├─ README.md                               # ← this file
└─ /img or /docs (optional)                # screenshots, diagrams, GIFs
```

> If you prefer scripts over notebooks, consider moving the scraping code into `src/` and exposing a CLI (see [Roadmap](#roadmap--future-ideas)).

---

## Setup & Quick Start

### 1. Clone & Environment

```bash
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

> If a `requirements.txt` isn’t present, freeze your notebook env or manually install: `playwright`, `pandas`, `sqlite3` (std lib), etc.

### 2. Initialize the Database (if starting fresh)

```bash
sqlite3 ships.db < ships_db.sql
```

### 3. Run the Scraper

* Open `Marine_Traffic_Scraper_Notebook.ipynb` in Jupyter / VSCode and run cells.
* Or refactor cells into a script:

  ```bash
  python src/scrape.py --out-db ships.db
  ```

### 4. Explore Data in DBeaver / DB Browser

* Connect to `ships.db`
* Run the example queries from [/sql](./sql) or the sections below.

---

## Database Schema

Two core tables (more can be added):

### `vessels`

| column      | type    | description                     |
| ----------- | ------- | ------------------------------- |
| ship\_id    | INTEGER | Primary key / unique identifier |
| shipname    | TEXT    | Vessel name                     |
| flag        | TEXT    | ISO country code                |
| destination | TEXT    | Last reported destination       |

### `positions`

| column   | type    | description                              |
| -------- | ------- | ---------------------------------------- |
| ship\_id | INTEGER | FK → vessels.ship\_id                    |
| lat      | REAL    | Latitude                                 |
| lon      | REAL    | Longitude                                |
| ts\_utc  | TEXT    | Timestamp in UTC (`YYYY-MM-DD HH:MM:SS`) |

> **Indexes**: Ensure an index on `positions(ts_utc)` and `positions(ship_id, ts_utc)` for freshness queries.

---

## Key SQL Queries

Below are the core analytics queries included in this repo. Drop them into DBeaver or `sqlite3`.

### 1. Inspect & Count

```sql
-- All rows (careful with large tables)
SELECT * FROM positions;

-- Total number of position updates collected
SELECT COUNT(*) FROM positions;
```

### 2. Most Recent Records

```sql
-- 50 newest rows
SELECT *
FROM positions
ORDER BY ts_utc DESC
LIMIT 50;

-- 5 newest rows
SELECT *
FROM positions
ORDER BY ts_utc DESC
LIMIT 5;
```

### 3. Data Latency Check

```sql
SELECT
  datetime('now')            AS now_utc,
  MAX(ts_utc)                AS newest_row,
  ROUND( (julianday('now') - julianday(MAX(ts_utc))) * 24*60, 2 ) AS lag_min
FROM positions;
```

* `lag_min` tells you how many minutes have passed since the most recent insert.

### 4. Top Updating Ships

```sql
SELECT v.shipname, p.ship_id, COUNT(*) AS updates, MAX(ts_utc) AS last_seen
FROM positions p
JOIN vessels v ON p.ship_id = v.ship_id
GROUP BY p.ship_id
ORDER BY updates DESC
LIMIT 10;
```

### 5. Latest Position per Ship (for Mapping)

```sql
SELECT v.shipname, p.ship_id, p.lat, p.lon, p.ts_utc
FROM positions p
JOIN vessels v ON p.ship_id = v.ship_id
WHERE (p.ship_id, p.ts_utc) IN (
  SELECT ship_id, MAX(ts_utc)
  FROM positions
  GROUP BY ship_id
);
```

### 6. Stale Ships (>5 min since last update)

```sql
SELECT shipname, ship_id, MAX(ts_utc) AS last_seen
FROM positions
JOIN vessels USING(ship_id)
GROUP BY ship_id
HAVING STRFTIME('%s', 'now') - STRFTIME('%s', last_seen) > 300
ORDER BY last_seen ASC;
```

### 7. Filter by Flag

```sql
SELECT shipname, flag, lat, lon, ts_utc
FROM positions
JOIN vessels USING(ship_id)
WHERE flag = 'US'
ORDER BY ts_utc DESC
LIMIT 20;
```

### 8. Destinations

```sql
-- Latest known destination per ship
SELECT shipname, destination, MAX(ts_utc) AS last_seen
FROM positions
JOIN vessels USING(ship_id)
WHERE destination IS NOT NULL AND destination != ''
GROUP BY ship_id
ORDER BY last_seen DESC
LIMIT 20;

-- Most common destinations overall
SELECT destination, COUNT(*) AS count
FROM positions
WHERE destination IS NOT NULL AND destination != ''
GROUP BY destination
ORDER BY count DESC
LIMIT 20;
```

> Add your own! e.g., average speed over ground if you capture it, clustering by region, etc.

---

## Data Freshness & Monitoring

* Run the **latency query** on a schedule (cron/Task Scheduler) and alert if `lag_min` exceeds a threshold.
* Store scraper logs (success/fail counts) in a separate table for observability.
* Optionally push metrics to Grafana/Prometheus if you extend beyond SQLite.

---

## Exporting & Visualizing Positions

### Export to CSV for Excel / Tableau

```sql
.mode csv
.output latest_positions.csv
SELECT v.shipname, p.ship_id, p.lat, p.lon, p.ts_utc
FROM positions p
JOIN vessels v ON p.ship_id = v.ship_id
WHERE (p.ship_id, p.ts_utc) IN (
  SELECT ship_id, MAX(ts_utc)
  FROM positions
  GROUP BY ship_id
);
.output stdout
```

### Plotting in Python (Optional Snippet)

```python
import sqlite3, pandas as pd
import matplotlib.pyplot as plt

con = sqlite3.connect('ships.db')
df = pd.read_sql_query("""
SELECT shipname, ship_id, lat, lon, ts_utc
FROM positions JOIN vessels USING(ship_id)
WHERE (ship_id, ts_utc) IN (
  SELECT ship_id, MAX(ts_utc) FROM positions GROUP BY ship_id
)
""", con)

plt.scatter(df['lon'], df['lat'])
plt.title('Latest Vessel Positions')
plt.xlabel('Longitude'); plt.ylabel('Latitude')
plt.show()
```

---

## Scheduling / Automation Ideas

* **Cron (Linux/macOS):** Run scraper every N minutes, then run a SQL freshness check.
* **Windows Task Scheduler:** Same idea as cron.
* **GitHub Actions:** Nightly ETL job that commits updated CSV snapshots.
* **Airflow/Prefect:** If you outgrow cron and want DAGs, retries, and monitoring.

---

## Roadmap / Future Ideas

* [ ] Convert notebook into a robust CLI (`src/`) with args for rate limits, retry, headless mode
* [ ] Add unit tests for parsing & database insert logic
* [ ] Include docker-compose for a Postgres option
* [ ] Build a lightweight Streamlit dashboard over SQLite
* [ ] Enrich data: speed/course, ship type, port lookups
* [ ] Geofence alerts (e.g., ship entering/leaving a bounding box)
* [ ] Batch image download toggle (optional already in scraping prefs)

---

## Acknowledgments


* **Data Sources:** Respect the terms of service of any site/API scraped.
* **Tools:** SQLite, Python, Playwright/Requests, Jupyter, DBeaver.

---

